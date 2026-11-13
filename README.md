# IESA girls basketball brackets

The repository root (`index.html`) is the home page for the **newest season**
in `seasons.json` (so each new season appears there with no edits): its title
and a row of 7th/8th grade links for every class, with the chosen team's class
marked by a gold *My team* badge (both themes). It shares the bracket pages' header, gear *Settings* dialog
(`2026\my-team.js`, including `?team=` links) and light/dark themes; earlier
seasons are reached through the year menu on any bracket page. It loads
`2026\styles.css`, `theme.css`, `theme.js` and `my-team.js` directly, so bump
their `?v=` there too when bumping them in the templates (the site-integrity
test checks this). The 1979–1985 tournaments
combined seventh and eighth grades into **one** bracket per year under
`<year>/combined/`. The 1986–1989 seasons have separate seventh- and
eighth-grade state tournaments but no class divisions. The 1990–2001 Class A
seasons have separate grade brackets; 1999–2001 also have published sectional
pairings, with W–L records only where IESA printed them. The 1998 state
tournament includes a first round, while 1990–1997 begin at the quarterfinals.
The pre-2002 archives do not infer regional seeds, sectionals, or missing
earlier rounds from the state bracket. Later seasons have separate
`<year>/7th/` and `<year>/8th/` static bracket pages. Every class IESA played
is archived through 2025: Class A and AA for 1990–2005 (IESA's 7A/7AA/8A/8AA
divisions; 1990–2001 are state-only) and Classes 1A–4A for 2006–2019 and
2021–2025. The first class archived for a year keeps `<year>/<grade>/` (1A for
2006–2023, 2A for 2024–2025, A before 2006); every other class lives in
`<year>/<class>/<grade>/`, and `seasons.json` lists a year's classes in
`classes`. The live 2026 season has all four classes: Class 2A keeps its
hand-maintained pages in `2026/7th/` and `2026/8th/`, and Classes 1A, 3A and 4A
live in `2026/<class>/<grade>/`, built from IESA's regional assignments and
state scoreboard by `.\Build-IesaSeason.ps1 -Year 2026 -ClassName 1A -Live`.
Historical pages show published seeds, bracket results and state pairings.
Sectional cards show each qualifying school's pre-sectional W–L record when
IESA prints it on the sectional-pairings page; missing records stay blank.
Older regular-season scores and team-by-team histories are not available.

## Add or refresh a season

From this directory in PowerShell:

```powershell
.\Build-IesaSeason.ps1 -Year 2027 -ClassName 2A -OutputRoot 'C:\inetpub\personalroot\IESA'
```

For a pre-2002 state archive, run
`.\Build-IesaEarlyArchive.ps1 -Years 1999 -OutputRoot 'C:\inetpub\personalroot\IESA'`
or omit `-Years` to rebuild 1979–2001; add `-ClassName AA` for the 1990–2001
Class AA tournaments. This importer reads the grade-specific
IESA state bracket (the combined bracket before 1986) and, for 1999–2001,
the published sectional pairings. It validates the round sizes, all winners
and scores, and the printed champion before writing pages. Use
`-CatalogueOnly` after copying already-validated pages to a new site root;
the catalogue is updated only if `seasons.json` is present. The archived
state-only pages let visitors click a school to see its published state
scores; they link to the original IESA sources. They do not offer a nightly
score refresh or claim unavailable full-season school results.

Set `-Year` to the tournament year and `-ClassName` to the published IESA class
(`A` or `AA` for 2002–2005, `1A` through `4A` thereafter). Run it once per
class; a class that is not the year's first archived class is published to
`<year>/<class>/` and added to that year's `classes` in `seasons.json`. For a
legacy archive, use
`.\Build-IesaSeason.ps1 -Year 2002 -ClassName A` to read the 7A and 8A
sources (`-ClassName AA` reads 7AA and 8AA). The old format has 32 regionals, 16 sectionals, and eight state
first-round games before the quarterfinals; it does not publish regional seed
brackets. For later years, wait until both grades have official regional seeds
and state quarterfinal pairings: the importer refuses incomplete seasons. It reads
IESA's year/class-specific regional assignments, sectional and state
qualifiers, state scoreboard, and girls-basketball calendar, plus seeded
regional brackets where published from 2006 onward; it validates
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
The 2004 7A assignment page's regional rosters belong to another bracket and
conflict with every published 7A regional final. Its archive shows only the two
verified finalists for each regional and uses hosts from the 7A sectional
qualifier page. In 2003, some regional-final rows are absent; a school named
on the published sectional pairing is shown as qualified without inventing a
regional-final score.
In 2008 eighth grade, Regional 10's first seed and Sectional 5's final are
unpublished, and the name of Regional 10's winner is blank even though its
score is printed. The state scoreboard independently reports Decatur St.
Patrick 26, Gardner 23 in state Game 2 without naming its sectional. Sectional
5 is the only one left unclaimed by the published pairings, so the slot is
filled by elimination rather than left empty: an unmapped slot would otherwise
collapse the bracket ordering, sliding every later sectional up one row and
stranding a card on the wrong half. Sectional 5 pairs Regionals 9 and 10, and
Regional 9's winner is published, so the blank first seed of Regional 10 is
Decatur St. Patrick. The archive records that seed, Regional 10's final as
Decatur St. Patrick over Atwood-Hammond 28-20, and Sectional 5 as Decatur St.
Patrick over Champaign Judah Christian with no score, since IESA never printed
one. The regional assignment page lists Bement in Regional 10 and never lists
Decatur St. Patrick; that roster is kept as published and only the bracket's
own team list is corrected.

