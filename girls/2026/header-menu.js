(function () {
    "use strict";
    // When the header runs out of room (phones), its less-used buttons move into a
    // "More" (⋯) menu, Scores first, then Rankings, then any other header button
    // marked data-menu-label="Label" (newest first). They move back when there is
    // room. The buttons themselves move, so their handlers and badges keep working.
    var topbar = document.querySelector(".topbar");
    var tools = topbar && topbar.querySelector(".tools");
    if (!tools) { return; }

    var more = document.createElement("button");
    more.type = "button";
    more.id = "more-button";
    more.title = "More";
    more.setAttribute("aria-label", "More");
    more.setAttribute("aria-haspopup", "true");
    more.setAttribute("aria-expanded", "false");
    more.textContent = "\u22EF";
    more.hidden = true;

    var menu = document.createElement("div");
    menu.className = "header-menu";
    menu.setAttribute("role", "menu");
    menu.hidden = true;

    var moved = [];

    function labelFor(button) {
        return button.getAttribute("data-menu-label") ||
            (button.id === "rankings-button" ? "Rankings" : "");
    }

    function candidates() {
        var list = [];
        ["updates-button", "rankings-button"].forEach(function (id) {
            var button = document.getElementById(id);
            if (button && button.parentElement === tools) { list.push(button); }
        });
        var marked = Array.prototype.filter.call(tools.querySelectorAll(":scope > [data-menu-label]"),
            function (button) { return list.indexOf(button) < 0; });
        return list.concat(marked.reverse());
    }

    function overflowing() {
        if (topbar.scrollWidth > topbar.clientWidth + 1) { return true; }
        var last = tools.lastElementChild;
        while (last && !last.offsetWidth) { last = last.previousElementSibling; }
        return !!last && last.getBoundingClientRect().right > document.documentElement.clientWidth + 1;
    }

    function close() {
        menu.hidden = true;
        more.setAttribute("aria-expanded", "false");
    }

    function restore() {
        close();
        while (moved.length) {
            var item = moved.pop();
            item.button.classList.remove("in-header-menu");
            if (item.label) { item.label.remove(); }
            item.marker.parentNode.insertBefore(item.button, item.marker);
            item.marker.remove();
        }
        more.hidden = true;
    }

    function fit() {
        restore();
        if (!overflowing()) { return; }
        more.hidden = false;
        var queue = candidates();
        while (overflowing() && queue.length) {
            var button = queue.shift();
            var marker = document.createComment("menu");
            button.parentNode.insertBefore(marker, button);
            var text = labelFor(button);
            var label = null;
            if (text) {
                label = document.createElement("span");
                label.className = "header-menu-label";
                label.textContent = text;
                button.appendChild(label);
            }
            button.classList.add("in-header-menu");
            button.setAttribute("role", "menuitem");
            menu.appendChild(button);
            moved.push({ button: button, marker: marker, label: label });
        }
        if (!moved.length) { more.hidden = true; }
    }

    more.addEventListener("click", function (event) {
        event.stopPropagation();
        var open = menu.hidden;
        menu.hidden = !open;
        more.setAttribute("aria-expanded", String(open));
        if (open) {
            var bar = topbar.getBoundingClientRect();
            menu.style.top = Math.round(bar.bottom) + "px";
        }
    });
    // Choosing an item runs its own click handler first, then the menu closes.
    menu.addEventListener("click", function () { setTimeout(close, 0); });
    document.addEventListener("click", function (event) {
        if (!menu.hidden && !menu.contains(event.target)) { close(); }
    });
    document.addEventListener("keydown", function (event) {
        if (event.key === "Escape" && !menu.hidden) { close(); more.focus(); }
    });

    var timer = 0;
    var fitting = false;
    function schedule() {
        clearTimeout(timer);
        timer = setTimeout(function () {
            fitting = true;
            fit();
            observer.takeRecords();
            fitting = false;
        }, 120);
    }
    // Buttons change after load too (the Scores count arrives with the score file,
    // another class hides it), so check again whenever the header's buttons change.
    // (Opening the menu changes its own attributes; that is not a header change.)
    var observer = new MutationObserver(function (records) {
        if (fitting) { return; }
        if (records.some(function (record) { return record.target !== menu && record.target !== more; })) { schedule(); }
    });
    function start() {
        tools.appendChild(more);
        document.body.appendChild(menu);
        fitting = true;
        fit();
        fitting = false;
        // The whole bar: the year and class menus fill in after load and widen it too.
        observer.observe(topbar, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ["style", "hidden", "class"] });
        observer.observe(menu, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ["style", "hidden", "class"] });
        window.addEventListener("resize", schedule);
    }
    // Other scripts add header buttons (Rankings) and set the Scores label as they
    // load, so wait for the whole page.
    if (document.readyState === "complete") { start(); } else { window.addEventListener("load", start); }
}());
