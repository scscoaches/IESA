(function () {
    "use strict";
    // Unofficial team rankings for the live season: each class and grade's
    // regular-season results (scores-<grade>.json) with the weekly strength of
    // schedule (strength-<grade>.json), both already published beside the pages.
    var data = window.tournamentData;
    var team = window.iesaMyTeam;
    var tools = document.querySelector(".topbar .tools");
    if (!document.body.classList.contains("live") || !data || !team || !tools ||
        ["7th", "8th"].indexOf(data.grade) < 0) { return; }
    var year = data.year || 2026;
    var iconUrl = new URL("rankings-icon.svg", document.currentScript.src).href;
    var classRoot = new URL("../", window.location.href).href;
    var files = {};
    var classRoots = null;

    // Each column's sort: the fields compared in turn and whether higher is
    // better. Clicking a column sorts it best-first; clicking again reverses it.
    var COLUMNS = [
        { id: "rank", label: "#" },
        { id: "team", label: "Team", sort: [["team", false]] },
        { id: "power", label: "Power", title: "Power rating (0-100): 40% win % (pulled toward .500 for few games), 30% scoring margin, 30% strength of schedule", sort: [["power", true], ["pct", true]] },
        { id: "record", label: "W-L", sort: [["wins", true], ["losses", false], ["pct", true]] },
        { id: "pct", label: "Win %", sort: [["pct", true], ["wins", true], ["diff", true]] },
        { id: "pf", label: "PF", title: "Points scored per game", sort: [["pf", true]] },
        { id: "pa", label: "PA", title: "Points allowed per game", sort: [["pa", false]] },
        { id: "diff", label: "Margin", title: "Average scoring margin per game", sort: [["diff", true], ["pct", true]] },
        { id: "close", label: "Close", title: "Record in games decided by 5 points or fewer", sort: [["closeWins", true], ["closeLosses", false]] },
        { id: "big", label: "Big W", title: "Wins by 15 or more points", sort: [["bigWins", true], ["pct", true]] },
        { id: "sos", label: "SoS", title: "Strength of schedule (unofficial, weekly)", sort: [["sos", true], ["pct", true]] },
        { id: "opp", label: "Opp %", title: "Opponents' win %", sort: [["oppPct", true], ["pct", true]] },
        { id: "quality", label: "QW", title: "Quality wins: wins over teams above .500", sort: [["qualityWins", true], ["pct", true]] },
        { id: "regional", label: "Reg.", title: "Regional", sort: [["regional", false], ["pct", true], ["wins", true]] }
    ];
    var state = { className: null, grade: data.grade, sort: "power", reversed: false };

    function element(tag, className, text) {
        var node = document.createElement(tag);
        if (className) { node.className = className; }
        if (text !== undefined) { node.textContent = text; }
        return node;
    }

    function json(url) {
        if (!files[url]) {
            files[url] = fetch(url, { cache: "no-store" }).then(function (response) {
                if (!response.ok) { throw new Error(url + " returned HTTP " + response.status); }
                return response.json();
            });
        }
        return files[url];
    }

    // Each class's folder for this season; the page's own class is the folder above this grade.
    function loadClasses() {
        if (classRoots) { return Promise.resolve(classRoots); }
        return team.load("seasons.json").then(function (seasons) {
            var season = seasons.filter(function (entry) { return entry.year === year; })[0];
            if (!season) { throw new Error("The " + year + " season is not in seasons.json."); }
            var classes = Array.isArray(season.classes) && season.classes.length ? season.classes : [season.className];
            classRoots = {};
            classes.forEach(function (className) {
                classRoots[className] = new URL("../", team.pageUrl(season, className, data.grade)).href;
            });
            state.className = classes.filter(function (className) {
                return classRoots[className] === classRoot;
            })[0] || season.className;
            return classRoots;
        });
    }

    var CLOSE_MARGIN = 5, BIG_MARGIN = 15;

    // IESA lists each result as "Winner def. Loser" with the winner's score first.
    function points(name, games) {
        var own = team.key(name), scored = 0, allowed = 0, counted = 0;
        var closeWins = 0, closeLosses = 0, bigWins = 0;
        (games || []).forEach(function (game) {
            var result = /^(.*) def\. (.*)$/.exec(game.opponent || "");
            var score = /^(\d+)-(\d+)$/.exec(game.score || "");
            if (!result || !score) { return; }
            var won = team.key(result[1]) === own;
            if (!won && team.key(result[2]) !== own) { return; }
            var gap = Number(score[1]) - Number(score[2]);
            scored += Number(won ? score[1] : score[2]);
            allowed += Number(won ? score[2] : score[1]);
            counted++;
            if (gap <= CLOSE_MARGIN) { if (won) { closeWins++; } else { closeLosses++; } }
            if (won && gap >= BIG_MARGIN) { bigWins++; }
        });
        return {
            pf: counted ? scored / counted : null,
            pa: counted ? allowed / counted : null,
            closeWins: closeWins, closeLosses: closeLosses, bigWins: bigWins
        };
    }

    function clamp(value) { return Math.max(0, Math.min(1, value)); }

    // Power rating, 0-100. Win % gets two phantom wins and losses, and margin the
    // same four phantom 0-point games, so a 6-1 start does not outrank a 17-0
    // season; margin is capped at +/-30; the strength of schedule rating (about
    // .23-.80 across classes) maps .20-.80 onto 0-1, and a team without one is
    // treated as average.
    function power(row, games) {
        if (!games) { return null; }
        var winScore = (row.wins + 2) / (games + 4);
        var shrunkMargin = row.diff === null ? 0 : row.diff * games / (games + 4);
        var marginScore = clamp((shrunkMargin + 30) / 60);
        var scheduleScore = row.sos === null ? 0.5 : clamp((row.sos - 0.2) / 0.6);
        return 100 * (0.4 * winScore + 0.3 * marginScore + 0.3 * scheduleScore);
    }

    function rows(scores, strength) {
        var ratings = (strength && strength.teams) || {};
        return Object.keys(scores.teams || {}).map(function (name) {
            var entry = scores.teams[name];
            var record = entry.record || {};
            var completed = record.completed || 0;
            var rating = ratings[name];
            var scoring = points(name, entry.games);
            var row = {
                team: name,
                wins: record.wins || 0,
                losses: record.losses || 0,
                pct: completed ? (record.wins || 0) / completed : null,
                pf: scoring.pf,
                pa: scoring.pa,
                diff: scoring.pf === null ? null : scoring.pf - scoring.pa,
                closeWins: scoring.closeWins,
                closeLosses: scoring.closeLosses,
                bigWins: scoring.bigWins,
                sos: rating && typeof rating.rating === "number" ? rating.rating : null,
                oppPct: rating && typeof rating.opponentsWinPct === "number" ? rating.opponentsWinPct : null,
                qualityWins: rating && typeof rating.qualityWins === "number" ? rating.qualityWins : null,
                regional: rating && rating.regional ? rating.regional : null
            };
            row.power = power(row, completed);
            return row;
        });
    }

    function column(id) { return COLUMNS.filter(function (entry) { return entry.id === id; })[0]; }

    // Missing values (no games, no rating) always sort last.
    function compare(a, b, field, higherFirst) {
        var x = a[field], y = b[field];
        if (x === null || y === null) { return x === y ? 0 : x === null ? 1 : -1; }
        var order = typeof x === "string" ? x.localeCompare(y) : x - y;
        return higherFirst ? -order : order;
    }

    function sorted(list) {
        var fields = column(state.sort).sort;
        return list.slice().sort(function (a, b) {
            for (var i = 0; i < fields.length; i++) {
                var higherFirst = i === 0 && state.reversed ? !fields[i][1] : fields[i][1];
                var result = compare(a, b, fields[i][0], higherFirst);
                if (result) { return result; }
            }
            return a.team.localeCompare(b.team);
        });
    }

    function rankKey(row) {
        return column(state.sort).sort.map(function (field) { return row[field[0]]; }).join("|");
    }

    function decimal(value) { return value === null ? "\u2014" : value.toFixed(3).replace(/^0/, ""); }
    function average(value) { return value === null ? "\u2014" : value.toFixed(1); }
    function margin(value) { return value === null ? "\u2014" : (value > 0 ? "+" : "") + value.toFixed(1); }

    var dialog, classPicker, gradePicker, table, scroll, body, headers = {};

    function picker(label) {
        var group = element("div", "updates-window");
        group.setAttribute("role", "group");
        group.setAttribute("aria-label", label);
        return group;
    }

    function pickerButton(group, text, active, onClick) {
        var button = element("button", active ? "active" : "", text);
        button.type = "button";
        button.setAttribute("aria-pressed", String(active));
        button.addEventListener("click", onClick);
        group.appendChild(button);
    }

    function renderPickers() {
        classPicker.replaceChildren();
        Object.keys(classRoots).forEach(function (className) {
            pickerButton(classPicker, className, className === state.className, function () {
                state.className = className;
                render();
            });
        });
        classPicker.hidden = Object.keys(classRoots).length < 2;
        gradePicker.replaceChildren();
        ["7th", "8th"].forEach(function (grade) {
            pickerButton(gradePicker, grade, grade === state.grade, function () {
                state.grade = grade;
                render();
            });
        });
    }

    function renderHeaders() {
        Object.keys(headers).forEach(function (id) {
            if (id !== state.sort) { headers[id].removeAttribute("aria-sort"); return; }
            var ascending = column(id).sort[0][1] === state.reversed;
            headers[id].setAttribute("aria-sort", ascending ? "ascending" : "descending");
        });
    }

    function message(text) {
        var cell = element("td", "rankings-empty", text);
        cell.colSpan = COLUMNS.length;
        var row = element("tr");
        row.appendChild(cell);
        body.replaceChildren(row);
    }

    var request = 0;
    function render() {
        var current = ++request;
        renderPickers();
        renderHeaders();
        var root = classRoots[state.className];
        message("Loading rankings\u2026");
        Promise.all([
            json(root + "scores-" + state.grade + ".json"),
            json(root + "strength-" + state.grade + ".json").catch(function () { return null; })
        ]).then(function (results) {
            if (current !== request) { return; }
            var list = sorted(rows(results[0], results[1]));
            if (!list.length) { message("No records are available yet."); return; }
            var rank = 0, previous = null, mine = null;
            body.replaceChildren();
            list.forEach(function (entry, index) {
                var key = rankKey(entry);
                if (key !== previous) { rank = index + 1; previous = key; }
                var row = element("tr");
                if (team.matches(entry.team)) { row.className = "my-team-row"; mine = mine || row; }
                [String(rank), entry.team, average(entry.power), entry.wins + "-" + entry.losses, decimal(entry.pct),
                    average(entry.pf), average(entry.pa), margin(entry.diff),
                    entry.closeWins + "-" + entry.closeLosses, String(entry.bigWins),
                    decimal(entry.sos), decimal(entry.oppPct),
                    entry.qualityWins === null ? "\u2014" : String(entry.qualityWins),
                    entry.regional === null ? "\u2014" : String(entry.regional)]
                    .forEach(function (text) { row.appendChild(element("td", "", text)); });
                body.appendChild(row);
            });
            // The team's row is sticky: pinned to the bottom while it is below the
            // visible rows and under the header once scrolled past.
            if (mine) {
                var headHeight = table.tHead.offsetHeight + "px";
                Array.prototype.forEach.call(mine.cells, function (cell) { cell.style.top = headHeight; });
            }
            scroll.scrollTop = 0;
        }).catch(function (error) {
            if (current !== request) { return; }
            console.error("Unable to load rankings:", error);
            message("Rankings are unavailable for Class " + state.className + " " + state.grade + " grade.");
        });
    }

    function buildDialog() {
        dialog = element("dialog");
        dialog.id = "rankings-dialog";
        var head = element("div", "dialog-head");
        head.appendChild(element("strong", "", "Team rankings"));
        var close = element("button", "", "\u00d7");
        close.type = "button";
        close.setAttribute("aria-label", "Close");
        close.addEventListener("click", function () { dialog.close(); });
        head.appendChild(close);
        dialog.appendChild(head);
        var controls = element("div", "rankings-controls");
        classPicker = picker("Class");
        gradePicker = picker("Grade");
        controls.appendChild(classPicker);
        controls.appendChild(gradePicker);
        dialog.appendChild(controls);
        scroll = element("div", "rankings-scroll");
        table = element("table");
        table.id = "rankings-table";
        table.setAttribute("aria-label", "Team rankings");
        var headRow = element("tr");
        COLUMNS.forEach(function (entry) {
            var cell = element("th");
            cell.scope = "col";
            if (entry.title) { cell.title = entry.title; }
            if (!entry.sort) {
                cell.textContent = entry.label;
            } else {
                var sortButton = element("button", "", entry.label);
                sortButton.type = "button";
                sortButton.addEventListener("click", function () {
                    state.reversed = state.sort === entry.id ? !state.reversed : false;
                    state.sort = entry.id;
                    render();
                });
                cell.appendChild(sortButton);
                headers[entry.id] = cell;
            }
            headRow.appendChild(cell);
        });
        var thead = element("thead");
        thead.appendChild(headRow);
        table.appendChild(thead);
        body = element("tbody");
        table.appendChild(body);
        scroll.appendChild(table);
        dialog.appendChild(scroll);
        document.body.appendChild(dialog);
    }

    function open() {
        loadClasses().then(function () {
            if (!dialog) { buildDialog(); }
            dialog.showModal();
            render();
        }).catch(function (error) {
            console.error("Unable to open rankings:", error);
            window.alert("Team rankings are unavailable right now.");
        });
    }

    var button = element("button");
    button.id = "rankings-button";
    button.type = "button";
    button.title = "Team rankings";
    button.setAttribute("aria-label", "Team rankings");
    var icon = element("img");
    icon.src = iconUrl;
    icon.alt = "";
    icon.setAttribute("aria-hidden", "true");
    button.appendChild(icon);
    button.addEventListener("click", open);
    var find = document.getElementById("find-button");
    tools.insertBefore(button, find ? find.nextSibling : tools.firstChild);
}());
