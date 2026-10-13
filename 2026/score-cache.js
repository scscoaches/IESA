(function () {
    "use strict";

    var grade = window.tournamentData.grade === "7th" ? "7th" : "8th";
    var cacheUrl = "../scores-" + grade + ".json";
    var dialog = document.getElementById("record-dialog");
    var name = document.getElementById("team-name");
    var record = document.getElementById("team-record");
    var body = document.querySelector("#score-history tbody");
    var note = document.getElementById("record-note");
    var official = document.getElementById("official-scores");
    var refresh = document.getElementById("refresh-scores");
    var cache = window.iesaScoreCache || { teams: {} };
    var cacheLoaded = Boolean(window.iesaScoreCache);
    var selected;

    official.onclick = null;

    // Each link is inserted directly after the IESA link, so build them in reverse.
    var streamLinks = ["hudl", "nfhs"].map(function (kind) {
        var link = document.createElement("a");
        link.className = "stream-link";
        link.target = "_blank";
        link.rel = "noopener";
        link.hidden = true;
        var label = kind === "nfhs" ? "NFHS Network" : "Hudl";
        var icon = document.createElement("img");
        icon.src = "../icons/" + kind + ".svg";
        icon.alt = "";
        link.title = label;
        link.appendChild(icon);
        official.insertAdjacentElement("afterend", link);
        return { kind: kind, label: label, link: link };
    });

    function showStreamLinks() {
        var links = (window.iesaTeamLinks || {})[selected] || {};
        streamLinks.forEach(function (entry) {
            var url = links[entry.kind];
            entry.link.hidden = !url;
            entry.link.href = url || "#";
            entry.link.setAttribute("aria-label", selected + " on " + entry.label);
        });
    }

    function isPending(game) {
        return !game.score || String(game.score).toUpperCase() === "PENDING";
    }

    // NFHS game cards use short school names ("Sangamon Valley vs. Morrisonville"),
    // so a card matches a score row when each card side's words appear in one team.
    var nfhsGames = null;
    var genericWords = /\b(?:middle|school|schools|jr|junior|high|jhs|ms|gs|hs|grade|co ?op|elementary|the|and)\b/g;

    function nameWords(text) {
        return String(text).toLowerCase().replace(/[^a-z0-9]+/g, " ")
            .replace(genericWords, " ").split(" ").filter(Boolean);
    }

    function sideMatches(side, words) {
        return side.length > 0 && side.every(function (word) { return words.indexOf(word) >= 0; });
    }

    async function loadNfhsGames() {
        try {
            var response = await fetch("../nfhs-events.json?v=" + Date.now(), { cache: "no-store" });
            if (!response.ok) { return; }
            var loaded = await response.json();
            var seen = {};
            var games = [];
            Object.keys(loaded.schools || {}).forEach(function (slug) {
                [].concat(loaded.schools[slug] || []).forEach(function (game) {
                    if (!game || !game.key || !game.url || seen[game.key]) { return; }
                    // Tournament streams prefix the matchup: "2026 ... Championship — A vs. B".
                    var sides = String(game.label).split(/\s+[\u2014\u2013]\s+/).pop().split(/\s+vs\.?\s+/i);
                    if (sides.length !== 2) { return; }
                    seen[game.key] = true;
                    games.push({ url: game.url, sides: sides.map(nameWords) });
                });
            });
            nfhsGames = games;
            if (selected && dialog.open) { showSelectedTeam(); }
        } catch (error) {
            nfhsGames = null;
        }
    }

    function opponentWords(matchup, ownWords) {
        var parts = String(matchup).split(/\s+(?:def\.|vs\.)\s+/i);
        if (parts.length !== 2) { return null; }
        var own = selected.replace(/\s+\(Co-?op\)$/i, "").trim().toLowerCase();
        var index = parts.findIndex(function (part) { return part.trim().toLowerCase() === own; });
        if (index < 0) {
            index = parts.findIndex(function (part) { return sideMatches(nameWords(part), ownWords); });
        }
        return index < 0 ? null : nameWords(parts[1 - index]);
    }

    // Only link a game when exactly one NFHS card fits the row and no other row
    // fits that card, so repeat opponents are left unlinked rather than guessed.
    function nfhsLinksFor(games) {
        var links = new Map();
        if (!nfhsGames || !nfhsGames.length) { return links; }
        var ownWords = nameWords(selected);
        var candidates = games.map(function (game) {
            var opponent = opponentWords(game.opponent, ownWords);
            if (!opponent || !opponent.length) { return []; }
            return nfhsGames.filter(function (nfhs) {
                return (sideMatches(nfhs.sides[0], ownWords) && sideMatches(nfhs.sides[1], opponent)) ||
                    (sideMatches(nfhs.sides[1], ownWords) && sideMatches(nfhs.sides[0], opponent));
            });
        });
        candidates.forEach(function (list, index) {
            if (list.length !== 1) { return; }
            var shared = candidates.filter(function (other) { return other.indexOf(list[0]) >= 0; }).length;
            if (shared === 1) { links.set(games[index], list[0].url); }
        });
        return links;
    }

    // Show the most recently posted scores first. Only games whose score changed
    // since tracking began carry a timestamp, so games without one keep IESA's
    // schedule order below them, and unplayed games stay at the bottom.
    function orderGames(games) {
        if (!games || !games.length) {
            return [{ opponent: "No IESA contests posted", score: "PENDING" }];
        }
        var changes = window.iesaScoreChanges;
        return games.map(function (game, index) {
            var postedAt = changes && !isPending(game)
                ? changes.postedAt(selected, game.opponent)
                : null;
            return { game: game, index: index, postedAt: postedAt };
        }).map(function (entry) {
            // 0 = scored before change tracking began, so oldest of all;
            // 1 = scored during tracking, ordered by its own timestamp;
            // 2 = not yet played.
            entry.tier = isPending(entry.game) ? 2 : (entry.postedAt === null ? 0 : 1);
            return entry;
        }).sort(function (a, b) {
            if (a.tier !== b.tier) { return a.tier - b.tier; }
            if (a.tier === 1) { return a.postedAt - b.postedAt || a.index - b.index; }
            return a.index - b.index;
        }).map(function (entry) {
            return entry.game;
        });
    }

    function showSelectedTeam() {
        var team = cache.teams[selected];
        name.textContent = selected;
        body.innerHTML = "";
        showStreamLinks();
        if (!cacheLoaded) {
            record.textContent = "Loading latest IESA score cache...";
            note.textContent = "Retrieving the most recent overnight IESA update.";
            official.hidden = true;
            return;
        }
        if (!team) {
            record.textContent = "Official IESA record unavailable";
            note.textContent = "No official IESA school match is available in the latest nightly score cache.";
            official.hidden = true;
            return;
        }

        record.textContent = "Official IESA record: " + team.record.wins + "-" + team.record.losses;
        var ordered = orderGames(team.games);
        var watchLinks = nfhsLinksFor(ordered);
        ordered.forEach(function (game) {
            var row = document.createElement("tr");
            var opponent = document.createElement("td");
            var score = document.createElement("td");
            opponent.textContent = game.opponent;
            score.textContent = game.score;
            score.className = "score-cell";
            var changes = window.iesaScoreChanges;
            if (changes && changes.isRecent(selected, game.opponent, 24)) {
                row.className = "recent-score";
            }
            row.appendChild(opponent);
            row.appendChild(score);
            if (watchLinks.size) {
                var watch = document.createElement("td");
                watch.className = "stream-cell";
                var url = watchLinks.get(game);
                if (url) {
                    var link = document.createElement("a");
                    link.href = url;
                    link.target = "_blank";
                    link.rel = "noopener";
                    link.title = "Watch on NFHS Network";
                    link.setAttribute("aria-label", "Watch " + game.opponent + " on NFHS Network");
                    var icon = document.createElement("img");
                    icon.src = "../icons/nfhs.svg";
                    icon.alt = "";
                    link.appendChild(icon);
                    watch.appendChild(link);
                }
                row.appendChild(watch);
            }
            body.appendChild(row);
        });
        note.textContent = team.updatedAt
            ? "Checked directly with IESA: " + team.updatedAt +
              ". Live result is for this browser session only."
            : "Nightly cache updated from IESA: " + cache.updatedAt + ".";
        official.hidden = !team.sourceUrl;
        official.href = team.sourceUrl || "#";
        official.textContent = selected + " IESA page";
    }

    async function loadCache() {
        try {
            var response = await fetch(cacheUrl + "?v=" + Date.now(), { cache: "no-store" });
            if (!response.ok) { throw new Error("HTTP " + response.status); }
            var loaded = await response.json();
            if (!loaded || !loaded.teams || !loaded.updatedAt) {
                throw new Error("Invalid nightly score cache");
            }
            if (cacheLoaded) { return; }
            cache = loaded;
            cacheLoaded = true;
            window.iesaScoreCache = cache;
            document.dispatchEvent(new CustomEvent("iesaScoresLoaded", { detail: cache }));
            if (selected) { showSelectedTeam(); }
        } catch (error) {
            if (selected) { note.textContent = "The nightly score cache could not be loaded: " + error.message; }
        }
    }

    async function fetchLiveTeam(requestedTeam) {
        var response = await fetch("../team-scores.ashx", {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: new URLSearchParams({ grade: grade, team: requestedTeam })
        });
        var body = await response.text();
        var result = null;
        try { result = JSON.parse(body); } catch (parseError) { result = null; }
        if (!result || typeof result !== "object") {
            throw new Error("The site's score service returned an unexpected response (HTTP " +
                response.status + "). Please try again in a moment.");
        }
        if (!response.ok) { throw new Error(result.error || "HTTP " + response.status); }
        if (result.team !== requestedTeam || !result.record ||
            !Array.isArray(result.games) || !result.updatedAt || !result.sourceUrl) {
            throw new Error("IESA returned an invalid score response.");
        }
        cache.teams[requestedTeam] = result;
        cacheLoaded = true;
        window.iesaScoreCache = cache;
        document.dispatchEvent(new CustomEvent("iesaScoresLoaded", { detail: cache }));
        if (selected === requestedTeam && dialog.open) { showSelectedTeam(); }
        return result;
    }
    // GitHub Pages serves static files only, so the ASP.NET live lookup exists only under IIS.
    var liveLookupAvailable = !/\.github\.io$/i.test(location.hostname);
    refresh.hidden = !liveLookupAvailable;
    if (liveLookupAvailable) { window.iesaFetchLiveTeam = fetchLiveTeam; }

    refresh.addEventListener("click", async function () {
        if (!selected) { return; }
        var requestedTeam = selected;
        refresh.disabled = true;
        note.textContent = "Checking " + requestedTeam + "'s scores directly with IESA...";
        try {
            await fetchLiveTeam(requestedTeam);
        } catch (error) {
            if (selected === requestedTeam) {
                note.textContent = "Live score check failed: " + error.message +
                    (/[.!?]$/.test(error.message) ? "" : ".") +
                    " The displayed scores have not been changed.";
            }
        } finally {
            refresh.disabled = false;
        }
    });

    document.addEventListener("click", function (event) {
        var entry = event.target.closest(".regional > .entry");
        if (!entry) { return; }
        event.stopImmediatePropagation();
        selected = entry.dataset.team || entry.childNodes[0].nodeValue.trim();
        if (!dialog.open) { dialog.showModal(); }
        showSelectedTeam();
    }, true);

    if (cacheLoaded) {
        document.dispatchEvent(new CustomEvent("iesaScoresLoaded", { detail: cache }));
    } else {
        loadCache();
    }
    loadNfhsGames();
}());
