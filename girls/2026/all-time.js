(function () {
    "use strict";
    // All-time stats popup: every school's state finishes and postseason record
    // from all-time.json (Build-IesaAllTime.ps1) at the sport's site root.
    // header-menu.js loads this on demand; elements with data-all-time open it too.
    var script = document.currentScript;
    var dataUrl = new URL("../all-time.json", script.src).href;
    var team = window.iesaMyTeam;
    var dialog, table, head, body, scroll, picker, search, data = null, loading = null, headWatcher = null;
    if (!document.querySelector('link[href*="all-time.css"]')) {
        var styles = document.createElement("link");
        styles.rel = "stylesheet";
        styles.href = new URL("all-time.css", script.src).href + (new URL(script.src).search || "");
        document.head.appendChild(styles);
    }

    // Columns of all-time.json, per school and grade.
    var T = 0, SECOND = 1, THIRD = 2, FOURTH = 3, TRIPS = 4, SW = 5, SL = 6, SECT = 7, REG = 8, PW = 9, PL = 10, LAST = 11, FIRST = 12;
    function pct(w, l) { return w + l ? w / (w + l) : -1; }
    function record(w, l) { return w + "-" + l; }
    function topFour(s) { return s[T] + s[SECOND] + s[THIRD] + s[FOURTH]; }
    var COLUMNS = [
        { label: "#" },
        { label: "School", text: true },
        { label: "Titles", title: "State championships", value: function (s) { return s[T]; } },
        { label: "2nd", title: "State runner-up", value: function (s) { return s[SECOND]; } },
        { label: "3rd", title: "State third place", value: function (s) { return s[THIRD]; } },
        { label: "4th", title: "State fourth place", value: function (s) { return s[FOURTH]; } },
        { label: "Top 4", title: "Top-four state finishes", value: topFour },
        { label: "Trips", title: "State tournament appearances", value: function (s) { return s[TRIPS]; } },
        { label: "State W-L", title: "State tournament games won and lost", value: function (s) { return s[SW] * 1000 - s[SL]; }, show: function (s) { return record(s[SW], s[SL]); } },
        { label: "State %", title: "State tournament winning percentage", value: function (s) { return pct(s[SW], s[SL]); }, show: function (s) { var p = pct(s[SW], s[SL]); return p < 0 ? "\u2014" : p.toFixed(3).replace(/^0/, ""); } },
        { label: "Sect.", title: "Sectional titles", value: function (s) { return s[SECT]; } },
        { label: "Reg.", title: "Regional titles", value: function (s) { return s[REG]; } },
        { label: "Playoff W-L", title: "Regional, sectional and state games won and lost", value: function (s) { return s[PW] * 1000 - s[PL]; }, show: function (s) { return record(s[PW], s[PL]); } },
        { label: "Last title", title: "Most recent state championship", value: function (s) { return s[LAST]; }, show: function (s) { return s[LAST] || "\u2014"; } },
        { label: "First trip", title: "First state tournament appearance", value: function (s) { return s[FIRST] ? -s[FIRST] : -9999; }, show: function (s) { return s[FIRST] || "\u2014"; } }
    ];
    var state = { sort: 2, ascending: false, grade: "all" };

    function element(tag, className, text) {
        var node = document.createElement(tag);
        if (className) { node.className = className; }
        if (text !== undefined) { node.textContent = text; }
        return node;
    }

    // Sums one school's counters for the chosen grade ("all": every grade).
    function totals(school) {
        var sum = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        Object.keys(school.g).forEach(function (g) {
            if (state.grade !== "all" && g !== state.grade) { return; }
            var counts = school.g[g];
            for (var i = 0; i <= PL; i++) { sum[i] += counts[i]; }
            if (counts[LAST] > sum[LAST]) { sum[LAST] = counts[LAST]; }
            if (counts[FIRST] && (!sum[FIRST] || counts[FIRST] < sum[FIRST])) { sum[FIRST] = counts[FIRST]; }
        });
        return sum;
    }

    function mine(name) { return !!(team && team.matches(name)); }

    function renderPicker() {
        // Ungraded results (girls' combined 1979-1985, boys' weight divisions) count under All.
        var options = [["all", "All"], ["7th", "7th"], ["8th", "8th"]];
        picker.replaceChildren();
        options.forEach(function (option) {
            var button = element("button", option[0] === state.grade ? "active" : "", option[1]);
            button.type = "button";
            if (option[2]) { button.title = option[2]; }
            button.setAttribute("aria-pressed", String(option[0] === state.grade));
            button.addEventListener("click", function () { state.grade = option[0]; renderPicker(); render(); });
            picker.appendChild(button);
        });
    }

    function message(text) {
        var row = element("tr");
        var cell = element("td", "all-time-empty", text);
        cell.colSpan = COLUMNS.length;
        row.appendChild(cell);
        body.replaceChildren(row);
    }

    function render() {
        var query = search.value.trim().toLowerCase();
        var column = COLUMNS[state.sort];
        // Every school with a postseason result (state trip, regional or sectional game).
        var rows = data.schools.map(function (school) { return { name: school.name, s: totals(school) }; })
            .filter(function (row) { return row.s.some(function (v, i) { return i <= PL && v; }); });
        rows.sort(function (a, b) {
            var order = column.text ? a.name.localeCompare(b.name) : column.value(a.s) - column.value(b.s);
            if (!state.ascending) { order = -order; }
            // Ties: more titles, more top-four finishes, more trips, then name.
            return order || b.s[T] - a.s[T] || topFour(b.s) - topFour(a.s) || b.s[TRIPS] - a.s[TRIPS] || a.name.localeCompare(b.name);
        });
        Array.prototype.forEach.call(head.rows[0].cells, function (th, index) {
            if (index === state.sort) { th.setAttribute("aria-sort", state.ascending ? "ascending" : "descending"); }
            else { th.removeAttribute("aria-sort"); }
        });
        body.replaceChildren();
        var myRow = null;
        rows.forEach(function (row, index) {
            var rank = String(index + 1);
            if (query && row.name.toLowerCase().indexOf(query) < 0) { return; }
            var tr = element("tr");
            if (mine(row.name)) { tr.className = "my-team-row"; myRow = myRow || tr; }
            COLUMNS.forEach(function (c, index) {
                var text = index === 0 ? rank : c.text ? row.name : c.show ? String(c.show(row.s)) : String(c.value(row.s));
                tr.appendChild(element("td", text === "0" || text === "0-0" ? "zero" : "", text));
            });
            body.appendChild(tr);
        });
        if (!body.rows.length) { message("No school matches \u201c" + search.value.trim() + "\u201d."); }
        // Like the rankings, the team's row sticks to the bottom (or under the header).
        if (myRow) {
            var pin = function () {
                var height = head.getBoundingClientRect().height + "px";
                Array.prototype.forEach.call(myRow.cells, function (cell) { cell.style.top = height; });
            };
            pin();
            if (window.ResizeObserver) {
                if (headWatcher) { headWatcher.disconnect(); }
                headWatcher = new ResizeObserver(pin);
                headWatcher.observe(head);
            }
        }
    }

    function build() {
        dialog = element("dialog");
        dialog.id = "all-time-dialog";
        var title = element("div", "dialog-head");
        title.appendChild(element("strong", "", "All-time stats"));
        var close = element("button", "", "\u00d7");
        close.type = "button";
        close.setAttribute("aria-label", "Close");
        close.addEventListener("click", function () { dialog.close(); });
        title.appendChild(close);
        dialog.appendChild(title);
        var controls = element("div", "all-time-controls");
        search = element("input");
        search.type = "search";
        search.placeholder = "Find a school";
        search.setAttribute("aria-label", "Find a school");
        search.autocomplete = "off";
        search.addEventListener("input", function () { if (data) { render(); scroll.scrollTop = 0; } });
        controls.appendChild(search);
        picker = element("div", "updates-window");
        picker.setAttribute("role", "group");
        picker.setAttribute("aria-label", "Grade");
        controls.appendChild(picker);
        dialog.appendChild(controls);
        scroll = element("div", "all-time-scroll");
        table = element("table");
        table.id = "all-time-table";
        table.setAttribute("aria-label", "All-time stats by school");
        head = element("thead");
        var headRow = element("tr");
        COLUMNS.forEach(function (column, index) {
            var th = element("th");
            th.scope = "col";
            if (column.title) { th.title = column.title; }
            if (index === 0) { th.textContent = column.label; headRow.appendChild(th); return; }
            var button = element("button", "", column.label);
            button.type = "button";
            button.addEventListener("click", function () {
                state.ascending = state.sort === index ? !state.ascending : !!column.text;
                state.sort = index;
                render();
                scroll.scrollTop = 0;
            });
            th.appendChild(button);
            headRow.appendChild(th);
        });
        head.appendChild(headRow);
        table.appendChild(head);
        body = element("tbody");
        table.appendChild(body);
        scroll.appendChild(table);
        dialog.appendChild(scroll);
        document.body.appendChild(dialog);
    }

    function load() {
        if (!loading) {
            loading = fetch(dataUrl, { cache: "no-store" }).then(function (response) {
                if (!response.ok) { throw new Error("all-time.json returned HTTP " + response.status); }
                return response.json();
            });
            loading.catch(function () { loading = null; });
        }
        return loading;
    }

    function open() {
        if (!dialog) { build(); }
        if (!dialog.open) { dialog.showModal(); }
        if (data) { render(); return; }
        message("Loading all-time stats\u2026");
        load().then(function (loaded) {
            data = loaded;
            renderPicker();
            render();
        }).catch(function (error) {
            console.error("Unable to load all-time stats:", error);
            message("All-time stats are unavailable right now.");
        });
    }

    window.iesaAllTime = { open: open };
    Array.prototype.forEach.call(document.querySelectorAll("[data-all-time]"), function (link) {
        link.addEventListener("click", function (event) { event.preventDefault(); open(); });
    });
}());
