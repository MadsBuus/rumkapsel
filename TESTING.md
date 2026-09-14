# Testing: where it stands, and the three changes to make

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
- Measured: 25 scenarios in 179 s, of which the twelve-minute idle soak is 100 s; the other 24 average 3 s.

## How game engines do it, and where this differs

Engines separate simulation from rendering. The simulation runs on a fixed timestep, is deterministic
for a given seed, and is tested headless: unit tests on rules, replay tests on recorded inputs, soak
tests that run for hours. Rendering is tested apart, with golden images. The station's simulator and
ledger tests already follow that shape; the scene is what is still mixed in.

## Change 1: waits in station seconds, the soak on demand

- Scenario waits and tails are written in "wall seconds at sixteen times", a leftover from a wall-clock
  runner. Rewrite every wait as plain station seconds; keep behaviour identical (multiply by 16 once).
- The idle soak runs only with `--scenarios soak` or an explicit `--soak` flag, not in the gate.
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
- Done so far: `Simulation` (`Simulation.swift`) owns the clock, the bodies, the orders, the walks, the rest and
  the idle life, and steps the quiet commands (goTo, sleep, work, bath, exercise, chore, qa, react, leave); the
  carries, office deliveries, stows and packs (`Carries.swift`) and the body reconciler (`Bodies.swift`) are its
  too, and a body's load is a fact on it, the scene lifting the node when the load appears and landing it where
  the body says it went. The scene runs the pallet errands between the simulation's steps and draws the pose
  the body says it holds. `--sim-tests` steps a bare `Simulation<Body>` through a send, a bath visit, a gym
  turn, a rest refused under a visit, the idle clock, the airlock, a carry from storage to the deck, and a
  wedged carrier giving up. Still the scene's: the pallets, the shuttles and the rockets, and the ledger's
  `landed` written by what the scene does when a carry lands.
