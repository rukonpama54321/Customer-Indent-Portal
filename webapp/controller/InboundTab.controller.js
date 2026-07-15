sap.ui.define([
    "sap/ui/core/mvc/Controller",
    "sap/ui/model/json/JSONModel",
    "sap/m/MessageBox",
    "sap/m/MessageToast",
    "sap/ui/model/Filter",
    "sap/ui/model/FilterOperator",
    "customerindent/util/UserInfo"
], function (Controller, JSONModel, MessageBox, MessageToast, Filter, FilterOperator, UserInfo) {
    "use strict";

    return Controller.extend("customerindent.controller.InboundTab", {

        onInit: function () {
            var oUserInfo = UserInfo.getLoginInfo();

            // Entry form + filter state
            this.getView().setModel(new JSONModel({
                MATNR:        "",
                QTY_KL:       "",
                QTY_KL15:     "",
                QTY_MT:       "",
                TT_NUMBER:    "",
                INVOICE_NO:   "",
                DATE_FROM:    "",
                DATE_TO:      "",
                KUNNR:        "",   // derived from ZSD_CUST_USR_MAP
                DEPOT:        "",   // derived from ZSD_CUST_USR_MAP
                EBMS:         "",   // 'Y' = inbound available for this customer
                CUST_USER_ID: oUserInfo.userId,
                SMTP_ADDR:    oUserInfo.email
            }), "inbForm");

            // Stock overview (read-only display) — field names match the Stock entity
            this.getView().setModel(new JSONModel({
                UNLD_STOCK:   "",
                UNLD_STOCK15: "",
                UNLD_STOCKMT: "",
                LN_HLD_KL:    "",
                LN_HLD_KL15:  "",
                LN_HLD_MT:    "",
                OPEN_INDT:    "",
                BAL_QTY:      ""
            }), "inbStock");

            // Indents result table
            this.getView().setModel(new JSONModel({ results: [] }), "inbTable");

            // Load the auto-derived material + customer/depot/EBMS defaults.
            // The material is system-assigned (one value per customer), so there
            // is no material dropdown - it is shown read-only. Mirrors the
            // WebDynpro inbound tab, which has no material picker.
            this._loadDefaults();
        },

        // Loads the auto-derived material + customer + depot (EBMS init).
        // Silent if the service isn't configured yet (runs on every load).
        _loadDefaults: function () {
            // Nested <mvc:XMLView> tabs run onInit before the component's
            // models propagate to the view, so getView().getModel() is still
            // undefined here. Pull the model straight from the owner component
            // (always available in onInit) and pin it on the view so the rest
            // of the controller's handlers resolve it too.
            var oModel = this.getView().getModel("inboundModel") ||
                         this.getOwnerComponent().getModel("inboundModel");
            if (!oModel) { return; }   // no info popup on init
            if (!this.getView().getModel("inboundModel")) {
                this.getView().setModel(oModel, "inboundModel");
            }

            var oUserInfo = UserInfo.getLoginInfo();
            oModel.read("/InboundInitSet", {
                filters: [
                    new Filter("CUST_USER_ID", FilterOperator.EQ, oUserInfo.userId),
                    new Filter("SMTP_ADDR",    FilterOperator.EQ, oUserInfo.email)
                ],
                success: function (oData) {
                    var o     = (oData.results && oData.results[0]) || {};
                    var oForm = this.getView().getModel("inbForm");
                    oForm.setProperty("/MATNR", o.MATNR || "");
                    oForm.setProperty("/KUNNR", o.KUNNR || "");
                    oForm.setProperty("/DEPOT", o.DEPOT || "");
                    oForm.setProperty("/EBMS",  o.EBMS  || "");
                    if ((o.EBMS || "").toUpperCase() !== "Y") {
                        MessageToast.show("Inbound indents are available only for EBMS-enabled customers.");
                    }
                }.bind(this),
                error: function () { /* leave fields blank */ }
            });
        },

        // Guard used by Stock / Save / fetch — material is auto-assigned,
        // so its absence means the customer isn't EBMS-enabled.
        _requireMaterial: function () {
            var sMatnr = this.getView().getModel("inbForm").getProperty("/MATNR");
            if (!sMatnr) {
                MessageBox.warning("No inbound material is assigned to your account. " +
                                   "Inbound is available only for EBMS-enabled customers.");
                return null;
            }
            return sMatnr;
        },

        // Returns the inbound OData model, or null if the service is not yet configured.
        _getModel: function () {
            var oModel = this.getView().getModel("inboundModel");
            if (!oModel) {
                MessageBox.information(
                    "The Inbound OData service is not configured yet.\n" +
                    "Provide the service metadata and it will be wired to Save, Show Stock and the indent searches."
                );
                return null;
            }
            return oModel;
        },

        // ── Show current stock figures ────────────────────────────
        onShowStock: function () {
            var oModel = this._getModel();
            if (!oModel) { return; }

            var sMatnr = this._requireMaterial();
            if (!sMatnr) { return; }

            var oUserInfo = UserInfo.getLoginInfo();
            oModel.read("/StockSet", {
                filters: [
                    new Filter("MATNR",        FilterOperator.EQ, sMatnr),
                    new Filter("CUST_USER_ID", FilterOperator.EQ, oUserInfo.userId),
                    new Filter("SMTP_ADDR",    FilterOperator.EQ, oUserInfo.email)
                ],
                success: function (oData) {
                    var o = (oData.results && oData.results[0]) || {};
                    this.getView().getModel("inbStock").setData(o);
                }.bind(this),
                error: function () {
                    MessageBox.error("Failed to load stock figures.");
                }
            });
        },

        // ── Save a new inbound indent ─────────────────────────────
        onSave: function () {
            var oForm = this.getView().getModel("inbForm").getData();

            if (!this._requireMaterial()) { return; }
            if (!oForm.QTY_KL)   { MessageBox.warning("Please enter Quantity (KL)."); return; }
            if (!oForm.TT_NUMBER){ MessageBox.warning("Please enter a TT Number."); return; }

            var oModel = this._getModel();
            if (!oModel) { return; }

            var oUserInfo = UserInfo.getLoginInfo();
            // Map the friendly form fields to the InboundIndent entity fields.
            // IND_DATE is set server-side (= SY-DATUM); IND_PLANT/IND_CUST are derived.
            var oPayload = {
                IND_MATNR:    oForm.MATNR,
                IND_VEH:      oForm.TT_NUMBER,
                IND_QTY:      oForm.QTY_KL || "0",
                IND_QTY15:    oForm.QTY_KL15 || "0",
                IND_QTYMT:    oForm.QTY_MT || "0",
                IND_INV:      oForm.INVOICE_NO,
                CUST_USER_ID: oUserInfo.userId,
                SMTP_ADDR:    oUserInfo.email
            };

            oModel.create("/InboundIndentSet", oPayload, {
                success: function () {
                    MessageToast.show("Inbound indent saved successfully.");
                    this.onOpenIndents();   // refresh while MATNR is still set
                    this._clear();
                }.bind(this),
                error: function (oErr) {
                    var sMsg = "Failed to save inbound indent.";
                    try { sMsg = JSON.parse(oErr.responseText).error.message.value || sMsg; } catch (e) {}
                    MessageBox.error(sMsg);
                }
            });
        },

        // ── Fetch OPEN inbound indents ────────────────────────────
        // No date range → backend FM Z_GET_CUST_UNLOAD_INDENT returns
        // records with ZSTATUS <> 'COMPLETE' for the selected material.
        onOpenIndents: function () {
            this._fetchIndents([]);
        },

        // ── Fetch ALL inbound indents in a date range ─────────────
        // Both dates required; backend returns all statuses where
        // IND_DATE is between From and To for the selected material.
        onAllIndents: function () {
            var oForm = this.getView().getModel("inbForm").getData();

            if (!oForm.DATE_FROM || !oForm.DATE_TO) {
                MessageBox.warning("Please enter both From Date and To Date for All Indents.");
                return;
            }
            // yyyyMMdd strings compare chronologically as plain strings.
            if (oForm.DATE_FROM > oForm.DATE_TO) {
                MessageBox.warning("From Date cannot be later than To Date.");
                return;
            }

            this._fetchIndents([
                new Filter("DATE_FROM", FilterOperator.EQ, oForm.DATE_FROM),
                new Filter("DATE_TO",   FilterOperator.EQ, oForm.DATE_TO)
            ]);
        },

        // Shared read. Material is mandatory (the FM ANDs IND_MATNR = matnr,
        // so without it the backend returns nothing).
        _fetchIndents: function (aDateFilters) {
            var oModel = this._getModel();
            if (!oModel) { return; }

            var sMatnr = this._requireMaterial();
            if (!sMatnr) { return; }

            var oUserInfo = UserInfo.getLoginInfo();

            var aFilters = [
                new Filter("CUST_USER_ID", FilterOperator.EQ, oUserInfo.userId),
                new Filter("SMTP_ADDR",    FilterOperator.EQ, oUserInfo.email),
                new Filter("IND_MATNR",    FilterOperator.EQ, sMatnr)
            ].concat(aDateFilters);

            oModel.read("/InboundIndentSet", {
                filters: aFilters,
                success: function (oData) {
                    this.getView().getModel("inbTable").setProperty("/results", oData.results || []);
                }.bind(this),
                error: function () {
                    MessageBox.error("Failed to load inbound indents.");
                }
            });
        },

        // ── Modify the selected indent ────────────────────────────
        // Edits quantities, vehicle (TT) and invoice of an OPEN indent.
        // Vehicle is part of the key, so on the backend a modify is a
        // delete-old + insert-new (UPDATE_ENTITY handles the key change).
        onModifyIndent: function () {
            var oTable = this.byId("inbIndentTable");
            var oItem  = oTable.getSelectedItem();
            if (!oItem) {
                MessageBox.warning("Please select an indent to modify.");
                return;
            }

            var oRow = oItem.getBindingContext("inbTable").getObject();
            if ((oRow.ZSTATUS || "").toUpperCase() === "COMPLETE") {
                MessageBox.warning("Completed indents cannot be modified.");
                return;
            }

            // Preserve the ORIGINAL key — the vehicle may be changed in the dialog.
            this._oModKey = {
                IND_DATE:  oRow.IND_DATE,
                IND_MATNR: oRow.IND_MATNR,
                IND_VEH:   oRow.IND_VEH
            };

            if (!this.getView().getModel("inbMod")) {
                this.getView().setModel(new JSONModel({}), "inbMod");
            }
            this.getView().getModel("inbMod").setData({
                IND_VEH:   oRow.IND_VEH,
                IND_INV:   oRow.IND_INV,
                IND_QTY:   oRow.IND_QTY,
                IND_QTY15: oRow.IND_QTY15,
                IND_QTYMT: oRow.IND_QTYMT
            });

            if (!this._oModDialog) {
                // Each label+input is wrapped in its own VBox with a bottom
                // margin so the fields breathe; inputs stretch to full width.
                var fnField = function (sLabel, oInput, bReq) {
                    return new sap.m.VBox({
                        items: [
                            new sap.m.Label({ text: sLabel, required: !!bReq })
                                .addStyleClass("sapUiTinyMarginBottom"),
                            oInput.setWidth("100%")
                        ]
                    }).addStyleClass("sapUiSmallMarginBottom");
                };

                this._oModDialog = new sap.m.Dialog({
                    title: "Modify Inbound Indent",
                    contentWidth: "26rem",
                    content: [
                        new sap.m.VBox({
                            items: [
                                fnField("TT Number (Vehicle)",
                                        new sap.m.Input({ value: "{inbMod>/IND_VEH}", maxLength: 10 }), true),
                                fnField("Invoice No",
                                        new sap.m.Input({ value: "{inbMod>/IND_INV}", maxLength: 10 })),
                                fnField("Quantity (KL)",
                                        new sap.m.Input({ value: "{inbMod>/IND_QTY}", type: "Number" }), true),
                                fnField("Quantity (KL @15°)",
                                        new sap.m.Input({ value: "{inbMod>/IND_QTY15}", type: "Number" })),
                                fnField("Quantity (MT)",
                                        new sap.m.Input({ value: "{inbMod>/IND_QTYMT}", type: "Number" }))
                            ]
                        }).addStyleClass("sapUiContentPadding")
                    ],
                    beginButton: new sap.m.Button({
                        text: "Save",
                        type: "Emphasized",
                        press: this._onModSave.bind(this)
                    }),
                    endButton: new sap.m.Button({
                        text: "Cancel",
                        press: function () { this._oModDialog.close(); }.bind(this)
                    })
                });
                this.getView().addDependent(this._oModDialog);
            }

            this._oModDialog.open();
        },

        _onModSave: function () {
            var oModel = this._getModel();
            if (!oModel) { return; }

            var oMod = this.getView().getModel("inbMod").getData();
            if (!oMod.IND_VEH) { MessageBox.warning("TT Number cannot be empty."); return; }
            if (!oMod.IND_QTY) { MessageBox.warning("Quantity (KL) cannot be empty."); return; }

            var k = this._oModKey;
            var sPath = "/InboundIndentSet(IND_DATE='" + k.IND_DATE +
                        "',IND_MATNR='" + k.IND_MATNR +
                        "',IND_VEH='" + k.IND_VEH + "')";

            // New values; IND_VEH may differ from the key → backend does
            // delete-old + insert-new in UPDATE_ENTITY.
            var oPayload = {
                IND_QTY:   oMod.IND_QTY   || "0",
                IND_QTY15: oMod.IND_QTY15 || "0",
                IND_QTYMT: oMod.IND_QTYMT || "0",
                IND_VEH:   oMod.IND_VEH,
                IND_INV:   oMod.IND_INV
            };

            oModel.update(sPath, oPayload, {
                success: function () {
                    MessageToast.show("Indent modified successfully.");
                    this._oModDialog.close();
                    this.onOpenIndents();
                }.bind(this),
                error: function (oErr) {
                    var sMsg = "Failed to modify indent.";
                    try { sMsg = JSON.parse(oErr.responseText).error.message.value || sMsg; } catch (e) {}
                    MessageBox.error(sMsg);
                }
            });
        },

        // ── Reset entry form ──────────────────────────────────────
        _clear: function () {
            // MATNR is system-assigned and must persist across saves - clearing
            // it would trip _requireMaterial() on every subsequent action.
            var oForm = this.getView().getModel("inbForm");
            oForm.setProperty("/QTY_KL", "");
            oForm.setProperty("/QTY_KL15", "");
            oForm.setProperty("/QTY_MT", "");
            oForm.setProperty("/TT_NUMBER", "");
            oForm.setProperty("/INVOICE_NO", "");
        }

    });
});
