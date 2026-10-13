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
    var strength = null;
    var strengthNote = document.createElement("div");
    strengthNote.className = "strength-note";
    strengthNote.hidden = true;
    record.insertAdjacentElement("afterend", strengthNote);
    // Only the schedule scrolls; the team name, strength card, close button and Update stay visible.
    var scrollArea = document.createElement("div");
    scrollArea.className = "record-scroll";
    strengthNote.insertAdjacentElement("afterend", scrollArea);
    scrollArea.appendChild(document.getElementById("score-history"));

    official.onclick = null;

    // Each link is inserted directly after the IESA link, so build them in reverse.
    var streamLabels = { nfhs: "NFHS Network", youtube: "YouTube", hudl: "Hudl" };
    var streamLinks = ["hudl", "youtube", "nfhs"].map(function (kind) {
        var link = document.createElement("a");
        link.className = "stream-link";
        link.target = "_blank";
        link.rel = "noopener";
        link.hidden = true;
        var label = streamLabels[kind];
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
    // Hudl games are published in the same shape, labelled with the bracket name.
    var streamKinds = [
        { kind: "nfhs", label: "NFHS Network", file: "../nfhs-events.json" },
        { kind: "hudl", label: "Hudl", file: "../hudl-events.json" }
    ];
    var streamGames = {};
    var genericWords = /\b(?:middle|school|schools|jr|junior|high|jhs|ms|gs|hs|grade|co ?op|elementary|the|and)\b/g;

    function nameWords(text) {
        return String(text).toLowerCase().replace(/[^a-z0-9]+/g, " ")
            .replace(genericWords, " ").split(" ").filter(Boolean);
    }

    function sideMatches(side, words) {
        return side.length > 0 && side.every(function (word) { return words.indexOf(word) >= 0; });
    }

    async function loadStreamGames(source) {
        try {
            var response = await fetch(source.file + "?v=" + Date.now(), { cache: "no-store" });
            if (!response.ok) { return; }
            var loaded = await response.json();
            var seen = {};
            var games = [];
            Object.keys(loaded.schools || {}).forEach(function (school) {
                [].concat(loaded.schools[school] || []).forEach(function (game) {
                    if (!game || !game.key || !game.url || seen[game.key]) { return; }
                    // Tournament streams prefix the matchup: "2026 ... Championship — A vs. B".
                    var sides = String(game.label).split(/\s+[\u2014\u2013]\s+/).pop().split(/\s+vs\.?\s+/i);
                    if (sides.length !== 2) { return; }
                    seen[game.key] = true;
                    games.push({ url: game.url, sides: sides.map(nameWords) });
                });
            });
            streamGames[source.kind] = games;
            if (selected && dialog.open) { showSelectedTeam(); }
        } catch (error) {
            delete streamGames[source.kind];
        }
    }

    function opponentWords(matchup, ownWords) {
        var name = opponentName(matchup, ownWords);
        return name === null ? null : nameWords(name);
    }

    function opponentName(matchup, ownWords) {
        var sides = matchupSides(matchup, ownWords);
        return sides ? sides.opponent : null;
    }

    function matchupSides(matchup, ownWords) {
        var text = String(matchup);
        var parts = text.split(/\s+(?:def\.|vs\.)\s+/i);
        if (parts.length !== 2) { return null; }
        var own = selected.replace(/\s+\(Co-?op\)$/i, "").trim().toLowerCase();
        var index = parts.findIndex(function (part) { return part.trim().toLowerCase() === own; });
        if (index < 0) {
            index = parts.findIndex(function (part) { return sideMatches(nameWords(part), ownWords); });
        }
        if (index < 0) { return null; }
        return { ownFirst: index === 0, decided: /\sdef\.\s/i.test(text), opponent: parts[1 - index].trim() };
    }

    // "def. Ramsey" / "lost to Westville JHS" / "vs. Litchfield" for narrow screens.
    function shortMatchup(matchup) {
        var sides = matchupSides(matchup, nameWords(selected));
        if (!sides) { return matchup; }
        if (!sides.decided) { return "vs. " + sides.opponent; }
        return (sides.ownFirst ? "def. " : "lost to ") + sides.opponent;
    }

    // Weekly, unofficial strength of schedule from Update-Strength.ps1.
    async function loadStrength() {
        try {
            var response = await fetch("../strength-" + grade + ".json?v=" + Date.now(), { cache: "no-store" });
            if (!response.ok) { return; }
            strength = await response.json();
            if (selected && dialog.open) { showSelectedTeam(); }
        } catch (error) {
            strength = null;
        }
    }

    function ordinal(n) {
        var suffixes = ["th", "st", "nd", "rd"];
        var v = n % 100;
        return n + (suffixes[(v - 20) % 10] || suffixes[v] || suffixes[0]);
    }

    function showStrength() {
        var entry = strength && strength.teams && strength.teams[selected];
        strengthNote.hidden = !entry;
        if (!entry) { return; }
        strengthNote.innerHTML = "";

        var head = el("div", "sos-head");
        head.appendChild(el("span", "sos-title", "Strength of schedule"));
        var rank = el("span", "sos-rank", ordinal(entry.rank) + " of " + entry.of);
        rank.title = "Rank among regional teams (1st = toughest)";
        head.appendChild(rank);
        strengthNote.appendChild(head);
        if (entry.ratedGames < 4) {
            strengthNote.appendChild(el("div", "sos-sub", "Early season, few games rated"));
        }

        var hasOwp = entry.opponentsWinPct !== null && entry.opponentsWinPct !== undefined;
        var bigger = entry.vsBigger.wins + entry.vsBigger.losses;
        var stats = el("div", "sos-stats");
        stats.appendChild(stat(hasOwp ? entry.opponentsWinPct.toFixed(3).replace(/^0/, "") : "—",
            "Opp. win %", entry.ratedGames + (entry.ratedGames === 1 ? " game" : " games")));
        stats.appendChild(stat(bigger ? entry.vsBigger.wins + "-" + entry.vsBigger.losses : "—",
            "vs 3A/4A", bigger ? "" : "none played"));
        stats.appendChild(stat(String(entry.qualityWins || 0), "Quality wins", "over .500 teams"));
        strengthNote.appendChild(stats);

        var classes = ["1A", "2A", "3A", "4A", "other"];
        var total = classes.reduce(function (sum, c) { return sum + (entry.mix[c] || 0); }, 0);
        if (total) {
            var bar = el("div", "sos-bar");
            bar.setAttribute("role", "img");
            var labels = [];
            classes.forEach(function (c) {
                var n = entry.mix[c] || 0;
                if (!n) { return; }
                var label = c === "other" ? "Other" : c;
                var seg = el("span", "sos-seg sos-" + c.toLowerCase(), label + "-" + n);
                seg.style.flexGrow = n;
                seg.title = label + ": " + n + (n === 1 ? " game" : " games");
                bar.appendChild(seg);
                labels.push(label + " " + n);
            });
            bar.setAttribute("aria-label", "Schedule by class: " + labels.join(", "));
            strengthNote.appendChild(el("div", "sos-label", total + (total === 1 ? " game" : " games")));
            strengthNote.appendChild(bar);
        }
    }

    function el(tag, className, text) {
        var node = document.createElement(tag);
        if (className) { node.className = className; }
        if (text !== undefined) { node.textContent = text; }
        return node;
    }

    function stat(value, label, note) {
        var box = el("div", "sos-stat");
        box.appendChild(el("b", "", value));
        box.appendChild(el("span", "", label));
        if (note) { box.appendChild(el("small", "", note)); }
        return box;
    }

    function opponentTag(game) {
        if (!strength || !strength.opponents) { return ""; }
        var name = opponentName(game.opponent, nameWords(selected));
        var info = name && strength.opponents[name.replace(/\((?:Host Info|Host|Co-?op|NON-COMPETITOR)\)/gi, "").replace(/\s+/g, " ").trim().toLowerCase()];
        if (!info) { return ""; }
        var bits = [];
        if (info.class) { bits.push(info.class); }
        if (info.wins !== undefined && info.wins !== null) { bits.push(info.wins + "-" + info.losses); }
        return bits.join(" · ");
    }

    // Only link a game when exactly one card from a provider fits the row and no
    // other row fits that card, so repeat opponents are left unlinked rather than guessed.
    function streamLinksFor(games) {
        var links = new Map();
        var ownWords = nameWords(selected);
        var opponents = games.map(function (game) { return opponentWords(game.opponent, ownWords); });
        streamKinds.forEach(function (source) {
            var cards = streamGames[source.kind];
            if (!cards || !cards.length) { return; }
            var candidates = opponents.map(function (opponent) {
                if (!opponent || !opponent.length) { return []; }
                return cards.filter(function (card) {
                    return (sideMatches(card.sides[0], ownWords) && sideMatches(card.sides[1], opponent)) ||
                        (sideMatches(card.sides[1], ownWords) && sideMatches(card.sides[0], opponent));
                });
            });
            candidates.forEach(function (list, index) {
                if (list.length !== 1) { return; }
                var shared = candidates.filter(function (other) { return other.indexOf(list[0]) >= 0; }).length;
                if (shared !== 1) { return; }
                if (!links.has(games[index])) { links.set(games[index], []); }
                links.get(games[index]).push({ url: list[0].url, source: source });
            });
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
        showStrength();
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
        var watchLinks = streamLinksFor(ordered);
        ordered.forEach(function (game) {
            var row = document.createElement("tr");
            var opponent = document.createElement("td");
            var score = document.createElement("td");
            var matchup = document.createElement("span");
            matchup.className = "matchup";
            var full = document.createElement("span");
            full.className = "matchup-full";
            full.textContent = game.opponent;
            var brief = document.createElement("span");
            brief.className = "matchup-short";
            brief.textContent = shortMatchup(game.opponent);
            matchup.appendChild(full);
            matchup.appendChild(brief);
            opponent.appendChild(matchup);
            var tagText = opponentTag(game);
            if (tagText) {
                opponent.classList.add("has-tag");
                var tag = document.createElement("span");
                tag.className = "opponent-tag";
                tag.title = "Opponent's IESA class and record (weekly)";
                tag.textContent = tagText;
                opponent.appendChild(tag);
            }
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
                (watchLinks.get(game) || []).forEach(function (entry) {
                    var link = document.createElement("a");
                    link.href = entry.url;
                    link.target = "_blank";
                    link.rel = "noopener";
                    link.title = "Watch on " + entry.source.label;
                    link.setAttribute("aria-label", "Watch " + game.opponent + " on " + entry.source.label);
                    var icon = document.createElement("img");
                    icon.src = "../icons/" + entry.source.kind + ".svg";
                    icon.alt = "";
                    link.appendChild(icon);
                    watch.appendChild(link);
                });
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
        official.textContent = "";
        official.append(el("span", "official-team", selected + " "), "IESA page");
        official.setAttribute("aria-label", selected + " IESA page");
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
    streamKinds.forEach(loadStreamGames);
    loadStrength();
}());
