(function() {
    "use strict";
    var d = window.tournamentData,
        b = document.querySelector("#bracket"),
        v = document.querySelector("#viewport"),
        s = document.querySelector("svg"),
        drag, openingRound = d.firstRound || d.quarterfinals,
        sectionalOrder = [].concat.apply([], openingRound.map(function(q) {
            return q.matchup
        })).map(function(id) {
            return Number.isInteger(id) && id >= 1 && id <= d.sectionals.length ? id : null;
        });
    // An unmapped slot keeps its place so the bracket halves stay aligned. Collapsing it
    // would slide every later sectional up one row and strand a card on the wrong side.
    var unplacedSectionals = d.sectionals.filter(function(sectional) {
        return sectionalOrder.indexOf(sectional.id) === -1;
    }).map(function(sectional) { return sectional.id; });
    sectionalOrder = sectionalOrder.map(function(id) {
        return id === null ? unplacedSectionals.shift() : id;
    }).filter(function(id) { return id !== undefined; });
    unplacedSectionals.forEach(function(id) { sectionalOrder.push(id); });
    var year = d.year || 2026;
    window.clampBracketTransform = function(x, y, scale) {
        var width = b.offsetWidth * scale;
        var height = b.offsetHeight * scale;
        var marginX = Math.min(60, v.clientWidth / 2);
        var marginY = Math.min(60, v.clientHeight / 2);
        return {
            x: width <= v.clientWidth ? (v.clientWidth - width) / 2 :
                Math.max(marginX - width, Math.min(v.clientWidth - marginX, x)),
            y: height <= v.clientHeight ? (v.clientHeight - height) / 2 :
                Math.max(marginY - height, Math.min(v.clientHeight - marginY, y)),
            scale: scale
        };
    };
    var results = window.iesaBracketCache;
    if (!results || results.year !== year || results.grade !== d.grade) {
        results = null;
    }
    if (results && results.quarterfinalMatchups) {
        var pairings = openingRound.map(function(q) {
            return results.quarterfinalMatchups[q.game];
        });
        var numbers = [].concat.apply([], pairings.filter(Array.isArray));
        if (pairings.every(function(pair) { return Array.isArray(pair) && pair.length === 2; }) &&
            numbers.length === d.sectionals.length &&
            numbers.every(function(n) { return Number.isInteger(n) && n >= 1 && n <= d.sectionals.length; }) &&
            new Set(numbers).size === d.sectionals.length) {
            openingRound.forEach(function(q, index) { q.matchup = pairings[index]; });
            sectionalOrder = numbers;
        }
    }
    function result(stage, id) {
        return results && results[stage] && results[stage][id];
    }
    function matchTeam(name, candidates) {
        if (!name) { return null; }
        var normalized = name.replace(/\s+\(Co-?op\)$/i, "").replace(/\s+/g, " ").trim().toLowerCase();
        var matches = candidates.filter(function(candidate) {
            return candidate && candidate.replace(/\s+\(Co-?op\)$/i, "").replace(/\s+/g, " ").trim().toLowerCase() === normalized;
        });
        return matches.length === 1 ? matches[0] : null;
    }
    var seedCache = window.iesaRegionalSeedCache;
    var seededRegionals = {};
    if (seedCache && seedCache.year === year && seedCache.grade === d.grade &&
        seedCache.regionalBrackets) {
        d.regionals.forEach(function(regional) {
            var bracket = seedCache.regionalBrackets[regional.id];
            if (!bracket || !Array.isArray(bracket.seeds) || !bracket.seeds.length) { return; }
            var names = bracket.seeds && bracket.seeds.map(function(seed) {
                return matchTeam(seed.team, regional.teams);
            });
            if (!names || names.length !== regional.teams.length ||
                new Set(names).size !== names.length ||
                bracket.seeds.some(function(seed, index) {
                    return seed.seed !== index + 1 + (bracket.missingSeed === 1 ? 1 : 0) || !names[index];
                })) {
                console.error("Invalid official seeding for Regional " + regional.id);
                return;
            }
            seededRegionals[regional.id] = bracket;
        });
    }
    function seedProgress(regional, bracket) {
        var bySeed = {};
        bracket.seeds.forEach(function(seed) { bySeed[seed.seed] = matchTeam(seed.team, regional.teams); });
        var names = [1, 8, 4, 5, 2, 7, 3, 6].map(function(seed) {
            return bySeed[seed] || null;
        });
        var roundNames = [names];
        var roundGameScores = [];
        for (var round = 0; round < 3; round++) {
            var current = roundNames[round];
            var following = [];
            var gameScores = [];
            for (var gameIndex = 0; gameIndex < current.length / 2; gameIndex++) {
                var pair = current.slice(gameIndex * 2, gameIndex * 2 + 2);
                var game = bracket.rounds && bracket.rounds[round] && bracket.rounds[round][gameIndex];
                // Only an empty first-round seed slot is a bye; later empty slots are pending.
                var winner = round === 0 && pair[0] && !pair[1] ? pair[0] : null;
                if (game && game.winner && pair[0] && pair[1] &&
                    Array.isArray(game.teams) && Array.isArray(game.scores) &&
                    game.teams.length === 2 && game.scores.length === 2 &&
                    game.teams.every(function(team, i) { return matchTeam(team, [pair[i]]) === pair[i]; }) &&
                    game.scores.every(function(score) { return Number.isInteger(score) && score >= 0; }) &&
                    game.scores[0] !== game.scores[1]) {
                    var officialWinner = matchTeam(game.winner, pair);
                    if (officialWinner && game.scores[pair.indexOf(officialWinner)] >
                        game.scores[1 - pair.indexOf(officialWinner)]) {
                        winner = officialWinner;
                        gameScores[gameIndex] = game.scores.slice();
                    }
                }
                following.push(winner);
            }
            roundNames.push(following);
            roundGameScores.push(gameScores);
        }
        return { names: roundNames, gameScores: roundGameScores };
    }
    var seededProgress = {};
    Object.keys(seededRegionals).forEach(function(id) {
        seededProgress[id] = seedProgress(d.regionals[id - 1], seededRegionals[id]);
    });
    var reportedMismatch = {};
    function regionalWinner(id) {
        var regional = d.regionals[id - 1];
        var game = result("regionals", id);
        var winner = game && matchTeam(game.winner, regional.teams);
        var loser = game && matchTeam(game.loser, regional.teams);
        var qualified = winner && ((loser && winner !== loser) || game.qualifierOnly) ? winner : null;
        var bracketWinner = seededProgress[id] && seededProgress[id].names[3][0];
        if (qualified && bracketWinner && qualified !== bracketWinner) {
            if (!reportedMismatch[id]) {
                console.error("Conflicting official regional winners for Regional " + id);
                reportedMismatch[id] = true;
            }
            return null;
        }
        return qualified || bracketWinner || null;
    }
    function sectionalWinner(id) {
        var game = result("sectionals", id);
        var entrants = d.sectionals[id - 1].regionals.map(regionalWinner);
        var winner = game && matchTeam(game.winner, entrants);
        var loser = game && matchTeam(game.loser, entrants);
        return winner && loser && winner !== loser ? winner : null;
    }
    function gameResult(id, entrants) {
        var game = result("games", id);
        // IESA sometimes never publishes a sectional final even though the state scoreboard
        // names the team that advanced. When one entrant is unresolved and the other matches
        // the published pairing, the remaining published name is unambiguous.
        if (game && Array.isArray(game.teams) && game.teams.length === 2) {
            [0, 1].forEach(function(side) {
                var other = entrants[1 - side];
                if (!entrants[side] && other &&
                    matchTeam(game.teams[1 - side], [other]) === other) {
                    entrants[side] = game.teams[side];
                }
            });
        }
        if (!game || !entrants[0] || !entrants[1] ||
            !Array.isArray(game.teams) || game.teams.length !== 2 ||
            !Array.isArray(game.scores) || game.scores.length !== 2 ||
            !game.scores.every(function(score) { return /^\d+$/.test(String(score)); })) {
            return null;
        }
        var teams = game.teams.map(function(name) { return matchTeam(name, entrants); });
        var winner = matchTeam(game.winner, entrants);
        var loser = matchTeam(game.loser, entrants);
        if (!teams[0] || !teams[1] || teams[0] === teams[1] ||
            !winner || !loser || winner === loser ||
            teams.indexOf(winner) === -1 || teams.indexOf(loser) === -1) {
            return null;
        }
        return { teams: teams, scores: game.scores, winner: winner, loser: loser, sourceUrl: game.sourceUrl };
    }
    var firstRoundResults = {}, quarterfinalResults = {}, semifinalResults = {};
    if (d.firstRound) d.firstRound.forEach(function(q) {
        firstRoundResults[q.game] = gameResult(q.game, q.matchup.map(sectionalWinner));
    });
    d.quarterfinals.forEach(function(q) {
        quarterfinalResults[q.game] = gameResult(q.game, q.matchup.map(function(id) {
            if (d.firstRound) return firstRoundResults[id] && firstRoundResults[id].winner;
            return id ? sectionalWinner(id) : null;
        }));
    });
    d.semifinals.forEach(function(q) {
        semifinalResults[q.game] = gameResult(q.game, q.matchup.map(function(id) {
            return quarterfinalResults[id] && quarterfinalResults[id].winner;
        }));
    });
    function entrants(names, game, label) {
        return names.map(function(name) {
            return {
                text: name,
                score: game && game.scores[game.teams.indexOf(name)],
                winner: game && game.winner === name,
                label: label,
                sourceUrl: game && game.sourceUrl
            };
        });
    }
    document.querySelector(".title").textContent = "IESA " + year + " " + d.grade +
        " Grade Class " + (d.className || "2A") + " State Tournament";
    function details() {
        return Array.prototype.filter.call(arguments, function(value) {
            return typeof value === "string" && value.trim();
        }).join(" • ");
    }
    document.querySelector(".detail").textContent = details(d.venue, d.stateDate,
        d.regionalRosterPartial ? "Regional finalists only" : "");

    function el(t, c, txt) {
        var n = document.createElement(t);
        n.className = c || "";
        n.textContent = txt || "";
        return n
    }

    function card(o) {
        var n = el("article", "match " + (o.kind || ""));
        n.id = o.id;
        n.style.left = o.x + "px";
        n.style.top = o.y + "px";
        var heading = el("div", "head", o.location ? "" : o.title);
        if (o.location) {
            heading.appendChild(el("span", "regional-name", o.title));
            var location = el("span", "regional-location", o.location);
            location.title = o.location;
            heading.appendChild(location);
        }
        n.appendChild(heading);
        if (o.meta) n.appendChild(el("div", "meta", o.meta));
        o.entries.forEach(function(e) {
            var entry = typeof e === "string" ? { text: e } : e;
            var row = el("div", "entry " + (o.path ? "path" : "") +
                (entry.winner ? " advanced" : ""), o.kind === "sectional" ? "" : entry.text);
            if ((entry.team || entry.text) === "Springfield Christian") {
                row.classList.add("springfield-christian");
            }
            if (o.kind === "sectional") {
                row.appendChild(el("span", "sectional-team", entry.text));
                if (entry.team) row.dataset.team = entry.team;
            }
            if (entry.seed) {
                row.dataset.team = entry.text;
                row.dataset.seed = entry.seed;
                row.textContent = "";
                row.appendChild(el("span", "seed-badge", entry.seed));
                row.appendChild(el("span", "team-label", entry.text));
                row.title = entry.text + " • Seed " + entry.seed;
            }
            if (entry.winner) { row.title = entry.label || "Confirmed winner on IESA"; }
            if (entry.sourceUrl) { row.title += (row.title ? " • " : "") + entry.sourceUrl; }
            if (entry.record) {
                row.appendChild(el("span", "record-badge", entry.record));
            }
            if (entry.score !== undefined && entry.score !== null) {
                row.appendChild(el("span", "postseason-score", " " + entry.score));
            }
            n.appendChild(row)
        });
        if (o.projected || o.official) {
            var projection = el("button", o.official ? "regional-official-link" : "regional-projection-link",
                o.official ? "Regional bracket (official)" : "Regional bracket (unofficial)");
            projection.type = "button";
            projection.setAttribute("aria-label", "Show " + (o.official ? "official" : "unofficial projected") +
                " Regional " + o.regionalId + " bracket");
            n.appendChild(projection);
        }
        if (o.note) n.appendChild(el("div", "regional-note", o.note));
        if (o.time) n.appendChild(el("div", "entry time", o.time));
        b.appendChild(n)
    }

    function title(x, t, sub) {
        var n = el("div", "stage", t);
        n.style.left = x + "px";
        if (sub) n.appendChild(el("small", "", sub));
        b.appendChild(n)
    }

    function wire(a, c) {
        var A = document.querySelector("#" + a),
            C = document.querySelector("#" + c),
            ax = A.offsetLeft + A.offsetWidth,
            ay = A.offsetTop + A.offsetHeight / 2,
            cx = C.offsetLeft,
            cy = C.offsetTop + C.offsetHeight / 2,
            m = ax + (cx - ax) / 2,
            p = document.createElementNS("http://www.w3.org/2000/svg", "path");
        p.setAttribute("class", "wire");
        p.setAttribute("d", "M " + ax + " " + ay + " H " + m + " V " + cy + " H " + cx);
        s.appendChild(p)
    }
    title(35, "Regional Pool Play", "Arranged by state-bracket path");
    title(690, "Sectional Champions", d.sectionals.length + " sectional finals");
    if (d.firstRound) title(960, "State First Round", "Sixteen state qualifiers");
    var stateDates = d.stateDate ? d.stateDate.split(",") : [];
    title(1180, "State Quarterfinals", stateDates[0]);
    title(1660, "Semifinals", stateDates[0]);
    title(2140, "Third Place", stateDates[1] && stateDates[1].trim());
    title(2620, "Championship", stateDates[1] && stateDates[1].trim());
    sectionalOrder.forEach(function(id, i) {
        var q = d.sectionals[id - 1],
            top = 110 + i * 245;
        q.regionals.forEach(function(r, column) {
            var regional = d.regionals[r - 1];
            var seeding = seededRegionals[r];
            var regionalResult = result("regionals", regional.id);
            var listedTeams = seeding ? seeding.seeds.map(function(seed) {
                return { name: matchTeam(seed.team, regional.teams), seed: seed.seed };
            }) : regional.teams.map(function(team) { return { name: team }; });
            card({
                id: "r" + regional.id,
                kind: "regional" + (seeding ? " seeded" : ""),
                x: 35 + column * 245,
                y: top,
                title: "Regional " + regional.id,
                location: regional.host,
                entries: listedTeams.map(function(listed) {
                    return { text: listed.name, seed: listed.seed,
                        winner: regionalWinner(regional.id) === listed.name,
                        label: "Regional champion confirmed by IESA" +
                            (regionalWinner(regional.id) === listed.name && regionalResult && regionalResult.score ?
                                " • " + regionalResult.score : "") };
                }),
                projected: !seeding && !d.archived,
                official: !!seeding,
                regionalId: regional.id,
                note: regional.note
            })
        });
        card({
            id: "s" + q.id,
            kind: "sectional",
            x: 690,
            y: 175 + i * 245,
            title: "Sectional " + q.id,
            meta: details(q.host, q.date),
            entries: q.regionals.map(function(r) {
                var winner = regionalWinner(r);
                var champion = sectionalWinner(q.id);
                var outcome = champion && result("sectionals", q.id);
                var score = outcome && /^\d+-\d+$/.test(outcome.score) ? outcome.score.split("-") : null;
                return { text: winner || "Winner Regional " + r, team: winner,
                    winner: winner && champion === winner,
                    record: winner && q.records && q.records[r],
                    score: winner && score ? score[winner === champion ? 0 : 1] : null,
                    sourceUrl: outcome && outcome.sourceUrl,
                    label: outcome && outcome.qualifierOnly ?
                        "State qualifier confirmed by IESA" :
                        "Sectional champion confirmed by IESA" };
            }),
            path: true
        })
    });
    document.addEventListener("iesaScoresLoaded", function(event) {
        var teams = event.detail && event.detail.teams;
        if (!teams) { return; }
        Array.prototype.forEach.call(document.querySelectorAll(".sectional > .entry[data-team]"), function(row) {
            var team = teams[row.dataset.team];
            if (!team || !team.record || !Number.isInteger(team.record.wins) ||
                !Number.isInteger(team.record.losses)) { return; }
            var badge = row.querySelector(".record-badge") || el("span", "record-badge");
            badge.textContent = team.record.wins + "-" + team.record.losses;
            row.insertBefore(badge, row.querySelector(".postseason-score"));
        });
    });
    if (d.firstRound) d.firstRound.forEach(function(q, i) {
        card({
            id: "f" + q.game,
            x: 960,
            y: 250 + i * 300,
            title: "State First Round • Game " + q.game,
            entries: entrants(q.matchup.map(function(id) {
                return sectionalWinner(id) || "Winner Sectional " + id;
            }), firstRoundResults[q.game]),
            time: details(q.date, q.time),
            path: true
        });
    });
    d.quarterfinals.forEach(function(q, i) {
        var names = q.matchup.map(function(r, side) {
            if (d.firstRound) return firstRoundResults[r] ?
                firstRoundResults[r].winner : "Winner Game " + r;
            var known = r && sectionalWinner(r);
            if (known) return known;
            // IESA sometimes never publishes a sectional final even though the state
            // scoreboard names the team that advanced. Trust the scoreboard's order only
            // when the opposite side confirms it matches the bracket.
            var published = result("games", q.game);
            var other = q.matchup[1 - side];
            var otherName = other && sectionalWinner(other);
            if (published && Array.isArray(published.teams) && published.teams.length === 2 &&
                published.teams[side] && otherName &&
                matchTeam(published.teams[1 - side], [otherName]) === otherName) {
                return published.teams[side];
            }
            return r ? "Winner Sectional " + r : "State entrant unreported";
        });
        card({
            id: "q" + q.game,
            x: 1180,
            y: 300 + i * 405,
            title: "State Quarterfinal • Game " + q.game,
            entries: entrants(names, quarterfinalResults[q.game]),
            time: details(q.date, q.time),
            path: true
        })
    });
    var semifinalIds = d.semifinals.map(function(game) { return game.game; });
    d.semifinals.forEach(function(q, i) {
        card({
            id: "m" + q.game,
            x: 1660,
            y: 500 + i * 810,
            title: "State Semifinal • Game " + q.game,
            entries: entrants(q.matchup.map(function(r) {
                return quarterfinalResults[r] ? quarterfinalResults[r].winner : "Winner Game " + r;
            }), semifinalResults[q.game]),
            time: details(q.date, q.time),
            path: true
        })
    });
    card({
        id: "third",
        kind: "placement",
        x: 2140,
        y: 900,
        title: "Third Place • Game " + (d.firstRound ? 15 : 7),
        entries: entrants(semifinalIds.map(function(id) {
            return semifinalResults[id] ? semifinalResults[id].loser : "Loser Game " + id;
        }), gameResult(d.firstRound ? 15 : 7, semifinalIds.map(function(id) {
            return semifinalResults[id] && semifinalResults[id].loser;
        })), "Third place confirmed by IESA"),
        time: details(d.thirdPlace.date, d.thirdPlace.time),
        path: true
    });
    card({
        id: "final",
        kind: "champion",
        x: 2620,
        y: 900,
        title: "State Championship",
        entries: entrants(semifinalIds.map(function(id) {
            return semifinalResults[id] ? semifinalResults[id].winner : "Winner Game " + id;
        }), gameResult(d.firstRound ? 16 : 8, semifinalIds.map(function(id) {
            return semifinalResults[id] && semifinalResults[id].winner;
        })), "State champion confirmed by IESA"),
        time: details(d.championship.date, d.championship.time),
        path: true
    });
    d.sectionals.forEach(function(q) {
        q.regionals.forEach(function(r) {
            wire("r" + r, "s" + q.id)
        })
    });
    if (d.firstRound) d.firstRound.forEach(function(q) {
        q.matchup.forEach(function(r) { wire("s" + r, "f" + q.game); });
    });
    d.quarterfinals.forEach(function(q) {
        q.matchup.forEach(function(r) {
            if (r) wire((d.firstRound ? "f" : "s") + r, "q" + q.game)
        })
    });
    d.semifinals.forEach(function(q) {
        q.matchup.forEach(function(r) {
            wire("q" + r, "m" + q.game)
        })
    });
    semifinalIds.forEach(function(id) {
        wire("m" + id, "third");
        wire("m" + id, "final");
    });
    var projectionDialog = document.getElementById("projection-dialog");
    var projectionTitle = document.getElementById("projection-title");
    var projectionRounds = document.getElementById("projection-rounds");
    var projectionSource = document.getElementById("projection-source");
    function projectedTeam(seed, entries, cache) {
        var entry = entries[seed - 1];
        if (!entry) { return "BYE"; }
        var name = entry.dataset.team;
        var record = cache.teams[name] && cache.teams[name].record;
        return { team: name, name: "#" + seed + " " + name + " (" +
            (record ? record.wins + "-" + record.losses : "record unavailable") + ")",
            standing: null };
    }
    function projectedStage(container, titleText, pairs, annotations) {
        var stage = el("section", "projection-stage");
        stage.appendChild(el("h3", "", titleText));
        var games = el("div", "projection-games");
        pairs.forEach(function(pair, index) {
            var game = el("div", "projection-match");
            pair.forEach(function(team) {
                var row = el("div", "projection-team");
                if (typeof team === "string") {
                    row.textContent = team;
                } else {
                    if (team.team === "Springfield Christian") { row.classList.add("springfield-christian"); }
                    row.appendChild(el("span", "projection-team-name", team.name));
                    if (team.standing !== null) {
                        row.appendChild(el("span", "projection-standing", team.standing));
                    }
                }
                game.appendChild(row);
            });
            if (annotations && annotations[index]) {
                game.appendChild(el("div", "projection-annotation", annotations[index]));
            }
            games.appendChild(game);
        });
        stage.appendChild(games);
        container.appendChild(stage);
    }
    function officialStages(regional, bracket) {
        var progress = seededProgress[regional.id];
        ["First round", "Semifinals", "Regional final"].forEach(function(titleText, stage) {
            var pairs = [];
            var annotations = [];
            for (var game = 0; game < progress.names[stage].length / 2; game++) {
                var match = [];
                for (var side = 0; side < 2; side++) {
                    var team = progress.names[stage][game * 2 + side];
                    if (!team) {
                        var seedNumber = [1, 8, 4, 5, 2, 7, 3, 6][game * 2 + side];
                        match.push(stage === 0 ?
                            (bracket.missingSeed === seedNumber ? "Unpublished " + seedNumber +
                                "st seed" : "BYE") : "Winner " +
                            (stage === 1 ? "first-round game " + (game * 2 + side + 1) :
                                "semifinal " + (side + 1)));
                        continue;
                    }
                    var seed = bracket.seeds.find(function(entry) {
                        return matchTeam(entry.team, regional.teams) === team;
                    });
                    var scores = progress.gameScores[stage][game];
                    match.push({ team: team, name: "#" + seed.seed + " " + team,
                        standing: scores ? String(scores[side]) : null });
                }
                pairs.push(match);
                var published = bracket.rounds && bracket.rounds[stage] && bracket.rounds[stage][game];
                annotations.push(published && published.annotation);
            }
            projectedStage(projectionRounds, titleText, pairs, annotations);
        });
    }
    b.addEventListener("click", function(event) {
        var button = event.target.closest(".regional-projection-link, .regional-official-link");
        if (!button) { return; }
        var card = button.closest(".regional");
        var regionalId = Number(card.id.substring(1));
        var regional = d.regionals[regionalId - 1];
        var official = seededRegionals[regionalId];
        var cache = window.iesaScoreCache;
        var entries = Array.prototype.slice.call(card.querySelectorAll(":scope > .entry"));
        projectionTitle.textContent = official ? "OFFICIAL Regional Bracket" : "UNOFFICIAL Projected Bracket";
        projectionDialog.setAttribute("aria-label", "Regional " + regionalId +
            (official ? " official bracket" : " unofficial projected bracket"));
        projectionRounds.replaceChildren();
        projectionSource.hidden = !official || !official.sourceUrl;
        if (!projectionSource.hidden) { projectionSource.href = official.sourceUrl; }
        if (official) {
            officialStages(regional, official);
        } else if (!cache || !cache.teams) {
            projectionRounds.textContent = "Official school records are unavailable; no projection can be shown.";
        } else {
            projectedStage(projectionRounds, "First round", [[1, 8], [4, 5], [2, 7], [3, 6]].map(function(pair) {
                return pair.map(function(seed) { return projectedTeam(seed, entries, cache); });
            }));
            projectedStage(projectionRounds, "Semifinals", [
                ["Winner first-round game 1", "Winner first-round game 2"],
                ["Winner first-round game 3", "Winner first-round game 4"]
            ]);
            projectedStage(projectionRounds, "Regional final", [
                ["Winner semifinal 1", "Winner semifinal 2"]
            ]);
        }
        projectionDialog.showModal();
    });
    document.getElementById("close-projection").addEventListener("click", function() {
        projectionDialog.close();
    });

    function current() {
        var m = b.style.transform.match(
            /translate\(([-\d.]+)px,\s*([-\d.]+)px\)\s*scale\(([-\d.]+)\)/);
        return m ? {
            x: Number(m[1]),
            y: Number(m[2]),
            z: Number(m[3])
        } : {
            x: 0,
            y: 0,
            z: 1
        }
    }

    function setTransform(t) {
        t = window.clampBracketTransform(t.x, t.y, t.z);
        b.style.transform = "translate(" + t.x + "px," + t.y + "px) scale(" + t.scale + ")"
    }

    function fit() {
        var z = Math.min((v.clientWidth - 30) / 3500, (v.clientHeight - 30) / 2080, 1);
        setTransform({
            x: (v.clientWidth - 3500 * z) / 2,
            y: (v.clientHeight - 2080 * z) / 2,
            z: z
        })
    }

    function zoom(k) {
        var c = current(),
            z = Math.max(.18, Math.min(2.5, c.z * k));
        setTransform({
            x: v.clientWidth / 2 - (v.clientWidth / 2 - c.x) * z / c.z,
            y: v.clientHeight / 2 - (v.clientHeight / 2 - c.y) * z / c.z,
            z: z
        })
    }
    document.querySelector("#plus").onclick = function() {
        zoom(1.2)
    };
    document.querySelector("#minus").onclick = function() {
        zoom(1 / 1.2)
    };
    document.querySelector("#fit").onclick = fit;
    v.onpointerdown = function(e) {
        if (e.target.closest("button, summary, a, input, select, textarea")) { return; }
        var c = current();
        drag = {
            a: e.clientX,
            b: e.clientY,
            x: c.x,
            y: c.y,
            z: c.z
        };
        v.classList.add("dragging");
        v.setPointerCapture(e.pointerId)
    };
    v.onpointermove = function(e) {
        if (drag) {
            setTransform({
                x: drag.x + e.clientX - drag.a,
                y: drag.y + e.clientY - drag.b,
                z: drag.z
            })
        }
    };
    v.onpointerup = v.onpointercancel = function() {
        drag = null;
        v.classList.remove("dragging")
    };
    window.onresize = fit;
    fit();
    if (d.archived) { return; }
    var dialog = document.querySelector("#record-dialog"),
        form = document.querySelector("#record-form"),
        name = document.querySelector("#team-name"),
        record = document.querySelector("#team-record"),
        history = document.querySelector("#score-history"),
        official = document.querySelector("#official-scores"),
        selected, key = "iesa-2026-" + d.grade + "-records";

    function saved() {
        try {
            return JSON.parse(localStorage.getItem(key) || "{}")
        } catch (e) {
            return {}
        }
    }

    function renderRecord() {
        var all = saved(),
            games = all[selected] || [],
            wins = games.filter(function(g) {
                return g.team > g.opponent
            }).length,
            losses = games.filter(function(g) {
                return g.team < g.opponent
            }).length;
        record.textContent = "Record: " + wins + "–" + losses;
        history.innerHTML = "";
        if (!games.length) {
            var pending = document.createElement("tr"),
                opponent = document.createElement("td"),
                status = document.createElement("td");
            opponent.textContent = "No reported scores";
            status.textContent = "PENDING";
            pending.appendChild(opponent);
            pending.appendChild(status);
            history.appendChild(pending)
        }
        games.forEach(function(g) {
            var row = document.createElement("tr"),
                opponent = document.createElement("td"),
                score = document.createElement("td");
            opponent.textContent = g.name;
            score.textContent = g.team + "–" + g.opponent;
            row.appendChild(opponent);
            row.appendChild(score);
            history.appendChild(row)
        })
    }
    Array.prototype.forEach.call(document.querySelectorAll(".regional .entry"), function(n) {
        n.addEventListener("pointerdown", function(e) {
            e.stopPropagation()
        });
        n.addEventListener("click", function() {
            selected = n.textContent;
            name.textContent = selected;
            form.reset();
            official.hidden = selected !== "Normal Epiphany";
            renderRecord();
            dialog.showModal()
        })
    });
    document.querySelector("#close-dialog").onclick = function() {
        dialog.close()
    };
    official.onclick = function() {
        window.open(
            "https://www.iesa.org/activities/memberStats.asp?SchoolID=417&ActivityCode=GBK&GradeLevel=7",
            "_blank", "noopener")
    };
    form.addEventListener("submit", function(e) {
        e.preventDefault();
        var all = saved();
        all[selected] = all[selected] || [];
        all[selected].push({
            name: document.querySelector("#opponent").value,
            team: Number(document.querySelector("#team-score").value),
            opponent: Number(document.querySelector("#opponent-score").value)
        });
        localStorage.setItem(key, JSON.stringify(all));
        renderRecord();
        form.reset()
    })
}());
