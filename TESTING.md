# Testing

How the station is checked, and the tools for looking at it. The rules under test are
[STATION.md](STATION.md) and [WIRING.md](WIRING.md); the seams they are tested at are in
[ARCHITECTURE.md](ARCHITECTURE.md).

## The gate

```bash
./test.sh            # every suite, then the three smoke scenarios
./test.sh offices    # the smoke scenarios whose name contains "offices" (the suites still run)
```

It builds with `./build.sh fast`, then runs every suite and the smoke scenarios, each in a throwaway
support folder, the scenarios, playback and intake beside the rest, so at most four processes at once.
About nine seconds with the build. It prints every failing line (`FAIL`, `not so`) and each suite's last
line, the scenarios' results, `gate: Ns`, and exits non-zero if any suite or scenario failed. Run it
before every commit.

Each suite is a flag on the one binary, `.build/debug/Rumkapsel --<name>-tests`, and exits non-zero on
a failure:

| Suite | Checks |
|---|---|
| `rule` | an event on given facts gives the right facts and effects; no station, no bodies |
| `intake` | the simulator's presses against a bare `World`, the clock jumped, no stepping: the right facts, log lines and events; fails on a refused press or a give-up |
| `playback` | one move or sequence on a bare `Simulation<Body>`, facts byte-equal before and after |
| `sim` | bodies: sends, visits, the gym, the board's preemption, give-ups, the bay, night, `step(600)` |
| `idle` | what an empty board leaves a body to, and the idle clock |
| `walk` | stepping along a path and passing |
| `work` | a branch, an issue and a pull request as one piece of work, and its office key |
| `deploy` | which Actions runs are deploys, their usual length, starts and ends |
| `pipeline` | a repository's way to production from its merges and branch names |
| `layout` | the floor: same rooms give the same cells, slots, the yard, the bay, signs, facts across a save |
| `spacelog` | the Station Log panel's story from the feed, releases and board |
| `look` | per theme: what it draws itself, its furniture and cones on the station's footprints, its launch within the climb |

## Smoke scenarios

`--scenarios [word]` builds a whole station per scenario with the simulator's made-up org, presses its
buttons and steps station time headless at 0.1 s, drawing nothing. A scenario stops once its checks hold
and the station is quiet. It fails on a give-up, a refused press, a forbidden or missing record, a
picture that never caught up with the facts, a watchdog snap, or its own floor check. There are three:

- **the pipeline**: my pull request merges to storage, staging takes it to the deck, it is ticked,
  released and goes up;
- **offices**: a teammate's office by shuttle, his merge hauled out before it folds, his closed pull
  request cleared, a neighbour in the gym;
- **outside work and a hotfix**: a bot's object cleared from decon into storage, a hotfix up in its own
  rocket beside the release.

`--scenarios-verbose` prints each scenario's whole log, the facts and what is shown.

## Looking at the picture

| Flag | Does |
|---|---|
| `--snapshot out.png` | renders a frame after `--delay` seconds (default 4) and exits; prints the node count |
| `--frames N --every S` | N numbered frames from the delay on, S seconds apart (default 0.5) |
| `--yaw`, `--pitch`, `--zoom` | the camera |
| `--focus <station>` | frames a station; with `--look <room or area>` frames one room, or `bay`, `pad`, `deck`, `storage`, `decon`, `hall`, `yard`, `gate` |
| `--follow <minion>` | keeps the camera on a minion: its id, the word after its colon, or its home's name |
| `--walk <seconds>` | steps into the walk after that long |
| `--log` | opens the Station Log panel |
| `--no-stars` | leaves the star backdrop out |
| `--demo` | fake sessions; `RK_DEMO_OFFICES=n` adds n offices |
| `--simulator` | a station on its own: scanner, GitHub and network off, driven by presses through the entry points production uses |
| `--simulate "Target: web#455,Set: commits ahead = 8,Merge PR"` | presses those in order, two seconds apart, from four seconds in. `Target:` picks the office, `Set: <knob> = <value>` turns a knob, anything else is a move; a move whose ground is not laid lays it. With `--snapshot`, the simulator's board and log go to stderr |
| `--playbook` | one moment per entry, its floor laid and its one thing pressed; `--entries` lists them, `--entry "QA approves"` plays the first whose name has those words |
| `--gallery` | every routine and every piece the current theme draws, a tile each; `--tiles` lists them, `--tile rockets` frames one; `]`, `[` and `0` in the window |
| `--look-dev <png> [shot]` | a still of the flight's rocket in a couple of seconds: `hull` (default), `wide`, a named camera, or `crates`, `rockets`, `signs` |

## Debugging

| Tool | Does |
|---|---|
| `--dump-facts [seconds] [repo]` | after 25 s (or the seconds given), every office, rocket and crate: its fact and what is shown; then exits |
| `--dump-bodies [seconds] [station]` | after 20 s, every body and its order; then exits |
| Develop › Copy Facts Report (⌘⇧L), Copy Body Report (⌘⇧B) | the same from the running app, to the clipboard and stderr |
| Develop › Skip to the Facts | shows the facts at once |
| Develop › Restack the Yard | lays every crate out afresh by the rules |
| Develop › Rehearse Launch, Rehearse Failed Launch | flies a pretend deploy |
| `kill -USR1 <pid>` | writes the state to `station.log` |
| `--github-diag [seconds] [--repo <path>]` | runs the GitHub poller alone against the real settings for 120 s (or the seconds given) and prints every ask and every answer that changed |
| `--dump-floor <theme>`, `--dump-colors` | the fixed floor as JSON for `floor/`; the repository colours |
| `--bake-plating`, `--bake-walls`, `--bake-detail`, `--bake-suits` | bake the textures into `Resources/` |

`station.log` in the support folder has a line per command, stage transition (`stage`), GitHub ask
(`github`), rule drift (`facts`), watchdog snap (`playback`), release step (`release`) and blocked walk
(`walk`).

| Environment | Does |
|---|---|
| `RUMKAPSEL_SUPPORT=<dir>` | the support folder (config, saves, logs) under that directory instead of `~/Library/Application Support` |
| `RK_FRAMES=1` | prints every slow frame and what took the time |
| `RK_FILL=1` | `--layout-tests` also prints forty- and eighty-office fills per placement |
| `GITHUB_DIAG=1` | the app echoes every GitHub ask to stderr |

A run on a copy of your config shares on the network like you; set `shareOnLAN` to false in the copy.