The resulting pages only require ordinary static-file hosting under IIS. They
share the 2026 renderer, styles and navigation scripts, so keep that folder
alongside the archived year folders. The root catalogue reads `seasons.json`;
publish that file together with each generated season. The year menu on every
page reads the same catalogue. Switching years retains the current grade
except that 1979–1985 open the combined bracket, and leaving a combined year
for a separate-grade year opens seventh grade. Keep `seasons.json` available
at the site root. The shared layout sizes
the SVG connector surface to each year's bracket canvas, including the taller
Class A canvas; keep both dimensions in sync if the layout changes.
Panning and zooming clamp to the bracket canvas edges, so empty space outside
the canvas cannot be exposed; when the canvas is larger than the viewport,
individual cards can still be off-screen while navigating. On mobile, the
initial bracket view is top-aligned and preserves its position during browser
chrome resize; active touch gestures rebase on resize to avoid jumps. This
applies to mouse drag and wheel zoom, touch pan and pinch, and card-focus
navigation across both seeded and state-only archive pages. The zoom floor is
below the scale needed to fit the widest tournament on a narrow mobile screen,
so the first zoom step does not jump from the initial fitted view
(`2026\app.js`, `2026\spaced-layout.js`, `2026\pointer-zoom.js`,
`2026\touch-navigation.js`, `2026\state-archive.js`). On mobile, the title
omits the year because the season selector already identifies it; regional
projection popups keep their three rounds in a compact horizontal bracket
instead of stacking the rounds vertically.

Desktops without a mouse wheel can zoom several ways (`2026\pointer-zoom.js`).
A trackpad pinch arrives as a `ctrlKey` wheel event with small deltas, so it is
scaled far more strongly than a wheel notch and follows the fingers. Double-
clicking empty canvas zooms in 1.6x at the pointer (Shift+double-click zooms
out); double-clicks on regional team names are ignored so they still open the
team dialog. Keyboard: `+`/`=` and `-` zoom about the center, `0` fits, and the
arrow keys pan; keys are ignored while a dialog is open, in form fields, or
with Ctrl/Cmd/Alt so browser zoom still works. The +/- buttons are shown on
desktop (hidden at 680px and below); a click steps 1.2x and holding one
zooms continuously after 300 ms.

Archive pages are rendered from `archive-grade-template.html`,
`archive-state-template.html` and `archive-season-template.html` by
`IesaSitePages.ps1`, which also owns the class-folder rule and catalogue
updates. After changing a template or bumping an asset version, run
`.\Update-IesaPageShells.ps1` to re-render every archived page (no IESA
requests). Then run `.\Build-IesaTeamIndex.ps1` after publishing any season or
class so the team picker and class navigation know about it.

**Settings and My team.** Every page has a gear button that opens *Settings*:
the *My team* choice and the dark-mode switch (moved out of the crowded
header; `theme.js` still finds it by id). A visitor can search every school on
the site and pick one; the choice is saved in that browser (`localStorage`
keys `iesa-my-team` and `iesa-my-team-keys`, the latter holding every spelling
of the school) and defaults to Springfield Christian until a visitor picks
another or clears it. Choosing a team keeps the dialog open and lists that
team's top-four state finishes with links to those brackets; closing it reloads
the page so the brackets and menus re-highlight. The chosen team is highlighted
in every bracket and the mobile view opens beside it (`2026\my-team.js`).

**Team links.** Adding `?team=<school>` to any page address (for example
`2026/1A/8th/index.html?team=Annawan`) chooses that school for the visitor, the
same as picking it in Settings (the parameter stays in the address). Opened on
a bracket page of another class, the link moves on to the class that school
played in for that season and grade (read from the page address and
`teams.json`), so `2026/7th/index.html?team=Pleasant+Plains` opens Class 3A. A
coach can share one link so every recipient sees their own school's
highlights, trophies and class. The choice replaces the recipient's saved team.
Settings' share icon (beside *Clear*; Apple's box-and-arrow on iPhone, iPad and
Mac, Android's three connected dots elsewhere) copies a link with the chosen
team: on a bracket page it opens the class that team played in for the year
and grade being viewed (otherwise, or when the class is unknown, the current
page), so a link shared while reading another class still lands on the team's
bracket. It uses the Clipboard API, falling back to a hidden text area; the
icon turns into a check mark and a small "Link copied" bubble appears below it
for a couple of seconds. It never opens a window, share sheet or prompt.

