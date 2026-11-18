(function () {
    "use strict";
    // On phones (up to 680px, the site's mobile breakpoint) the header's Settings,
    // Find a team and Rankings buttons, and any other header button marked
    // data-menu-label="Label", go into a ☰ menu, leaving room for the season menus
    // and Scores (which shows its count). If the header still runs out of room,
    // Scores moves into the menu too. On wider screens buttons only move when the
    // header overflows. The buttons themselves move, so their handlers and badges
    // keep working.
    var topbar = document.querySelector(".topbar");
    var tools = topbar && topbar.querySelector(".tools");
    if (!tools) { return; }
    var phone = window.matchMedia("(max-width: 680px)");

    var more = document.createElement("button");
    more.type = "button";
    more.id = "more-button";
    more.title = "Menu";
    more.setAttribute("aria-label", "Menu");
    more.setAttribute("aria-haspopup", "true");
    more.setAttribute("aria-expanded", "false");
    more.innerHTML = '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">' +
        '<path d="M4 6h16M4 12h16M4 18h16" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" fill="none"/></svg>';
    more.hidden = true;

    var menu = document.createElement("div");
    menu.className = "header-menu";
    menu.setAttribute("role", "menu");
    menu.hidden = true;

    var LABELS = { "my-team-button": "Settings", "find-button": "Find a team", "rankings-button": "Rankings" };
    var moved = [];

    function labelFor(button) {
        return button.getAttribute("data-menu-label") || LABELS[button.id] || "";
    }

    function inTools(id) {
        var button = document.getElementById(id);
        return button && button.parentElement === tools ? button : null;
    }

    function marked() {
        return Array.prototype.filter.call(tools.querySelectorAll(":scope > [data-menu-label]"),
            function (button) { return !LABELS[button.id] && button.id !== "updates-button"; });
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
            item.button.removeAttribute("role");
            if (item.label) { item.label.remove(); }
            item.marker.parentNode.insertBefore(item.button, item.marker);
            item.marker.remove();
        }
        more.hidden = true;
    }

    function move(button) {
        if (!button || button.parentElement !== tools) { return; }
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

    function fit() {
        restore();
        if (phone.matches) {
            more.hidden = false;
            ["my-team-button", "find-button", "rankings-button"].forEach(function (id) { move(inTools(id)); });
            marked().forEach(move);
            if (overflowing()) { move(inTools("updates-button")); }
        } else if (overflowing()) {
            more.hidden = false;
            var queue = [inTools("updates-button"), inTools("rankings-button")].concat(marked().reverse());
            while (overflowing() && queue.length) { move(queue.shift()); }
        }
        if (!moved.length) { more.hidden = true; }
    }

    more.addEventListener("click", function (event) {
        event.stopPropagation();
        var open = menu.hidden;
        menu.hidden = !open;
        more.setAttribute("aria-expanded", String(open));
        if (open) { menu.style.top = Math.round(topbar.getBoundingClientRect().bottom) + "px"; }
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
    function refit() {
        fitting = true;
        fit();
        observer.takeRecords();
        fitting = false;
    }
    function schedule() {
        clearTimeout(timer);
        timer = setTimeout(refit, 120);
    }
    // Buttons change after load too (the Scores count arrives with the score file,
    // the class menu appears once the season list loads), so check again whenever
    // the header changes. Opening the menu changes only the menu and ☰ themselves.
    var observer = new MutationObserver(function (records) {
        if (fitting) { return; }
        if (records.some(function (record) { return record.target !== menu && record.target !== more; })) { schedule(); }
    });
    function start() {
        tools.appendChild(more);
        document.body.appendChild(menu);
        refit();
        observer.observe(topbar, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ["style", "hidden", "class"] });
        observer.observe(menu, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ["style", "hidden", "class"] });
        window.addEventListener("resize", schedule);
    }
    // Other scripts add header buttons (Settings, Rankings) as they load, so wait
    // for the whole page.
    if (document.readyState === "complete") { start(); } else { window.addEventListener("load", start); }
}());
