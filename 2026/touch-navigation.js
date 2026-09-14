(function () {
    "use strict";

    var viewport = document.getElementById("viewport");
    var bracket = document.getElementById("bracket");
    var pointers = new Map();
    var gesture;

    function transform() {
        var match = bracket.style.transform.match(/translate\(([-\d.]+)px,\s*([-\d.]+)px\)\s*scale\(([-\d.]+)\)/);
        return match ? { x: Number(match[1]), y: Number(match[2]), scale: Number(match[3]) } : { x: 0, y: 0, scale: 1 };
    }

    function apply(value) {
        bracket.style.transform = "translate(" + value.x + "px," + value.y + "px) scale(" + value.scale + ")";
    }

    function point(event) {
        var bounds = viewport.getBoundingClientRect();
        return { x: event.clientX - bounds.left, y: event.clientY - bounds.top };
    }

    function startGesture() {
        var active = Array.from(pointers.values());
        var current = transform();
        if (active.length === 1) {
            gesture = { type: "pan", point: active[0], transform: current };
            return;
        }
        if (active.length === 2) {
            var midpoint = { x: (active[0].x + active[1].x) / 2, y: (active[0].y + active[1].y) / 2 };
            gesture = {
                type: "pinch",
                distance: Math.hypot(active[1].x - active[0].x, active[1].y - active[0].y),
                midpoint: midpoint,
                canvas: { x: (midpoint.x - current.x) / current.scale, y: (midpoint.y - current.y) / current.scale },
                transform: current
            };
        }
    }

    viewport.addEventListener("pointerdown", function (event) {
        if (event.pointerType !== "touch") { return; }
        pointers.set(event.pointerId, point(event));
        viewport.setPointerCapture(event.pointerId);
        startGesture();
        event.preventDefault();
        event.stopImmediatePropagation();
    }, { capture: true, passive: false });

    viewport.addEventListener("pointermove", function (event) {
        if (event.pointerType !== "touch" || !pointers.has(event.pointerId)) { return; }
        pointers.set(event.pointerId, point(event));
        var active = Array.from(pointers.values());
        if (!gesture || !active.length) { return; }

        if (gesture.type === "pan" && active.length === 1) {
            apply({ x: gesture.transform.x + active[0].x - gesture.point.x, y: gesture.transform.y + active[0].y - gesture.point.y, scale: gesture.transform.scale });
        } else if (gesture.type === "pinch" && active.length === 2) {
            var midpoint = { x: (active[0].x + active[1].x) / 2, y: (active[0].y + active[1].y) / 2 };
            var distance = Math.hypot(active[1].x - active[0].x, active[1].y - active[0].y);
            var scale = Math.max(.18, Math.min(2.5, gesture.transform.scale * distance / gesture.distance));
            apply({ x: midpoint.x - gesture.canvas.x * scale, y: midpoint.y - gesture.canvas.y * scale, scale: scale });
        }
        event.preventDefault();
        event.stopImmediatePropagation();
    }, { capture: true, passive: false });

    function end(event) {
        if (event.pointerType !== "touch") { return; }
        pointers.delete(event.pointerId);
        startGesture();
        event.preventDefault();
        event.stopImmediatePropagation();
    }

    viewport.addEventListener("pointerup", end, { capture: true, passive: false });
    viewport.addEventListener("pointercancel", end, { capture: true, passive: false });
}());
