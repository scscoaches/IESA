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

    function showSelectedTeam() {
        var team = cache.teams[selected];
        name.textContent = selected;
        body.innerHTML = "";
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
        (team.games.length ? team.games : [{ opponent: "No IESA contests posted", score: "PENDING" }]).forEach(function (game) {
            var row = document.createElement("tr");
            var opponent = document.createElement("td");
            var score = document.createElement("td");
            opponent.textContent = game.opponent;
            score.textContent = game.score;
            // Keep IESA's schedule order; highlight recently posted scores in place.
            var changes = window.iesaScoreChanges;
            if (changes && changes.isRecent(selected, game.opponent, 24)) {
                row.className = "recent-score";
            }
            row.appendChild(opponent);
            row.appendChild(score);
            body.appendChild(row);
        });
        note.textContent = (team.updatedAt ? "Checked directly with IESA: " + team.updatedAt +
            ". Results may be reused for up to five minutes. This live result is for this browser only; the shared site cache still refreshes nightly." :
            "Nightly cache updated from IESA: " + cache.updatedAt + ".") +
            " PENDING games do not affect the record.";
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

    refresh.addEventListener("click", async function () {
        if (!selected) { return; }
        var requestedTeam = selected;
        refresh.disabled = true;
        note.textContent = "Checking " + requestedTeam + "'s scores directly with IESA...";
        try {
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
            if (selected === requestedTeam) { showSelectedTeam(); }
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
}());
