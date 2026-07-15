sap.ui.define([
    "sap/ui/core/mvc/Controller"
], function(e) {
    "use strict";
"use strict";return e.extend("customerindent.controller.CustomerIndent",{onInit:function(){var e=new sap.ui.model.json.JSONModel({tiles:[{header:"Entry",subheader:"Enter and Manage Indent Data",icon:"sap-icon://add",key:"Entry"},{header:"Reports",subheader:"View Indent Reports",icon:"sap-icon://display",key:"Reports"}]});this.getView().setModel(e)},handleTilePress:function(e){var n=e.getSource().getBindingContext().getProperty("key");if(n==="Entry"){this.onPressEntry()}else if(n==="Reports"){this.onPressReports()}},getGridLayout:function(){return new sap.f.GridContainerSettings({columnsM:2,columnsL:3,columnsXL:4,gap:"1rem"})},onPressReports:function(){this.getOwnerComponent().getRouter().navTo("ReportPage")},onPressEntry:function(){this.getOwnerComponent().getRouter().navTo("EntryPage")},onPressBulk:function(){this.getOwnerComponent().getRouter().navTo("BulkPortal")}})
});
