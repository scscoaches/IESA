(function () {
    "use strict";
    var select = document.getElementById("season-select");
    var data = window.tournamentData || window.earlyTournamentData;
    var year = data && (data.year || 2026);
    var team = window.iesaMyTeam;
    if (!select || !data || !Number.isInteger(year) || !team ||
        !["7th", "8th", "combined"].includes(data.grade)) {
        throw new Error("Tournament year selector requires valid season data.");
    }
    var labelClass = /Class (A{1,2})$/.exec(data.label || "");
    var pageClass = data.className || (labelClass && labelClass[1]) || null;
    var TROPHY = " \uD83C\uDFC6";

    var classSelect = document.createElement("select");
    classSelect.id = "class-select";
    classSelect.setAttribute("aria-label", "Tournament class");
    classSelect.hidden = true;
    select.insertAdjacentElement("afterend", classSelect);

    // Picking a year keeps you in the grade you are reading, except where that
    // grade did not exist. Trophies must describe the page you would land on,
    // so both use this.
    function gradeFor(selectedYear) {
        return selectedYear <= 1985 ? "combined" :
            data.grade === "combined" ? "7th" : data.grade;
    }

    function classesOf(season) {
        return Array.isArray(season.classes) && season.classes.length ? season.classes :
            season.className ? [season.className] : [];
    }

    function validSeason(season) {
        if (!Number.isInteger(season.year) || season.year < 1979 || season.year > 2100) { return false; }
        var allowed = season.year <= 1989 ? [] : season.year <= 2005 ? ["A", "AA"] : ["1A", "2A", "3A", "4A"];
        if (season.year <= 1989) {
            return season.className === null &&
                season.gradeMode === (season.year <= 1985 ? "combined" : "separate") && !season.classes;
        }
        return allowed.includes(season.className) &&
            classesOf(season).every(function (className) { return allowed.includes(className); }) &&
            classesOf(season).includes(season.className);
    }

    function markTrophies(seasons) {
        return team.finishes().then(function (finishes) {
            Array.prototype.forEach.call(select.options, function (option) {
                var optionYear = Number(option.value);
                var placed = finishes.filter(function (finish) {
                    return finish.year === optionYear && finish.grade === gradeFor(optionYear);
                });
                if (!placed.length) { return; }
                option.textContent = option.value + TROPHY;
                option.title = team.name + ": " + placed.map(team.describe).join(", ");
            });
        }).catch(function (error) {
            console.warn("Unable to mark tournament placements:", error);
        });
    }

    var seasonList = [];
    function seasonOf(selectedYear) {
        return seasonList.filter(function (season) { return season.year === selectedYear; })[0];
    }

    team.load("seasons.json").then(function (seasons) {
        if (!Array.isArray(seasons) || !seasons.length || !seasons.every(validSeason) ||
            new Set(seasons.map(function (season) { return season.year; })).size !== seasons.length ||
            !seasons.some(function (season) { return season.year === year; })) {
            throw new Error("Season list does not include valid years for this page.");
        }
        seasonList = seasons;
        select.replaceChildren();
        seasons.forEach(function (season) {
            select.appendChild(new Option(String(season.year), String(season.year)));
        });
        select.value = String(year);
        select.disabled = false;

        var current = seasonOf(year);
        pageClass = pageClass || current.className;
        var classes = classesOf(current);
        classes.forEach(function (className) {
            classSelect.appendChild(new Option(className, className));
        });
        classSelect.value = pageClass || "";
        classSelect.hidden = classes.length < 2;
        document.body.classList.toggle("has-class-select", classes.length >= 2);
        return markTrophies(seasons);
    }).catch(function (error) {
        console.error("Unable to load tournament seasons:", error);
        select.replaceChildren(new Option("Years unavailable", ""));
        select.disabled = true;
    });

    function go(season, className, grade) {
        window.location.assign(team.pageUrl(season, className, grade));
    }

    select.addEventListener("change", function () {
        var selectedYear = Number(select.value);
        var season = seasonOf(selectedYear);
        if (!season) { throw new Error("Selected tournament year is not in the season list."); }
        var grade = gradeFor(selectedYear);
        var classes = classesOf(season);
        select.disabled = true;
        // Prefer the class your team played in that year, then the class you are
        // reading, then the year's first archived class.
        team.classFor(selectedYear, grade).catch(function () { return null; }).then(function (teamClass) {
            var className = classes.includes(teamClass) ? teamClass :
                classes.includes(pageClass) ? pageClass : season.className;
            go(season, className, grade);
        });
    });

    classSelect.addEventListener("change", function () {
        var season = seasonOf(year);
        if (!season || !classesOf(season).includes(classSelect.value)) {
            throw new Error("Selected class is not available for this year.");
        }
        go(season, classSelect.value, data.grade);
    });

    // The 7th | 8th switch is a toggle: a tap anywhere on it opens the other grade,
    // so visitors need not hit the inactive label exactly.
    var gradeSwitch = document.querySelector(".grade-switch");
    if (gradeSwitch) {
        gradeSwitch.title = "Switch grade";
        gradeSwitch.addEventListener("click", function (event) {
            var other = gradeSwitch.querySelector("a:not(.active)");
            if (!other) { return; }
            event.preventDefault();
            window.location.assign(other.href);
        });
    }
}());
