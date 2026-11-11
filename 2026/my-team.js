(function () {
    "use strict";
    // The visitor's own team: highlighted in every bracket and marked with a
    // trophy in the year and class menus for each top-four state finish.
    // Saved per browser; Springfield Christian until a visitor picks another.
    var STORAGE_KEY = "iesa-my-team";
    // Every name the chosen school appears under (IESA sometimes drops or adds
    // the town), saved with the choice so highlighting needs no extra request.
    var KEYS_KEY = "iesa-my-team-keys";
    var DEFAULT_TEAM = "Springfield Christian";
    var PLACES = ["state champion", "state runner-up", "third place", "fourth place"];
    var ORDINALS = ["1st", "2nd", "3rd", "4th"];
    var root = new URL("../", document.currentScript.src);
    var files = {};

    // Must match Get-TeamKey in Build-IesaTeamIndex.ps1: records, "(Co-op)",
    // possessive 's, periods and hyphens do not distinguish schools.
    function key(name) {
        return String(name || "").replace(/\s*\(\d+-\d+\)\s*$/, "").replace(/\s*\(co-?op\)\s*$/i, "")
            .toLowerCase().replace(/['\u2019]s\b/g, "").replace(/\./g, "").replace(/-/g, " ")
            .replace(/\s+/g, " ").trim();
    }

    function stored() {
        try {
            var value = window.localStorage.getItem(STORAGE_KEY);
            return value === null ? DEFAULT_TEAM : value;
        } catch (error) {
            return DEFAULT_TEAM;
        }
    }

    var name = stored();
    var myKey = key(name);
    var myKeys = [myKey];
    try {
        var savedKeys = JSON.parse(window.localStorage.getItem(KEYS_KEY) || "null");
        if (Array.isArray(savedKeys) && savedKeys.indexOf(myKey) >= 0) { myKeys = savedKeys; }
    } catch (error) { /* keep the single key */ }

    function matches(team) { return !!myKey && myKeys.indexOf(key(team)) >= 0; }

    // The index of a school in teams.json, following known name aliases.
    function indexOf(teams, schoolKey) {
        var aliases = teams.aliases || {};
        if (Object.prototype.hasOwnProperty.call(aliases, schoolKey)) { return aliases[schoolKey]; }
        return (teams.names || []).findIndex(function (school) { return key(school) === schoolKey; });
    }

    function keysFor(teams, schoolKey) {
        var index = indexOf(teams, schoolKey);
        if (index < 0) { return [schoolKey]; }
        var keys = [key(teams.names[index])];
        Object.keys(teams.aliases || {}).forEach(function (alias) {
            if (teams.aliases[alias] === index) { keys.push(alias); }
        });
        if (keys.indexOf(schoolKey) < 0) { keys.push(schoolKey); }
        return keys;
    }

    function saveKeys(keys) {
        try { window.localStorage.setItem(KEYS_KEY, JSON.stringify(keys)); } catch (error) { /* best effort */ }
    }

    function load(file) {
        if (!files[file]) {
            files[file] = fetch(new URL(file, root).href, { cache: "no-store" }).then(function (response) {
                if (!response.ok) { throw new Error(file + " returned HTTP " + response.status); }
                return response.json();
            });
        }
        return files[file];
    }

    // Every top-four state finish of the chosen team, newest first.
    function finishes() {
        if (!myKey) { return Promise.resolve([]); }
        return load("placements.json").then(function (placements) {
            var found = [];
            (placements.results || []).forEach(function (result) {
                (result.places || []).forEach(function (school, index) {
                    if (matches(school)) {
                        found.push({ year: result.year, grade: result.grade, className: result.className,
                            place: index + 1, source: result.source });
                    }
                });
            });
            return found;
        });
    }

    // The class the chosen team played in that season and grade, if known.
    function classFor(year, grade) {
        if (!myKey) { return Promise.resolve(null); }
        return load("teams.json").then(function (teams) {
            var index = indexOf(teams, myKey);
            var classes = teams.seasons && teams.seasons[year] && teams.seasons[year][grade];
            if (index < 0 || !classes) { return null; }
            var match = Object.keys(classes).filter(function (className) {
                return classes[className].indexOf(index) >= 0;
            })[0];
            return match && match !== "-" ? match : null;
        });
    }

    // The page for a season, class and grade. The first class archived for a
    // year keeps <year>/<grade>; other classes live in <year>/<class>/<grade>.
    function pageUrl(season, className, grade) {
        var folder = !className || className === season.className ? String(season.year) :
            season.year + "/" + className;
        return new URL(folder + "/" + grade + "/index.html", root).href;
    }

    function describe(finish) {
        return PLACES[finish.place - 1] + (finish.className ? " (Class " + finish.className + ")" : "");
    }

    // Choosing a team keeps the dialog open so its state finishes can be read;
    // closing the dialog reloads the page to re-highlight brackets and menus.
    var changed = false;
    var renderDialog = null;
    function choose(team, keys) {
        try {
            window.localStorage.setItem(STORAGE_KEY, team);
            window.localStorage.setItem(KEYS_KEY, JSON.stringify(keys || [key(team)]));
        } catch (error) {
            window.alert("Your browser is not allowing this site to save your team.");
            return;
        }
        name = team;
        myKey = key(team);
        myKeys = keys || [myKey];
        changed = true;
        if (renderDialog) { renderDialog(); }
    }

    function element(tag, className, text) {
        var node = document.createElement(tag);
        if (className) { node.className = className; }
        if (text !== undefined) { node.textContent = text; }
        return node;
    }

    function buildDialog() {
        var dialog = element("dialog");
        dialog.id = "my-team-dialog";
        var head = element("div", "dialog-head");
        head.appendChild(element("strong", "", "Settings"));
        var close = element("button", "", "\u00d7");
        close.type = "button";
        close.setAttribute("aria-label", "Close");
        close.addEventListener("click", function () { dialog.close(); });
        head.appendChild(close);
        dialog.appendChild(head);

        var current = element("div", "my-team-current");
        dialog.appendChild(current);

        var label = element("label", "", "Choose a team");
        label.htmlFor = "my-team-search";
        dialog.appendChild(label);
        var input = element("input");
        input.id = "my-team-search";
        input.type = "search";
        input.autocomplete = "off";
        input.placeholder = "Search all schools";
        dialog.appendChild(input);
        var results = element("div", "my-team-results");
        results.setAttribute("role", "list");
        dialog.appendChild(results);

        var history = element("div", "my-team-history");
        dialog.appendChild(history);

        var names = [];
        var teamsData = { names: [] };
        load("teams.json").then(function (teams) { teamsData = teams; names = teams.names || []; }).catch(function (error) {
            results.textContent = "The team list could not be loaded.";
            console.warn("Unable to load teams:", error);
        });
        input.addEventListener("input", function () {
            var query = key(input.value);
            results.replaceChildren();
            if (query.length < 2) { return; }
            // Older names find the school under its current name.
            var found = {};
            names.forEach(function (school) { if (key(school).indexOf(query) >= 0) { found[school] = true; } });
            Object.keys(teamsData.aliases || {}).forEach(function (alias) {
                if (alias.indexOf(query) >= 0) { found[names[teamsData.aliases[alias]]] = true; }
            });
            var matches = Object.keys(found);
            matches.sort(function (a, b) {
                return (key(a).indexOf(query) === 0 ? 0 : 1) - (key(b).indexOf(query) === 0 ? 0 : 1) ||
                    a.localeCompare(b);
            });
            matches.slice(0, 25).forEach(function (school) {
                var option = element("button", "my-team-option", school);
                option.type = "button";
                option.setAttribute("role", "listitem");
                option.addEventListener("click", function () { choose(school, keysFor(teamsData, key(school))); });
                results.appendChild(option);
            });
            if (!matches.length) { results.appendChild(element("p", "my-team-empty", "No schools match.")); }
        });

        var rendering = 0;
        function render() {
            var token = ++rendering;
            current.replaceChildren(element("h3", "my-team-heading", "My team"),
                element(name ? "strong" : "span", name ? "" : "my-team-empty", name || "None"));
            if (name) {
                var clear = element("button", "my-team-clear", "Clear");
                clear.type = "button";
                clear.addEventListener("click", function () { choose(""); });
                current.appendChild(clear);
            }
            input.value = "";
            results.replaceChildren();
            history.replaceChildren();
            if (!name) { return; }
            Promise.all([finishes(), load("seasons.json")]).then(function (loaded) {
                if (token !== rendering) { return; }
                var list = loaded[0];
                var seasons = loaded[1];
                history.appendChild(element("strong", "", "State finishes"));
                if (!list.length) {
                    history.appendChild(element("p", "my-team-empty", "No top-four state finishes on record."));
                    return;
                }
                var items = element("ul");
                list.forEach(function (finish) {
                    var item = element("li");
                    var season = seasons.filter(function (entry) { return entry.year === finish.year; })[0];
                    var text = finish.year + " " + (finish.grade === "combined" ? "Combined" : finish.grade) +
                        " \u2013 " + ORDINALS[finish.place - 1] + (finish.className ? ", Class " + finish.className : "");
                    var classes = season ? (season.classes || [season.className]) : [];
                    if (season && (!finish.className || classes.indexOf(finish.className) >= 0)) {
                        var link = element("a", "", text);
                        link.href = pageUrl(season, finish.className, finish.grade);
                        item.appendChild(link);
                    } else {
                        item.textContent = text;
                    }
                    item.insertBefore(document.createTextNode("\uD83C\uDFC6 "), item.firstChild);
                    items.appendChild(item);
                });
                history.appendChild(items);
            }).catch(function (error) {
                console.warn("Unable to load state finishes:", error);
            });
        }
        renderDialog = render;
        render();

        // The dark-mode toggle lives here rather than in the crowded header.
        // theme.js finds it by id, so it is moved, not recreated.
        var toggle = document.getElementById("theme-toggle");
        if (toggle) {
            var row = element("div", "settings-row");
            row.appendChild(element("span", "", "Dark mode"));
            row.appendChild(toggle);
            dialog.appendChild(row);
        }
        dialog.addEventListener("close", function () {
            if (changed) { window.location.reload(); }
        });
        document.body.appendChild(dialog);
        return dialog;
    }

    var dialog = null;
    function open() {
        if (!dialog) { dialog = buildDialog(); }
        dialog.showModal();
        document.getElementById("my-team-search").focus();
    }

    function addButton() {
        var tools = document.querySelector(".topbar .tools");
        if (!tools || document.getElementById("my-team-button")) { return; }
        var button = element("button");
        button.id = "my-team-button";
        button.type = "button";
        var icon = element("img");
        icon.src = new URL("2026/settings-icon.svg", root).href;
        icon.alt = "";
        icon.setAttribute("aria-hidden", "true");
        button.appendChild(icon);
        button.title = "Settings" + (name ? " \u2013 my team: " + name : "");
        button.setAttribute("aria-label", button.title);
        button.addEventListener("click", open);
        tools.insertBefore(button, tools.firstChild);
        if (!dialog) { dialog = buildDialog(); }
    }

    window.iesaMyTeam = {
        name: name,
        key: key,
        matches: matches,
        load: load,
        finishes: finishes,
        classFor: classFor,
        pageUrl: pageUrl,
        describe: describe,
        open: open
    };

    // Keep the saved name variants current (aliases can be added later);
    // the next page load highlights with them.
    if (myKey) {
        load("teams.json").then(function (teams) {
            var keys = keysFor(teams, myKey);
            if (keys.join("|") !== myKeys.join("|")) { myKeys = keys; saveKeys(keys); }
        }).catch(function () { /* the picker reports load failures */ });
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", addButton);
    } else {
        addButton();
    }
}());
