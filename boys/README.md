# IESA boys basketball brackets

This folder (`boys\`) is the complete boys' site. It runs the same code as
`..\girls\` (copied there by `..\Sync-IesaSharedCode.ps1`; edit the code in
`girls\`, never here), so `..\girls\README.md` describes how everything works.
Paths below are relative to this folder. What differs is in `sport.json`:
IESA's boys' pages (`www.iesa.org/activities/bbk/`, activity code `BBK`), the
"BOYS BASKETBALL" calendar, and the boys' class eras.

## Seasons and years

The boys' season runs from late October to February, so one season spans two
calendar years. Folders and `seasons.json` use **IESA's tournament year**, the
year the state finals are played: `2027\` is the 2026–27 season, the one IESA's
calendar lists as "2026-2027" (`yearOffset` 1 in `sport.json`).

- **2027 (live):** all four classes (1A–4A), built from IESA's regional
  assignments and state scoreboard with
  `.\Build-IesaSeason.ps1 -Year 2027 -ClassName 2A -Live`. Class 2A (Springfield
  Christian's class) is the followed class and keeps `2027\7th\` and
  `2027\8th\`; the others live in `2027\<class>\<grade>\`. Regional brackets
  show as unofficial until IESA posts seeds (January).
- **2007–2026:** Classes 1A–4A with seeded regional brackets, sectionals and
  state results, built with `.\Build-IesaSeason.ps1 -Year <year> -ClassName <class>`
  (Class 2A keeps `<year>\<grade>\` where it was built first). Not archived,
  because IESA's own pages are incomplete or inconsistent: 2021 (no
  tournament), 2007 2A and 4A, 2008 4A, 2009 1A (a bracket school missing from
  the seeds), 2011 2A (an unfinished state game with a score), 2015 3A (a state
  qualifier that matches no sectional). Rerun the command after IESA corrects a
  page.
- **1985–2006:** Class A and AA (IESA's 7A/7AA/8A/8AA) as state-tournament
  archives from IESA's state brackets (`.\Build-IesaEarlyArchive.ps1`, then
  `-ClassName AA`; `earlyLast` is 2006). IESA's regional assignments for these
  years do not match their published results, so regionals and sectionals are
  not shown. Class AA is missing 1989, 1996, 1997 and 1999, whose IESA state
  brackets have missing games or garbled scores.
- **Before 1985** (Heavyweight and Lightweight 1930–1984, 7th grade Class C
  1973–1984, Class A and AA 1977–1984): IESA publishes winners but no brackets
  in the same form, so these appear only as trophies (`placements.json`,
  `.\Build-IesaPlacements.ps1`) in the *My team* state-finish list.

## Score refreshes

`live-season.json` has `"refreshEnabled": true`, so the *Boys: Update scores*
workflow (`..\.github\workflows\update-scores-boys.yml`) refreshes scores on the
same schedule as the girls' one, from `gamesFrom` to `endDate`. Set it to
`false` and push to stop all requests to IESA, NFHS and Hudl, even for runs
started by hand. The setting carries over when the next season is created.

*Boys: Set up season* (`..\.github\workflows\season-setup-boys.yml`) runs
each morning September–December, makes no request while 2027 is current, and
creates the 2028 season once IESA publishes it.

## Not available for boys

- The single-school *Update* button in the team dialog: it needs the score
  cache beside `2026\team-scores.ashx`, which only the girls' hand-maintained
  Class 2A pages have.
- Watch links: `2026\team-links.js` starts from the girls' schools with
  school-level NFHS pages; add `/basketball/boys/middle-school` where NFHS has a
  boys' page, and Hudl/YouTube links by hand.

## Tests

From the repository root: `.\tests\Run-Tests.ps1` runs the girls' tests, the
same site-integrity checks against this folder, and checks that the shared code
here matches `girls\`.
