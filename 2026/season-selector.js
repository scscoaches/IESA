(function () {
    "use strict";
    var select = document.getElementById("season-select");
    var data = window.tournamentData;
    var year = data && (data.year || 2026);
    if (!select || !data || !Number.isInteger(year) ||
        !["7th", "8th"].includes(data.grade)) {
        throw new Error("Tournament year selector requires grade-specific season data.");
    }

    fetch("../../seasons.json", { cache: "no-store" }).then(function (response) {
        if (!response.ok) { throw new Error("Season list returned HTTP " + response.status); }
        return response.json();
    }).then(function (seasons) {
        if (!Array.isArray(seasons) || !seasons.length ||
            seasons.some(function (season) {
                return !Number.isInteger(season.year) || season.year < 2000 || season.year > 2100 ||
                    !/^[1-4]A$/.test(season.className);
            }) || new Set(seasons.map(function (season) { return season.year; })).size !== seasons.length ||
            !seasons.some(function (season) { return season.year === year; })) {
            throw new Error("Season list does not include valid years for this page.");
        }
        select.replaceChildren();
        seasons.forEach(function (season) {
            var option = document.createElement("option");
            option.value = String(season.year);
            option.textContent = String(season.year);
            select.appendChild(option);
        });
        select.value = String(year);
        select.disabled = false;
    }).catch(function (error) {
        console.error("Unable to load tournament seasons:", error);
        select.replaceChildren(new Option("Years unavailable", ""));
        select.disabled = true;
    });

    select.addEventListener("change", function () {
        if (!Array.prototype.some.call(select.options, function (option) {
            return option.value === select.value && option.value !== "";
        })) {
            throw new Error("Selected tournament year is not in the season list.");
        }
        window.location.assign(new URL("../../" + select.value + "/" + data.grade + "/index.html",
            window.location.href).href);
    });
}());
