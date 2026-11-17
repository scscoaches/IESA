# IESA basketball brackets

Interactive state-tournament brackets for the Illinois Elementary School
Association, one self-contained site per sport:

| Folder | Site | IESA pages |
|---|---|---|
| `girls\` | Girls' basketball, 1979 onward ([girls\README.md](girls/README.md)) | `www.iesa.org/activities/gbk/` |
| `boys\` | Boys' basketball (not built yet) | `www.iesa.org/activities/bbk/` |

`index.html` at the root lets visitors pick a sport. Each sport folder is a
complete site: its seasons, `seasons.json`, `live-season.json`, templates,
build scripts, tests and the shared assets in `<sport>\2026\`. Every path in a
sport's README is relative to that sport's folder. Run its scripts from
there, for example `cd girls; .\tests\Run-Tests.ps1`.

## Old addresses

The girls' site used to live at the root. Every old page address
(`<year>\...\index.html`) is now a small redirect page that forwards to the
same page under `girls\`, keeping `?team=` and `#` parts, so bookmarks and
shared team links keep working. `index.html?team=...` forwards to the girls'
home page. IIS here has no URL Rewrite module and GitHub Pages only serves
static files, so the redirects are HTML pages. Do not add new content to these
root year folders.

## Automation

The workflows in `.github\workflows\` run in `girls\`
(`defaults.run.working-directory`): *Update IESA scores*, *Set up IESA season*
and *Tests*. A boys' site would get its own copies pointed at `boys\`.

## Adding the boys' site

IESA's boys' pages have the same layout (7th and 8th grade, Classes 1A–4A),
but the season runs from late October to February, so a season spans two
calendar years. Folders use the year the season starts (`boys\2026\` is
2026–27). Before building it, the girls-specific parts of the scripts need a
per-sport setting rather than hard-coded values: the IESA activity code (`gbk`/
`GBK` in the request URLs and the calendar), the calendar's "GIRLS BASKETBALL"
table headings, the NFHS (`basketball/girls/middle-school`) and Hudl filters,
the page titles, and the *My team* storage keys in `my-team.js`, so a
visitor's girls' and boys' teams are saved separately.
