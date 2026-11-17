(function () {
    "use strict";

    var bracket = document.getElementById("bracket");
    var dialog = document.getElementById("find-dialog");
    var input = document.getElementById("team-search");
    var results = document.getElementById("team-results");
    var message = document.getElementById("find-message");
    var entries = Array.prototype.map.call(bracket.querySelectorAll(".regional > .entry"), function (entry) {
        return { name: entry.dataset.team || entry.textContent.trim(), cardId: entry.parentElement.id };
    }).sort(function (a, b) { return a.name.localeCompare(b.name); });

    // Schools in the season's other classes come from teams.json; picking one opens
    // that class's page, which finds the school from "#find=<name>" once it loads.
    var team = window.iesaMyTeam;
    var data = window.tournamentData || {};
    var others = [];
    if (team) {
        Promise.all([team.load("teams.json"), team.load("seasons.json")]).then(function (loaded) {
            var teams = loaded[0];
            var year = data.year || 2026;
            var season = loaded[1].filter(function (entry) { return entry.year === year; })[0];
            var classes = teams.seasons && teams.seasons[year] && teams.seasons[year][data.grade];
            if (!season || !classes) { return; }
            var pageClass = data.className || season.className;
            var here = {};
            entries.forEach(function (entry) { here[team.key(entry.name)] = true; });
            Object.keys(classes).forEach(function (className) {
                if (className === pageClass || className === "-" ||
                    (season.classes || [season.className]).indexOf(className) < 0) { return; }
                classes[className].forEach(function (index) {
                    var name = teams.names[index];
                    if (name && !here[team.key(name)]) {
                        others.push({ name: name, className: className, url: team.pageUrl(season, className, data.grade) });
                    }
                });
            });
            others.sort(function (a, b) { return a.name.localeCompare(b.name); });
        }).catch(function (error) { console.warn("Other classes are not searchable:", error); });
    }

    function find(name) {
        var wanted = team ? team.key(name) : name.toLocaleLowerCase();
        return entries.filter(function (entry) {
            return (team ? team.key(entry.name) : entry.name.toLocaleLowerCase()) === wanted;
        })[0];
    }

    function navigate(cardId, team) {
        dialog.close();
        document.dispatchEvent(new CustomEvent("iesaNavigateBracket", {
            detail: { cardId: cardId, team: team }
        }));
    }

    document.getElementById("find-button").addEventListener("click", function () {
        input.value = "";
        results.replaceChildren();
        message.textContent = "Type a team name to search.";
        dialog.showModal();
        input.focus();
    });
    document.getElementById("close-find").addEventListener("click", function () { dialog.close(); });

    input.addEventListener("input", function () {
        var query = input.value.trim().toLocaleLowerCase();
        results.replaceChildren();
        if (!query) {
            message.textContent = "Type a team name to search.";
            return;
        }
        var matches = entries.filter(function (entry) { return entry.name.toLocaleLowerCase().includes(query); });
        var elsewhere = others.filter(function (entry) { return entry.name.toLocaleLowerCase().includes(query); });
        var total = matches.length + elsewhere.length;
        message.textContent = total ? total + " team" + (total === 1 ? "" : "s") + " found" : "No matching teams.";
        matches.forEach(function (entry) {
            var button = document.createElement("button");
            button.type = "button";
            button.textContent = entry.name + " — " + document.querySelector("#" + entry.cardId + " .head").textContent;
            button.addEventListener("click", function () { navigate(entry.cardId, entry.name); });
            results.appendChild(button);
        });
        elsewhere.forEach(function (entry) {
            var button = document.createElement("button");
            button.type = "button";
            button.textContent = entry.name + " — Class " + entry.className;
            button.addEventListener("click", function () {
                window.location.assign(entry.url + "#find=" + encodeURIComponent(entry.name));
            });
            results.appendChild(button);
        });
    });
    input.addEventListener("keydown", function (event) {
        if (event.key === "Enter") {
            var first = results.querySelector("button");
            if (first) {
                event.preventDefault();
                first.click();
            }
        }
    });

    // Arriving from another class's search: center and highlight the school.
    var arriving = /^#find=(.+)$/.exec(window.location.hash);
    if (arriving) {
        var target = find(decodeURIComponent(arriving[1]));
        history.replaceState(null, "", window.location.pathname + window.location.search);
        if (target) {
            var go = function () {
                setTimeout(function () {
                    document.dispatchEvent(new CustomEvent("iesaNavigateBracket", {
                        detail: { cardId: target.cardId, team: target.name }
                    }));
                }, 0);
            };
            if (document.readyState === "complete") { go(); } else { window.addEventListener("load", go); }
        }
    }
}());
