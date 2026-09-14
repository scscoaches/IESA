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
            row.appendChild(opponent);
            row.appendChild(score);
            body.appendChild(row);
        });
        note.textContent = "Updated from IESA: " + cache.updatedAt + ". PENDING games do not affect the record.";
        official.hidden = !team.sourceUrl;
        official.href = team.sourceUrl || "#";
        official.textContent = "Visit " + selected + "'s " + grade + "-grade IESA basketball page";
    }

    function loadCache() {
        refresh.disabled = true;
        var script = document.createElement("script");
        script.src = "../scores-" + grade + ".js?v=" + Date.now();
        script.onload = function () {
            cache = window.iesaScoreCache;
            cacheLoaded = true;
            window.iesaScoreCache = cache;
            document.dispatchEvent(new CustomEvent("iesaScoresLoaded", { detail: cache }));
            if (window.applyIesaRegionalRecords) {
                window.applyIesaRegionalRecords(cache.teams);
            }
            if (selected) { showSelectedTeam(); }
            script.remove();
            refresh.disabled = false;
        };
        script.onerror = function () {
            note.textContent = "The nightly score cache could not be loaded from this website.";
            refresh.disabled = false;
            script.remove();
        };
        document.head.appendChild(script);
    }

    document.addEventListener("click", function (event) {
        var entry = event.target.closest(".regional > .entry");
        if (!entry) { return; }
        event.stopImmediatePropagation();
        selected = entry.dataset.team || entry.childNodes[0].nodeValue.trim();
        if (!dialog.open) { dialog.showModal(); }
        showSelectedTeam();
    }, true);

    refresh.onclick = loadCache;
    if (cacheLoaded) {
        document.dispatchEvent(new CustomEvent("iesaScoresLoaded", { detail: cache }));
    } else {
        loadCache();
    }
}());
