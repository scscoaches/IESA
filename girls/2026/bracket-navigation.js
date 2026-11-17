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
        message.textContent = matches.length ? matches.length + " team" + (matches.length === 1 ? "" : "s") + " found" : "No matching teams.";
        matches.forEach(function (entry) {
            var button = document.createElement("button");
            button.type = "button";
            button.textContent = entry.name + " — " + document.querySelector("#" + entry.cardId + " .head").textContent;
            button.addEventListener("click", function () { navigate(entry.cardId, entry.name); });
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
}());
