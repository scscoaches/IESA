(function () {
    "use strict";

    var data = window.tournamentData;
    var bracket = document.getElementById("bracket");
    var viewport = document.getElementById("viewport");
    var svg = bracket.querySelector("svg");
    var groupHeight = 300;
    var order = [].concat.apply([], data.quarterfinals.map(function (game) { return game.matchup; }));

    function setPosition(id, left, top) {
        var card = document.getElementById(id);
        card.style.left = left + "px";
        card.style.top = top + "px";
    }

    order.forEach(function (sectionalId, index) {
        var sectional = data.sectionals[sectionalId - 1];
        var top = 110 + (index % 4) * groupHeight;
        var lowerHalf = index > 3;
        var regionalLeft = lowerHalf ? 3430 : 35;
        var sectionalLeft = lowerHalf ? 3000 : 580;

        sectional.regionals.forEach(function (regionalId, column) {
            setPosition("r" + regionalId, regionalLeft + column * 245, top);
        });
        setPosition("s" + sectionalId, sectionalLeft, 185 + (index % 4) * groupHeight);
    });

    data.quarterfinals.forEach(function (game, index) {
        setPosition("q" + game.game, index < 2 ? 970 : 2570, 330 + (index % 2) * 600);
    });
    setPosition("m5", 1450, 720);
    setPosition("m6", 2150, 720);
    setPosition("final", 1800, 500);
    setPosition("third", 1800, 930);

    function edge(id, right) {
        var card = document.getElementById(id);
        return {
            x: card.offsetLeft + (right ? card.offsetWidth : 0),
            y: card.offsetTop + card.offsetHeight / 2
        };
    }

    function connect(from, to) {
        var fromCard = document.getElementById(from);
        var toCard = document.getElementById(to);
        var start = edge(from, fromCard.offsetLeft < toCard.offsetLeft);
        var end = edge(to, fromCard.offsetLeft < toCard.offsetLeft ? false : true);
        var midpoint = start.x + (end.x - start.x) / 2;
        var path = document.createElementNS("http://www.w3.org/2000/svg", "path");
        path.setAttribute("class", "wire");
        path.setAttribute("d", "M " + start.x + " " + start.y + " H " + midpoint + " V " + end.y + " H " + end.x);
        svg.appendChild(path);
    }

    svg.innerHTML = "";
    data.sectionals.forEach(function (sectional) {
        sectional.regionals.forEach(function (regionalId) { connect("r" + regionalId, "s" + sectional.id); });
    });
    data.quarterfinals.forEach(function (game) {
        game.matchup.forEach(function (sectionalId) { connect("s" + sectionalId, "q" + game.game); });
    });
    data.semifinals.forEach(function (game) {
        game.matchup.forEach(function (quarterfinalId) { connect("q" + quarterfinalId, "m" + game.game); });
    });
    connect("m5", "third");
    connect("m6", "third");
    connect("m5", "final");
    connect("m6", "final");

    function isMobile() {
        return window.matchMedia("(max-width: 680px)").matches;
    }

    function fitAll() {
        var scale = Math.min((viewport.clientWidth - 30) / 3900, (viewport.clientHeight - 30) / 1450, 1);
        var panX = (viewport.clientWidth - 3900 * scale) / 2;
        var panY = (viewport.clientHeight - 1450 * scale) / 2;
        bracket.style.transform = "translate(" + panX + "px," + panY + "px) scale(" + scale + ")";
    }

    function focusCard(card, scale) {
        if (!card) { return; }
        scale = Math.max(.18, Math.min(2.5, scale || 1));
        var centerX = card.offsetLeft + card.offsetWidth / 2;
        var centerY = card.offsetTop + card.offsetHeight / 2;
        var panX = viewport.clientWidth / 2 - centerX * scale;
        var panY = viewport.clientHeight / 2 - centerY * scale;
        bracket.style.transform = "translate(" + panX + "px," + panY + "px) scale(" + scale + ")";
    }

    // Fits the viewport around the bounding box of several cards (e.g. both
    // regionals feeding a sectional) instead of a single card, so the whole
    // group is readable at once on a narrow mobile screen.
    function fitToCards(ids, padding) {
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        ids.forEach(function (id) {
            var card = document.getElementById(id);
            if (!card) { return; }
            minX = Math.min(minX, card.offsetLeft);
            minY = Math.min(minY, card.offsetTop);
            maxX = Math.max(maxX, card.offsetLeft + card.offsetWidth);
            maxY = Math.max(maxY, card.offsetTop + card.offsetHeight);
        });
        if (minX === Infinity) { fitAll(); return; }
        var width = maxX - minX, height = maxY - minY;
        var scale = Math.max(.18, Math.min(2.5, (viewport.clientWidth - padding * 2) / width, (viewport.clientHeight - padding * 2) / height));
        var panX = viewport.clientWidth / 2 - (minX + width / 2) * scale;
        var panY = viewport.clientHeight / 2 - (minY + height / 2) * scale;
        bracket.style.transform = "translate(" + panX + "px," + panY + "px) scale(" + scale + ")";
    }

    function initialView() {
        if (isMobile()) {
            var highlighted = bracket.querySelector(".springfield-christian");
            var card = highlighted && highlighted.closest(".match");
            if (card) {
                var scsOnRight = card.offsetLeft > bracket.offsetWidth / 2;
                var groupIds = Array.prototype.filter.call(bracket.querySelectorAll(".regional"), function (regional) {
                    return (regional.offsetLeft > bracket.offsetWidth / 2) === scsOnRight;
                }).map(function (regional) {
                    return regional.id;
                });
                Array.prototype.forEach.call(bracket.querySelectorAll(".match:not(.regional)"), function (sectional) {
                    if ((sectional.offsetLeft > bracket.offsetWidth / 2) === scsOnRight && sectional.id.charAt(0) === "s") {
                        groupIds.push(sectional.id);
                    }
                });
                fitToCards(groupIds, 20);
                return;
            }
        }
        fitAll();
    }

    // Tapping a card's header/meta zooms the bracket into that section, which is
    // the quickest way to read a regional's teams on a narrow mobile screen
    // without pinch-zooming the whole 3900px-wide bracket first.
    bracket.addEventListener("click", function (event) {
        var trigger = event.target.closest(".head, .meta");
        if (!trigger) { return; }
        var card = trigger.closest(".match");
        if (card) { focusCard(card, 1.3); }
    });

    bracket.addEventListener("pointerdown", function (event) {
        if (event.target.closest(".head, .meta")) { event.stopPropagation(); }
    }, true);

    document.getElementById("fit").onclick = fitAll;
    window.addEventListener("resize", initialView);
    initialView();
}());
