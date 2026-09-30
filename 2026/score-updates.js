(function () {
    "use strict";

    var cache = window.iesaScoreCache || { updatedAt: "", updatedGames: [] };
    var button = document.getElementById("updates-button");
    var dialog = document.getElementById("updates-dialog");
    var tableBody = document.querySelector("#updates-table tbody");
    var summary = document.getElementById("updates-summary");
    var changes = cache.updatedGames || [];

    var fullLabel = document.createElement("span");
    fullLabel.className = "score-label-full";
    fullLabel.textContent = "Score updates (" + changes.length + ")";
    var shortLabel = document.createElement("span");
    shortLabel.className = "score-label-short";
    shortLabel.textContent = "Scores(" + changes.length + ")";
    button.replaceChildren(fullLabel, shortLabel);
    button.setAttribute("aria-label", "Score updates (" + changes.length + ")");

    changes.forEach(function (change) {
        var row = document.createElement("tr");
        var teamCell = document.createElement("td");
        var teamLink = document.createElement("a");
        teamLink.href = change.sourceUrl;
        teamLink.target = "_blank";
        teamLink.rel = "noopener";
        teamLink.textContent = change.team;
        teamCell.appendChild(teamLink);
        row.appendChild(teamCell);
        [change.opponent, change.score].forEach(function (value) {
            var cell = document.createElement("td");
            cell.textContent = value;
            row.appendChild(cell);
        });
        tableBody.appendChild(row);
    });

    if (changes.length) {
        summary.textContent = changes.length + " posted score change(s) since " + (cache.previousCaptureAt || "the previous available capture") + ".";
    } else if (cache.previousCaptureAt) {
        summary.textContent = "No newly posted or changed scores since " + cache.previousCaptureAt + ".";
    } else {
        summary.textContent = "No previous capture is available for comparison yet. Updates will appear after the next IESA score refresh.";
    }
    summary.textContent += " Last refreshed: " + (cache.updatedAt || "unavailable") + ".";

    button.addEventListener("click", function () { dialog.showModal(); });
    document.getElementById("close-updates").addEventListener("click", function () { dialog.close(); });
}());