**Stale pages.** Each page carries `<meta name="iesa-site-version">` and loads
its data scripts with `?v=<version>`. `my-team.js` compares the meta tag with
`site-version.json` (fetched without the cache) and, when the page is older,
reloads it once with `?v=<version>` so a browser-cached shell picks up new
menus and data. `.\Update-IesaPageShells.ps1` bumps `site-version.json` and
re-stamps every page, including the version tag on the hand-maintained
`2026\7th\` and `2026\8th\` pages.

**Grade switch.** The 7th and 8th grade buttons are one joined "7th | 8th"
box; tapping anywhere on it opens the other grade (combined 1979–1985 pages
hide it). On phones every header control is 40px tall and the switch takes
54px.

School names are matched ignoring case, a trailing `(Co-op)` or printed W–L
record, possessive `'s`, periods and hyphens (`Get-TeamKey` in
`Build-IesaTeamIndex.ps1` and `key()` in `my-team.js` must agree). Names that
differ only by a school-type suffix (JHS, IJHS, MS, GS, ES, UGC) are merged
unless both appear in one 2002+ roster, and town-prefix variants are merged
only through the curated `$aliasOf` list (for example West Lincoln-Broadwell /
Lincoln West Lincoln-Broadwell, and the 1986 bracket's "Mahomet" /
Mahomet-Seymour, which already appears under that name in 1984). Pleasant Hill and Peoria Pleasant Hill, and the
four St. Joseph schools, are deliberately kept apart. `teams.json` publishes the
merges as `aliases`, and the most recent spelling is displayed.

