# How rumkapsel is put together

The rule the code is cut by: `(event, facts) → (new facts, effects)`, at once and the same every time.
Everything that moves on screen is playback, catching the picture up to the facts. Skipping it is
`shown := facts`. Playback never writes a fact.

```
 Integrations   sources read and cache; World turns what they say into reports and events
      │  Event + now
      ▼
 Rules          Rules.apply(events, now, &facts, yard) → [Effect]      pure: no clock, no bodies, no scene
      │  Facts (per station, saved)          Effects: log, quiet, renamed, hatch
      ▼
 Layout         Layout.spots(facts, yard) → where every crate belongs      pure
      ▼
 Playback       Simulation: shown vs facts → moves → order board → bodies → `shown`
      ▼
 Scene          draws `shown`, the bodies and the flights; HUD and log read the facts and effects
```

What each source says and how often is [WIRING.md](WIRING.md); what things may do is
[STATION.md](STATION.md). Everything is one SwiftPM target, `Sources/Rumkapsel/`, in seven folders.

## The folders

**State/**: the values the rest share.

| File | What it is |
|---|---|
| `Facts.swift` | the facts: `Facts`, `CrateFact` and its `Place`, `Zone`, `OfficeFact`, `RocketFact`, `StagingFact`, `RepoFacts` |
| `Stages.swift` | `Stage`, `Source`, `Signal`, `Transition`, and `Record.hear`, the priority rules |
| `Work.swift` | `Work`, one piece of work's names and office key, and `WorkBook`, a record per work with every alias |
| `Workflow.swift` | a repository's answers per stage |
| `Station.swift` | cells, colours, rooms, the `Station` (rooms, hallway, pathfinding, facts, saving) and the `Fleet` |
| `Plan.swift` | the plaza and the two fixed arms, to the yard and the bay |
| `Floorplan.swift` | a baked plan: the quarters, the hallway lit at start, the office slots; `OfficePlacement` |
| `BakedPlans.swift` | the plans baked by `floor/bake.py`, per theme |
| `Hall.swift` | the yard's geometry: walkway, aisles, the three zones' grids, decon, the pad, its slots and field |
| `Hull.swift` | the hull round the station |
| `Fixtures.swift` | where the bath's and lounge's fixtures stand |
| `OfficeMarks.swift` | an office's package cell and cube pile |
| `Obstacles.swift` | footprints, and what a walk goes round |
| `Theme.swift` | `Theme`, `Vocabulary`, `Words` |
| `SpaceLog.swift` | the Station Log panel's story, read from the feed, releases and board |
| `Migration.swift` | an old save's ledger turned into facts, once |
| `EventLog.swift` | the event log: a line per applied batch, baselines, writing, pruning, replay, each crate's history |
| `CrateStory.swift` | a crate's story in words, from its history: a row per step, the waits between, the lead time |
| `EventCoding.swift` | how an `Event` and the yard are written in a log line |

**Rules/**: pure functions of the facts.

| File | What it is |
|---|---|
| `Rules.swift` | `Event`, `Effect`, `Rules.apply`: crates, offices, decon, staging; `normalize` |
| `RocketRules.swift` | releases, hotfixes, launches, ships-on-merge rockets, go, pad slots |
| `Layout.swift` | `YardGeometry`, `YardSpot`, `Layout`: homes, columns, spots, relayout |
| `FactFeed.swift` | intake: `World.learn`, batching, routing to a station, the save throttle |

**Integrations/**: the sources, and `World`.

| File | What it is |
|---|---|
| `World.swift` | the model's front door: rooms, offices, crew, decon, neighbours; turns answers into reports and events |
| `Releases.swift` | releases, hotfixes, staging releases and the counts, turned into events |
| `PullRequests.swift` | a pull request's state: yours by branch, a teammate's from the feed, then by number, then by branch |
| `GitHub.swift` | `GitHubResolver`: every GitHub and git read, cached, on its interval, with doorbells; the counts |
| `GitHubHTTP.swift` | conditional REST reads with the `gh` token |
| `GitHubDiag.swift` | `--github-diag` |
| `Pipelines.swift` | a repository's way to production, detected or from `.github/rumkapsel.json` |
| `Deployments.swift` | which Actions runs are deploys, their usual length, starts and ends |
| `Scanner.swift` | the transcripts: sessions, activity, prompts |
| `Watcher.swift` | FSEvents on a folder |
| `Workspaces.swift` | whether a checkout is still open |
| `Peers.swift` | `PeerSnapshot` and `PeerHub`: Bonjour, the links, the heartbeat |
| `Config.swift` | `AppConfig` (`config.json`), `ConfigStore`, the support folder |
| `Events.swift` | `WorldEvent`: what World hands the scene that is not a fact: log lines, prompts, crew, deploys |

**Playback/**: the `Simulation`, which owns the clock, the bodies and `shown`.

| File | What it is |
|---|---|
| `Simulation.swift` | the clock, step, tick and beat, timers, orders, rest, walks; `Cargo`, `Cue`, `Hands`, `Tempo` |
| `Playback.swift` | `Shown`, the crate diff, moves, physical order, parking, skip and snap, the crate watchdog |
| `Offices.swift` | shown offices: arrival, delivery, fold, stows, packs, the office watchdog |
| `Rockets.swift` | `RocketGeometry` and shown rockets: arrival, dock, weld, vent, launch, climb, the rocket watchdog |
| `Vortex.swift` | the vortex: the ring, the crates pulled, the close |
| `Drones.swift` | the pad drones: rack, weld, vortex ring |
| `Shuttles.swift` | flights: arrival and departure styles, legs, the bay |
| `Board.swift` | the order board: `Rank`, openings, own orders, who takes what, preemption |
| `Carries.swift` | the hands: lift, carry, set-down, deliveries, stows, packs; `Patience` |
| `Bodies.swift` | the body reconciler: stalls given up |
| `Body.swift` | `Body`: one body's state |
| `Minion.swift` | `Minion`, the app's body, with its figure |
| `Commands.swift` | `Command` (kind, phases, words), `Spot`, `CrateRef` |
| `Walk.swift` | stepping along a path, and passing |
| `Idle.swift` | the idle clock, the pick after an order, roam spots |
| `Routines.swift` | what a body does with its hands and wears, per activity |
| `Callsigns.swift` | callsigns for the bubble |
| `CrateMotion.swift` | crate arcs on the station clock |

**Scene/**: SceneKit. `StationController` is one class in extensions.

| File | What it is |
|---|---|
| `Scene.swift` | the controller: scene graph, input wiring, the frame tick, `WorldEvent` glue, the peer snapshot |
| `SceneStatic.swift` | the floor, walls and the names on it |
| `SceneMarkers.swift` | crates, cones, pad rings, berth and office lights |
| `SceneTick.swift` | the per-frame minion loop, poses, cues, the demo |
| `OfficeView.swift` | offices drawn from what playback shows |
| `Actors.swift` | shuttles and rockets drawn from the flights and shown rockets |
| `PadLift.swift`, `PadWall.swift` | the pad lift; the pad wall's field and the drone rack |
| `DronesView.swift`, `VortexView.swift`, `HangarView.swift` | drones, the vortex, the bay's field and berths |
| `Props.swift` | shared props: crates, packages, cones, cubes, the classic rocket |
| `RocketShape.swift` | the one rocket shape, for the station and the flight |
| `Mission.swift`, `FlightCraft.swift`, `Colony.swift`, `Planets.swift`, `Plating.swift` | the deploy flight: cameras and clock, its rocket, colonies, planets, baked plating |
| `FirstPerson.swift` | walking the station |
| `HUD.swift` | the overlay: hover lines, bubbles, the corner log, links |
| `Jobs.swift` | minions spawned and despawned, the seam to the simulation's orders, the state dump |
| `Signs.swift` | direction signs at hallway junctions |
| `Walls.swift`, `Detail.swift`, `Suits.swift` | baked wall panels, surface detail, suits |
| `Drone.swift` | the music |
| `Looks/` | the `Look` protocol and the looks: see [THEMES.md](THEMES.md) |

**App/**: `main.swift` (flags, menus, windows), `StationView.swift` (input and camera), `Settings.swift`,
`SpaceLogPanel.swift`, `NeighboursPanel.swift`, `CrateStoryPanel.swift`, `StationLog.swift` (`station.log`), and the tools:
`Simulator.swift`, `Playbook.swift`, `Gallery.swift`, `LookDev.swift`, `FactsDump.swift`, `BodyDump.swift`,
`FloorDump.swift`, `Replay.swift` (`--replay`: a log file replayed and checked, or one crate's story).

**Tests/**: the suites and the smoke scenarios, run by flag from the one executable: see
[TESTING.md](TESTING.md).

## Who writes what

| Thing | Written by | Read by |
|---|---|---|
| `WorkBook` records | World, from the sources | World, to make `.work` events |
| `Station.facts` | `Rules.apply` only | playback, the HUD, the log, saving |
| `Station.rooms` (cells, hallway) | World, through `ensureRoom`, `renameRoom`, `removeRoom` | rules (keys), playback, the scene |
| `Simulation.shown`, `cargo`, vortices, flights | playback | the scene |
| bodies | the simulation | the scene |

Seams: rules take value types and a `now` and touch nothing else. `Layout` has no cache: every caller works
spots out from the facts, so nothing can disagree with them. Playback reads facts and writes `shown`. The
scene reads `shown`, bodies and facts and writes nothing back.

## The model clock

`Simulation.step(dt:)` owns time; the scene only draws (`onStep`, `onBeat`).

- A step runs in substeps of 1/30 s (`Tempo.substep`). Each runs the timers (`Simulation.after`), the beat
  every half second, then shuttles, rockets, vortices, drones and bodies, then `onStep` for the scene.
- The beat: `World.settle(tick: true)` (rules, with `.tick`), `play()`, the board hands out orders, the
  body reconciler, obstacles, the scene's flush, re-planned walks.
- A `dt` over five seconds (`Tempo.catchUp`) jumps the clock and skips: the picture shows the facts and
  nothing replays.
- `now`: live in the app, the wall clock; simulated everywhere else (scenarios, the simulator, the
  playbook, tests), a fixed epoch plus the station clock. Facts are stamped with `now`, so holding space,
  which multiplies the app's `dt` by four, speeds the picture and never the facts.
- In the app a frame plays at most a quarter second (`Tempo.frame`), unless the gap is long enough to skip.

## Saving and loading

- `fleet-v25.json` in the support folder holds per station its dug hallway, its rooms and its facts (without
  launched rockets and the crates aboard them), plus the repository colours.
- The facts are saved on a beat at most every five seconds once they have changed (`FactFeed.saveEvery`).
- On load: the saved facts, or, from a save that has none, `Facts.migrate` of the old ledger, once: every
  crate placed by where it stood, the busiest repository first, laid out afresh. Facts of another
  `Facts.scheme` are laid out afresh. A save that cannot be read is kept beside it as
  `fleet-v25.unreadable-<time>.json`, and what it held starts afresh.
- After loading, rooms and office facts are reconciled (`officeDrift`) and the picture is snapped to the
  facts: nothing half-done resumes.
- Elsewhere in the support folder: `config.json`, `board.json` (the board, its owners and which
  repositories use it), `station.log` (rolled at 4 MB).

## Intake

- `World.learn(event, repo:)` queues an event and settles at once, unless inside `World.batch`, which a scan,
  a GitHub answer, a neighbour's snapshot and a kick each are; the batch settles once at its end.
- Settling routes each event to the station holding its repository; events for a repository no station holds
  yet wait (up to 500). It adds `.policy` where a repository's `RepoFacts` changed, merges launches of one
  repository (`FactFeed.together`), and calls `Rules.apply`. Up to four rounds, so what one round routes
  the next applies.
- Office news go straight to `Rules.apply` for their station (`World.learn(_:station:)`).
- A record's transition becomes a `.work` event (`World.learn(record, transition)`); a quiet first word
  is a quiet event. A record whose number changes is `.renumbered`, and its crate keeps its place.
- On the tick, rooms that have no office fact, and office facts with no room, are set right and logged
  under `facts` (`officeDrift`).

## Playback

`Shown`, per station: crates (in an office, on a row, parked, in hands, in the vortex, aboard, falling),
offices, deliveries, cube counts, rockets, and the rockets that have flown.

- `play(station)` runs on every beat and every change of facts: crates, offices, rockets. The first play
  of a station snaps it. It does nothing when facts, picture and jobs are as it left them (`Calm`).
- **The crate diff** compares `shown` with the targets from `Layout.spots`. What needs hands becomes a
  move: a **haul** out of an office, a **carry** between zones, a **park** to set a blocker aside, a
  **hold** to lift one up while its pile is sorted. What needs none is shown directly: a crate that appears,
  one that falls in from the decon hatch, one that settles a level (`falling`, `Hands.settleSeconds`), one
  that fades.
- **Physical order.** A move is offered on the board only when nothing blocks it: no crate shown above it
  (decon excepted), and its place free with a standing crate under it. A blocker with no move of its own
  is parked at the nearest free spot no target uses, or held up, one at a time. A cycle is broken by
  holding one. A blocker takes the rank of what it blocks.
- **Ranks** on the board, low to high: idle, tidy, crew, desk, QA, yard, release, message, leaving. A
  carry to the cleared rows is `release`; between zones, `yard`; within one zone, a stray going home,
  `tidy`.
- Moves become `Cargo` on the board (`hire`); a body takes one at a safe point. Lifting puts the crate in
  `hands`; setting down shows it on its row or parked. When the facts change, an unlifted move is called
  off or re-aimed, a lifted one re-aimed or set down where it was going, and the next play goes on from
  there.
- **Skip and snap**: `skip()` snaps every station; `snap(station)` calls off its carries, drops its vortices
  and shows the targets; `snap(station, crate)` does one crate and whatever stands on its spot. Used on
  load, on a long `dt`, for a quiet effect, from Develop › Skip to the Facts, and by the watchdog.
- **The watchdog**: a crate, office or rocket shown off its fact whose mark has not changed for 90 s
  (`Patience.waitLimit`; a rocket waits for its deploy's usual length when longer) is snapped, logged under
  `playback`, and counted (`Simulation.snapped`). `Simulation.lag()` says what is behind.

**Offices.** An office in the facts and not shown arrives by its `via`: built at once, fading in, or by a
delivery (a flight drops the hexagon crate, a carrier takes it to the doorway, it unfolds). It waits for
any office still folding on its cells. An office shown and gone from the facts folds once no crate is shown
in it, no haul comes from it and nobody is inside. Unfolding, fading and folding are functions of the
station clock (`ShownOffice.tile`, `label`, `crate`), so a skip ends them and a capture shows them. Stows
and packs are posted to the office's own minion as the cube and crate counts catch up.

**Rockets.** A rocket in the facts appears once its slot is clear of shown rockets. `dock` eases toward 1
when docked or launched over `RocketGeometry.dockSeconds` (9 s), at once in a look whose kick stage does
not rise; `RocketGeometry` turns it into iris, tip and deck. The tip is welded from the staging fact. It
vents when go and docked. Launched and docked, it opens a vortex for every crate whose fact is aboard it;
it climbs once the vortex has closed with nothing pending, on the station clock for the look's
`launchSeconds`, then is flown. The deploy flight itself is the scene's (`Mission.swift`), started by deploy
events.

## Obstacles

`Simulation.obstacles(station)`, on every beat: crates as shown (rows, falling, office packages, parked off
the lanes), office packages and cube piles, cones from the bodies that own them, shown rockets, the
furniture each look draws (`Station.furniture(theme:offices:)`, held equal to what is drawn by
`--look-tests`), and the glass doors' posts. The planner also walks round standing bodies (`crowd`).

## Neighbours

Bonjour `_rumkapsel._tcp`, one JSON `PeerSnapshot` per line, `version` 2; any other version is ignored.
It carries the station's name, start and send time, whether the link works both ways; its offices (key,
name, repository, branch, colour, cells, pushed, started, last active, boxes, dim, the pull request's
number, state, review and checks), only those checked out on that machine in shared repositories; its
minions (a hashed id, office, asleep, busy, activity, waiting, cones, what it is doing, callsign); every 30
s its GitHub knowledge (open pull requests and recent feed per repository) and the board; and its
repository colour slots. The scene makes it (`makeSnapshot`); `World.applyPeer` takes it in: rooms adopted
on the neighbour's cells (the lower name's cells win a dispute), `.office` news, Inbound by neighbour, and
colours from the lower name. `dropPeer` holds a vanished neighbour's offices for a day.
