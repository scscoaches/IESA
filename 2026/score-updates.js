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
        { id: "24", label: "24 hours", phrase: "in the last 24 hours", hours: 24 },
        { id: "48", label: "48 hours", phrase: "in the last 48 hours", hours: 48 },
        { id: "168", label: "7 days", phrase: "in the last 7 days", hours: 168 }
    ];
    var activeWindow = WINDOWS[0];

    // Each grade and season is its own page, so scope the marker to the path.
    var SEEN_KEY = "iesa-updates-seen:" + window.location.pathname;

    function readSeen() {
        try {
            var raw = window.localStorage.getItem(SEEN_KEY);
            var value = raw ? Number(raw) : NaN;
            return isFinite(value) && value > 0 ? value : null;
        } catch (error) {
            return null;
        }
    }

    function writeSeen(value) {
        try {
            window.localStorage.setItem(SEEN_KEY, String(value));
        } catch (error) {
            /* Private browsing or a full quota: the window options still work. */
        }
    }

    // Captured once so the list does not empty out while the dialog is open.
    var lastSeen = readSeen();

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

    function inWindow(change, option) {
        if (!option.since) { return within(change, option.hours); }
        var seen = changeTime(change);
        if (!seen) { return true; }
        return seen.getTime() > option.since;
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

    function countIn(option) {
        return collapseMirrors(allChanges.filter(function (change) {
            return inWindow(change, option);
        })).length;
    }

    // Offered only to a returning visitor; there is no "last visit" on a first view.
    var newWindow = lastSeen
        ? { id: "new", label: "New for you", phrase: "since your last visit", since: lastSeen }
        : null;
    var newCount = newWindow ? countIn(newWindow) : 0;
    if (newWindow) {
        WINDOWS.unshift(newWindow);
        // Defaulting to an empty list would look broken, so only lead with it
        // when it has something to say.
        if (newCount) { activeWindow = newWindow; }
    }

    // Changes expire from the cache, so a long absence cannot be covered in full.
    function retentionNote() {
        if (!activeWindow.since) { return ""; }
        var kept = parseStamp(cache.retainedSince);
        if (!kept || activeWindow.since >= kept.getTime()) { return ""; }
        var days = cache.retainedDays || 7;
        return " Your last visit was before the " + days +
            "-day history begins, so only the kept changes are listed.";
    }

    function render() {
        var visible = collapseMirrors(allChanges.filter(function (change) {
            return inWindow(change, activeWindow);
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
            summary.textContent = visible.length + " posted score change(s) " +
                activeWindow.phrase + ".";
        } else {
            summary.textContent = "No newly posted or changed scores " +
                activeWindow.phrase + ".";
        }
        summary.textContent += retentionNote();
        summary.textContent += " Last refreshed: " + (cache.updatedAt || "unavailable") + ".";
    }

    var badgeCount = newWindow ? newCount : countIn(WINDOWS[0]);
    var badgeScope = newWindow ? "new since your last visit" : "in the last 24 hours";
    button.replaceChildren(label("score-label-full", "Score updates (" + badgeCount + ")"),
        label("score-label-short", "Scores(" + badgeCount + ")"));
    button.setAttribute("aria-label", "Score updates, " + badgeCount + " " + badgeScope);
    button.classList.toggle("has-new", badgeCount > 0);

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

    // Opening the dialog is the read receipt. A plain page view does not clear the
    // badge, and the marker is written even on a first visit so the next one works.
    button.addEventListener("click", function () {
        dialog.showModal();
        writeSeen(Date.now());
    });
    document.getElementById("close-updates").addEventListener("click", function () { dialog.close(); });
}());
