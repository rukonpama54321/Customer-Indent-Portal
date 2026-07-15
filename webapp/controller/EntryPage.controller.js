sap.ui.define([
    "sap/ui/core/mvc/Controller"
], function (Controller) {
    "use strict";

    var sDefaultTab = "withVehicletab"; // default landing tab

    return Controller.extend("customerindent.controller.EntryPage", {

        onInit: function () {
            var oTabs = this.byId("entryTabs");
            oTabs.setSelectedKey(sDefaultTab);
            this._updatePageTitle(sDefaultTab);
        },

        onTabSelect: function (oEvent) {
            var sKey = oEvent.getParameter("key");
            this._updatePageTitle(sKey);
        },

        onNavBack: function () {
            // Return to the Customer Portal tile page.
            this.getOwnerComponent().getRouter().navTo("RouteCustomerIndent");
        },

        _updatePageTitle: function (sKey) {
            var oPage = this.byId("entryPage");
            switch (sKey) {
                case "withVehicletab":
                    oPage.setTitle("Place Sales Indent - With Vehicle");
                    break;
                case "withoutVehicletab":
                    oPage.setTitle("Place Sales Indent - Without Vehicle");
                    break;
                case "inboundtab":
                    oPage.setTitle("Place Sales Indent - Inbound");
                    break;
                default:
                    oPage.setTitle("Place Sales Indent");
            }
        }

    });
});
