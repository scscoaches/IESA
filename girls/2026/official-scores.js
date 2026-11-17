(function () {
    "use strict";

    var directoryUrl = "https://www.iesa.org/activities/members.asp";
    var statsUrl = "https://www.iesa.org/activities/memberStats.asp?ActivityCode=GBK";
    var directory;
    var selectedTeam;
    var selectedSchoolId;
    var dialog = document.getElementById("record-dialog");
    var teamName = document.getElementById("team-name");
    var teamRecord = document.getElementById("team-record");
    var history = document.querySelector("#score-history tbody");
    var note = document.getElementById("record-note");
    var refresh = document.getElementById("refresh-scores");
    var official = document.getElementById("official-scores");

    function normalize(value) {
        return value.replace(/\s+\(Co-op\)/g, "").replace(/\s+/g, " ").trim().toLowerCase();
    }

    async function getDirectory() {
        if (directory) { return directory; }
        var html = await (await fetch(directoryUrl)).text();
        var documentPage = new DOMParser().parseFromString(html, "text/html");
        directory = {};
        Array.prototype.forEach.call(documentPage.querySelectorAll('a[href*="memberdetail.asp?SchoolID="]'), function (link) {
            var match = link.getAttribute("href").match(/SchoolID=(\d+)/);
            if (match) { directory[normalize(link.textContent)] = match[1]; }
        });
        return directory;
    }

    function setRows(games) {
        document.getElementById("score-history").innerHTML = "<tbody></tbody>";
        history = document.querySelector("#score-history tbody");
        games.forEach(function (game) {
            var row = document.createElement("tr");
            var opponent = document.createElement("td");
            var score = document.createElement("td");
            opponent.textContent = game.opponent;
            score.textContent = game.score;
            row.appendChild(opponent);
            row.appendChild(score);
            history.appendChild(row);
        });
    }

    function parseGames(html) {
        var page = new DOMParser().parseFromString(html, "text/html");
        var games = [];
        Array.prototype.forEach.call(page.querySelectorAll("tr"), function (row) {
            var cells = Array.prototype.map.call(Array.prototype.filter.call(row.children, function (cell) {
                return cell.tagName === "TD";
            }), function (cell) {
                return cell.textContent.replace(/\s+/g, " ").trim();
            }).filter(Boolean);
            if (cells.length >= 2 && (/^PENDING$/i.test(cells[cells.length - 1]) || /^\d+\s*-\s*\d+$/.test(cells[cells.length - 1]))) {
                games.push({ opponent: cells[0], score: cells[cells.length - 1].toUpperCase() });
            }
        });
        return games;
    }

    async function loadScores() {
        refresh.disabled = true;
        official.disabled = true;
        teamRecord.textContent = "Loading official IESA results...";
        note.textContent = "Checking IESA’s posted Girls Basketball contests.";
        try {
            var schools = await getDirectory();
            selectedSchoolId = schools[normalize(selectedTeam)];
            if (!selectedSchoolId) {
                throw new Error("This bracket name was not found in the IESA member-school directory.");
            }
            official.disabled = false;
            var response = await fetch(statsUrl + "&SchoolID=" + encodeURIComponent(selectedSchoolId) + "&GradeLevel=" + encodeURIComponent(window.tournamentData.grade === "7th" ? "7" : "8"));
            if (!response.ok) { throw new Error("IESA returned " + response.status + "."); }
            var games = parseGames(await response.text());
            var completed = games.filter(function (game) { return game.score !== "PENDING"; });
            var record = completed.reduce(function (total, game) {
                var scores = game.score.split("-").map(Number);
                if (scores[0] > scores[1]) { total.wins++; }
                if (scores[0] < scores[1]) { total.losses++; }
                return total;
            }, { wins: 0, losses: 0 });
            if (!games.length) { games = [{ opponent: "No IESA contests posted", score: "PENDING" }]; }
            setRows(games);
            teamRecord.textContent = "Official IESA record: " + record.wins + "–" + record.losses;
            note.textContent = "Last refreshed from IESA. PENDING games do not affect the record.";
        } catch (error) {
            setRows([{ opponent: "Unable to load official results", score: "PENDING" }]);
            teamRecord.textContent = "Official IESA record unavailable";
            note.textContent = error.message;
        } finally {
            refresh.disabled = false;
        }
    }

    Array.prototype.forEach.call(document.querySelectorAll(".regional .entry"), function (entry) {
        entry.addEventListener("click", function () {
            selectedTeam = entry.textContent;
            selectedSchoolId = null;
            teamName.textContent = selectedTeam;
            if (!dialog.open) { dialog.showModal(); }
            loadScores();
        });
    });

    refresh.addEventListener("click", loadScores);
    official.onclick = function () {
        if (selectedSchoolId) {
            window.open(statsUrl + "&SchoolID=" + selectedSchoolId + "&GradeLevel=" + (window.tournamentData.grade === "7th" ? "7" : "8"), "_blank", "noopener");
        }
    };
}());
