sap.ui.define([], function () {
    "use strict";
    return {
        getLoginInfo: function () {
            var sUserId = "", sEmail = "";
            if (sap.ushell && sap.ushell.Container && sap.ushell.Container.getUser) {
                sUserId = sap.ushell.Container.getUser().getId();
                sEmail  = sap.ushell.Container.getUser().getEmail();
            }
            if (!sUserId || sUserId === "DEFAULT_USER") {
                sUserId = "100620";
                sEmail  = "rupam.borah@nrl.co.in";
            }
            return { userId: sUserId, email: sEmail };
        }
    };
});
