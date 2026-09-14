(function () {
    "use strict";

    var viewport = document.getElementById("viewport");
    var bracket = document.getElementById("bracket");
    var dragging = false;

    viewport.addEventListener("pointerdown", function () {
        dragging = true;
    }, true);

    window.addEventListener("pointerup", function () {
        dragging = false;
    });

    window.addEventListener("pointercancel", function () {
        dragging = false;
    });

    viewport.addEventListener("wheel", function (event) {
        event.preventDefault();
        if (dragging || event.buttons) {
            event.stopImmediatePropagation();
            return;
        }

        var values = bracket.style.transform.match(/translate\(([-\d.]+)px,\s*([-\d.]+)px\)\s*scale\(([-\d.]+)\)/);
        if (!values) { return; }

        var panX = Number(values[1]);
        var panY = Number(values[2]);
        var currentScale = Number(values[3]);
        var nextScale = Math.max(.18, Math.min(2.5, currentScale * (event.deltaY < 0 ? 1.12 : 1 / 1.12)));
        var bounds = viewport.getBoundingClientRect();
        var pointerX = event.clientX - bounds.left;
        var pointerY = event.clientY - bounds.top;
        var nextPanX = pointerX - (pointerX - panX) * nextScale / currentScale;
        var nextPanY = pointerY - (pointerY - panY) * nextScale / currentScale;

        bracket.style.transform = "translate(" + nextPanX + "px," + nextPanY + "px) scale(" + nextScale + ")";
        event.stopImmediatePropagation();
    }, { capture: true, passive: false });
}());
