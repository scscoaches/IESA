# IESA girls basketball brackets

The repository root is the all-season landing page. The 1979–1985 tournaments
combined seventh and eighth grades into **one** bracket per year under
`<year>/combined/`. The 1986–1989 seasons have separate seventh- and
eighth-grade state tournaments but no class divisions. The 1990–2001 Class A
seasons have separate grade brackets; 1999–2001 also have published sectional
pairings, with W–L records only where IESA printed them. The 1998 state
tournament includes a first round, while 1990–1997 begin at the quarterfinals.
The pre-2002 archives do not infer regional seeds, sectionals, or missing
earlier rounds from the state bracket. Later seasons have separate
`<year>/7th/` and `<year>/8th/` static bracket pages. Class A archives cover
2002–2005 (IESA's 7A/8A divisions, the predecessors of 1A); Class 1A
archives cover 2006–2019 and 2021–2023; Class 2A archives cover 2024–2025. The live 2026
Class 2A site retains its separate scheduled score and postseason refreshes.
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
or omit `-Years` to rebuild 1979–2001. This importer reads the grade-specific
IESA state bracket (the combined bracket before 1986) and, for 1999–2001,
the published sectional pairings. It validates the round sizes, all winners
and scores, and the printed champion before writing pages. Use
`-CatalogueOnly` after copying already-validated pages to a new site root;
the catalogue is updated only if `seasons.json` is present. The archived
state-only pages let visitors click a school to see its published state
scores; they link to the original IESA sources. They do not offer a nightly
score refresh or claim unavailable full-season school results.

Set `-Year` to the tournament year and `-ClassName` to the published IESA class
(`A` for 2002–2005, `1A` through `4A` thereafter). For a legacy archive, use
`.\Build-IesaSeason.ps1 -Year 2002 -ClassName A` to read the 7A and 8A
sources. The old format has 32 regionals, 16 sectionals, and eight state
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
unpublished. The scoreboard independently reports Decatur St. Patrick 26,
Gardner 23 in state Game 2 without naming Decatur St. Patrick's sectional.
Sectional 5 is the only one left unclaimed by the published pairings, so the
slot is filled by elimination rather than left empty: an unmapped slot would
otherwise collapse the bracket ordering, sliding every later sectional up one
row and stranding a card on the wrong half. The card names the team from the
scoreboard and says so, since IESA never published that sectional final.

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

The year menu also marks seasons in which Springfield Christian finished in the
top four with a dot, so the handful worth revisiting stand out among nearly
fifty years. `Build-IesaPlacements.ps1` derives those placements from the two
final games of each archived bracket - the championship winner and loser are
first and second, the third place game's winner and loser are third and fourth -
and writes `placements.json` at the site root. The dot is **grade aware**: it
describes the page the menu would open, so the eighth-grade menu marks the years
that team placed in eighth grade. A season where both grades placed is marked in
both. Marking is best effort; if `placements.json` is missing or unreadable the
menu still lists every year, just without dots. The bracket's own game numbers
determine its shape, so a season in progress is covered even though its
`data.js` is executable JavaScript rather than JSON. Once the state bracket is
published the refresh runs this automatically, so a finish in the current season
appears without manual action; run it by hand after adding an archived year.

## End the scheduled refresh

IESA's [girls-basketball calendar](https://www.iesa.org/activities/calendar.asp?activitycode=GBK)
lists December 17 as the last 2026 eighth-grade state date (the seventh-grade
finals end December 10). The Windows task `IESA 2026 Score Refresh` runs at
**6 AM, noon and 6 PM local time on weekdays**, plus **6 PM on Saturdays and
Sundays**, not midnight. Its end boundary is
**December 18, 2026 at 6:05 AM local time**: the final morning run captures
results from December 17, and there are no later scheduled runs. Reapply its
four bounded triggers with `.\2026\Set-IesaScoreSchedule.ps1` after moving
the site or recreating the task. `2026\Update-IesaScores.ps1` also refuses to
fetch after December 18 if run manually or from an accidentally extended
task. Existing static caches and archived pages remain available.

Each refresh reads the member directory and about 212 separate team pages;
weekday runs make approximately 639 IESA requests a day, while weekend runs
make approximately 212 requests per day, plus postseason queries when those
begin. The updater waits two seconds between school requests to avoid a
burst. Do not add additional runs without reconsidering the source load; use
the single-school Update button for occasional immediate checks.

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
