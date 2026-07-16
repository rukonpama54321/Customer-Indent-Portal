sap.ui.define([
    "sap/ui/core/mvc/Controller",
    "sap/ui/core/UIComponent",
    "sap/ui/model/Filter",
    "sap/ui/model/FilterOperator",
    "sap/ui/model/Sorter",
    "sap/ui/model/json/JSONModel",
    "sap/m/SelectDialog",
    "sap/m/StandardListItem",
    "sap/m/GroupHeaderListItem",
    "sap/m/MessageBox",
    "sap/m/MessageToast",
    "sap/ui/core/BusyIndicator",
    "customerindent/util/formatter",
    "customerindent/util/UserInfo"
], function (Controller, UIComponent, Filter, FilterOperator, Sorter, JSONModel,
             SelectDialog, StandardListItem, GroupHeaderListItem, MessageBox, MessageToast, BusyIndicator, formatter, UserInfo) {
    "use strict";

    // Compartment field id helpers
    var COMP_PRODUCT = function (i) { return "comp" + i + "Product"; };
    var COMP_QTY = function (i) { return "comp" + i + "Qty"; };

    return Controller.extend("customerindent.controller.WithVehicleTab", {

        formatter: formatter,

        /* ════════════════════════════════════════════════════════════
           INIT  (WebDynpro: WDDOINIT)
           - default loading date = today
           - load the user's mapped customers (ZSD_CUST_USR_MAP -> ZUSERSet)
           - keep compartments / flushing / save disabled until a vehicle
             has been executed
        ════════════════════════════════════════════════════════════ */
        onInit: function () {
            this._login = this._getLoginInfo();

            // Default loading date to today (sy-datum in WDDOINIT)
            var oDate = this.byId("loadingDatePicker");
            if (oDate) {
                oDate.setDateValue(new Date());
            }

            // Saved-indents report has its own date filter — default it to today too
            var oFilterDate = this.byId("filterDate");
            if (oFilterDate) {
                oFilterDate.setDateValue(new Date());
            }

            this._resetCompartments();

            // Initial load: populate the Saved Indents table with the indents
            // already created for the customers mapped to this user. The date
            // filter now holds today's value and _userFilters() scopes the read
            // to CUST_USER_ID / SMTP_ADDR, so a plain onGetIndents() fetches
            // exactly this user's indents without any manual Search.
            if (oFilterDate && oFilterDate.getValue()) {
                this.onGetIndents();
            }
            // Customers are NOT preloaded here. Like the Without-Vehicle tab,
            // the customer list is fetched on demand the first time the value
            // help opens (onCustomerSearch), so a page reload does not fire a
            // /ZUSERSet read.

            // The Change Indent screen is a separate routed page; on return the
            // main view (and this tab) is retained but nothing re-queries
            // GETINDENTSet, so the edited row would still show its pre-change
            // values. ChangeIndentWithVehicleTab publishes "indent/changed" on a
            // successful update — re-run the search so the list reflects the DB.
            this.getOwnerComponent().getEventBus()
                .subscribe("indent", "changed", this._onIndentChanged, this);
        },

        _onIndentChanged: function () {
            // onGetIndents errors without a date; the retained view still holds
            // the user's last filter, so only refresh when a date is present.
            var oDate = this.byId("filterDate");
            if (oDate && oDate.getValue()) {
                this.onGetIndents();
            }
        },

        onExit: function () {
            this.getOwnerComponent().getEventBus()
                .unsubscribe("indent", "changed", this._onIndentChanged, this);
        },

        // Delegate to the shared UserInfo helper, which falls back to the
        // known portal user when the launchpad shell is absent (standalone
        // `npm start`, sap.ushell.Container undefined). The previous inline
        // version returned empty strings there, so _userFilters() sent no
        // CUST_USER_ID / SMTP_ADDR and Search silently found nothing.
        _getLoginInfo: function () {
            return UserInfo.getLoginInfo();
        },

        _getModel: function () {
            return this.getOwnerComponent().getModel();
        },

        _toYyyymmdd: function (sDdMmYyyy) {
            if (!sDdMmYyyy) { return ""; }
            var a = sDdMmYyyy.split(".");
            return a.length === 3 ? (a[2] + a[1] + a[0]) : sDdMmYyyy;
        },

        // SaveIndent/IndentUpdate BEGDA deserializes into an ABAP DATS field,
        // so the create/update BODY must be ISO (YYYY-MM-DD) or the id
        // transform dumps (CX_SY_CONVERSION_NO_DATE_TIME). $filter reads keep
        // the compressed YYYYMMDD form.
        _toIsoDate: function (sDdMmYyyy) {
            if (!sDdMmYyyy) { return ""; }
            var a = sDdMmYyyy.split(".");
            return a.length === 3 ? (a[2] + "-" + a[1] + "-" + a[0]) : sDdMmYyyy;
        },

        // Filter pair used everywhere: current user id + email (OR-combined)
        _userFilters: function () {
            var a = [];
            if (this._login.userId) {
                a.push(new Filter("CUST_USER_ID", FilterOperator.EQ, this._login.userId));
            }
            if (this._login.email) {
                a.push(new Filter("SMTP_ADDR", FilterOperator.EQ, this._login.email));
            }
            return a;
        },

        /* ════════════════════════════════════════════════════════════
           DATE VALIDATION
        ════════════════════════════════════════════════════════════ */
        onDateChange: function (oEvent) {
            var oDP = oEvent.getSource();
            var sValue = oEvent.getParameter("value");
            var rDate = /^(0[1-9]|[12][0-9]|3[01])\.(0[1-9]|1[0-2])\.(19|20)\d\d$/;
            if (!rDate.test(sValue)) {
                oDP.setValueState("Error");
                oDP.setValueStateText("Please enter date in format dd.MM.yyyy");
            } else {
                oDP.setValueState("None");
                oDP.setValueStateText("");
            }
        },

        _isValidLoadingDate: function () {
            var oDP = this.byId("loadingDatePicker");
            var sValue = oDP.getValue();
            if (!sValue || oDP.getValueState() === "Error") {
                oDP.setValueState("Error");
                oDP.setValueStateText("Please enter a valid loading date");
                MessageBox.error("Please enter a valid loading date.");
                return false;
            }
            oDP.setValueState("None");
            return true;
        },

        /* ════════════════════════════════════════════════════════════
           VEHICLE DATA  (shared by value-help dialog + type-ahead)
           - loads VehicleSet once, caches in _aVehicleData
           - exposes it as a view-level JSON model "veh" so both the
             SelectDialog items and the Input suggestionItems bind to it
        ════════════════════════════════════════════════════════════ */
        _ensureVehicleData: function (fnDone, fnFail) {
            var that = this;
            if (this._aVehicleData) {
                if (fnDone) { fnDone(this._aVehicleData); }
                return;
            }
            // VehicleSet is a large read; show the global loading wheel while
            // it is in flight so the value-help / type-ahead wait is visible.
            BusyIndicator.show(0);
            this._getModel().read("/VehicleSet", {
                success: function (oData) {
                    that._aVehicleData = (oData.results || []).sort(function (a, b) {
                        return (a.TU_NUMBER || "").localeCompare(b.TU_NUMBER || "");
                    });
                    var oVehModel = that.getView().getModel("veh");
                    if (!oVehModel) {
                        oVehModel = new JSONModel();
                        that.getView().setModel(oVehModel, "veh");
                    }
                    oVehModel.setData({ results: that._aVehicleData });
                    BusyIndicator.hide();
                    if (fnDone) { fnDone(that._aVehicleData); }
                },
                error: function () {
                    BusyIndicator.hide();
                    MessageToast.show("Failed to load vehicle list");
                    if (fnFail) { fnFail(); }
                }
            });
        },

        /* ════════════════════════════════════════════════════════════
           VEHICLE TYPE-AHEAD  (HEADER vehicle + filter vehicle)
           - lazy-loads the list on first keystroke, then lets the Input
             filter suggestionItems itself; full dialog stays available
             via the value-help icon
        ════════════════════════════════════════════════════════════ */
        onVehicleSuggest: function (oEvent) {
            // First time a user types, the cache is empty: load it so the
            // next keystroke (or re-render) has suggestions to filter.
            if (!this._aVehicleData) {
                this._ensureVehicleData();
            }
        },

        onVehicleSuggestionSelected: function (oEvent) {
            var oInput = oEvent.getSource();
            var oItem = oEvent.getParameter("selectedItem");
            if (!oItem) { return; }
            oInput.setValue(oItem.getText());
            // Selecting the header vehicle triggers GET_VEHICLE
            if (oInput === this.byId("vehicleInput")) {
                this.onGetVehicle();
            }
        },

        /* ════════════════════════════════════════════════════════════
           VEHICLE VALUE HELP  (HEADER vehicle + filter vehicle)
        ════════════════════════════════════════════════════════════ */
        onVehicleValueHelp: function (oEvent) {
            var that = this;
            this._oLastVehicleInput = oEvent.getSource();

            var fnApply = function (sQuery) {
                var s = (sQuery || "").toLowerCase();
                var aAll = that._aVehicleData || [];
                var aRes = s ? aAll.filter(function (o) {
                    return (o.TU_NUMBER && o.TU_NUMBER.toLowerCase().indexOf(s) !== -1) ||
                           (o.TU_TEXT && o.TU_TEXT.toLowerCase().indexOf(s) !== -1);
                }) : aAll;
                var oModel = that._oVehicleDialog.getModel("veh");
                if (oModel) { oModel.setProperty("/results", aRes); }
            };

            if (!this._oVehicleDialog) {
                this._oVehicleDialog = new SelectDialog({
                    title: "Select Vehicle",
                    multiSelect: false,
                    growing: true,
                    growingThreshold: 100,
                    rememberSelections: false,
                    liveChange: function (e) { fnApply((e.getParameter("value") || "").trim()); },
                    search: function (e) { fnApply((e.getParameter("value") || "").trim()); },
                    confirm: function (e) {
                        var oItem = e.getParameter("selectedItem");
                        if (oItem && that._oLastVehicleInput) {
                            var oCtx = oItem.getBindingContext("veh");
                            var sVeh = oCtx ? oCtx.getProperty("TU_NUMBER") : oItem.getTitle();
                            that._oLastVehicleInput.setValue(sVeh);
                            // Selecting the header vehicle triggers GET_VEHICLE
                            if (that._oLastVehicleInput === that.byId("vehicleInput")) {
                                that.onGetVehicle();
                            }
                        }
                        fnApply("");
                    },
                    cancel: function () { fnApply(""); }
                });
                this._oVehicleDialog.bindAggregation("items", {
                    path: "veh>/results",
                    sorter: new Sorter("TU_TEXT", false, true),   // group by vehicle type
                    groupHeaderFactory: function (oGroup) {
                        return new GroupHeaderListItem({
                            title: oGroup.key,
                            upperCase: true
                        }).addStyleClass("ciVehTypeHeader");
                    },
                    template: new StandardListItem({
                        title: "{veh>TU_NUMBER}",
                        description: "{veh>TU_TEXT}",
                        info: "{veh>STATUS}",
                        infoState: "{= ${veh>STATUS} === 'Valid' ? 'Success' : 'Error' }"
                    }),
                    templateShareable: false
                });
                this.getView().addDependent(this._oVehicleDialog);
            }

            this._ensureVehicleData(function (aData) {
                // The dialog gets its own model copy so its in-place
                // filtering never shrinks the shared type-ahead list.
                if (!that._bVehDlgModelSet) {
                    that._oVehicleDialog.setModel(new JSONModel({ results: aData.slice() }), "veh");
                    that._bVehDlgModelSet = true;
                }
                fnApply("");
                that._oVehicleDialog.open();
            });
        },

        /* ════════════════════════════════════════════════════════════
           GET_VEHICLE  (WebDynpro: ONACTIONGET_VEHICLE)
           1. license check  -> CheckLicenseSet (Z_CHECK_VEHICLE_LICENSE)
           2. compartments   -> GETCompartmentNoSet (Z_GET_COMP_CAPACITY + OIGCC)
              -> populate qty (capacity), enable products/qty per compartment,
                 enable ATF flushing only for ATF vehicles, enable Save.
        ════════════════════════════════════════════════════════════ */
        onGetVehicle: function () {
            var that = this;
            var sVehicle = this.byId("vehicleInput").getValue().trim();

            // reset dependent fields (end use / compartments) on every execute
            this.byId("endUseSelect").setValue("");
            this._resetCompartments();

            if (!sVehicle) {
                MessageBox.error("Please enter a Vehicle.");
                return;
            }
            if (!this._isValidLoadingDate()) { return; }

            var aFilter = [new Filter("VEHICLE", FilterOperator.EQ, sVehicle)];

            // 1) License check (errors are fatal — abort, like WebDynpro)
            this._getModel().read("/CheckLicenseSet", {
                filters: aFilter,
                success: function (oData) {
                    if (!oData.results || oData.results.length === 0) {
                        MessageBox.warning("Invalid vehicle no: " + sVehicle);
                        return;
                    }
                    var oRow = oData.results[0];
                    var aMsg = [];
                    for (var i = 1; i <= 14; i++) {
                        if (oRow["MESSAGE" + i]) { aMsg.push(oRow["MESSAGE" + i]); }
                    }
                    if (aMsg.length > 0) {
                        MessageBox.error(aMsg.join("\n"), { title: "License Check Failed" });
                        return;
                    }
                    // 2) License OK -> load compartments
                    that._loadCompartments(sVehicle, aFilter);
                },
                error: function (oErr) {
                    MessageBox.error(that._extractError(oErr, "Error while checking vehicle license."));
                }
            });
        },

        _loadCompartments: function (sVehicle, aFilter) {
            var that = this;
            this._getModel().read("/GETCompartmentNoSet", {
                filters: aFilter,
                success: function (oData) {
                    var aComp = (oData && oData.results) ? oData.results : [];
                    var sVehType = "";

                    aComp.forEach(function (oComp) {
                        var iNo = parseInt(oComp.COM_NUMBER, 10);
                        if (isNaN(iNo) || iNo < 1 || iNo > 8) { return; }
                        sVehType = oComp.VEH_TYPE || sVehType;

                        var oProd = that.byId(COMP_PRODUCT(iNo));
                        var oQty = that.byId(COMP_QTY(iNo));
                        if (oProd) { oProd.setEditable(true); }
                        if (oQty) {
                            oQty.setValue((oComp.COMPOSITION || "").toString().trim());
                            oQty.setEditable(oComp.COMP_ENABLED === "X");
                            // M13: show the derived KL/KG unit beside the qty so the
                            // magnitude is unambiguous (WebDynpro shows capacity + suffix).
                            var sUom = (oComp.UOM || "").toString().trim();
                            oQty.setDescription(sUom);
                            oQty.setFieldWidth(sUom ? "70%" : "100%");
                        }
                    });

                    var bHasComp = aComp.length > 0;
                    that.byId("masterProductSelect").setEditable(bHasComp);
                    that.byId("masterQty").setEditable(bHasComp);

                    // ATF flushing is only relevant for ATF tankers
                    that._sVehType = sVehType;
                    var bAtf = sVehType === "ATF";
                    that.byId("flushingSelect").setEnabled(bAtf);
                    if (!bAtf) {
                        that.byId("flushingSelect").setSelectedKey("");
                        that.byId("flushingReasonSelect").setEnabled(false).setValue("");
                    }

                    that.byId("saveIndentBtn").setEnabled(bHasComp);

                    if (bHasComp) {
                        MessageToast.show("Vehicle " + sVehicle + " is valid.");
                    } else {
                        MessageBox.warning("No compartments found for vehicle " + sVehicle);
                    }
                },
                error: function () {
                    MessageBox.error("Failed to load compartments for vehicle " + sVehicle);
                }
            });
        },

        _resetCompartments: function () {
            for (var i = 1; i <= 8; i++) {
                var oProd = this.byId(COMP_PRODUCT(i));
                var oQty = this.byId(COMP_QTY(i));
                if (oProd) { oProd.setValue("").setEditable(false); }
                if (oQty) {
                    oQty.setValue("").setEditable(false);
                    oQty.setDescription("").setFieldWidth("100%"); // M13: clear stale KL/KG unit
                }
            }
            var oMP = this.byId("masterProductSelect");
            var oMQ = this.byId("masterQty");
            if (oMP) { oMP.setValue("").setEditable(false); }
            if (oMQ) { oMQ.setValue("").setEditable(false); }
            var oFlush = this.byId("flushingSelect");
            if (oFlush) { oFlush.setSelectedKey("").setEnabled(false); }
            var oReason = this.byId("flushingReasonSelect");
            if (oReason) { oReason.setValue("").setEnabled(false); }
            var oSave = this.byId("saveIndentBtn");
            if (oSave) { oSave.setEnabled(false); }
        },

        /* ════════════════════════════════════════════════════════════
           CUSTOMER VALUE HELP  (HEADER_DATA.KUNNR / NAME1)
           GSTN field becomes editable for DI/EX customers (GSTIN_ENABLE = X)
        ════════════════════════════════════════════════════════════ */
        onCustomerSearch: function () {
            var that = this;

            var fnApply = function (sQuery) {
                var aAll = that._aCustomerData || [];
                var aRes = sQuery ? aAll.filter(function (o) {
                    return (o.KUNNR && o.KUNNR.indexOf(sQuery) !== -1) ||
                           (o.NAME1 && o.NAME1.toLowerCase().indexOf(sQuery.toLowerCase()) !== -1);
                }) : aAll;
                that._oCustomerDialog.getModel("cust").setProperty("/results", aRes);
            };

            if (!this._oCustomerDialog) {
                this._oCustomerDialog = new SelectDialog({
                    title: "Select Customer",
                    search: function (e) { fnApply((e.getParameter("value") || "").trim()); },
                    liveChange: function (e) { fnApply((e.getParameter("value") || "").trim()); },
                    confirm: function (e) {
                        var oItem = e.getParameter("selectedItem");
                        if (oItem) {
                            var oCtx = oItem.getBindingContext("cust").getObject();
                            that.byId("customerSelect").setValue(oCtx.NAME1);
                            that._sSelectedCustomerId = oCtx.KUNNR;
                            that._sSelectedKdgrp = oCtx.KDGRP;
                            that._applyGstinEnable(oCtx);
                        }
                        fnApply("");
                    },
                    cancel: function () { fnApply(""); }
                });
                this._oCustomerDialog.bindAggregation("items", {
                    path: "cust>/results",
                    template: new StandardListItem({ title: "{cust>NAME1}", description: "{cust>KUNNR}" }),
                    templateShareable: false
                });
                this.getView().addDependent(this._oCustomerDialog);
            }

            if (!this._aCustomerData) {
                this._getModel().read("/ZUSERSet", {
                    filters: this._userFilters(),
                    and: false,
                    success: function (oData) {
                        that._aCustomerData = oData.results || [];
                        that._oCustomerDialog.setModel(new JSONModel({ results: that._aCustomerData }), "cust");
                        that._oCustomerDialog.open();
                    },
                    error: function () { MessageToast.show("Failed to load customer data"); }
                });
            } else {
                if (!this._oCustomerDialog.getModel("cust")) {
                    this._oCustomerDialog.setModel(new JSONModel({ results: this._aCustomerData }), "cust");
                }
                fnApply("");
                this._oCustomerDialog.open();
            }
        },

        // GSTN editable only for DI/EX customers (WebDynpro ET1)
        _applyGstinEnable: function (oCust) {
            var bEnable = oCust.GSTIN_ENABLE === "X" ||
                          oCust.KDGRP === "DI" || oCust.KDGRP === "EX";
            var oGstn = this.byId("transporterSelect");
            oGstn.setEditable(bEnable);
            if (!bEnable) { oGstn.setValue(""); }
        },

        /* ════════════════════════════════════════════════════════════
           COMPARTMENT PRODUCT VALUE HELP  (PROD1-8 / master)
        ════════════════════════════════════════════════════════════ */
        onCompProductSearch: function (oEvent) {
            var that = this;
            this._oLastProductInput = oEvent.getSource();
            var sVehicle = this.byId("vehicleInput").getValue();

            var fnApply = function (sQuery) {
                var aAll = that._aProductData || [];
                var aRes = sQuery ? aAll.filter(function (o) {
                    return o.PRODUCT && o.PRODUCT.toLowerCase().indexOf(sQuery.toLowerCase()) !== -1;
                }) : aAll;
                that._oProductDialog.getModel("prod").setProperty("/results", aRes);
            };

            if (!this._oProductDialog) {
                this._oProductDialog = new SelectDialog({
                    title: "Select Product",
                    search: function (e) { fnApply((e.getParameter("value") || "").trim()); },
                    liveChange: function (e) { fnApply((e.getParameter("value") || "").trim()); },
                    confirm: function (e) {
                        var oItem = e.getParameter("selectedItem");
                        if (oItem && that._oLastProductInput) {
                            that._oLastProductInput.setValue(oItem.getTitle());
                        }
                        fnApply("");
                    },
                    cancel: function () { fnApply(""); }
                });
                this._oProductDialog.bindAggregation("items", {
                    path: "prod>/results",
                    template: new StandardListItem({ title: "{prod>PRODUCT}" }),
                    templateShareable: false
                });
                this.getView().addDependent(this._oProductDialog);
            }

            var aFilters = [];
            if (sVehicle) { aFilters.push(new Filter("VEHICLE", FilterOperator.EQ, sVehicle)); }
            aFilters = aFilters.concat(this._userFilters());

            this._getModel().read("/GETProductSet", {
                filters: aFilters,
                and: true,
                success: function (oData) {
                    that._aProductData = oData.results || [];
                    that._oProductDialog.setModel(new JSONModel({ results: that._aProductData }), "prod");
                    that._oProductDialog.open();
                },
                error: function () { MessageToast.show("Failed to load product data"); }
            });
        },

        // Fill-all: copy master product/qty into every enabled compartment
        onFillAllProducts: function () {
            var sProduct = this.byId("masterProductSelect").getValue();
            var sQty = this.byId("masterQty").getValue();
            for (var i = 1; i <= 8; i++) {
                var oProd = this.byId(COMP_PRODUCT(i));
                var oQty = this.byId(COMP_QTY(i));
                if (oProd && oProd.getEditable()) { oProd.setValue(sProduct); }
                if (oQty && oQty.getEditable()) { oQty.setValue(sQty); }
            }
        },

        /* ════════════════════════════════════════════════════════════
           SALES CONTRACT VALUE HELP  (EXPORT.VBELN)
        ════════════════════════════════════════════════════════════ */
        onSalesContractSearch: function () {
            var that = this;

            // WebDynpro ONACTIONSELECT_EXPORT requires a customer first; the
            // contract list is keyed off the customer + the chosen products.
            if (!this._sSelectedCustomerId) {
                MessageBox.error("Please select the customer first.");
                return;
            }

            // Keep the $filter a FLAT conjunction of simple EQ comparisons.
            // A nested OR group (as _userFilters() produces) makes SAP Gateway's
            // GET_FILTER_SELECT_OPTIONS( ) return an empty table, so the backend
            // reads no KUNNR/PRODUCT1 and the contract list comes back empty.
            // The backend only needs CUST_USER_ID here (not SMTP_ADDR).
            var aFilters = [];
            if (this._login.userId) {
                aFilters.push(new Filter("CUST_USER_ID", FilterOperator.EQ, this._login.userId));
            }
            aFilters.push(new Filter("KUNNR", FilterOperator.EQ,
                ("" + this._sSelectedCustomerId).padStart(10, "0")));
            for (var i = 1; i <= 8; i++) {
                var sProd = (this.byId("comp" + i + "Product").getValue() || "").trim();
                if (sProd) { aFilters.push(new Filter("PRODUCT" + i, FilterOperator.EQ, sProd)); }
            }

            this._getModel().read("/SalesContractSet", {
                filters: aFilters,
                and: true,
                success: function (oData) {
                    var aItems = (oData && oData.results) ? oData.results : [];
                    var oJson = new JSONModel({ items: aItems });

                    if (!that._oSalesDialog) {
                        that._oSalesDialog = new SelectDialog({
                            title: "Select Sales Contract",
                            search: function (e) {
                                var s = (e.getParameter("value") || "").toUpperCase();
                                e.getSource().getItems().forEach(function (oItem) {
                                    var oCtx = oItem.getBindingContext("sc");
                                    if (!oCtx) { return; }
                                    var sText = (oCtx.getProperty("TEXT") || "").toUpperCase();
                                    var sDesc = (oCtx.getProperty("DESC") || "").toUpperCase();
                                    oItem.setVisible(!s || sText.indexOf(s) !== -1 || sDesc.indexOf(s) !== -1);
                                });
                            },
                            confirm: function (e) {
                                var oItem = e.getParameter("selectedItem");
                                if (oItem) {
                                    var oCtx = oItem.getBindingContext("sc").getObject();
                                    that.byId("salesContractSelect").setValue(oCtx.TEXT || "");
                                    that._oSelectedContract = oCtx;
                                }
                            }
                        });
                        that._oSalesDialog.bindAggregation("items", {
                            path: "sc>/items",
                            template: new StandardListItem({ title: "{sc>TEXT}", description: "{sc>DESC}" }),
                            templateShareable: false
                        });
                        that.getView().addDependent(that._oSalesDialog);
                    }
                    that._oSalesDialog.setModel(oJson, "sc");
                    that._oSalesDialog.open();
                },
                error: function () { MessageToast.show("Failed to load Sales Contract data"); }
            });
        },

        /* ════════════════════════════════════════════════════════════
           TRANSPORTER GSTN VALUE HELP  (GSTN.TPT_GSTN)
        ════════════════════════════════════════════════════════════ */
        onTransporterSearch: function (oEvent) {
            var that = this;
            var oInput = oEvent.getSource();

            if (!this._oGstnDialog) {
                this._oGstnDialog = new SelectDialog({
                    title: "Select Transporter GSTN",
                    multiSelect: false,
                    liveChange: function (e) {
                        var s = (e.getParameter("value") || "").trim();
                        var oBinding = e.getSource().getBinding("items");
                        oBinding.filter(s ? [new Filter({
                            path: "GSTIN", operator: FilterOperator.Contains, value1: s, caseSensitive: false
                        })] : []);
                    },
                    confirm: function (e) {
                        var oItem = e.getParameter("selectedItem");
                        if (oItem) { oInput.setValue(oItem.getTitle()); }
                        e.getSource().getBinding("items").filter([]);
                    },
                    cancel: function (e) { e.getSource().getBinding("items").filter([]); }
                });
                this._oGstnDialog.bindAggregation("items", {
                    path: "gstn>/items",
                    template: new StandardListItem({ title: "{gstn>GSTIN}", description: "{gstn>NAME}" }),
                    templateShareable: false
                });
                this.getView().addDependent(this._oGstnDialog);
            }

            this._getModel().read("/GSTNSet", {
                success: function (oData) {
                    that._oGstnDialog.setModel(new JSONModel({ items: oData.results || [] }), "gstn");
                    that._oGstnDialog.open();
                },
                error: function () { MessageToast.show("Failed to load GSTN list"); }
            });
        },

        /* ════════════════════════════════════════════════════════════
           END USE VALUE HELP  (IND_CAT.IND_CATEGORY)
           Filter by vehicle / customer / date / chosen products.
        ════════════════════════════════════════════════════════════ */
        onEndUseSearch: function () {
            var that = this;
            var aFilters = [];
            if (this._login.email) {
                aFilters.push(new Filter("SMTP_ADDR", FilterOperator.EQ, this._login.email));
            }
            var sVehicle = this.byId("vehicleInput").getValue();
            if (sVehicle) { aFilters.push(new Filter("VEHICLE", FilterOperator.EQ, sVehicle)); }
            if (this._sSelectedCustomerId) {
                aFilters.push(new Filter("KUNNR", FilterOperator.EQ,
                    ("" + this._sSelectedCustomerId).padStart(10, "0")));
            }
            var sDate = this._toYyyymmdd(this.byId("loadingDatePicker").getValue());
            if (sDate) { aFilters.push(new Filter("BEGDA", FilterOperator.EQ, sDate)); }
            for (var i = 1; i <= 8; i++) {
                var sProd = (this.byId(COMP_PRODUCT(i)).getValue() || "").trim();
                if (sProd) { aFilters.push(new Filter("PRODUCT" + i, FilterOperator.EQ, sProd)); }
            }

            if (!this._oEndUseDialog) {
                this._oEndUseDialog = new SelectDialog({
                    title: "Select End Use",
                    noDataText: "No End Use found",
                    confirm: function (e) {
                        var oItem = e.getParameter("selectedItem");
                        if (oItem) { that.byId("endUseSelect").setValue(oItem.getTitle()); }
                    }
                });
                this.getView().addDependent(this._oEndUseDialog);
            }

            this._getModel().read("/GetEndUseSet", {
                filters: aFilters,
                success: function (oData) {
                    that._oEndUseDialog.setModel(new JSONModel({ items: oData.results || [] }), "enduse");
                    that._oEndUseDialog.bindAggregation("items", {
                        path: "enduse>/items",
                        template: new StandardListItem({ title: "{enduse>DDTEXT}" }),
                        templateShareable: false
                    });
                    that._oEndUseDialog.open();
                },
                error: function () { MessageToast.show("Failed to load End Use list"); }
            });
        },

        /* ════════════════════════════════════════════════════════════
           FLUSHING  (ATF_FLUSH.DESC / FLUSH_REASON.FLSH_REASON)
        ════════════════════════════════════════════════════════════ */
        onFlushingSelectChange: function (oEvent) {
            var sKey = oEvent.getSource().getSelectedKey();
            var oReason = this.byId("flushingReasonSelect");
            if (sKey === "YES") {
                oReason.setEnabled(true);
            } else {
                oReason.setEnabled(false).setValue("");
            }
        },

        onFlushingReasonSearch: function (oEvent) {
            var that = this;
            var oInput = oEvent.getSource();

            if (!this._oFlushReasonDialog) {
                this._oFlushReasonDialog = new SelectDialog({
                    title: "Select Flushing Reason",
                    multiSelect: false,
                    liveChange: function (e) {
                        var s = (e.getParameter("value") || "").trim();
                        var oBinding = e.getSource().getBinding("items");
                        if (oBinding) {
                            oBinding.filter(s ? [new Filter("DDTEXT", FilterOperator.Contains, s)] : []);
                        }
                    },
                    confirm: function (e) {
                        var oItem = e.getParameter("selectedItem");
                        if (oItem) { oInput.setValue(oItem.getTitle()); }
                        var b = e.getSource().getBinding("items");
                        if (b) { b.filter([]); }
                    },
                    cancel: function (e) {
                        var b = e.getSource().getBinding("items");
                        if (b) { b.filter([]); }
                    }
                });
                this._oFlushReasonDialog.bindAggregation("items", {
                    path: "flush>/results",
                    template: new StandardListItem({ title: "{flush>DDTEXT}" }),
                    templateShareable: false
                });
                this.getView().addDependent(this._oFlushReasonDialog);
            }

            this._getModel().read("/FlushreasonSet", {
                success: function (oData) {
                    // de-duplicate on DDTEXT (WebDynpro reads distinct domain texts)
                    var aRaw = (oData && oData.results) ? oData.results : [];
                    var oSeen = Object.create(null);
                    var aRes = [];
                    aRaw.forEach(function (o) {
                        var s = (o.DDTEXT || "").trim();
                        if (s && !oSeen[s]) { oSeen[s] = true; aRes.push({ DDTEXT: s, DOMNAME: o.DOMNAME }); }
                    });
                    that._oFlushReasonDialog.setModel(new JSONModel({ results: aRes }), "flush");
                    that._oFlushReasonDialog.open();
                },
                error: function () { MessageToast.show("Failed to load flushing reasons"); }
            });
        },

        /* ════════════════════════════════════════════════════════════
           SAVE INDENT  (WebDynpro: ONACTIONSAVE_INDENT)
           Client-side pre-checks mirror the WebDynpro popups; the server
           SaveIndentSet performs the full validation and returns ERROR.
        ════════════════════════════════════════════════════════════ */
        onSaveIndent: function () {
            var oView = this.getView();

            if (!this._isValidLoadingDate()) { return; }

            var sVehicle = oView.byId("vehicleInput").getValue().trim();
            if (!sVehicle) { MessageBox.error("Please enter a Vehicle."); return; }

            if (!this._sSelectedCustomerId) {
                MessageBox.error("Please select Customer.");
                return;
            }

            var sFlushDesc = oView.byId("flushingSelect").getSelectedKey();
            var sFlushReason = oView.byId("flushingReasonSelect").getValue();
            if (this._sVehType === "ATF") {
                if (!sFlushDesc) {
                    MessageBox.error("Please select Flushing requirement for ATF tanker.");
                    return;
                }
                if (sFlushDesc === "YES" && !sFlushReason) {
                    MessageBox.error("Please select Flushing reason.");
                    return;
                }
            }

            // Every enabled compartment must have a product
            for (var i = 1; i <= 8; i++) {
                var oProd = oView.byId(COMP_PRODUCT(i));
                if (oProd.getEditable() && !oProd.getValue().trim()) {
                    MessageBox.error("Please select Product for all compartments.");
                    return;
                }
            }

            // Transporter GSTN required for DI/EX customers
            var oGstn = oView.byId("transporterSelect");
            if (oGstn.getEditable() && !oGstn.getValue().trim()) {
                MessageBox.error("Please enter GSTN of Transporter.");
                return;
            }

            // End Use: the dropdown (GetEndUseSet) returns entries tagged
            // "MS-..." or "HSD-...". The WebDynpro keeps two separate
            // attributes (IND_USE_MS / IND_USE_HSD); route by prefix.
            var sEndUse = oView.byId("endUseSelect").getValue();
            var bHsdEndUse = sEndUse.indexOf("HSD-") === 0;

            var oPayload = {
                BEGDA: this._toIsoDate(oView.byId("loadingDatePicker").getValue()),
                VEHICLE: sVehicle,
                KUNNR: this._sSelectedCustomerId,
                // KUNNR_DESC is an EDM string of MaxLength 30 (DDIC C(30)); the
                // customer name from ZUSERSet.NAME1 is CHAR35, so long names
                // (e.g. "RELIANCE INDUSTRIES LIMITED, NRL DU…") overflow the
                // facet and the create dumps with CX_DS_EDM_FACET_ERROR. Cap it.
                KUNNR_DESC: (oView.byId("customerSelect").getValue() || "").substring(0, 30),
                CONTRACT: oView.byId("salesContractSelect").getValue(),
                TPT_GSTN: oGstn.getValue(),
                MS_END_USE: bHsdEndUse ? "" : sEndUse,
                HSD_END_USE: bHsdEndUse ? sEndUse : "",
                ATF_FLUSH: formatter.formatFlushKey(sFlushDesc),
                FLUSH_REASON: sFlushReason,
                ZTT_STATUS: "4",
                ZTT_STATUS_DESC: "Indent Saved",
                ZDELETE: "Y",
                INDENT_TYPE: "PORTAL",
                CUST_USER_ID: this._login.userId || "",
                SMTP_ADDR: this._login.email || ""
            };
            for (var c = 1; c <= 8; c++) {
                oPayload["PROD_CMP" + c] = oView.byId(COMP_PRODUCT(c)).getValue();
                oPayload["QUAN_COMP" + c] = oView.byId(COMP_QTY(c)).getValue();
            }

            var that = this;
            this._getModel().create("/SaveIndentSet", oPayload, {
                success: function (oResp) {
                    if (oResp && oResp.ERROR) {
                        MessageBox.error(oResp.ERROR, { title: "Indent not saved" });
                        return;
                    }
                    MessageBox.success("Indent saved successfully.");
                    that._clearIndentForm();
                    that.onGetIndents();
                },
                error: function (oErr) {
                    MessageBox.error(that._extractError(oErr, "Error saving indent. Please try again."));
                }
            });
        },

        _clearIndentForm: function () {
            var oView = this.getView();
            oView.byId("vehicleInput").setValue("");
            oView.byId("customerSelect").setValue("");
            oView.byId("salesContractSelect").setValue("");
            oView.byId("transporterSelect").setValue("");
            oView.byId("endUseSelect").setValue("");
            this._sSelectedCustomerId = null;
            this._sSelectedKdgrp = null;
            this._oSelectedContract = null;
            this._sVehType = null;
            this._resetCompartments();
        },

        /* ════════════════════════════════════════════════════════════
           GET INDENTS  (WebDynpro: ONACTIONGET_INDENTS / filter search)
           -> GETINDENTSet bound to the Saved Indents table.
        ════════════════════════════════════════════════════════════ */
        onGetIndents: function () {
            var oView = this.getView();
            var that = this;

            var aFilters = this._userFilters();

            var sDate = this._toYyyymmdd(oView.byId("filterDate").getValue());
            if (!sDate) {
                MessageBox.error("Please enter a Date.");
                return;
            }
            aFilters.push(new Filter("BEGDA", FilterOperator.EQ, sDate));

            var sVehicle = oView.byId("filterVehicle").getValue();
            if (sVehicle) { aFilters.push(new Filter("VEHICLE", FilterOperator.EQ, sVehicle)); }

            var sMode = oView.byId("filterIndentMode").getSelectedKey();
            if (sMode) { aFilters.push(new Filter("INDENT_TYPE", FilterOperator.EQ, sMode)); }

            var sDel = oView.byId("filterDelInd").getSelectedKey();
            if (sDel) { aFilters.push(new Filter("ZDELETE", FilterOperator.EQ, sDel)); }

            oView.byId("indentScroll").setBusy(true);
            this._getModel().read("/GETINDENTSet", {
                filters: aFilters,
                success: function (oData) {
                    var oTableModel = new JSONModel({ IndentReport: (oData && oData.results) || [] });
                    oView.setModel(oTableModel, "tableData");
                    oView.byId("indentScroll").setBusy(false);
                },
                error: function (oErr) {
                    oView.byId("indentScroll").setBusy(false);
                    MessageBox.error(that._extractError(oErr, "Failed to load indents."));
                }
            });
        },

        /* ════════════════════════════════════════════════════════════
           SUBMIT  (WebDynpro: ONACTIONSUBMIT_INDENT / ONACTIONSUBMIT_INDENT_ALL)
           Submit moves saved (status 4) indents to status 5 via the deep
           entity ZCREATESet.
        ════════════════════════════════════════════════════════════ */
        onSubmitSelected: function () {
            var aRows = this._getSelectedRows();
            if (!aRows.length) {
                MessageToast.show("Please select at least one row.");
                return;
            }
            this._submitRows(aRows);
        },

        onSubmitAll: function () {
            // All saved (status '4') indents currently in the table
            var oModel = this.getView().getModel("tableData");
            var aAll = oModel ? (oModel.getProperty("/IndentReport") || []) : [];
            var aRows = aAll.filter(function (o) { return o.ZTT_STATUS === "4"; });
            if (!aRows.length) {
                MessageToast.show("No saved indents available to submit.");
                return;
            }
            this._submitRows(aRows);
        },

        _submitRows: function (aRows) {
            var that = this;
            var oView = this.getView();
            var aItems = aRows.map(function (r) {
                return {
                    DEPOT: r.DEPOT,
                    KUNNR: r.KUNNR,
                    BEGDA: r.BEGDA,
                    VEHICLE: r.VEHICLE,
                    CUST_USER_ID: r.CUST_USER_ID,
                    ZTT_STATUS: r.ZTT_STATUS,
                    ZTT_STATUS_DESC: r.ZTT_STATUS_DESC
                };
            });
            var oPayload = {
                SMTP_ADDR: this._login.email,
                CUST_USER_ID: this._login.userId,
                HDR_TO_ITEM_NAV: aItems
            };

            oView.byId("indentScroll").setBusy(true);
            var oDeep = this.getOwnerComponent().getModel("deepEntityModel");
            oDeep.create("/ZCREATESet", oPayload, {
                success: function () {
                    oView.byId("indentScroll").setBusy(false);
                    MessageBox.success("Indent submitted successfully.");
                    that.onGetIndents();
                },
                error: function (oErr) {
                    oView.byId("indentScroll").setBusy(false);
                    MessageBox.error(that._extractError(oErr, "Error while submitting data."));
                }
            });
        },

        /* ════════════════════════════════════════════════════════════
           DELETE  (WebDynpro: ONACTIONDELETE_INDENT)
           Only un-processed indents (status 4/5, ZDELETE='Y') are deletable.
        ════════════════════════════════════════════════════════════ */
        onDeleteIndent: function () {
            var aRows = this._getSelectedRows();
            if (!aRows.length) {
                MessageBox.error("Please select the indents to be deleted.");
                return;
            }

            // Deletable rule must mirror the backend (delete_indents): a
            // draft (status 4) is always deletable; a submitted indent
            // (status 5) only when flagged ZDELETE='Y'. Counting status 5
            // alone as deletable produced a false "success" (201) with the
            // row left untouched.
            var fnDeletable = function (r) {
                return r.ZTT_STATUS === "4" || (r.ZTT_STATUS === "5" && r.ZDELETE === "Y");
            };

            var iDeletable = 0;
            var iProcessed = 0;
            aRows.forEach(function (r) {
                if (fnDeletable(r)) { iDeletable++; }
                else { iProcessed++; }
            });

            if (iDeletable === 0 && iProcessed > 0) {
                MessageBox.error("Selected indents already processed and cannot be deleted.");
                return;
            }

            var sMsg = iProcessed > 0
                ? "Only indents not yet processed will be deleted. Continue?"
                : "Do you want to delete the selected indent(s)?";

            var that = this;
            MessageBox.confirm(sMsg, {
                title: "Confirm Delete",
                actions: [MessageBox.Action.DELETE, MessageBox.Action.CANCEL],
                emphasizedAction: MessageBox.Action.DELETE,
                onClose: function (sAction) {
                    if (sAction !== MessageBox.Action.DELETE) { return; }
                    var aDel = aRows.filter(fnDeletable).map(function (r) {
                        return {
                            DEPOT: r.DEPOT,
                            KUNNR: r.KUNNR,
                            BEGDA: r.BEGDA,
                            VEHICLE: r.VEHICLE,
                            CUST_USER_ID: r.CUST_USER_ID,
                            ZTT_STATUS: r.ZTT_STATUS,
                            ZTT_STATUS_DESC: r.ZTT_STATUS_DESC
                        };
                    });
                    var oPayload = {
                        SMTP_ADDR: that._login.email,
                        CUST_USER_ID: that._login.userId,
                        HDR_TO_ITEM_DEL_NAV: aDel
                    };
                    var oDeep = that.getOwnerComponent().getModel("deepEntityModel");
                    oDeep.create("/ZDELETESet", oPayload, {
                        success: function () {
                            MessageToast.show("Deleted successfully.");
                            that.onGetIndents();
                        },
                        error: function (oErr) {
                            MessageBox.error(that._extractError(oErr, "Error while deleting data."));
                        }
                    });
                }
            });
        },

        /* ════════════════════════════════════════════════════════════
           CHANGE INDENT  (WebDynpro: ONACTIONMODIFY_INDENT)
           One row, status '4' only (submitted indents cannot be modified).
        ════════════════════════════════════════════════════════════ */
        onChangeIndent: function () {
            var aRows = this._getSelectedRows();
            if (aRows.length === 0) {
                MessageBox.error("Please select indent to be modified.");
                return;
            }
            if (aRows.length > 1) {
                MessageBox.error("Please select only one indent.");
                return;
            }
            var oRow = aRows[0];
            if (oRow.ZTT_STATUS !== "4") {
                MessageBox.error("Already submitted indent cannot be modified.");
                return;
            }
            var oClone = JSON.parse(JSON.stringify(oRow));
            this.getOwnerComponent().setModel(new JSONModel(oClone), "SelectedIndent");
            UIComponent.getRouterFor(this).navTo("ChangeIndentWithVehicleTab");
        },

        /* ════════════════════════════════════════════════════════════
           HELPERS
        ════════════════════════════════════════════════════════════ */
        _getSelectedRows: function () {
            var oTable = this.byId("idVehicleIndentReport");
            return oTable.getSelectedItems().map(function (oItem) {
                return oItem.getBindingContext("tableData").getObject();
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
