(function () {
    "use strict";

    var viewport = document.getElementById("viewport");

    ["gesturestart", "gesturechange", "gestureend"].forEach(function (name) {
        viewport.addEventListener(name, function (event) {
            event.preventDefault();
        }, { passive: false });
    });

    viewport.addEventListener("touchmove", function (event) {
        event.preventDefault();
    }, { passive: false });

    viewport.addEventListener("wheel", function (event) {
        if (event.ctrlKey) {
            event.preventDefault();
            event.stopImmediatePropagation();
        }
    }, { capture: true, passive: false });
}());
