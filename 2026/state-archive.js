(function () {
    "use strict";
    var data = window.earlyTournamentData;
    if (!data || !data.rounds || !data.champion) {
        throw new Error("The state archive has no verified tournament data.");
    }
    var bracket = document.getElementById("bracket");
    var viewport = document.getElementById("viewport");
    window.clampBracketTransform = function(x, y, scale) {
        var scaledWidth = bracket.offsetWidth * scale;
        var scaledHeight = bracket.offsetHeight * scale;
        var marginX = Math.min(60, viewport.clientWidth / 2);
        var marginY = Math.min(60, viewport.clientHeight / 2);
        return {
            x: scaledWidth <= viewport.clientWidth ? (viewport.clientWidth - scaledWidth) / 2 :
                Math.max(marginX - scaledWidth, Math.min(viewport.clientWidth - marginX, x)),
            y: scaledHeight <= viewport.clientHeight ? (viewport.clientHeight - scaledHeight) / 2 :
                Math.max(marginY - scaledHeight, Math.min(viewport.clientHeight - marginY, y)),
            scale: scale
        };
    };
    var svg = bracket.querySelector("svg");
    var dialog = document.getElementById("archive-dialog");
    var dialogTitle = document.getElementById("archive-dialog-title");
    var dialogContent = document.getElementById("archive-dialog-content");
    var roundNames = data.rounds["First Round"] ?
        ["First Round", "Quarterfinals", "Semifinals", "State Championship"] :
        ["Quarterfinals", "Semifinals", "State Championship"];
    var cardWidth = 252, columnWidth = 305, gap = 134;
    var openingCount = data.rounds[roundNames[0]].length;
    var width = (roundNames.length + 1) * columnWidth + 65;
    var height = Math.max(790, 125 + openingCount * gap);
    bracket.style.width = width + "px";
    bracket.style.height = height + "px";
    svg.setAttribute("width", width);
    svg.setAttribute("height", height);
    svg.setAttribute("viewBox", "0 0 " + width + " " + height);
    document.getElementById("state-source").href = data.source;
    document.querySelector(".detail").textContent = data.venue ?
        "State tournament at " + data.venue : "IESA state tournament archive";

    document.querySelectorAll(".grade-link").forEach(function (link) {
        link.hidden = data.grade === "combined";
        link.classList.toggle("active", link.classList.contains(
            data.grade === "7th" ? "grade-seventh" : "grade-eighth"));
    });

    function addElement(parent, tag, className, text) {
        var element = document.createElement(tag);
        if (className) { element.className = className; }
        if (text !== undefined) { element.textContent = text; }
        parent.appendChild(element);
        return element;
    }

    function showTeam(name) {
        dialogTitle.textContent = name;
        dialogContent.replaceChildren();
        var table = addElement(dialogContent, "table");
        var header = addElement(table, "tr");
        ["Round", "Opponent", "Score"].forEach(function (label) {
            addElement(header, "th", "", label);
        });
        Object.keys(data.rounds).forEach(function (round) {
            data.rounds[round].forEach(function (game) {
                var index = game.teams.indexOf(name);
                if (index < 0) { return; }
                var row = addElement(table, "tr");
                addElement(row, "td", "", round);
                addElement(row, "td", "", game.teams[1 - index]);
                addElement(row, "td", "", game.scores[index] + "–" + game.scores[1 - index] +
                    (game.note ? " " + game.note : ""));
            });
        });
        var link = addElement(dialogContent, "a", "", "View official IESA bracket");
        link.href = data.source;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        dialog.showModal();
    }

    function openSectionals() {
        dialogTitle.textContent = data.year + " " + data.label + " sectional pairings";
        dialogContent.replaceChildren();
        var table = addElement(dialogContent, "table");
        var header = addElement(table, "tr");
        ["Sectional", "Published pairing"].forEach(function (label) {
            addElement(header, "th", "", label);
        });
        data.sectionals.forEach(function (pairing, index) {
            var row = addElement(table, "tr");
            addElement(row, "td", "", String(index + 1));
            addElement(row, "td", "", pairing.teams.join(" vs. "));
        });
        var link = addElement(dialogContent, "a", "", "View official IESA sectional pairings");
        link.href = data.sectionalSource;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        dialog.showModal();
    }
    var sectionButton = document.getElementById("sectional-button");
    if (data.sectionals.length) {
        sectionButton.hidden = false;
        sectionButton.addEventListener("click", openSectionals);
    }
    document.getElementById("archive-dialog-close").addEventListener("click", function () {
        dialog.close();
    });

    function drawWire(start, finish, third) {
        var path = document.createElementNS("http://www.w3.org/2000/svg", "path");
        var middle = (start.x + cardWidth + finish.x) / 2;
        path.setAttribute("d", "M" + (start.x + cardWidth) + " " + start.y +
            " H" + middle + " V" + finish.y + " H" + finish.x);
        path.setAttribute("class", third ? "wire archive-wire-third" : "wire");
        svg.appendChild(path);
    }

    var positions = [];
    roundNames.forEach(function (round, column) {
        var games = data.rounds[round];
        var centers = column === 0 ?
            games.map(function (_, index) { return 123 + index * gap; }) :
            games.map(function (_, index) {
                return (positions[column - 1][2 * index].y + positions[column - 1][2 * index + 1].y) / 2;
            });
        var x = 30 + column * columnWidth;
        addElement(bracket, "div", "stage", round).style.left = x + "px";
        positions.push(games.map(function (game, index) {
            var center = centers[index];
            var card = addElement(bracket, "article", "match archive-match" +
                (round === "State Championship" ? " champion" : ""));
            card.style.left = x + "px";
            card.style.top = (center - 50) + "px";
            var head = addElement(card, "div", "head", round +
                (games.length > 1 ? " " + (index + 1) : ""));
            if (game.note) { addElement(head, "small", "", game.note); }
            game.teams.forEach(function (team, side) {
                var entry = addElement(card, "button", "entry" + (team === game.winner ? " advanced" : "") +
                    (team === "Springfield Christian" ? " springfield-christian" : ""));
                entry.type = "button";
                addElement(entry, "span", "", team);
                addElement(entry, "span", "score", String(game.scores[side]));
                entry.addEventListener("click", function () { showTeam(team); });
            });
            return { x: x, y: center };
        }));
        if (column > 0) {
            positions[column - 1].forEach(function (position, index) {
                drawWire(position, positions[column][Math.floor(index / 2)], false);
            });
        }
    });
    var finalPosition = positions[positions.length - 1][0];
    var third = data.rounds["Third Place"][0];
    var thirdX = finalPosition.x;
    var thirdY = finalPosition.y + 178;
    var thirdCard = addElement(bracket, "article", "match archive-match placement");
    thirdCard.style.left = thirdX + "px";
    thirdCard.style.top = (thirdY - 50) + "px";
    var thirdHead = addElement(thirdCard, "div", "head", "Third Place");
    if (third.note) { addElement(thirdHead, "small", "", third.note); }
    third.teams.forEach(function (team, side) {
        var entry = addElement(thirdCard, "button", "entry" + (team === third.winner ? " advanced" : "") +
            (team === "Springfield Christian" ? " springfield-christian" : ""));
        entry.type = "button";
        addElement(entry, "span", "", team);
        addElement(entry, "span", "score", String(third.scores[side]));
        entry.addEventListener("click", function () { showTeam(team); });
    });
    positions[positions.length - 2].forEach(function (position) {
        drawWire(position, { x: thirdX, y: thirdY }, true);
    });
    var champion = addElement(bracket, "div", "archive-champion", data.year + " Champion: " + data.champion);
    champion.style.left = (finalPosition.x + columnWidth) + "px";
    champion.style.top = (finalPosition.y - 17) + "px";

    function fit() {
        var scale = Math.min(1, (viewport.clientWidth - 32) / width, (viewport.clientHeight - 32) / height);
        var x = (viewport.clientWidth - width * scale) / 2;
        var y = (viewport.clientHeight - height * scale) / 2;
        bracket.style.transform = "translate(" + x + "px," + y + "px) scale(" + scale + ")";
    }
    document.getElementById("fit").addEventListener("click", fit);
    window.addEventListener("resize", fit);
    fit();
}());