The year menu marks seasons in which the chosen team finished in the top four
with a trophy, so the handful worth revisiting stand out among nearly fifty
years; the class menu itself carries no trophies. A year with more
than one archived class shows a class menu beside the year menu; switching
years opens the class the chosen team played in that year (from `teams.json`),
otherwise the class being viewed, otherwise the year's first class.
`Build-IesaPlacements.ps1` stores IESA's
official [State Tournament Winners](https://www.iesa.org/activities/gbk/winners.asp)
history, which lists the champion, runner-up, third and fourth place school for
every class and year since 1979. All fifteen classes are stored for every
school in `placements.json` at the site root, so the trophies work for any team. Nothing is written unless
every class page is read and validated, so an IESA outage or layout change keeps
the previous file. Requests go through `2026\IesaRequest.ps1`, so they are spaced
3 seconds apart and honour `iesa-pause.json` and `IESA_OFFLINE`. The trophy is
**grade aware**: it describes the page the menu would open, so the eighth-grade
menu marks the years that team placed in eighth grade. A season where both
grades placed is marked in both. Marking is best effort; if `placements.json` is
missing or unreadable the menu still lists every year, just without trophies.
Once the state finals begin the refresh runs this and the team index
automatically, so a current-season finish appears as soon as IESA adds it to
the history; run them by hand at any time to re-check the history.

On phones (680 px and below) the Fit and +/- buttons are hidden, as pinch-zoom
replaces them (+/- are also hidden up to 760 px so small tablets fit), and the
header keeps the year and class menus, grade buttons, settings, find, rankings and (on
the live season) Score updates on one line down to 320 px: the title is hidden when a
class menu is shown (the menus already identify the page), and on the live
season below 430 px. The IESA logo is hidden below 400 px, and on live pages
below 455 px to make room for the rankings button.

Archiving every class surfaced IESA data quirks the importers now handle
generically: canceled regionals (`Regional 2 has been canceled`, with the
partner regional's champion advancing unopposed), empty regional assignment
lists filled from the published bracket, regional brackets that
omit trailing BYE rows, a regional final printed without its winner (taken from
the published bracket only when its loser and score agree), unpublished
sectional finals inferred from a state qualifier's regional title, and a school
named with and without its town prefix or school-type suffix on different pages
(accepted only as a unique match), a district named on the scoreboard where the
sectional page names its school ("Calumet City Dolton 149" / "Calumet City
Dirksen", accepted only as the unique same-town winner), regionals with no
schools at all (2011–2018 7-3A Regional 1), "Regional 2/Sectional 1 Canceled",
scores printed as ".31", score text in a bracket name cell, a pairing line with
a game result appended, and bracket participants missing from 2021+
assignments (archives treat the published bracket as authoritative; the live
season stays strict). A canceled regional is shown as "Canceled by IESA" and
its sectional slot as "Regional N canceled".

`.\Repair-IesaArchiveSpacing.ps1` collapses doubled spaces (including
non-breaking spaces) left in archived school names, such as "Gardner  (Co-op)"
after a "(Host)" marker is removed, in the 1979–2025 page data, bracket caches
and seed caches. It writes only files that change (`-WhatIf` to preview) and is
safe to re-run.

## Start the next season (automatic)

Each season follows IESA's
[girls basketball calendar](https://www.iesa.org/activities/calendar.asp?activitycode=GBK),
read by `IesaCalendar.ps1` (it lists four seasons; "2027-2028" is the 2027
season). No prompts or hand edits are needed:

| Calendar date (2027 example) | What happens |
|---|---|
| Final Entry Deadline (Aug 1) | From this day `.github\workflows\season-setup.yml` (7 AM Central daily, August–October) runs `Sync-IesaSeason.ps1`. It checks whether IESA has published the followed class's regional assignments (both grades) and state scoreboard; until then it waits and checks again the next day (4 requests). Once published it runs `Start-IesaSeason.ps1 -Year 2027`: the finished season is archived from IESA's final results, every class of the new season is built with its regionals, sectionals and state pairings, `live-season.json` gets the calendar's dates, every page is re-rendered and `teams.json` rebuilt. The workflow commits, pushes and re-enables *Update IESA scores*. |
| Games may begin (Sept 25) | `gamesFrom`: scheduled score refreshes start; before it they request nothing. |
| Online Ranking (Thu; 7th Nov 11, 8th Nov 18) | `grades.<grade>.seedsFrom`: that grade's official seeds are checked. |
| First regional date (7th Nov 20, 8th Nov 29) | `grades.<grade>.bracketFrom`: that grade's postseason results are checked; the earliest (`bracketFrom`) starts the 9 PM weekday runs and stops the roster check and strength of schedule. |
| Every state final decided | The refresh makes no further request and *Update IESA scores* disables its own schedule. |
| Season must end (Dec 20) | `seasonMustEnd`; refreshes stop on this date at the latest (`endDate` is the day before) and the schedule is disabled. |

Once a season exists, the setup workflow's daily runs make no IESA request.
It can also be started by hand from the Actions tab. To set up a season
yourself (for example a different followed class), run
`.\Start-IesaSeason.ps1 -Year 2027 [-FollowedClass 3A]`; dates come from the
calendar unless `-SeedsFrom`, `-BracketFrom` or `-EndDate` are given. Each
class costs about 13 IESA requests. The shared scripts and assets stay in
`2026\`. Neither script has yet run end to end against a real new season (2027
assignments are not published yet); check the first automatic run's log in
August 2027.
## Tests

`.\tests\Run-Tests.ps1` runs three suites and exits 1 on any failure; it makes
no IESA requests and takes about 15 seconds.

- `tests\Test-SiteIntegrity.ps1` checks the published files: one catalogue
  entry per year, `live-season.json` dates, pages and data for every listed
  class, no unreplaced template placeholders, one site version and one
  version of each shared asset across pages, unique team names and aliases,
  and complete state history.
- `tests\Test-Season.ps1` reads a saved copy of IESA's calendar
  (`tests\fixtures\gbk-calendar.html`) and runs `Sync-IesaSeason.ps1` against a
  fake IESA: nothing before the Final Entry Deadline or once the season exists,
  waiting while IESA has not published the season, and creating it with the
  calendar's dates once it has.
- `tests\Test-Refresh.ps1` runs `2026\Update-IesaScores.ps1` against a fake
  IESA site in a temporary folder: the first daily run reads all classes, later
  runs read only the followed class (while seeds and brackets are still checked
  for every class), the postseason `-Evening` run reads every class, eliminated
  schools (including state quarterfinal losers) are never re-read, a finished
  grade is skipped, and once every final is decided nothing is requested and
  `complete=true` is reported; a class's
  first capture is a silent baseline, `-Classes` limits the run, nothing is
  requested before `gamesFrom`, and seed, bracket (per grade) and end dates
  come from `live-season.json`.

`.github\workflows\tests.yml` runs them on every push and pull request
(the score-refresh commits do not trigger it).

## End the scheduled refresh

IESA's [girls-basketball calendar](https://www.iesa.org/activities/calendar.asp?activitycode=GBK)
lists December 17 as the last 2026 eighth-grade state date (the seventh-grade
finals end December 10). The GitHub Actions workflow
(`.github\workflows\update-scores.yml`) runs at **5 AM, 11 AM and 5 PM Central
on weekdays** and **9 PM Central on Saturdays** (cron in UTC: weekdays 11:00,
17:00 and 23:00; Sunday 03:00). During the postseason (from `bracketFrom` in
`live-season.json`) it also runs at **9 PM Central on weekdays** (Tuesday–Saturday
03:00 UTC), so evening tournament games appear the same night; that run
re-reads only the schools still playing, in every class, plus the seeds and
brackets, with no strength of schedule, watch links or roster check
(`Update-IesaScores.ps1 -Evening`). GitHub can start scheduled runs hours late.

**Official brackets only.** When IESA releases seeds or brackets and the school
scores are not needed, start *Update IESA scores* by hand with *Only the
official seeds and bracket results* ticked (`gh workflow run update-scores.yml
-f brackets_only=true`), or run `.\2026\Update-IesaScores.ps1 -BracketsOnly`
locally. It reads only the seed pages (even before a grade's `seedsFrom`) and,
from `bracketFrom`, the bracket results for every class: about 8 IESA pages per
class, with no school pages, watch links or strength of schedule. Use
`-Classes 3A` to limit it.

**Everything stops at the end of the tournaments.** A grade whose state
third-place and championship games are both decided is never requested again
(no school pages, seeds or bracket). Once every class's 7th- and 8th-grade
finals are decided, the refresh makes no IESA request at all and reports
`complete=true`; the workflow commits the final results and then **disables
its own schedule** (`gh workflow disable`, which is why it has `actions: write`).
Cron has no end date, so scheduled runs after the `endDate` in
`live-season.json` (**December 20, 2026**, the day before IESA's "Season must
end" date of December 21, Central) are skipped and also
disable the schedule; `2026\Update-IesaScores.ps1` itself refuses to fetch after
that date. Re-enable the workflow for the next season in the repository's
Actions tab (*Update IESA scores* → *Enable workflow*) or with
`gh workflow enable update-scores.yml`. IESA's state-winners history (the year
menu's trophies) is read at most once a day, and only after a state final has
been played; if IESA posts the 2026 winners after the schedule has stopped, run
`.\Build-IesaPlacements.ps1` and `.\Build-IesaTeamIndex.ps1` once by hand. The
workflow commits the score, stream-link, strength, seed, bracket, placement and
team-index files. The local Windows task `IESA 2026 Score Refresh` (and
`.\2026\Set-IesaScoreSchedule.ps1`, which set its triggers) is disabled and no
longer used. Existing static caches and archived pages remain available.

The day's first refresh reads **all four classes**: the member directory, two
assignment pages per class and about 830 school pages (about 850 requests,
roughly 43 minutes). The 11 AM and 5 PM refreshes re-read **only Class 2A**
(about 210 requests); Classes 1A, 3A and 4A are read once a day, decided by the
`fullSweepDate` in each class's `scores-<grade>.json`. Each class has its own
700-request budget. A regular-season weekday therefore makes about 1,270 IESA
requests (850 + 210 + 210), and Saturday about 850 plus the weekly Class 2A
strength-of-schedule rebuild (about 600): roughly 7,800 a week. Once the
brackets begin, eliminated schools are never re-read, the roster check and
strength of schedule stop, and the load falls quickly as teams are knocked out.

From the seed and bracket start dates in `live-season.json`, every run also
checks **every class's** regional seeds and postseason results (8 IESA pages per
class: one seed page and three qualifier/scoreboard pages per grade), so 1A, 3A
and 4A brackets update at 11 AM and 5 PM too instead of waiting for the next
morning. That adds about 24 requests to each later run; their school scores
are still read once a day (and at the postseason 9 PM run). A grade's seed page
is no longer read once all its regional finals are decided.

A class's first capture is a silent baseline: games already played are not
listed under "Score updates" (otherwise a new class would report every result
as newly posted). On 2026 pages, the "Score updates" button appears only for the
class the visitor's chosen team plays in that grade (all classes when no team
is chosen), so other classes' changes do not bury the team's own.
Strength of schedule is rebuilt per class (`Update-Strength.ps1 -SitePath
2026\<class>`), on Saturdays or when missing or stale, until the brackets begin
(`bracketFrom`); opponents already in
another 2026 class's score cache are reused instead of re-read from IESA (the
first 1A build reused 96 records per grade and read about 134 pages per grade).
"Bigger" opponents are the classes above the team's own (1A: 2A-4A).
To refresh one class by hand, run
`.\2026\Update-IesaScores.ps1 -Classes 1A` (the 2-hour check applies only
when 2A is included). Requests go through `2026\IesaRequest.ps1` (see below), which spaces
them at least three seconds apart to avoid a
burst. Do not add additional runs without reconsidering the source load; use
the single-school Update button for occasional immediate checks. The unofficial
regional bracket popup has an icon-only refresh button that runs the same
single-school lookup for every school in that regional, one request at a time,
then re-sorts the regional and redraws the projection. Like the single-school
button, its results apply to the current browser session only; official
(seeded) and archived popups do not show it. Both live buttons need IIS to run
`2026\team-scores.ashx`. The public copy on GitHub Pages
(`scscoaches.github.io`) serves static files only and answers that POST with
HTTP 405, so `score-cache.js` hides both buttons on `*.github.io` hosts; those
visitors see the scheduled score refresh only.

### Going easy on IESA

Every script that reads www.iesa.org (`Update-IesaScores`, `Update-Strength`,
`Update-IesaSeeds`, `Update-IesaBracket`, `Build-IesaSeason`,
`Build-IesaEarlyArchive`) dot-sources `2026\IesaRequest.ps1` and calls
`Invoke-IesaPage` instead of `Invoke-WebRequest`. The guard:

- spaces IESA requests at least 3 seconds apart and stops a single run after
  700 requests;
- after **3 failures in a row** writes `2026\iesa-pause.json`
  (`{"until":"yyyy-MM-dd HH:mm","reason":"..."}`, local time) and refuses
  every IESA request until then (6 hours). Delete the file to resume sooner,
  or create it by hand to pause on purpose during an IESA outage;
- blocks all IESA requests when `$env:IESA_OFFLINE = "1"`. Use this when
  testing script changes so they run against the saved files only.

While paused, `Update-IesaScores.ps1` still refreshes NFHS/Hudl links but
skips IESA, and a grade interrupted by a pause is not saved, so the last good
scores stay. It also skips IESA when the score files are under 2 hours old
(`-MinimumHoursBetweenRuns`), so repeated manual runs do not re-read all 212
schools; `-Force` overrides this.

Each refresh reads only the schools that can still change. IESA's school pages
list no game dates, so the first run of each Central day is a **full check**
(the member directory, two assignment pages for roster drift before the
brackets begin, and every school still playing). Later runs that day re-read
the followed class (`fullSweepDate` in `scores-<grade>.json` records the day).
Every school still playing is re-read, because schools may enter a game with
its final score without ever listing it as `PENDING`. A school is **never
requested again once its season is over**: it lost a regional, sectional or
state quarterfinal game, or played the state third-place or championship game
(from `regional-seeds-<grade>.json` and `bracket-<grade>.json`; state games 1–4
are quarterfinals, 5–6 semifinals, 7 third place, 8 the final). Its last capture
is kept. Once the regionals are played most schools are eliminated, so runs read
only the remaining qualifiers. `-Force` always does a full check (still
skipping eliminated schools).

The scheduled refresh runs only on GitHub Actions
(`.github\workflows\update-scores.yml`): weekdays 5:00 AM, 11:00 AM and 5:00 PM
and Saturdays 9:00 PM Central, plus weekdays 9:00 PM during the postseason,
through the `endDate` in `live-season.json`. The local Windows task "IESA 2026 Score
Refresh" is disabled; re-enabling it would double the IESA traffic. Season
dates in `Update-IesaScores.ps1` are Central dates even on the UTC runner.

`team-scores.ashx` honors the same `iesa-pause.json` (HTTP 503 with a
friendly message), keeps each school's live result for 30 minutes, and makes
at most one live IESA request every 10 seconds across all visitors (others get
HTTP 429 "try again"). The pause file is in `.gitignore`, so it pauses this PC
only; to pause the GitHub copy, disable the `update-scores` workflow under
**Actions**.

Each 2026 team dialog can also link to the school's streaming page
(`2026\team-links.js`, read by `score-cache.js`). Entries are keyed by the
exact team name in `data.js` and hold any of an `nfhs`, `youtube` and `hudl`
URL (shown in that order after the IESA link); a button
appears only for the services a school has, so unmatched schools show none.
YouTube links are the school's athletics channel, added by hand (Bluffs
(Co-op), the Winchester/Bluffs co-op, uses "WC Athletics"); there are no
per-game YouTube links.
NFHS links use `https://www.nfhsnetwork.com/schools/<slug>/basketball/girls/middle-school`.
The 46 initial NFHS slugs came from
`https://search-api.nfhsnetwork.com/search/schools?state=IL&search_term=<name>`
(only `search_term` filters, and `state` - not `state_code` - limits to
Illinois) and were kept only when the girls middle-school page's title says
"Girls Middle School" **and** it lists at least one `gam...` event key; NFHS
answers HTTP 200 for any sport/level path, so status codes prove nothing.
Matches in another town or a different school in the same town (for example
the Decatur and Washington public schools) were rejected rather than guessed.
Hudl URLs are the school's `fan.hudl.com/.../organization/<id>/...` page. Hudl
has no documented API, but its fan site's public GraphQL endpoint
(`https://www.hudl.com/api/public/graphql/query`, no login) answers
`fanSearch(input:{searchTerm, types:[ORGANIZATION], organizationClassificationIds:[],
resultStartIndex:0, resultSize:40})`; a search of every bracket team found
only Greenfield, Arcola, Effingham St. Anthony and Liberty with junior-high
girls basketball broadcasts, and those four were added. Search results lean
toward colleges and other states, so new Hudl URLs are still added by hand.

Beside each score the team dialog can show an NFHS icon that opens that game's
broadcast (`https://www.nfhsnetwork.com/events/<host>/gam...`). NFHS refuses
cross-site browser requests, so `Update-IesaScores.ps1` finishes each run by
calling `2026\Update-NfhsEvents.ps1`, which reads the girls middle-school page
of every school in `team-links.js` (about 63 requests, one second apart) and
writes `nfhs-events.json`; a failure only warns, and a school that cannot be
read keeps its previous games. Only cards bannered "Middle School Girls
Basketball" and starting on or after August 1 are kept - pages without a
middle-school section fall back to every school event, and the school pages
still show last season's tournament streams. IESA lists no game dates, so
`score-cache.js` matches on names: a card such as "Sangamon Valley vs.
Morrisonville" fits a row when each side's words (ignoring words like "JHS",
"Middle School" and "Co-op") appear in one of the two IESA team names, and a
tournament prefix ("2026 ... Championship — A vs. B") is dropped first. A
link is shown only when exactly one card fits the row and no other row fits
that card, so a team met twice is left unlinked rather than guessed. Because
every school's cards are pooled, a team with no NFHS page still gets links for
games against linked schools. The page does not distinguish seventh from
eighth grade, so both grades link the same broadcast.

Hudl game links work the same way. `Update-IesaScores.ps1` then calls
`2026\Update-HudlEvents.ps1`, which asks the GraphQL endpoint above for
`fanBroadcasts` (upcoming/streaming and archived, `sortType: BROADCAST_DATE`)
of each school with a Hudl URL and writes `hudl-events.json` in the
`nfhs-events.json` shape. It keeps broadcasts from August 1 on whose team is
women's basketball **and** whose team name says JH/Jr./Junior/Middle/7th/8th
(one school files volleyball under a basketball team). Hudl titles use the
high school's name ("Greenfield/Northwestern High School vs North Greene
Womens Other Basketball"), so the label is rewritten as "<bracket team> vs.
<opponent>" with the sport suffix, "JH" and "Lady ..." removed. The watch
link is `<organizationProfileUrl>/watch?b=<broadcast id>`. Each provider is
matched separately, so a row can show both icons.

### Strength of schedule (unofficial, weekly)

`2026\Update-Strength.ps1` writes `strength-7th.json` and `strength-8th.json`.
It is called on every `Update-IesaScores.ps1` run but returns at once unless
it is Saturday (Central time; the Saturday 9 PM run is the week's only Saturday
run) and has not run today, the file is 8+ days old or
missing, the bracket team list changed, or `-Force` is given. A full build reads
the member directory, eight assignment pages and every non-bracket opponent a
bracket team has played (about 600 requests by mid-November), so it takes about
30 minutes at 3 seconds apart and has its own 700-request budget rather than
sharing the score refresh's.

It goes one step out from the bracket, not class-wide:

- **Class**: the eight `assignments_Regional.asp?Year=2026&Class=<7|8>-<1A..4A>`
  pages give every member's class (the other grade's map fills gaps).
  Non-members and placeholders ("... Tournament", "TBD") show no class.
- **Opponent records**: each bracket team's record comes from the
  `scores-<grade>.json` cache. Other opponents' `memberStats.asp` pages are
  fetched only when a bracket team has a decided game against them. Games
  against the team being rated are excluded from its opponents' win %.
- **Rating** = `0.6 × (opp. wins + 2) / (opp. games + 4)` +
  `0.4 × (average opponent class − 1) / 3`, ranked within each regional.
  Fewer than 4 rated games shows "early season".

The team dialog shows the rank, opponents' win %, class mix (all scheduled
games), record against 3A/4A, and wins over teams above .500. Each result row
gets a class and record tag. If a fetch fails, the previous week's data is
kept for that opponent.

### Team rankings (unofficial)

Live pages have a rankings button (`2026\rankings.js`, `rankings.css`) that
opens a popup listing every team in a class and grade, with class (1A-4A) and
grade buttons. It reads only files already published beside the pages -
`scores-<grade>.json` and `strength-<grade>.json` in each class folder - so it
adds no IESA requests. Columns: a power rating (the default sort), W-L, win %,
points scored (PF) and allowed (PA)
per game, average margin, close-game record (decided by 5 or fewer), big wins
(by 15 or more), strength-of-schedule rating, opponents' win %, quality wins
(over teams above .500) and regional. Points come
from each decided game's "Winner def. Loser" text with the winner's score
first; pending games are skipped. The power rating (0-100) is 40% win % with
two phantom wins and two phantom losses, 30% average margin (shrunk by the same
four phantom games, capped at +/-30) and 30% strength of schedule (.20-.80 mapped
to 0-1; average when missing), so a short schedule cannot outrank a long
unbeaten one. Every column header sorts (best first, click
again to reverse), tied rows share a rank, and the visitor's team is
highlighted and kept in sight: its row is pinned to the bottom of the table
while it is below the visible rows and under the header once scrolled past.
Only the table scrolls.

Regional rosters are fixed in each grade's `data.js` and are **not** updated
automatically when a school withdraws. Every run of `Update-IesaScores.ps1`
compares those rosters with the IESA regional assignment page
(`assignments_Regional.asp?Year=2026&Class=7-2A` / `8-2A`), prints a warning
(a `::warning` annotation under GitHub Actions) for each regional whose
schools were added or removed, and records the drift as `rosterChanges` in the
score cache. A failed check only warns. Fix the roster in `data.js` by hand
and bump that page's `data.js?v=` token. In 2026, Bluffs (Co-op) withdrew from
8th-grade Regional 15, and Evanston King and Evanston St. Athanasius from
8th-grade Regional 1; 7th-grade Regional 15 still lists Bluffs (Co-op).

`Update-IesaScores.ps1` writes `scores-<grade>.json` and `scores-<grade>.js`
atomically, to a `.tmp` file that is then moved over the target. This matters
because `team-scores.ashx` reads the same JSON while visitors browse: an
in-place rewrite of the ~170 KB cache leaves a truncated file readable for the
duration of the write, and `JavaScriptSerializer` then throws
`ArgumentException`, which surfaced as an HTML ASP.NET error page and a
"Live score check failed: Unexpected token '<'" message in the team dialog.
Keep future writes to these files atomic. The handler also retries the cache
read, catches `ArgumentException`, and wraps the whole request so that every
response - including an unexpected failure - is JSON rather than an error
page; the client reports the HTTP status when a body is not valid JSON.

The "Score updates" dialog shows a **rolling 24-hour window**, not the
difference between the last two captures. With three refreshes a day a
per-capture delta covered only six to twelve hours, so a score posted in the
morning disappeared from the list by evening. Each change record now carries
`firstSeenAt` (when the updater first observed the new score) and `latestAt`,
and `Update-IesaScores.ps1` merges the previous window forward, dropping
records older than `-RetentionDays` (default 7). The cache therefore reports
`retainedSince` and `retainedDays`, and the dialog offers 24-hour, 48-hour and
7-day views; the header badge counts the 24-hour window. Records written
before this change have no timestamp and are stamped with `previousCaptureAt`
on the next run. A game between two teams in the field produces one change
record per team; both are kept in the cache and collapsed to a single row for
display. The team dialog shows no posted-time column; instead it **sorts
chronologically**, oldest first - completed games that predate change tracking
lead (in IESA's schedule order), then games with a recorded
`firstSeenAt`/`latestAt` in ascending timestamp order, and `PENDING` games last.
Any game scored within the last 24 hours is highlighted.

A returning visitor also gets a **"New for you"** window listing only changes
posted since they last opened the dialog. The marker is a timestamp in
`localStorage`, keyed by page path so each grade and season counts separately.
Opening the dialog is the read receipt - merely loading the page does not clear
the badge, so a change cannot be missed by navigating past it. The option is
absent on a first visit (there is nothing to compare against) and the view falls
back to 24 hours when nothing is new, rather than opening on an empty list. When
the last visit predates `retainedSince`, the summary says so instead of implying
the list is complete; the site only keeps `retainedDays` of history. The header
badge counts the new-for-you total for a returning visitor, the 24-hour window
otherwise, and turns solid when it is non-zero.

`Merge-ChangeWindow` must be called as `@(Merge-ChangeWindow ...)`. PowerShell
unwraps a single-element array on return, which would make `ConvertTo-Json`
emit `updatedGames` as an object and break the client's `.filter()`.

A failed team fetch no longer drops that team from the cache; the previous
capture's record is carried forward, so a transient IESA error cannot silently
empty a school's schedule.

The generated caches are marked `-merge` in `.gitattributes`. The working tree
*is* the deployment, so an unresolved merge is a live site outage: Git's default
text merge writes `<<<<<<<` markers into the very files `team-scores.ashx` reads
and the browser parses. The caches are regenerated several times a day on more
than one machine, and a line-level blend of two captures is never correct - one
capture or the other is. The binary merge strategy keeps the local version in
the working tree and marks the path conflicted *without* inserting markers, so
the site keeps serving valid JSON while the conflict is resolved with
`git checkout --ours|--theirs <path>` or by simply re-running the updater.
Diffs are left enabled, since the caches are pretty-printed over thousands of
lines and a textual diff is how a capture is checked for score regressions.

For a future live season, confirm the *later* grade's final date on the
official calendar when creating its Windows refresh task. Set every trigger's
`EndBoundary` to five minutes after the first morning run following the
final, and give the score updater the same last-capture date.
Verify both the task's saved end boundary and its next run; do not rely on a
calendar date alone to stop an open-ended scheduled task.
