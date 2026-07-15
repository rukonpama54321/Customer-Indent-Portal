sap.ui.define([
    "sap/ui/core/mvc/Controller",
    "customerindent/util/UserInfo",
    "sap/ui/model/Filter",
    "sap/ui/model/FilterOperator",
    "customerindent/util/formatter",
    "sap/ui/model/json/JSONModel",
    "sap/m/MessageBox",
    "sap/m/MessageToast",
    "sap/ui/export/library",
    "sap/ui/export/Spreadsheet"
], function(e,t,s,r,a,o,i,l,n,u) {
    "use strict";
"use strict";var d=n.EdmType;return e.extend("customerindent.controller.ReptCustClosBal",{formatter:a,onInit:function(){var e=sap.ui.core.UIComponent.getRouterFor(this);e.getRoute("ReptCustClosBal").attachMatched(this._onRouteMatched,this);var s=t.getLoginInfo();this.oReportModel=this.getOwnerComponent().getModel("reportModel");var r=this.byId("iKunnr8");if(r){r.setValue(s.userId)}},onSearch8:function(){this.getView().byId("vboxTableBody8").setBusy(true);var e=this.getView();var t=[];var s=e.byId("idDateFrom8").getValue();if(!s){sap.m.MessageBox.error("Please enter a Date.");this.getView().byId("vboxTableBody8").setBusy(false);return}if(s){if(s.includes(".")){var r=s.split(".");if(r.length===3){s=r[2]+r[1]+r[0]}}}var a;if(s.includes(".")){var r=s.split(".");a=new Date(r[2],r[1]-1,r[0])}else{a=new Date(s.substring(0,4),s.substring(4,6)-1,s.substring(6,8))}if(s){t.push(new sap.ui.model.Filter("DATE",sap.ui.model.FilterOperator.EQ,s))}var l=e.byId("iBukrs8").getValue();if(!l){sap.m.MessageBox.error("Please enter a Company Code.");this.getView().byId("vboxTableBody8").setBusy(false);return}if(l){}var n=e.byId("iKunnr8").getValue();if(n){t.push(new sap.ui.model.Filter("CUST_USER_ID",sap.ui.model.FilterOperator.EQ,n))}var u=new o;this.getView().setModel(u,"tableData8");var d=this;this.oReportModel.read("/ClosingBalanceSet",{filters:t,success:function(e){if(e.results.length===0){i.alert("No Data Found for the Given Filters.");this.getView().byId("vboxTableBody6").setBusy(false);return}var t=e.results.find(e=>e.ROW_TYPE==="H")||{};var s=e.results.filter(e=>e.ROW_TYPE==="B");var r=e.results.filter(e=>e.ROW_TYPE==="F");var a=this.getView().getModel("tableData8");a.setData({Header:t,ClosingBalance:s,Footer:r});this.getView().byId("vboxTableBody8").setBusy(false)}.bind(this),error:function(e){console.error("OData Get Failed: ",e);this.getView().byId("vboxTableBody8").setBusy(false)}.bind(this)})},_onRouteMatched:function(e){this._clearScreen();this.getView().byId("vboxTableBody8").setBusy(false)},_clearScreen:function(){var e=this.getView();var s=e.getModel("tableData8");if(s){s.setData({Header:{},ReconAccount:[],Footer:{}})}e.byId("idDateFrom8")?.setValue("");e.byId("iBukrs8")?.setValue("2000");var r=t.getLoginInfo();if(r&&r.userId){e.byId("iKunnr8")?.setValue(r.userId)}else{e.byId("iKunnr8")?.setValue("")}}})
});
