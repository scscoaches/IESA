(function () {
    "use strict";

    var key = "iesa-2026-theme";
    // Dark unless the visitor has chosen light with the toggle.
    var dark = localStorage.getItem(key) !== "light";
    var iconBase = document.currentScript.src;

    function applyTheme() {
        document.documentElement.classList.toggle("dark-theme", dark);
        var button = document.getElementById("theme-toggle");
        if (button) {
            button.querySelector("img").src = new URL(dark ? "theme-sun.svg" : "theme-moon.svg", iconBase).href;
            button.setAttribute("aria-label", dark ? "Switch to light mode" : "Switch to dark mode");
            button.setAttribute("aria-pressed", String(dark));
        }
    }

    applyTheme();
    document.addEventListener("DOMContentLoaded", function () {
        applyTheme();
        document.getElementById("theme-toggle").addEventListener("click", function () {
            dark = !dark;
            localStorage.setItem(key, dark ? "dark" : "light");
            applyTheme();
        });
    });
}());
