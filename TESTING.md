# Testing: where it stands, and the changes to make

## The gate

Every change runs all of it before it is committed; it takes half a minute.

```bash
swift build --build-system native
.build/debug/Rumkapsel --scenarios
.build/debug/Rumkapsel --sim-tests
.build/debug/Rumkapsel --idle-tests
.build/debug/Rumkapsel --walk-tests
.build/debug/Rumkapsel --ledger-tests
.build/debug/Rumkapsel --pipeline-tests
```

The native build system is named because Xcode 26.1's default lays the products out where the debug binary
cannot find the Sparkle framework beside it; the app bundle is fine either way. `--scenarios pallet` runs
the scenarios whose name contains a word; `--scenarios-verbose` prints each
scenario's whole log, ledger and bodies. For a look at the picture, `--simulator --snapshot out.png
--simulate "Target: web#455,Open PR,Merge PR" --delay 19` renders a frame after those presses, without
taking the keyboard.

## How the station is tested today

- `--scenarios` builds a station of its own per scenario, with a made-up org, presses simulator buttons,
  and steps station time in 1/30 s ticks in a tight loop. No frames are drawn and no wall clock is
  involved. A scenario is judged on the record of events and commands, on invariants checked every
  tick, and on the floor at the end.
- `--ledger-tests`, `--pipeline-tests` and the body rules are model-only: facts in, rules out, no station.
- The suite runs the exact code the app runs, scene-side logic included, which is where most bugs have
  lived: walks, doorways, deliveries, carries. That is its strength. Its weakness is the same fact: every
  tick drags SceneKit bookkeeping along, so a station second costs milliseconds, and model rules cannot
  be tested apart from the picture.
- Measured when this was written: 25 scenarios in 179 s, of which one twelve-minute idle run was 100 s.

## How game engines do it, and where this differs

Engines separate simulation from rendering. The simulation runs on a fixed timestep, is deterministic
for a given seed, and is tested headless: unit tests on rules, replay tests on recorded inputs, soak
tests that run for hours. Rendering is tested apart, with golden images. The station's simulator and
ledger tests already follow that shape; the scene is what is still mixed in.

## Change 1: waits in station seconds

- Scenario waits and tails are written in "wall seconds at sixteen times", a leftover from a wall-clock
  runner. Rewrite every wait as plain station seconds; keep behaviour identical (multiply by 16 once).
- The three-hour idle run is gone: what it watched, that visits happen in a mix and last their whole time,
  the idle tests and the sim tests check in seconds.
- Target: the gate under 90 s, and a scenario readable as "press, wait 40 station seconds, judge".

## Change 2: model-only tests for rules that are pure already

- The idle pick (weights, one clock, no reset on leaving) and the doorway lane (claim, renew, lapse,
  wait outside) can be tested without a station: a fake clock, a fake set of bodies, facts in and orders
  out. Same shape as `LedgerTests` and `PipelineTests`: `--idle-tests`, `--lane-tests`.
- The scenario suite keeps one end-to-end check per rule; the model tests carry the edge cases.

## Change 3: the model apart from the picture

- Today `StationController` owns both the world model and the SceneKit scene, and minion movement
  lives in `SceneTick` with node positions. Split it: a `Simulation` that owns stations, ledger, bodies,
  commands, walks and the clock, with no SceneKit import; a `Scene` that draws whatever the simulation
  says, frame by frame, and never decides anything.
- Then the whole scenario suite runs against `Simulation` alone, at microseconds per tick, and the
  scene gets its own thin tests: given a simulation state, the right nodes exist at the right places.
- This is the largest change; do it in slices: bodies and walks first (already close), then carries and
  crates, then rockets and shuttles. The rulebook is STATION.md; every rule keeps its scenario.
- Done, the four slices: `Simulation` (`Simulation.swift`) owns the clock, the bodies, the orders, the walks,
  the rest and the idle life, and steps every command a body runs: the quiet ones there, the carries, office
  deliveries, stows and packs in `Carries.swift`, the pallet errand in `Pallet.swift`, and the body reconciler
  in `Bodies.swift`; the shuttles' flights and the rockets' stages are its too (`Ships.swift`). A body's load
  and pose are facts on it; a pallet, a flight and a rocket are numbers on the station clock; the scene keeps a
  node for each and places it from those facts, and what it shows once comes back as a cue. Nothing the scene
  draws decides anything, and the simulation borrows nothing from the scene any more.
- `--sim-tests` steps a bare `Simulation<Body>` through a send, a bath visit, a gym turn, a rest refused under
  a visit, the idle clock, the airlock, a carry from storage to the deck with the ledger in step, a wedged
  carrier giving up, and the whole pallet errand from the console to the deck.
- Measured on 2026-09-14, the gate of sixteen scenarios: 17 s before the split, 12 s after it and after the
  station's fixed cells, the placement's neighbour distances and the furniture's obstacle cells stopped being
  rebuilt on every read. A sample of the run puts what is left in three places: the bodies' step and their
  routes, about a third; the invariants and the yard reconciliation, about a fifth; the simulator's presses,
  which place rooms and redraw the static floor, about an eighth.

## Change 4: the scenario suite on the simulation alone

Not done. Three things still make a scenario need a `StationController`, and they are the remaining slice:

- The event glue. `Scene.handle(_:)` turns a `WorldEvent` into what happens: an office merged becomes a haul
  from where the package node stands, a staging release becomes a pallet order, an archive cancels carries and
  sinks the tiles. The decisions in it belong in the simulation, with the drawing left as cues; the package's
  cell, today read off its node, would come from the office's far cells worked out on the model side.
- The obstacles. `refreshObstacles` reads the props' bounding boxes to tell the station what a walk goes round.
  The crates come from the ledger's layout, the cones from the bodies, the pallet and the rockets from the
  simulation already; the furniture is the last part read off nodes, and would become a table of footprints per
  room kind that `SceneStatic` draws from too.
- The stows. `rebuildMarkers` notices a commit count going up and hands the owner a stow while it draws; the
  count is the world's, and the order should be issued from the model's diff, not from the redraw.
- With those three moved, `ScenarioRunner` can build a `Simulation<Body>` and a `World` without a view, press
  the same simulator buttons through the world's entry points, and judge the same records and invariants,
  the invariants reading the ledger and the bodies rather than the nodes. The scene then gets its own test:
  given a simulation state, the right nodes exist at the right places, checked on one frame.
