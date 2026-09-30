# IESA girls basketball brackets

The repository root is the all-season landing page. Each season has its own
`<year>/7th/` and `<year>/8th/` static bracket pages. Class 1A archives cover
2006–2019 and 2021–2023; Class 2A archives cover 2024–2025. The live 2026
Class 2A site retains its separate nightly score and postseason refreshes.
Historical pages show published seeds, bracket results and state pairings.
Sectional cards show each qualifying school's pre-sectional W–L record when
IESA prints it on the sectional-pairings page; missing records stay blank.
Older regular-season scores and team-by-team histories are not available.

## Add or refresh a season

From this directory in PowerShell:

```powershell
.\Build-IesaSeason.ps1 -Year 2027 -ClassName 2A -OutputRoot 'C:\inetpub\personalroot\IESA'
```

Set `-Year` to the tournament year and `-ClassName` to the published IESA class
(`1A` through `4A`). Wait until both grades have official regional seeds and
state quarterfinal pairings: the importer refuses incomplete seasons. It reads
IESA's year/class-specific regional assignments, regional brackets, sectional
and state qualifiers, state scoreboard, and girls-basketball calendar; validates
both grades in a temporary directory; then writes the season pages, grade data,
official bracket caches and `seasons.json`. Run the same command again to
refresh a published season. Do not schedule this command as the regular-season
score updater.

When the current calendar does not cover an older year, state-game dates are
left blank rather than inferred. Sectional dates come from that year's
assignments when published. IESA's regional bracket is authoritative for
participants and hosts. Where its participants differ from the published
assignment list, the data retains `assignedTeams` for provenance without
calling attention to the difference on the bracket:
2021 eighth-grade Regional 16 adds Brussels; both 2024 grades' Regionals 5 and
6 add Bement and Armstrong-Ellis, respectively. A listed `NON-COMPETITOR` is
preserved in `assignedTeams` but excluded from bracket seeds. Published
`FORFEIT` and `OT` game annotations appear in the official regional popup.
For the early archives, incomplete assignment rosters are supplemented only
by published bracket participants; legacy `(Coop)` and `(Co-op)` labels refer
to the same school. The 2006 eighth-grade scoreboard establishes eight state
qualifiers even though the sectional results and final scores are unpublished.
In 2008 eighth grade, Regional 10's first seed and final are unpublished.
The scoreboard independently reports Decatur St. Patrick 26, Gardner 23
in state Game 2, but does not identify Decatur St. Patrick's sectional;
its state result is shown without an invented sectional connector.

The resulting pages only require ordinary static-file hosting under IIS. They
share the 2026 renderer, styles and navigation scripts, so keep that folder
alongside the archived year folders. The root catalogue reads `seasons.json`;
publish that file together with each generated season. The year menu on every
grade page reads the same catalogue, and switching years retains the current
grade. Keep `seasons.json` available at the site root.

## End the nightly refresh

IESA's [girls-basketball calendar](https://www.iesa.org/activities/calendar.asp?activitycode=GBK)
lists December 17 as the last 2026 eighth-grade state date (the seventh-grade
finals end December 10). The Windows task `IESA 2026 Score Refresh` has an
end boundary of **December 18, 2026 at 12:05 AM local time**: its midnight
December 18 run is the final capture, and there is no December 19 run.
`2026\Update-IesaScores.ps1` also refuses to fetch after December 18 if run
manually or from an accidentally extended task. Existing static caches and
archived pages remain available.

For a future live season, confirm the *later* grade's final date on the
official calendar when creating its Windows nightly task. Set that daily
trigger's `EndBoundary` to five minutes after the midnight run immediately
following the final, and give the score updater the same last-capture date.
Verify both the task's saved end boundary and its next run; do not rely on a
calendar date alone to stop an open-ended scheduled task.
