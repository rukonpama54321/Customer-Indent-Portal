sap.ui.define([
    "sap/ui/core/mvc/Controller"
], function (Controller) {
    "use strict";

    return Controller.extend("customerindent.controller.BulkPortal", {

        onInit: function () {
            // Resolve the standalone bulk app URL through UI5's resource resolver
            // rather than a hard-coded relative path. A relative "bulk/index.html"
            // resolves against the current document URL — which is wrong under the
            // FLP sandbox (e.g. /test/flpSandbox.html → /test/bulk/index.html, 404).
            // toUrl() uses the "customerindent" resourceroot, so it returns the
            // correct served path in every environment (sandbox, root, BSP).
            var sUrl = sap.ui.require.toUrl("customerindent/bulk/index.html");
            this.byId("bulkFrame").setContent(
                '<iframe src="' + sUrl + '" class="ciBulkFrame"></iframe>'
            );

            // The back button now lives inside the bulk mast (rendered in the
            // iframe). It posts a message asking the host to navigate back.
            this._fnNavBackListener = function (oEvent) {
                if (oEvent.data && oEvent.data.type === "bulkPortalNavBack") {
                    this.onNavBack();
                }
            }.bind(this);
            window.addEventListener("message", this._fnNavBackListener);
        },

        onExit: function () {
            if (this._fnNavBackListener) {
                window.removeEventListener("message", this._fnNavBackListener);
            }
        },

        onNavBack: function () {
            // Return to the host main menu (tile page).
            this.getOwnerComponent().getRouter().navTo("RouteCustomerIndent");
        }

    });
});
