(function () {
    "use strict";

    var cache = window.iesaScoreCache || { updatedAt: "", updatedGames: [] };
    var button = document.getElementById("updates-button");
    var dialog = document.getElementById("updates-dialog");
    var tableBody = document.querySelector("#updates-table tbody");
    var summary = document.getElementById("updates-summary");
    var windowControls = document.getElementById("updates-window");
    var allChanges = cache.updatedGames || [];

    // The refresh runs several times a day, so "since the previous capture" would be
    // only a few hours. Changes are retained for a week and filtered to a window here.
    var WINDOWS = [
        { id: "24", label: "24 hours", hours: 24 },
        { id: "48", label: "48 hours", hours: 48 },
        { id: "168", label: "7 days", hours: 168 }
    ];
    var activeWindow = WINDOWS[0];

    function parseStamp(value) {
        if (!value) { return null; }
        var match = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})/.exec(value);
        if (!match) { return null; }
        return new Date(+match[1], +match[2] - 1, +match[3], +match[4], +match[5]);
    }

    function changeTime(change) {
        return parseStamp(change.latestAt) || parseStamp(change.firstSeenAt);
    }

    function within(change, hours) {
        var seen = changeTime(change);
        if (!seen) { return true; }
        return (Date.now() - seen.getTime()) <= hours * 3600 * 1000;
    }

    // A game between two teams in the field is reported under each of them. Show it once.
    function collapseMirrors(changes) {
        var seen = Object.create(null);
        var rows = [];
        changes.forEach(function (change) {
            var names = String(change.opponent || "").split(/\s+(?:vs\.?|def\.)\s+/i);
            var key = names.length === 2
                ? names.map(function (n) { return n.trim().toLowerCase(); }).sort().join("|") + "|" + change.score
                : change.team + "|" + change.opponent + "|" + change.score;
            if (seen[key]) { return; }
            seen[key] = true;
            rows.push(change);
        });
        return rows;
    }

    function describeAge(change) {
        var seen = changeTime(change);
        if (!seen) { return ""; }
        var hours = Math.floor((Date.now() - seen.getTime()) / 3600000);
        if (hours < 1) { return "just now"; }
        if (hours < 24) { return hours + "h ago"; }
        var days = Math.round(hours / 24);
        return days === 1 ? "1 day ago" : days + " days ago";
    }

    // The team dialog sorts by when a score was posted, so expose the change
    // timestamps by matchup. Only games changed since tracking began have one.
    function matchupKey(team, opponent) {
        var names = String(opponent || "").split(/\s+(?:vs\.?|def\.)\s+/i);
        if (names.length !== 2) { return team + "|" + opponent; }
        return team + "|" + names.map(function (n) {
            return n.trim().toLowerCase();
        }).sort().join("|");
    }

    var changeIndex = Object.create(null);
    allChanges.forEach(function (change) {
        changeIndex[matchupKey(change.team, change.opponent)] = change;
    });
    window.iesaScoreChanges = {
        describeAge: function (team, opponent) {
            var change = changeIndex[matchupKey(team, opponent)];
            return change ? describeAge(change) : "";
        },
        isRecent: function (team, opponent, hours) {
            var change = changeIndex[matchupKey(team, opponent)];
            return Boolean(change) && within(change, hours || 24);
        },
        postedAt: function (team, opponent) {
            var change = changeIndex[matchupKey(team, opponent)];
            var seen = change ? changeTime(change) : null;
            return seen ? seen.getTime() : null;
        }
    };

    function label(className, text) {
        var span = document.createElement("span");
        span.className = className;
        span.textContent = text;
        return span;
    }

    function render() {
        var visible = collapseMirrors(allChanges.filter(function (change) {
            return within(change, activeWindow.hours);
        }));

        tableBody.replaceChildren();
        visible.forEach(function (change) {
            var row = document.createElement("tr");
            var teamCell = document.createElement("td");
            var teamLink = document.createElement("a");
            teamLink.href = change.sourceUrl;
            teamLink.target = "_blank";
            teamLink.rel = "noopener";
            teamLink.textContent = change.team;
            teamCell.appendChild(teamLink);
            row.appendChild(teamCell);
            [change.opponent, change.score, describeAge(change)].forEach(function (value) {
                var cell = document.createElement("td");
                cell.textContent = value;
                row.appendChild(cell);
            });
            tableBody.appendChild(row);
        });

        if (visible.length) {
            summary.textContent = visible.length + " posted score change(s) in the last " +
                activeWindow.label + ".";
        } else {
            summary.textContent = "No newly posted or changed scores in the last " +
                activeWindow.label + ".";
        }
        summary.textContent += " Last refreshed: " + (cache.updatedAt || "unavailable") + ".";
    }

    var badgeCount = collapseMirrors(allChanges.filter(function (change) {
        return within(change, 24);
    })).length;
    button.replaceChildren(label("score-label-full", "Score updates (" + badgeCount + ")"),
        label("score-label-short", "Scores(" + badgeCount + ")"));
    button.setAttribute("aria-label", "Score updates, " + badgeCount + " in the last 24 hours");

    if (windowControls) {
        WINDOWS.forEach(function (option) {
            var choice = document.createElement("button");
            choice.type = "button";
            choice.textContent = option.label;
            if (option === activeWindow) { choice.className = "active"; }
            choice.addEventListener("click", function () {
                activeWindow = option;
                Array.prototype.forEach.call(windowControls.children, function (child) {
                    child.className = child === choice ? "active" : "";
                });
                render();
            });
            windowControls.appendChild(choice);
        });
    }

    render();

    button.addEventListener("click", function () { dialog.showModal(); });
    document.getElementById("close-updates").addEventListener("click", function () { dialog.close(); });
}());
