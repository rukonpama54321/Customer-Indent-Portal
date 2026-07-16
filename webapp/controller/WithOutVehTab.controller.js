sap.ui.define([
    "sap/ui/core/mvc/Controller",
    "sap/ui/model/json/JSONModel",
    "sap/m/MessageBox",
    "sap/m/MessageToast",
    "sap/m/SelectDialog",
    "sap/m/StandardListItem",
    "sap/ui/model/Filter",
    "sap/ui/model/FilterOperator",
    "sap/ui/model/Sorter",
    "customerindent/util/UserInfo"
], function (Controller, JSONModel, MessageBox, MessageToast, SelectDialog,
             StandardListItem, Filter, FilterOperator, Sorter, UserInfo) {
    "use strict";

    /* ════════════════════════════════════════════════════════════════
       WebDynpro INDMAIN → "Without Vehicle" tab (Indent Without Vehicle).

       Model: withoutvehModel (ZSD_CUST_IND_NOVEH_SRV, v2, useBatch=false).
       Entity sets used:
         GetCustomerSet   – customer value help (SELECT_MAT_AND_GSTN entry)
         MaterialSet      – customer's material(s) + ACTIVE1/ACTIVE2 flags
         GetOrderIdSet    – sales-contract value help (keyed by customer+material)
         GetTransGSTINSet – transporter GSTIN value help
         GetOpenIndentsSet– open-indents grid + create(place)/delete/short-close

       View state (JSON models):
         novehForm  – header + material entry fields
         novehTable – open-indents table rows
    ════════════════════════════════════════════════════════════════ */
    return Controller.extend("customerindent.controller.WithOutVehTab", {

        /* ═══════════════════════════════════════════
           INIT  (WebDynpro: WDDOINIT)
        ═══════════════════════════════════════════ */
        onInit: function () {
            this._resetForm();
            this.getView().setModel(new JSONModel({ results: [] }), "novehTable");
            // eligible-material dropdown list (one entry per material for the
            // customer's group); populated on customer select by _loadMaterials
            this.getView().setModel(new JSONModel({ items: [] }), "novehMat");
        },

        _getModel: function () {
            return this.getView().getModel("withoutvehModel");
        },

        _resetForm: function () {
            var oUserInfo = UserInfo.getLoginInfo();
            var oData = {
                KUNNR:        "",
                KUNNR_DESC:   "",
                BEGDA:        "",
                CONTRACT1:    "",
                MATNR1:       "",
                ACTIVE1:      "",
                MATNR2:       "",
                ACTIVE2:      "",
                QUANTITY1:    "",
                QUANTITY2:    "",
                TPT_GSTN:     "",
                CH_INDT:      false,   // change-indent mode (locks customer)
                CUST_USER_ID: oUserInfo.userId,
                SMTP_ADDR:    oUserInfo.email
            };
            var oForm = this.getView().getModel("novehForm");
            if (oForm) {
                oForm.setData(oData);
            } else {
                this.getView().setModel(new JSONModel(oData), "novehForm");
            }
        },

        /* ═══════════════════════════════════════════
           CUSTOMER VALUE HELP  (HEADER_DATA.KUNNR / NAME1)
           On select → auto-load the customer's material(s) (SELECT_MAT_AND_GSTN).
        ═══════════════════════════════════════════ */
        onCustomerSearch: function () {
            var oUserInfo = UserInfo.getLoginInfo();

            if (!this._oCustDialog) {
                // client-side model behind the dialog: GetCustomerSet is fetched
                // ONCE with the user-scope filter (the only filter the backend
                // honours), then search runs locally against these rows.
                this._oCustVHModel = new JSONModel({ rows: [] });

                this._oCustDialog = new SelectDialog({
                    title: "Select Customer",
                    confirm: function (oEv) {
                        var oItem = oEv.getParameter("selectedItem");
                        if (!oItem) { return; }
                        var oCtx  = oItem.getBindingContext("custVH").getObject();
                        // eligibility is pre-computed by GetCustomerSet; block
                        // the selection here so the user never lands on a
                        // customer that has no material configured.
                        if (oCtx.ELIGIBLE !== "X") {
                            MessageToast.show("No material is configured for this customer.");
                            return;
                        }
                        var oForm = this.getView().getModel("novehForm");
                        oForm.setProperty("/KUNNR",      oCtx.KUNNR);
                        oForm.setProperty("/KUNNR_DESC", oCtx.KUNNR_DESC);
                        this._loadMaterials(oCtx.KUNNR);
                    }.bind(this),
                    // match on both the customer name and number; client-side so
                    // it actually filters (server ignores these filters)
                    search:     this._filterCustVH,
                    liveChange: this._filterCustVH
                });

                this._oCustDialog.setModel(this._oCustVHModel, "custVH");
                this._oCustDialog.bindAggregation("items", {
                    model:    "custVH",
                    path:     "/rows",
                    // valid (material-configured) customers first: ELIGIBLE 'X'
                    // sorts above blank when descending. Client-side so the
                    // ordering holds regardless of the backend row order; KUNNR
                    // keeps a stable order within each block.
                    sorter:   [new Sorter("ELIGIBLE", true), new Sorter("KUNNR", false)],
                    template: new StandardListItem({
                        title:       "{custVH>KUNNR_DESC}",
                        description: "{custVH>KUNNR}",
                        // right-aligned material status: green count when configured,
                        // red "No material" otherwise (parity with the save-time toast)
                        info: {
                            parts: ["custVH>ELIGIBLE", "custVH>MAT_COUNT"],
                            formatter: function (sEligible, sCount) {
                                if (sEligible !== "X") { return "No material"; }
                                return (sCount || "0") + " material" + (sCount === "1" ? "" : "s");
                            }
                        },
                        infoState: {
                            path: "custVH>ELIGIBLE",
                            formatter: function (sEligible) {
                                return sEligible === "X" ? "Success" : "Error";
                            }
                        }
                    })
                });
                this.getView().addDependent(this._oCustDialog);
            }

            // (re)load the user-scoped customer list, then open
            this._oCustDialog.open();
            this._getModel().read("/GetCustomerSet", {
                filters: [
                    new Filter("CUST_USER_ID", FilterOperator.EQ, oUserInfo.userId),
                    new Filter("SMTP_ADDR",    FilterOperator.EQ, oUserInfo.email)
                ],
                success: function (oData) {
                    this._oCustVHModel.setProperty("/rows", (oData && oData.results) || []);
                }.bind(this),
                error: function (oErr) {
                    MessageBox.error(this._extractError(oErr,
                        "Could not load the customer list."));
                }.bind(this)
            });
        },

        // client-side customer value-help filter (name OR number contains)
        _filterCustVH: function (oEv) {
            var sVal     = oEv.getParameter("value");
            var oBinding = oEv.getSource().getBinding("items");
            oBinding.filter(sVal
                ? [new Filter({
                    filters: [
                        new Filter("KUNNR_DESC", FilterOperator.Contains, sVal),
                        new Filter("KUNNR",      FilterOperator.Contains, sVal)
                    ],
                    and: false
                })]
                : []);
        },

        // Load the customer's material(s) + per-material enable flags.
        _loadMaterials: function (sKunnr) {
            var oUserInfo = UserInfo.getLoginInfo();
            var oForm     = this.getView().getModel("novehForm");

            // reset material/qty on every customer change
            oForm.setProperty("/MATNR1", "");
            oForm.setProperty("/ACTIVE1", "");
            oForm.setProperty("/MATNR2", "");
            oForm.setProperty("/ACTIVE2", "");
            oForm.setProperty("/QUANTITY1", "");
            oForm.setProperty("/QUANTITY2", "");
            oForm.setProperty("/CONTRACT1", "");
            this.getView().getModel("novehMat").setProperty("/items", []);

            this._getModel().read("/MaterialSet", {
                filters: [
                    new Filter("KUNNR",        FilterOperator.EQ, sKunnr),
                    new Filter("CUST_USER_ID", FilterOperator.EQ, oUserInfo.userId),
                    new Filter("SMTP_ADDR",    FilterOperator.EQ, oUserInfo.email)
                ],
                success: function (oData) {
                    // MaterialSet now returns one row per eligible material
                    // (WD dropdown). ACTIVE1/ACTIVE2 are per-group slot flags,
                    // identical on every row.
                    var aRows  = (oData && oData.results) || [];
                    var oFirst = aRows[0] || {};
                    oForm.setProperty("/ACTIVE1", oFirst.ACTIVE1 || "");
                    oForm.setProperty("/ACTIVE2", oFirst.ACTIVE2 || "");
                    // blank leading entry (WD) lets the user clear the choice
                    var aItems = [{ MATNR: "", MATDESC: "" }].concat(aRows);
                    this.getView().getModel("novehMat").setProperty("/items", aItems);
                    if (!aRows.length) {
                        MessageToast.show("No material is configured for this customer.");
                    }
                }.bind(this),
                error: function (oErr) {
                    MessageBox.error(this._extractError(oErr,
                        "Could not load materials for the selected customer."));
                }.bind(this)
            });
        },

        // Material 1 drives the contract value help (GetOrderIdSet is keyed by
        // MATNR1). When the user picks a different material, any contract chosen
        // for the previous material is stale and must be cleared.
        onMaterial1Change: function () {
            this.getView().getModel("novehForm").setProperty("/CONTRACT1", "");
        },

        /* ═══════════════════════════════════════════
           SALES CONTRACT VALUE HELP  (NO_VEH_CONTRACT.VBELN1)
           GetOrderIdSet keyed by customer + material(s). ORDER_NO = contract.
        ═══════════════════════════════════════════ */
        onSalesContractSearch: function () {
            var oUserInfo = UserInfo.getLoginInfo();
            var oForm     = this.getView().getModel("novehForm");
            var sKunnr    = oForm.getProperty("/KUNNR");

            if (!sKunnr) {
                MessageBox.error("Please select the customer first.");
                return;
            }

            if (!this._oContractDialog) {
                this._oContractDialog = new SelectDialog({
                    title: "Select Sales Contract",
                    confirm: function (oEv) {
                        var oItem = oEv.getParameter("selectedItem");
                        if (!oItem) { return; }
                        this.getView().getModel("novehForm")
                            .setProperty("/CONTRACT1", oItem.getTitle());
                    }.bind(this),
                    search: function (oEv) {
                        var sVal     = oEv.getParameter("value");
                        var oBinding = oEv.getSource().getBinding("items");
                        oBinding.filter(sVal
                            ? [new Filter("ORDER_NO", FilterOperator.Contains, sVal)]
                            : []);
                    }
                });
                this.getView().addDependent(this._oContractDialog);
            }

            var aFilters = [
                new Filter("KUNNR",        FilterOperator.EQ, sKunnr),
                new Filter("CUST_USER_ID", FilterOperator.EQ, oUserInfo.userId),
                new Filter("SMTP_ADDR",    FilterOperator.EQ, oUserInfo.email)
            ];
            var sMatnr1 = oForm.getProperty("/MATNR1");
            if (sMatnr1) { aFilters.push(new Filter("MATNR1", FilterOperator.EQ, sMatnr1)); }

            this._oContractDialog.bindAggregation("items", {
                model:    "withoutvehModel",
                path:     "/GetOrderIdSet",
                filters:  aFilters,
                template: new StandardListItem({
                    // title stays ORDER_NO - confirm() reads getTitle() for CONTRACT1
                    title:       "{withoutvehModel>ORDER_NO}",
                    // product name + contract ordered qty + shipping conditions
                    description: {
                        parts: [
                            "withoutvehModel>MATNR1_DESC",
                            "withoutvehModel>CON_ORD_QTY1",
                            "withoutvehModel>CON_UOM1",
                            "withoutvehModel>VSBED"
                        ],
                        formatter: function (sDesc, sOrd, sUom, sVsbed) {
                            var aParts = [];
                            if (sDesc) { aParts.push(sDesc); }
                            if (sOrd)  { aParts.push("Contract " + sOrd + (sUom ? " " + sUom : "")); }
                            if (sVsbed) { aParts.push(sVsbed); }
                            return aParts.join("  ·  ");
                        }
                    },
                    // remaining available balance, right-aligned
                    info: {
                        parts: ["withoutvehModel>CON_AVL_QTY1", "withoutvehModel>CON_UOM1"],
                        formatter: function (sAvl, sUom) {
                            return sAvl ? ("Avail " + sAvl + (sUom ? " " + sUom : "")) : "";
                        }
                    },
                    infoState: "Success"
                })
            });
            this._oContractDialog.open();
        },

        /* ═══════════════════════════════════════════
           TRANSPORTER GSTIN VALUE HELP  (GSTN.TPT_GSTN)
        ═══════════════════════════════════════════ */
        onTransporterSearch: function () {
            var oUserInfo = UserInfo.getLoginInfo();

            if (!this._oTptDialog) {
                this._oTptDialog = new SelectDialog({
                    title: "Select Transporter GSTIN",
                    confirm: function (oEv) {
                        var oItem = oEv.getParameter("selectedItem");
                        if (!oItem) { return; }
                        this.getView().getModel("novehForm")
                            .setProperty("/TPT_GSTN", oItem.getTitle());
                    }.bind(this),
                    search: function (oEv) {
                        var sVal     = oEv.getParameter("value");
                        var oBinding = oEv.getSource().getBinding("items");
                        oBinding.filter(sVal
                            ? [new Filter({
                                filters: [
                                    new Filter("TPT_GSTN", FilterOperator.Contains, sVal),
                                    new Filter("NAME",     FilterOperator.Contains, sVal)
                                ],
                                and: false
                            })]
                            : []);
                    }
                });
                this.getView().addDependent(this._oTptDialog);
            }

            this._oTptDialog.bindAggregation("items", {
                model:    "withoutvehModel",
                path:     "/GetTransGSTINSet",
                filters:  [
                    new Filter("CUST_USER_ID", FilterOperator.EQ, oUserInfo.userId),
                    new Filter("SMTP_ADDR",    FilterOperator.EQ, oUserInfo.email)
                ],
                template: new StandardListItem({
                    title:       "{withoutvehModel>TPT_GSTN}",
                    description:  "{withoutvehModel>NAME}"
                })
            });
            this._oTptDialog.open();
        },

        /* ═══════════════════════════════════════════
           GET OPEN INDENTS  (TBL_INDENTS refresh)
           Requires a customer (open indents are shown per customer).
        ═══════════════════════════════════════════ */
        onGetOpenIndents: function () {
            var oUserInfo = UserInfo.getLoginInfo();
            var oForm     = this.getView().getModel("novehForm");
            var sKunnr    = oForm.getProperty("/KUNNR");

            if (!sKunnr) {
                MessageBox.error("Please select a Customer.");
                return;
            }

            var aFilters = [
                new Filter("KUNNR",        FilterOperator.EQ, sKunnr),
                new Filter("CUST_USER_ID", FilterOperator.EQ, oUserInfo.userId),
                new Filter("SMTP_ADDR",    FilterOperator.EQ, oUserInfo.email)
            ];

            this.getView().byId("novehScrollContainer").setBusy(true);
            this._getModel().read("/GetOpenIndentsSet", {
                filters: aFilters,
                success: function (oData) {
                    this.getView().getModel("novehTable")
                        .setProperty("/results", (oData && oData.results) || []);
                    this.getView().byId("novehScrollContainer").setBusy(false);
                }.bind(this),
                error: function (oErr) {
                    this.getView().byId("novehScrollContainer").setBusy(false);
                    MessageBox.error(this._extractError(oErr, "Failed to load open indents."));
                }.bind(this)
            });
        },

        /* ═══════════════════════════════════════════
           SAVE DATA  (BTN_SAVE_DATA → SAVE_NOV_VEH_INDENT)
           Create a new indent on GetOpenIndentsSet.
        ═══════════════════════════════════════════ */
        onSaveData: function () {
            var oForm = this.getView().getModel("novehForm");
            var oData = oForm.getData();

            if (!oData.BEGDA) {
                MessageBox.error("Please select a Loading Date.");
                return;
            }
            if (!oData.KUNNR) {
                MessageBox.error("Please select a Customer.");
                return;
            }
            if (!oData.MATNR1) {
                MessageBox.error("Please select Material 1.");
                return;
            }
            if (!oData.QUANTITY1) {
                MessageBox.error("Please enter Quantity 1.");
                return;
            }
            if (oData.ACTIVE2 === "X" && oData.MATNR2 && !oData.QUANTITY2) {
                MessageBox.error("Please enter Quantity 2.");
                return;
            }

            var oUserInfo = UserInfo.getLoginInfo();
            var oPayload = {
                KUNNR:        oData.KUNNR,
                KUNNR_DESC:   oData.KUNNR_DESC,
                BEGDA:        oData.BEGDA,
                CONTRACT1:    oData.CONTRACT1 || "",
                MATNR1:       oData.MATNR1,
                QUANTITY1:    oData.QUANTITY1 || "0",
                MATNR2:       oData.MATNR2 || "",
                QUANTITY2:    oData.QUANTITY2 || "0",
                TPT_GSTN:     oData.TPT_GSTN || "",
                ROW_TYPE:     "",   // blank = new (place) row
                ORDER_NO:     "",
                CUST_USER_ID: oUserInfo.userId,
                SMTP_ADDR:    oUserInfo.email
            };

            this.getView().byId("novehSaveBtn").setBusy(true);
            this._getModel().create("/GetOpenIndentsSet", oPayload, {
                success: function (oResp) {
                    this.getView().byId("novehSaveBtn").setBusy(false);
                    if (oResp && oResp.ERROR) {
                        MessageBox.error(oResp.ERROR, { title: "Indent not saved" });
                        return;
                    }
                    var sOrder = (oResp && oResp.ORDER_NO) ? " Order No: " + oResp.ORDER_NO : "";
                    MessageBox.success("Indent saved successfully." + sOrder);
                    // refresh the open-indents grid for the just-saved customer
                    // BEFORE resetting the form - onGetOpenIndents reads KUNNR from
                    // the form, and _resetForm() blanks it (which otherwise triggers
                    // a spurious "Please select a Customer." right after a save).
                    this.onGetOpenIndents();
                    this._resetForm();
                }.bind(this),
                error: function (oErr) {
                    this.getView().byId("novehSaveBtn").setBusy(false);
                    MessageBox.error(this._extractError(oErr, "Failed to save indent."));
                }.bind(this)
            });
        },

        /* ═══════════════════════════════════════════
           DELETE ORDER  (BTN_DELETE_ORDER → REACT_TO_DEL_ORDER)
        ═══════════════════════════════════════════ */
        onDeleteOrder: function () {
            var aRows = this._getSelectedRows();
            if (!aRows.length) {
                MessageBox.error("Please select the order(s) to be deleted.");
                return;
            }

            MessageBox.confirm("Delete " + aRows.length + " selected order(s)?", {
                title: "Confirm Delete",
                actions: [MessageBox.Action.DELETE, MessageBox.Action.CANCEL],
                emphasizedAction: MessageBox.Action.DELETE,
                onClose: function (sAction) {
                    if (sAction !== MessageBox.Action.DELETE) { return; }
                    this._processRows(aRows, "delete", "Order(s) deleted successfully.");
                }.bind(this)
            });
        },

        /* ═══════════════════════════════════════════
           CLOSE ORDER  (BTN_CLOSE_ORDER → REACT_TO_CLOSE_ORDER)
           Short-close: update the row with ROW_TYPE = 'C'.
        ═══════════════════════════════════════════ */
        onCloseOrder: function () {
            var aRows = this._getSelectedRows();
            if (!aRows.length) {
                MessageBox.error("Please select the order(s) to be closed.");
                return;
            }

            MessageBox.confirm("Close " + aRows.length + " selected order(s)?", {
                title: "Confirm Close",
                actions: [MessageBox.Action.OK, MessageBox.Action.CANCEL],
                emphasizedAction: MessageBox.Action.OK,
                onClose: function (sAction) {
                    if (sAction !== MessageBox.Action.OK) { return; }
                    this._processRows(aRows, "close", "Order(s) closed successfully.");
                }.bind(this)
            });
        },

        /* ═══════════════════════════════════════════
           HELPERS
        ═══════════════════════════════════════════ */
        _getSelectedRows: function () {
            var oTable = this.byId("novehIndentTable");
            return oTable.getSelectedItems().map(function (oItem) {
                return oItem.getBindingContext("novehTable").getObject();
            });
        },

        _keyPath: function (oRow) {
            return "/GetOpenIndentsSet(KUNNR='" + encodeURIComponent(oRow.KUNNR) +
                   "',ORDER_NO='" + encodeURIComponent(oRow.ORDER_NO) + "')";
        },

        // Run delete/close over the selected rows, then report once and refresh.
        _processRows: function (aRows, sMode, sOkMsg) {
            var oModel   = this._getModel();
            var oUserInfo = UserInfo.getLoginInfo();
            var iTotal   = aRows.length;
            var iDone    = 0;
            var aErrors  = [];
            var that     = this;

            var fnFinish = function () {
                if (iDone < iTotal) { return; }
                if (aErrors.length) {
                    MessageBox.error(aErrors.length + " of " + iTotal +
                        " failed:\n" + aErrors.join("\n"));
                } else {
                    MessageToast.show(sOkMsg);
                }
                that.onGetOpenIndents();
            };

            var fnErr = function (oRow) {
                return function (oErr) {
                    iDone++;
                    aErrors.push("Order " + oRow.ORDER_NO + ": " +
                        that._extractError(oErr, "operation failed."));
                    fnFinish();
                };
            };
            var fnOk = function () {
                iDone++;
                fnFinish();
            };

            aRows.forEach(function (oRow) {
                var sPath = that._keyPath(oRow);
                if (sMode === "delete") {
                    oModel.remove(sPath, { success: fnOk, error: fnErr(oRow) });
                } else {
                    // short-close: ROW_TYPE = 'C'
                    var oPayload = {
                        KUNNR:        oRow.KUNNR,
                        ORDER_NO:     oRow.ORDER_NO,
                        ROW_TYPE:     "C",
                        CUST_USER_ID: oUserInfo.userId,
                        SMTP_ADDR:    oUserInfo.email
                    };
                    oModel.update(sPath, oPayload, { success: fnOk, error: fnErr(oRow) });
                }
            });
        },

        _extractError: function (oErr, sFallback) {
            try {
                if (oErr && oErr.responseText) {
                    var o = JSON.parse(oErr.responseText);
                    if (o.error && o.error.message && o.error.message.value) {
                        return o.error.message.value;
                    }
                }
            } catch (e) { /* ignore */ }
            return sFallback;
        }

    });
});
