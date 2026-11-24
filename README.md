# IESA basketball brackets

Interactive state-tournament brackets for the Illinois Elementary School
Association, one self-contained site per sport:

| Folder | Site | IESA pages |
|---|---|---|
| `girls\` | Girls' basketball, 1979 onward ([girls\README.md](girls/README.md)) | `www.iesa.org/activities/gbk/` |
| `boys\` | Boys' basketball, 1985 onward, trophies from 1930 ([boys\README.md](boys/README.md)) | `www.iesa.org/activities/bbk/` |

The root `index.html` opens the visitor's default sport (Girls initially); the
Settings gear changes it, and shared links carrying a team and gender set that
default and open the matching sport. Each sport's home page links to the other.
Settings shows the chosen team's Girls and Boys state finishes together, with
links to the appropriate sport's bracket.
Each sport folder is a complete site: its seasons,
`seasons.json`, `live-season.json`, `placements.json`, `teams.json`, page
templates, build scripts and the shared assets in `<sport>\2026\`. Paths in a
sport's README are relative to that sport's folder; run its scripts from there
(for example `cd boys; .\Build-IesaSeason.ps1 -Year 2026 -ClassName 3A`).

## One codebase, two sports

Both sports run the same code. Each folder's `sport.json` says which IESA pages
to read (`gbk`/`bbk`), the calendar's wording, how IESA numbers the season
(boys' tournaments are played in the second year of a "2026-2027" season), and
the class eras (combined, grade-only, Class A/AA, Classes 1A–4A). Fixes for one
sport's data (the girls' 2004, 2008, 2021 and 2024 exceptions) only apply to that
sport. In the browser, `2026\my-team.js` tells the sports apart by the folder
and keeps each sport's *My team* choice separately; `season-selector.js` reads
the eras from `sport.json`.

`girls\` holds the master copy of the code. Change it there, then run
`.\Sync-IesaSharedCode.ps1` to copy the build scripts, templates and `2026\`
scripts, styles and icons to `boys\`; `-Check` only reports differences.
Each sport keeps its own data, home page, `2026\team-links.js` and
`2026\manifest.json`. The manifests have no `start_url` on purpose: a page
saved to a phone's home screen then reopens that page, not a fixed start page.

## Tests

`.\tests\Run-Tests.ps1` checks the root sport picker and default-page setting,
runs the girls' suites, the site-integrity checks against `boys\`, and the
shared-code check. `.github\workflows\tests.yml` runs it on every push and pull
request.

## Old addresses

The girls' site used to live at the root. Every old page address
(`<year>\...\index.html`) is now a small redirect page that forwards to the
same page under `girls\`, keeping `?team=` and `#` parts, so bookmarks and
shared team links keep working. `index.html?team=...` forwards to the girls'
home page. IIS here has no URL Rewrite module and GitHub Pages only serves
static files, so the redirects are HTML pages. Do not add new content to these
root year folders.

## Automation

| Workflow | Sport | What it does |
|---|---|---|
| *Girls: Update scores* (`update-scores.yml`) | girls | Score, seed and bracket refreshes for the live season |
| *Girls: Set up season* (`season-setup.yml`) | girls | Creates the next season (August–October) |
| *Boys: Update scores* (`update-scores-boys.yml`) | boys | Same as the girls' refresh; set `"refreshEnabled": false` in `boys\live-season.json` to stop it |
| *Boys: Set up season* (`season-setup-boys.yml`) | boys | Creates the next boys' season (September–December) |
| *Both: Tests* (`tests.yml`) | both | `tests\Run-Tests.ps1` |

Workflow names start with the sport they act on (*Girls:*, *Boys:*, or *Both:*).

Each sport's jobs run in its folder (`defaults.run.working-directory`) and have
their own concurrency group; every push pulls and rebases first.
