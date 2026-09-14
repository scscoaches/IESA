(function () {
    "use strict";

    function sortRegional(card, teams) {
        var entries = Array.prototype.slice.call(card.querySelectorAll(":scope > .entry"));
        var records = teams || {};
        entries.forEach(function (entry) {
            entry.dataset.team = entry.dataset.team || entry.textContent;
            var data = records[entry.dataset.team];
            if (!data) { return; }
            var badge = entry.querySelector(".record-badge") || document.createElement("span");
            badge.className = "record-badge";
            badge.textContent = data.record.wins + "-" + data.record.losses;
            entry.appendChild(badge);
        });
        var hasCompleted = entries.some(function (entry) {
            return records[entry.dataset.team] && records[entry.dataset.team].record.completed;
        });
        if (!hasCompleted) { return; }

        entries.sort(function (left, right) {
            var leftRecord = records[left.dataset.team] ? records[left.dataset.team].record : { wins: 0, losses: 0, completed: 0 };
            var rightRecord = records[right.dataset.team] ? records[right.dataset.team].record : { wins: 0, losses: 0, completed: 0 };
            if (!leftRecord.completed && !rightRecord.completed) { return 0; }
            if (!leftRecord.completed) { return 1; }
            if (!rightRecord.completed) { return -1; }
            return rightRecord.wins / rightRecord.completed - leftRecord.wins / leftRecord.completed ||
                rightRecord.wins - leftRecord.wins || left.dataset.team.localeCompare(right.dataset.team);
        });

        entries.forEach(function (entry) {
            card.appendChild(entry);
        });
    }

    function applyRecords(teams) {
        Array.prototype.forEach.call(document.querySelectorAll(".regional"), function (regional) {
            sortRegional(regional, teams);
        });
    }

    document.addEventListener("iesaScoresLoaded", function (event) {
        applyRecords(event.detail.teams);
    });

    window.applyIesaRegionalRecords = applyRecords;
    if (window.iesaScoreCache) {
        applyRecords(window.iesaScoreCache.teams);
    }
}());
