(function () {
    "use strict";

    var viewport = document.getElementById("viewport");
    var bracket = document.getElementById("bracket");
    var touches = new Map();
    var pinch;

    function distance(first, second) {
        return Math.hypot(second.x - first.x, second.y - first.y);
    }

    function values() {
        var match = bracket.style.transform.match(/translate\(([-\d.]+)px,\s*([-\d.]+)px\)\s*scale\(([-\d.]+)\)/);
        return match ? { x: Number(match[1]), y: Number(match[2]), scale: Number(match[3]) } : null;
    }

    function beginPinch() {
        var points = Array.from(touches.values());
        if (points.length !== 2) { return; }
        var current = values();
        pinch = {
            distance: distance(points[0], points[1]),
            midpoint: { x: (points[0].x + points[1].x) / 2, y: (points[0].y + points[1].y) / 2 },
            transform: current
        };
    }

    viewport.addEventListener("pointerdown", function (event) {
        if (event.pointerType !== "touch") { return; }
        var bounds = viewport.getBoundingClientRect();
        touches.set(event.pointerId, { x: event.clientX - bounds.left, y: event.clientY - bounds.top });
        if (touches.size === 2) { beginPinch(); }
    }, true);

    viewport.addEventListener("pointermove", function (event) {
        if (event.pointerType !== "touch" || !touches.has(event.pointerId)) { return; }
        var bounds = viewport.getBoundingClientRect();
        touches.set(event.pointerId, { x: event.clientX - bounds.left, y: event.clientY - bounds.top });
        if (!pinch || touches.size !== 2) { return; }

        var points = Array.from(touches.values());
        var nextDistance = distance(points[0], points[1]);
        var nextScale = Math.max(.18, Math.min(2.5, pinch.transform.scale * nextDistance / pinch.distance));
        var midpoint = { x: (points[0].x + points[1].x) / 2, y: (points[0].y + points[1].y) / 2 };
        var canvasX = (pinch.midpoint.x - pinch.transform.x) / pinch.transform.scale;
        var canvasY = (pinch.midpoint.y - pinch.transform.y) / pinch.transform.scale;

        bracket.style.transform = "translate(" + (midpoint.x - canvasX * nextScale) + "px," +
            (midpoint.y - canvasY * nextScale) + "px) scale(" + nextScale + ")";
        event.preventDefault();
        event.stopImmediatePropagation();
    }, { capture: true, passive: false });

    function endTouch(event) {
        touches.delete(event.pointerId);
        pinch = null;
    }

    viewport.addEventListener("pointerup", endTouch, true);
    viewport.addEventListener("pointercancel", endTouch, true);
}());
