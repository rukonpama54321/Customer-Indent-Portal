sap.ui.define([
    "sap/ui/core/mvc/Controller",
    "customerindent/util/formatter",
    "customerindent/util/UserInfo"
], function (Controller, formatter, UserInfo) {
    "use strict";

    return Controller.extend("customerindent.controller.ChangeIndentWithVehicleTab", {

        formatter: formatter,

        // ──────────────────────────────────────────────────────────────────────
        // Lifecycle
        // ──────────────────────────────────────────────────────────────────────

        onInit: function () {
            var oRouter = sap.ui.core.UIComponent.getRouterFor(this);
            oRouter.getRoute("ChangeIndentWithVehicleTab")
                   .attachPatternMatched(this._onObjectMatched, this);
        },

        _onObjectMatched: function () {
            var oOwnerModel = this.getOwnerComponent().getModel("SelectedIndent");
            if (!oOwnerModel) { return; }
            var oData    = JSON.parse(JSON.stringify(oOwnerModel.getData()));

            // Saved compartment quantities are stored WITH the UOM appended
            // (backend create_entity: CONCATENATE lv_qc lv_uom -> e.g. "5000.000KL").
            // The Qty Inputs are type="Number", and an HTML number field cannot
            // render "5000.000KL", so it shows blank. Strip the trailing UOM to
            // the leading numeric part so the value both displays and, on Update,
            // is re-sent clean (the backend re-appends the UOM again on save).
            for (var i = 1; i <= 8; i++) {
                var sKey = "QUAN_COMP" + i;
                if (oData[sKey] !== undefined && oData[sKey] !== null) {
                    oData[sKey] = this._stripQtyUom(oData[sKey]);
                }
            }

            // Non-special products have no sales contract; the backend instead
            // pushes the pricing group (KONDM) and saves it in the pricing-group
            // column. The change screen exposes a single combined
            // "Sales Contract/Pricing Group" Input bound to /CONTRACT, so show
            // whichever value the saved indent actually carries: prefer the
            // sales contract when it is not initial, otherwise fall back to the
            // pricing group.
            var fnInitial = function (v) { return !v || !String(v).trim(); };
            if (fnInitial(oData.CONTRACT) && !fnInitial(oData.KONDM)) {
                oData.CONTRACT = oData.KONDM;
            }

            var oViewModel = new sap.ui.model.json.JSONModel(oData);
            this.getView().setModel(oViewModel, "SelectedIndent");
            if (oData.VEHICLE) {
                this._loadCompartments(oData.VEHICLE);
            }
            // The view hardcodes the reason field disabled; re-open it when the
            // loaded indent already has flushing = Yes so an ATF indent can be
            // modified without tripping the server's mandatory-reason check (M8).
            this._syncFlushReasonEnabled(oData.ATF_FLUSH);
        },

        // ──────────────────────────────────────────────────────────────────────
        // Compartments
        // ──────────────────────────────────────────────────────────────────────

        _loadCompartments: function (sVehicle) {
            var oThis   = this;
            var oModel  = this.getOwnerComponent().getModel();
            var aFilter = [new sap.ui.model.Filter("VEHICLE", sap.ui.model.FilterOperator.EQ, sVehicle)];

            // Reset only the EDITABILITY of the compartment inputs — never their
            // values. The product/qty Inputs are two-way bound to
            // SelectedIndent>/PROD_CMPn and /QUAN_COMPn, which already hold the
            // user's saved indent (loaded in _onObjectMatched). Calling setValue()
            // here would write back through the binding and clobber the saved
            // quantities/products (H4). WD REACT_TO_MODIFY only re-binds the
            // product dropdowns and re-enables fields; it never wipes stored qty.
            for (var k = 1; k <= 8; k++) {
                var oProd = oThis.byId("changeComp" + k + "Product");
                var oQty  = oThis.byId("changeComp" + k + "Qty");
                if (oProd) { oProd.setEditable(false); }
                if (oQty)  { oQty.setEditable(false);  }
            }

            oModel.read("/GETCompartmentNoSet", {
                filters: aFilter,
                success: function (oData) {
                    var aResults = oData && oData.results ? oData.results : [];
                    var sVehType = "";
                    aResults.forEach(function (oComp) {
                        var iNum  = parseInt(oComp.COM_NUMBER, 10);
                        if (isNaN(iNum) || iNum < 1 || iNum > 8) { return; }
                        sVehType = oComp.VEH_TYPE || sVehType;
                        var oProd = oThis.byId("changeComp" + iNum + "Product");
                        var oQty  = oThis.byId("changeComp" + iNum + "Qty");
                        // Re-enable the fields the vehicle supports, but keep the
                        // saved values — do NOT set qty to oComp.COMPOSITION (H4).
                        if (oProd) { oProd.setEditable(true); }
                        if (oQty)  { oQty.setEditable(oComp.COMP_ENABLED === "X"); }
                    });

                    // ATF flushing is only relevant for ATF tankers. Mirror the
                    // create flow (WithVehicleTab _loadCompartments): gate the
                    // Flushing Select on vehicle type so a non-ATF vehicle can't
                    // carry flushing. Without this the Select is always enabled.
                    oThis._sVehType = sVehType;
                    var bAtf   = sVehType === "ATF";
                    var oFlush = oThis.byId("changeFlushingSelect");
                    var oVM    = oThis.getView().getModel("SelectedIndent");
                    if (oFlush) { oFlush.setEnabled(bAtf); }
                    if (!bAtf) {
                        if (oVM) {
                            oVM.setProperty("/ATF_FLUSH", "");
                            oVM.setProperty("/FLUSH_REASON", "");
                        }
                        oThis._syncFlushReasonEnabled("");
                    } else {
                        oThis._syncFlushReasonEnabled(oVM ? oVM.getProperty("/ATF_FLUSH") : "");
                    }
                },
                error: function () {
                    sap.m.MessageBox.error("Failed to load compartments for vehicle " + sVehicle);
                }
            });
        },

        // ──────────────────────────────────────────────────────────────────────
        // Value-help: Customer
        // ──────────────────────────────────────────────────────────────────────

        onCustomerSearch: function () {
            var oThis      = this;
            var oLoginInfo = UserInfo.getLoginInfo();
            var sUserId    = oLoginInfo.userId;
            var sEmail     = oLoginInfo.email;

            if (!this._oCustomerDialog) {
                this._oCustomerDialog = new sap.m.SelectDialog({
                    title: "Select Customer",
                    search: function (oEvent) {
                        var sVal      = (oEvent.getParameter("value") || "").toLowerCase();
                        var aAll      = oThis._aCustomerData || [];
                        var aFiltered = sVal
                            ? aAll.filter(function (o) {
                                return (o.KUNNR || "").toLowerCase().indexOf(sVal) !== -1 ||
                                       (o.NAME1 || "").toLowerCase().indexOf(sVal) !== -1;
                              })
                            : aAll;
                        oThis._oCustomerDialog.getModel("local").setProperty("/results", aFiltered);
                    },
                    confirm: function (oEvent) {
                        var oItem = oEvent.getParameter("selectedItem");
                        if (!oItem) { return; }
                        var sKunnr = oItem.getDescription();
                        var sName  = oItem.getTitle();
                        var oVM    = oThis.getView().getModel("SelectedIndent");
                        oVM.setProperty("/KUNNR", sKunnr);
                        oVM.setProperty("/NAME1", sName);

                        // check if transporter GSTN field should be enabled
                        var aF = [new sap.ui.model.Filter("KUNNR", sap.ui.model.FilterOperator.EQ, sKunnr)];
                        oThis.getOwnerComponent().getModel().read("/EnableGSTINSet", {
                            filters: aF,
                            success: function (oData) {
                                var oTpt = oThis.byId("changeTransporterSelect");
                                var bEna = oData && oData.results && oData.results.length > 0 &&
                                           oData.results[0].ENABLE === "X";
                                if (oTpt) {
                                    oTpt.setEditable(bEna);
                                    if (!bEna) {
                                        oTpt.setValue("");
                                        oVM.setProperty("/TPT_GSTN", "");
                                    }
                                }
                            },
                            error: function () {}
                        });
                    },
                    cancel: function () {}
                });
                var oTemplate = new sap.m.StandardListItem({
                    title:       "{local>NAME1}",
                    description: "{local>KUNNR}"
                });
                this._oCustomerDialog.bindAggregation("items", {
                    path:              "local>/results",
                    template:          oTemplate,
                    templateShareable: false
                });
                this.getView().addDependent(this._oCustomerDialog);
            }

            var aFilters = [];
            if (sUserId) { aFilters.push(new sap.ui.model.Filter("CUST_USER_ID", sap.ui.model.FilterOperator.EQ, sUserId)); }
            if (sEmail)  { aFilters.push(new sap.ui.model.Filter("SMTP_ADDR",    sap.ui.model.FilterOperator.EQ, sEmail));  }

            this.getOwnerComponent().getModel().read("/ZUSERSet", {
                filters:    aFilters,
                and:        false,
                success: function (oData) {
                    oThis._aCustomerData = oData.results || [];
                    var oJM = new sap.ui.model.json.JSONModel({ results: oThis._aCustomerData });
                    oThis._oCustomerDialog.setModel(oJM, "local");
                    oThis._oCustomerDialog.open();
                },
                error: function () {
                    sap.m.MessageToast.show("Failed to load customer data");
                }
            });
        },

        // ──────────────────────────────────────────────────────────────────────
        // Value-help: Sales Contract
        // ──────────────────────────────────────────────────────────────────────

        onSalesContractSearch: function () {
            var oThis      = this;
            var oLoginInfo = UserInfo.getLoginInfo();
            var sUserId    = oLoginInfo.userId;
            var oVMFilter  = oThis.getView().getModel("SelectedIndent");
            var sKunnr     = (oVMFilter && oVMFilter.getProperty("/KUNNR")) || "";

            // Keep the $filter a FLAT conjunction of simple EQ comparisons.
            // A nested OR group (CUST_USER_ID or SMTP_ADDR) makes SAP Gateway's
            // GET_FILTER_SELECT_OPTIONS( ) return an empty table, so the backend
            // reads no filter values and the contract list comes back empty.
            // Backend needs CUST_USER_ID + KUNNR + PRODUCT1..5 (not SMTP_ADDR).
            var aFilters = [];
            if (sUserId) { aFilters.push(new sap.ui.model.Filter("CUST_USER_ID", sap.ui.model.FilterOperator.EQ, sUserId)); }
            if (sKunnr)  { aFilters.push(new sap.ui.model.Filter("KUNNR", sap.ui.model.FilterOperator.EQ, ("" + sKunnr).padStart(10, "0"))); }
            for (var i = 1; i <= 8; i++) {
                var sProd = (oVMFilter && oVMFilter.getProperty("/PROD_CMP" + i)) || "";
                if (sProd) { aFilters.push(new sap.ui.model.Filter("PRODUCT" + i, sap.ui.model.FilterOperator.EQ, sProd)); }
            }

            this.getOwnerComponent().getModel().read("/SalesContractSet", {
                filters: aFilters,
                and: true,
                success: function (oData) {
                    var aResults = (oData && oData.results) ? oData.results : [];
                    var oJM      = new sap.ui.model.json.JSONModel({ items: aResults });

                    if (!oThis._oSalesDialog) {
                        oThis._oSalesDialog = new sap.m.SelectDialog({
                            title: "Select Sales Contract",
                            search: function (oEvent) {
                                var sVal = (oEvent.getParameter("value") || "").toUpperCase();
                                oEvent.getSource().getItems().forEach(function (oItem) {
                                    var oCtx  = oItem.getBindingContext("local");
                                    var sText = (oCtx.getProperty("TEXT") || "").toUpperCase();
                                    var sDesc = (oCtx.getProperty("DESC") || "").toUpperCase();
                                    oItem.setVisible(!sVal || sText.indexOf(sVal) !== -1 || sDesc.indexOf(sVal) !== -1);
                                });
                            },
                            confirm: function (oEvent) {
                                var oItem = oEvent.getParameter("selectedItem");
                                if (!oItem) { return; }
                                var oCtx  = oItem.getBindingContext("local");
                                var sText = oCtx.getProperty("TEXT");
                                var sDesc = oCtx.getProperty("DESC");
                                var oVM   = oThis.getView().getModel("SelectedIndent");
                                oThis.byId("changeSalesContractSelect").setValue(sText || "");
                                oVM.setProperty("/CONTRACT",      sText);
                                oVM.setProperty("/CONTRACT_DESC", sDesc);
                                oThis._selectedSalesContract = JSON.parse(JSON.stringify(oCtx.getObject()));
                            },
                            cancel: function () {}
                        });
                        var oTemplate = new sap.m.StandardListItem({
                            title:       "{local>TEXT}",
                            description: "{local>DESC}"
                        });
                        oThis._oSalesDialog.bindAggregation("items", {
                            path:     "local>/items",
                            template: oTemplate
                        });
                        oThis.getView().addDependent(oThis._oSalesDialog);
                    }

                    oThis._oSalesDialog.setModel(oJM, "local");
                    oThis._oSalesDialog.open();
                },
                error: function () {
                    sap.m.MessageToast.show("Failed to load Sales Contract data");
                }
            });
        },

        // ──────────────────────────────────────────────────────────────────────
        // Value-help: Transporter GSTN
        // ──────────────────────────────────────────────────────────────────────

        onTransporterSearch: function (oEvent) {
            var oSource = oEvent.getSource();
            var oThis   = this;

            if (!this._oTransporterDialog) {
                this._oTransporterDialog = new sap.m.SelectDialog({
                    title:       "Select Transporter GSTN",
                    multiSelect: false,
                    liveChange: function (oEv) {
                        var sVal     = (oEv.getParameter("value") || "").trim();
                        var oBinding = oEv.getSource().getBinding("items");
                        oBinding.filter(sVal
                            ? [new sap.ui.model.Filter({
                                  path:          "GSTIN",
                                  operator:      sap.ui.model.FilterOperator.Contains,
                                  value1:        sVal,
                                  caseSensitive: false
                              })]
                            : []);
                    },
                    confirm: function (oEv) {
                        var oItem = oEv.getParameter("selectedItem");
                        if (oItem) { oSource.setValue(oItem.getTitle()); }
                        oEv.getSource().getBinding("items").filter([]);
                    },
                    cancel: function (oEv) {
                        oEv.getSource().getBinding("items").filter([]);
                    }
                });
                this._oTransporterDialog.bindAggregation("items", {
                    path:              "tpt>/items",
                    template:          new sap.m.StandardListItem({
                                           title:       "{tpt>GSTIN}",
                                           description: "{tpt>NAME}"
                                       }),
                    templateShareable: false
                });
                this.getView().addDependent(this._oTransporterDialog);
            }

            this.getOwnerComponent().getModel().read("/GSTNSet", {
                success: function (oData) {
                    var oJM = new sap.ui.model.json.JSONModel({ items: oData.results || [] });
                    oThis._oTransporterDialog.setModel(oJM, "tpt");
                    oThis._oTransporterDialog.open();
                },
                error: function () {
                    sap.m.MessageToast.show("Failed to load GSTN list");
                }
            });
        },

        // ──────────────────────────────────────────────────────────────────────
        // Value-help: End Use
        // ──────────────────────────────────────────────────────────────────────

        onEndUseSearch: function () {
            var oThis      = this;
            var oLoginInfo = UserInfo.getLoginInfo();
            var sEmail     = oLoginInfo.email || "";
            var oVM        = this.getView().getModel("SelectedIndent");
            var sVehicle   = (this.byId("changeVehicleInput") && this.byId("changeVehicleInput").getValue()) || "";
            var sKunnr     = oVM.getProperty("/KUNNR") || "";

            var aFilters = [];
            if (sEmail)   { aFilters.push(new sap.ui.model.Filter("SMTP_ADDR", sap.ui.model.FilterOperator.EQ, sEmail));   }
            if (sVehicle) { aFilters.push(new sap.ui.model.Filter("VEHICLE",   sap.ui.model.FilterOperator.EQ, sVehicle)); }
            if (sKunnr)   { aFilters.push(new sap.ui.model.Filter("KUNNR",     sap.ui.model.FilterOperator.EQ, ("" + sKunnr).padStart(10, "0"))); }

            if (!this._oEndUseDialog) {
                this._oEndUseDialog = new sap.m.SelectDialog({
                    title:      "Select End Use",
                    noDataText: "No End Use found",
                    confirm: function (oEvent) {
                        var oItem = oEvent.getParameter("selectedItem");
                        if (!oItem) { return; }
                        var sTitle = oItem.getTitle();
                        // GetEndUseSet tags entries "MS-..." / "HSD-...". The backend
                        // (INDENTUPDATESET_CREATE_ENTITY) reads MS_END_USE and HSD_END_USE
                        // separately, so route the picked value by its prefix — mirroring
                        // the WebDynpro's IND_USE_MS / IND_USE_HSD split.
                        var bHsd = sTitle.indexOf("HSD-") === 0;
                        oVM.setProperty("/MS_END_USE",  bHsd ? "" : sTitle);
                        oVM.setProperty("/HSD_END_USE", bHsd ? sTitle : "");
                        var oInput = oThis.byId("changeEndUseSelect");
                        if (oInput) { oInput.setValue(sTitle); }
                    },
                    cancel: function () {}
                });
                this.getView().addDependent(this._oEndUseDialog);
            }

            this.getOwnerComponent().getModel().read("/GetEndUseSet", {
                filters: aFilters,
                success: function (oData) {
                    var oJM = new sap.ui.model.json.JSONModel({ items: oData.results || [] });
                    oThis._oEndUseDialog.setModel(oJM, "enduse");
                    oThis._oEndUseDialog.destroyItems();
                    oThis._oEndUseDialog.bindAggregation("items", {
                        path:              "enduse>/items",
                        template:          new sap.m.StandardListItem({ title: "{enduse>DDTEXT}" }),
                        templateShareable: false
                    });
                    oThis._oEndUseDialog.open();
                },
                error: function () {
                    sap.m.MessageToast.show("Failed to load End Use list");
                }
            });
        },

        // ──────────────────────────────────────────────────────────────────────
        // Value-help: Compartment Product
        // ──────────────────────────────────────────────────────────────────────

        onCompProductSearch: function (oEvent) {
            var oSource    = oEvent.getSource();
            var oThis      = this;
            var oLoginInfo = UserInfo.getLoginInfo();
            var sUserId    = oLoginInfo.userId;
            var sEmail     = oLoginInfo.email;
            var sVehicle   = (this.byId("changeVehicleInput") && this.byId("changeVehicleInput").getValue()) || "";

            if (!this._oProductDialog) {
                this._oProductDialog = new sap.m.SelectDialog({
                    title: "Select Product",
                    search: function (oEvent) {
                        var sVal      = (oEvent.getParameter("value") || "").toLowerCase();
                        var aAll      = oThis._aProductData || [];
                        var aFiltered = sVal
                            ? aAll.filter(function (o) {
                                  return (o.PRODUCT || "").toLowerCase().indexOf(sVal) !== -1;
                              })
                            : aAll;
                        oThis._oProductDialog.getModel("local").setProperty("/results", aFiltered);
                    },
                    confirm: function (oEvent) {
                        var oItem = oEvent.getParameter("selectedItem");
                        if (oItem && oThis._oLastProductInput) {
                            oThis._oLastProductInput.setValue(oItem.getTitle());
                        }
                        if (oThis._aProductData) {
                            oThis._oProductDialog.getModel("local").setProperty("/results", oThis._aProductData);
                        }
                    },
                    cancel: function () {}
                });
                var oTemplate = new sap.m.StandardListItem({ title: "{local>PRODUCT}" });
                this._oProductDialog.bindAggregation("items", {
                    path:              "local>/results",
                    template:          oTemplate,
                    templateShareable: false
                });
                this.getView().addDependent(this._oProductDialog);
            }

            this._oLastProductInput = oSource;

            var aFilters = [];
            if (sVehicle) { aFilters.push(new sap.ui.model.Filter("VEHICLE",     sap.ui.model.FilterOperator.EQ, sVehicle)); }
            if (sUserId)  { aFilters.push(new sap.ui.model.Filter("CUST_USER_ID", sap.ui.model.FilterOperator.EQ, sUserId)); }
            if (sEmail)   { aFilters.push(new sap.ui.model.Filter("SMTP_ADDR",   sap.ui.model.FilterOperator.EQ, sEmail));  }

            this.getOwnerComponent().getModel().read("/GETProductSet", {
                filters: aFilters,
                and:     true,
                success: function (oData) {
                    oThis._aProductData = oData.results || [];
                    var oJM = new sap.ui.model.json.JSONModel({ results: oThis._aProductData });
                    oThis._oProductDialog.setModel(oJM, "local");
                    oThis._oProductDialog.open();
                },
                error: function () {
                    sap.m.MessageToast.show("Failed to load product data");
                }
            });
        },

        // ──────────────────────────────────────────────────────────────────────
        // Fill all compartments with master product
        // ──────────────────────────────────────────────────────────────────────

        onFillAllProducts: function () {
            var oView          = this.getView();
            var oVM            = oView.getModel("SelectedIndent");
            var sMasterProduct = (oView.byId("changeMasterProductSelect") && oView.byId("changeMasterProductSelect").getValue()) || "";
            var sMasterQty     = (oView.byId("changeMasterQty")          && oView.byId("changeMasterQty").getValue())           || "";

            for (var i = 1; i <= 8; i++) {
                var oProd = oView.byId("changeComp" + i + "Product");
                var oQty  = oView.byId("changeComp" + i + "Qty");
                if (oProd && oProd.getEditable()) {
                    oProd.setValue(sMasterProduct);
                    oVM.setProperty("/PROD_CMP" + i, sMasterProduct);
                }
                if (oQty && oQty.getEditable()) {
                    oQty.setValue(sMasterQty);
                    oVM.setProperty("/QUAN_COMP" + i, sMasterQty);
                }
            }
        },

        // ──────────────────────────────────────────────────────────────────────
        // Flushing (ATF) — enable the reason field only when flushing = Yes
        // ──────────────────────────────────────────────────────────────────────

        // Mirrors the main WithVehicleTab onFlushingSelectChange, but the change
        // view's Select uses the ATF_FLUSH domain keys ("Y"/"N"/"") — not "YES".
        // The server rejects an ATF indent that needs flushing when FLUSH_REASON
        // is blank (create_entity:628–634), so the field must be reachable here.
        _syncFlushReasonEnabled: function (sKey) {
            var oReason = this.byId("changeFlushingReasonSelect");
            if (!oReason) { return; }
            if (sKey === "Y") {
                oReason.setEnabled(true);
            } else {
                oReason.setEnabled(false).setValue("");
                var oVM = this.getView().getModel("SelectedIndent");
                if (oVM) { oVM.setProperty("/FLUSH_REASON", ""); }
            }
        },

        onFlushingSelectChange: function (oEvent) {
            this._syncFlushReasonEnabled(oEvent.getSource().getSelectedKey());
        },

        // ──────────────────────────────────────────────────────────────────────
        // Value-help: Flushing Reason
        // ──────────────────────────────────────────────────────────────────────

        onFlushingReasonSearch: function (oEvent) {
            var oSource = oEvent.getSource();
            var oThis   = this;

            if (!this._oFlushReasonDialog) {
                this._oFlushReasonDialog = new sap.m.SelectDialog({
                    title:       "Select Flushing Reason",
                    multiSelect: false,
                    liveChange: function (oEv) {
                        var sVal     = (oEv.getParameter("value") || "").trim();
                        var oBinding = oEv.getSource().getBinding("items");
                        if (!oBinding) { return; }
                        oBinding.filter(sVal
                            ? [new sap.ui.model.Filter("DDTEXT", sap.ui.model.FilterOperator.Contains, sVal)]
                            : []);
                    },
                    confirm: function (oEv) {
                        var oItem = oEv.getParameter("selectedItem");
                        if (oItem) {
                            oSource.setValue(oItem.getTitle());
                            var oVM = oThis.getView().getModel("SelectedIndent");
                            if (oVM) { oVM.setProperty("/FLUSH_REASON", oItem.getTitle()); }
                        }
                        var oBinding = oEv.getSource().getBinding("items");
                        if (oBinding) { oBinding.filter([]); }
                    },
                    cancel: function (oEv) {
                        var oBinding = oEv.getSource().getBinding("items");
                        if (oBinding) { oBinding.filter([]); }
                    }
                });
                this._oFlushReasonDialog.bindAggregation("items", {
                    path:              "flush>/results",
                    template:          new sap.m.StandardListItem({ title: "{flush>DDTEXT}" }),
                    templateShareable: false
                });
                this.getView().addDependent(this._oFlushReasonDialog);
            }

            if (this._flushLocalModel) {
                var oBinding = this._oFlushReasonDialog.getBinding("items");
                if (oBinding) { oBinding.filter([]); }
                this._oFlushReasonDialog.open();
                return;
            }

            this.getOwnerComponent().getModel().read("/FlushreasonSet", {
                success: function (oData) {
                    var aRaw    = (oData && oData.results) ? oData.results : [];
                    var oSeen   = Object.create(null);
                    var aUnique = [];
                    aRaw.forEach(function (o) {
                        var s = (o.DDTEXT || "").trim();
                        if (s && !oSeen[s]) { oSeen[s] = true; aUnique.push({ DDTEXT: s, DOMNAME: o.DOMNAME }); }
                    });
                    oThis._flushLocalModel = new sap.ui.model.json.JSONModel({ results: aUnique });
                    oThis._oFlushReasonDialog.setModel(oThis._flushLocalModel, "flush");
                    oThis._oFlushReasonDialog.open();
                },
                error: function () {
                    sap.m.MessageToast.show("Failed to load flushing reasons");
                }
            });
        },

        // ──────────────────────────────────────────────────────────────────────
        // Save / Cancel
        // ──────────────────────────────────────────────────────────────────────

        onUpdateIndent: function () {
            var oThis      = this;
            var oLoginInfo = UserInfo.getLoginInfo();
            var sUserId    = oLoginInfo.userId || "";
            var sEmail     = oLoginInfo.email  || "";
            var oVM        = this.getView().getModel("SelectedIndent");
            var oData      = oVM.getData();

            // IndentUpdate BEGDA deserializes into an ABAP DATS field, so the
            // update BODY must be ISO (YYYY-MM-DD) or the id transform dumps
            // (CX_SY_CONVERSION_NO_DATE_TIME). Accept dotted or compressed input.
            function formatDate(sDate) {
                if (!sDate) { return null; }
                if (sDate.indexOf(".") !== -1) {
                    var a = sDate.split(".");
                    if (a.length === 3) { return a[2] + "-" + a[1] + "-" + a[0]; }
                }
                if (/^\d{8}$/.test(sDate)) {
                    return sDate.slice(0, 4) + "-" + sDate.slice(4, 6) + "-" + sDate.slice(6, 8);
                }
                return sDate;
            }

            var oPayload = {
                CUST_USER_ID:    sUserId,
                SMTP_ADDR:       sEmail,
                BEGDA:           formatDate(oData.BEGDA),
                VEHICLE:         oData.VEHICLE,
                KUNNR:           oData.KUNNR,
                KUNNR_DESC:      oData.NAME1,
                PROD_CMP1:       oData.PROD_CMP1,  QUAN_COMP1: oData.QUAN_COMP1,
                PROD_CMP2:       oData.PROD_CMP2,  QUAN_COMP2: oData.QUAN_COMP2,
                PROD_CMP3:       oData.PROD_CMP3,  QUAN_COMP3: oData.QUAN_COMP3,
                PROD_CMP4:       oData.PROD_CMP4,  QUAN_COMP4: oData.QUAN_COMP4,
                PROD_CMP5:       oData.PROD_CMP5,  QUAN_COMP5: oData.QUAN_COMP5,
                PROD_CMP6:       oData.PROD_CMP6,  QUAN_COMP6: oData.QUAN_COMP6,
                PROD_CMP7:       oData.PROD_CMP7,  QUAN_COMP7: oData.QUAN_COMP7,
                PROD_CMP8:       oData.PROD_CMP8,  QUAN_COMP8: oData.QUAN_COMP8,
                ZTT_STATUS:      oData.ZTT_STATUS,
                ZTT_STATUS_DESC: oData.ZTT_STATUS_DESC,
                ATF_FLUSH:       oData.ATF_FLUSH,
                FLUSH_REASON:    oData.FLUSH_REASON,
                CONTRACT:        oData.CONTRACT,
                TPT_GSTN:        oData.TPT_GSTN,
                INDENT_TYPE:     oData.INDENT_TYPE,
                MS_END_USE:      oData.MS_END_USE,
                HSD_END_USE:     oData.HSD_END_USE,
                ZDELETE:         oData.ZDELETE
            };
            Object.keys(oPayload).forEach(function (k) { if (oPayload[k] === undefined) { delete oPayload[k]; } });

            sap.ui.core.BusyIndicator.show(0);
            this.getOwnerComponent().getModel().create("/IndentUpdateSet", oPayload, {
                success: function (oResult) {
                    sap.ui.core.BusyIndicator.hide();
                    if (oResult && oResult.ERROR) {
                        sap.m.MessageBox.error("Update failed: " + oResult.ERROR);
                    } else {
                        // Tell the (retained) WithVehicleTab list to re-query
                        // GETINDENTSet so the edited row shows the saved values
                        // instead of the stale pre-change data.
                        oThis.getOwnerComponent().getEventBus().publish("indent", "changed");
                        sap.m.MessageBox.success("Indent updated successfully.", {
                            onClose: function () {
                                var oHistory      = sap.ui.core.routing.History.getInstance();
                                var sPreviousHash = oHistory.getPreviousHash();
                                if (sPreviousHash !== undefined) {
                                    window.history.go(-1);
                                } else {
                                    oThis.getOwnerComponent().getRouter().navTo("RouteCustomerIndent");
                                }
                            }
                        });
                    }
                },
                error: function () {
                    sap.ui.core.BusyIndicator.hide();
                    sap.m.MessageBox.error("Failed to update indent. Please try again.");
                }
            });
        },

        onCancelIndent: function () {
            this._clearFields();
            var oHistory      = sap.ui.core.routing.History.getInstance();
            var sPreviousHash = oHistory.getPreviousHash();
            if (sPreviousHash !== undefined) {
                window.history.go(-1);
            } else {
                this.getOwnerComponent().getRouter().navTo("RouteCustomerIndent");
            }
        },

        // ──────────────────────────────────────────────────────────────────────
        // Helpers
        // ──────────────────────────────────────────────────────────────────────

        // Extract the leading numeric part of a stored quantity, dropping the
        // trailing UOM the backend appends (e.g. "5000.000KL" -> "5000.000").
        _stripQtyUom: function (v) {
            if (v === undefined || v === null || v === "") { return v; }
            var m = ("" + v).match(/[0-9]*\.?[0-9]+/);
            return m ? m[0] : "";
        },

        _clearFields: function () {
            var oView = this.getView();
            var aIds  = [
                "changeSalesContractSelect", "changeTransporterSelect",
                "changeEndUseSelect",        "changeMasterProductSelect",
                "changeFlushingReasonSelect"
            ];
            aIds.forEach(function (sId) {
                var oCtrl = oView.byId(sId);
                if (!oCtrl) { return; }
                if (typeof oCtrl.setValue    === "function") { oCtrl.setValue(""); }
                if (typeof oCtrl.setSelectedKey === "function") { oCtrl.setSelectedKey(""); }
            });
            var oMasterQty = oView.byId("changeMasterQty");
            if (oMasterQty) { oMasterQty.setValue(""); }
            for (var i = 1; i <= 8; i++) {
                var oProd = oView.byId("changeComp" + i + "Product");
                var oQty  = oView.byId("changeComp" + i + "Qty");
                if (oProd) { oProd.setValue(""); }
                if (oQty)  { oQty.setValue("");  }
            }
        }

    });
});
