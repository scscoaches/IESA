(function () {
    "use strict";

    var viewport = document.getElementById("viewport");
    var bracket = document.getElementById("bracket");
    var dragging = false;
    var animation = 0;
    var MIN = .05;
    var MAX = 2.5;

    function read() {
        var values = bracket.style.transform.match(/translate\(([-\d.]+)px,\s*([-\d.]+)px\)\s*scale\(([-\d.]+)\)/);
        return values ? { x: Number(values[1]), y: Number(values[2]), scale: Number(values[3]) } : null;
    }

    function apply(x, y, scale) {
        var next = window.clampBracketTransform ? window.clampBracketTransform(x, y, scale) : { x: x, y: y, scale: scale };
        bracket.style.transform = "translate(" + next.x + "px," + next.y + "px) scale(" + next.scale + ")";
    }

    // Scales about a viewport point so the content under that point stays put.
    function zoomAbout(pointX, pointY, factor) {
        var current = read();
        if (!current) { return; }
        var scale = Math.max(MIN, Math.min(MAX, current.scale * factor));
        apply(pointX - (pointX - current.x) * scale / current.scale,
            pointY - (pointY - current.y) * scale / current.scale, scale);
    }

    function center() {
        return { x: viewport.clientWidth / 2, y: viewport.clientHeight / 2 };
    }

    function animateZoom(pointX, pointY, factor) {
        cancelAnimationFrame(animation);
        var start = performance.now();
        var applied = 1;
        (function step(now) {
            var t = Math.min(1, (now - start) / 180);
            var target = Math.pow(factor, 1 - Math.pow(1 - t, 3));
            zoomAbout(pointX, pointY, target / applied);
            applied = target;
            if (t < 1) { animation = requestAnimationFrame(step); }
        }(start));
    }

    function animatePan(dx, dy) {
        cancelAnimationFrame(animation);
        var start = performance.now();
        var moved = 0;
        (function step(now) {
            var t = Math.min(1, (now - start) / 160);
            var eased = 1 - Math.pow(1 - t, 3);
            var current = read();
            if (current) { apply(current.x + dx * (eased - moved), current.y + dy * (eased - moved), current.scale); }
            moved = eased;
            if (t < 1) { animation = requestAnimationFrame(step); }
        }(start));
    }

    viewport.addEventListener("pointerdown", function () {
        dragging = true;
        cancelAnimationFrame(animation);
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
        cancelAnimationFrame(animation);

        var pixels = event.deltaY * (event.deltaMode === 1 ? 16 :
            event.deltaMode === 2 ? viewport.clientHeight : 1);
        var bounds = viewport.getBoundingClientRect();
        // Trackpad pinches arrive as ctrlKey wheel events with small deltas,
        // so they need a much stronger response than a mouse wheel notch.
        var factor = event.ctrlKey ?
            Math.exp(-Math.max(-50, Math.min(50, pixels)) * .012) :
            Math.pow(1.06, -Math.max(-120, Math.min(120, pixels)) / 100);
        zoomAbout(event.clientX - bounds.left, event.clientY - bounds.top, factor);
        event.stopImmediatePropagation();
    }, { capture: true, passive: false });

    viewport.addEventListener("dblclick", function (event) {
        if (event.target.closest("button, summary, a, input, select, textarea, .regional .entry")) { return; }
        event.preventDefault();
        var bounds = viewport.getBoundingClientRect();
        animateZoom(event.clientX - bounds.left, event.clientY - bounds.top, event.shiftKey ? 1 / 1.6 : 1.6);
    });

    document.addEventListener("keydown", function (event) {
        if (event.ctrlKey || event.metaKey || event.altKey || event.defaultPrevented) { return; }
        if (document.querySelector("dialog[open]")) { return; }
        if (event.target.closest && event.target.closest("input, select, textarea, [contenteditable]")) { return; }
        var middle = center();
        var step = 120;
        switch (event.key) {
            case "+": case "=": animateZoom(middle.x, middle.y, 1.25); break;
            case "-": case "_": animateZoom(middle.x, middle.y, 1 / 1.25); break;
            case "0": document.getElementById("fit").click(); break;
            case "ArrowLeft": animatePan(step, 0); break;
            case "ArrowRight": animatePan(-step, 0); break;
            case "ArrowUp": animatePan(0, step); break;
            case "ArrowDown": animatePan(0, -step); break;
            default: return;
        }
        event.preventDefault();
    });

    // Holding + or - zooms continuously; a quick click keeps the single step.
    [["plus", 1.025], ["minus", 1 / 1.025]].forEach(function (pair) {
        var button = document.getElementById(pair[0]);
        if (!button) { return; }
        var timer = 0;
        var frame = 0;
        var held = false;

        function stop() {
            clearTimeout(timer);
            cancelAnimationFrame(frame);
            timer = frame = 0;
        }

        button.addEventListener("pointerdown", function (event) {
            if (event.button !== 0) { return; }
            held = false;
            stop();
            timer = setTimeout(function () {
                held = true;
                var middle = center();
                (function step() {
                    zoomAbout(middle.x, middle.y, pair[1]);
                    frame = requestAnimationFrame(step);
                }());
            }, 300);
        });
        ["pointerup", "pointerleave", "pointercancel"].forEach(function (name) {
            button.addEventListener(name, stop);
        });
        button.addEventListener("click", function (event) {
            if (held) {
                held = false;
                event.stopImmediatePropagation();
            }
        }, true);
    });
}());
