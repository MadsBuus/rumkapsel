# How rumkapsel is put together

Three layers, and the seams between them are where bugs have hidden.

## 1. Sources

Each polls one thing and caches the answer. None of them knows about the picture.

| Source | File | Asks | How often |
|---|---|---|---|
| Sessions | `Scanner.swift` | `~/.claude/projects`: who is working where, on which branch | every 5 s and on file change |
| GitHub | `GitHub.swift` | per-branch pull request, team open PRs, activity feed, release PRs, commits ahead | 5 min (feed 2 min, commits 1 min) |
| Board | `GitHub.swift` (`refreshProject`) | the project's Status per issue, via GraphQL | 5 min, shared with peers |
| Peers | `Peers.swift` | other rumkapsels on the LAN: their claimed offices, minions, GitHub answers | every 3 s |

A failed call keeps the previous answer. A source's **first** answer is taken quietly: whatever it holds
already existed. `readyRepos` tracks which repositories have answered; only changes after that are events.

## 2. Model and diffs

`Station.swift` holds the floor plan: rooms keyed by branch (`task:repo#N` for `gh-N/...` branches), fixed
rooms (`kind:...`), the hall, doorways, and pathfinding on a 3x3 grid per cell around props. The hallway's
skeleton and the office slots are a `Floorplan` (`Floorplan.swift`), drawn offline (`floor/`), baked, and
picked from the station's name: the quarters, the hallway lit before anything opens, and a hundred office
slots in rings out from the monolith, each with the run of hallway that first reaches it. A new office takes
a free slot and lights its run (`takeSlot`). Which slot is a setting (`OfficePlacement`): the next one out
in rings, or the one nearest its repository's other offices, a repository's first office going to an inner
slot clear of the others. Either way ties go to the earlier slot, so two machines with the same rooms
choose alike; whoever opens an office places it, and peers adopt the cells. `Fleet` arranges
stations and saves the layout (`fleet-v25.json`).

The hall is a value (`Hall.swift`), worked out from where the hallway's west arm ends: one room five cells
wide and eight deep, a walkway down one side, and three zones of crate rows, cleared, staged and storage,
each two rows of four tiles with its own grid, an aisle between each zone and the next. Decon lies behind
storage. Across the pad wall, past the pad field, is the pad, with the drone rack at its edge.

`World.swift` owns that floor plan and the diffs. `applyScan`, `applyGitHub`, `applyPeer` and `dropPeer` take
one fresh answer each, compare it with what was known, change the model, and hand back `WorldEvent`s
(`Events.swift`): an office opened or archived, a board column change, a pull request opened or closed, a peer
arriving. Counts in the yard are reconciled, not snapped: crates that reach QA are carried across by
minions (`stationEvents`, `carryToDeck`), and only what is not carried is redrawn (`reconcile`).

One thing the model cannot see for itself, whether an office has a package on its floor, the scene lends it
as a closure (`hasPackage`); whether a rocket is mid-load the simulation answers (`rocketBusy`).

Rules that keep the place steady:

- An update re-plans, it never resets. After the floor changes, `resettle` leaves settled minions alone and
  lets walkers keep their destination.
- The yard layout is drawn from the ledger's rows (`Station.layout(of:)`, `Yard.swift`): every crate keeps the place its row records,
  so a carrier is sent to the place its crate will occupy and nothing jumps when the layout redraws.
- A peer's office is adopted where the peer put it, with a dig to reach it if need be. When both machines
  placed the same room before hearing each other, the lower peer name's cells stand and the other side
  takes them, hallway dug under them given back, so a shared station converges within one round.
- Offices exist because of a checkout, a pushed branch, or a pull request. A closed issue never makes one,
  whatever column the board left it in. The board column only says how
  solid an office is. Unclaimed offices clear once their repository has answered; a peer's are held a day.
- A merged office that clears while its session lingers is retired for the day; the minion waits in the lounge.

## 3. Scene

`Scene.swift` renders the model and consumes events once each in `handle(_:)`, deciding the cue: a shuttle,
a haul, a fade, a log line. It reads state through `world` and never writes the model behind its back. The
tick moves minions along their paths and plays their poses. It never re-derives "what just happened" from raw
data. A rebuild is not immediate: `handle` marks the floor or the props dirty and `flushScene` redraws once,
after the caller has finished placing its workers.

Shapes mean things: a hexagon is a packed office, a cube is a piece of work, a square strapped crate is a pull
request, a pyramid is a session input. Nothing is round.

The station apart from the picture is `Simulation` (`Simulation.swift`, no SceneKit): the clock, the bodies
and the orders they run, the walks (`Walk.swift`), the rest, the idle life (`Idle.swift`), the hands, the
carries, deliveries, stows and packs (`Carries.swift`), the body reconciler (`Bodies.swift`), the order
board (`Board.swift`), the shuttles (`Shuttles.swift`), the rockets (`Rockets.swift`), the pad drones
(`Drones.swift`) and the vortex (`Vortex.swift`). It is generic over the body:
`Simulation<Minion>` in the app, `Simulation<Body>` under `--sim-tests`. A frame is three steps per body,
`stepWalk`, `stepThere` and `stepRest`, and a step each for the rockets, the shuttles, the rocket tips, the
vortices and the drones; the scene runs them and draws after. What the scene shows once, a flush, a fidget,
a hop, a landing, a reveal, a rocket's flame, is a `Cue` the simulation hands back and the scene plays at
the end of the frame. A body's pose is a fact on the body, lying, seated, on the bench, and so is its load: a
crate by number or an office's crate by key, with `landing` saying where it left the arms. The scene mirrors
that each frame (`mirrorLoad`): the node is lifted when the load appears, sent down its arc when the
set-down phase begins, and put where the landing says when the load goes; a crate under way is a `Cargo` on
the simulation and a node on the scene, by command id. A flight (`Flight`), a rocket (`RocketJob`), a pad
drone (`PadDrone`) and a vortex (`Vortex`) are the same shape: the simulation keeps where they are and what
they hold, the scene keeps a view per one (`ShuttleView`, `RocketView`, `DroneView`, `VortexView`) and places
it from those facts. Where the
fixtures stand is the station's (`Fixtures.swift`).

The scene is split by reason to change, all of it one `StationController` in extensions: `Scene.swift` holds the
shared helpers, every stored property, `buildScene`, the scan and event glue and the outer tick; `StationView.swift`
the input view and the camera it moves; `SceneStatic.swift` the floor, walls and the names written on it;
`SceneMarkers.swift` the crates, cones, the due rings, steam and power, and `restackYard`; `SceneTick.swift` the per-frame
worker loop and the demo clock, the load mirror, the cues and the pose; `Jobs.swift` the hauls the events
order, the crew, and the seam through which the scene asks the simulation for orders and walks by their old
names; `HUD.swift` the overlay; `Minion.swift` one worker's figure on its `Body`; `Actors.swift` the ship and
rocket nodes drawn from the simulation's flights and rockets; `DronesView.swift` and `VortexView.swift` the
drones and the vortex with the crates it pulls; `PadWall.swift` the pad field and the drone rack.

## Debts

- Every actor runs one `Command` at a time with a phase index (`Commands.swift`), so "what am I doing now"
  has a single owner: minions, the crew, the shuttles and the rockets alike. What is left outside it:
  `place`, `activity` and the wander timers still steer a worker's day.
- What is still on a timer is pure decoration, nothing the model can read: the steam emitter puffing off a
  loaded rocket, the flame and the twelve-second climb of a lift-off, the shower drops, the weld light, the
  ghost of an archived room sinking through the floor. None of it decides anything.
- `makeSnapshot` still lives in the scene, because what goes on the wire includes box counts and lit rooms
  that only the scene knows. The ingest side (`applyPeer`) is in the model, where compatibility matters most.
- Three decisions are still the scene's, and they are what keeps a scenario needing a `StationController`
  (TESTING.md, Change 4): the event glue in `Scene.handle`, the obstacles read off the props' boxes, and the
  stows ordered from inside the redraw.
- `Spot` carries a world position, so the scene's geometry leaks a little into the model side. Left alone
  on purpose: fixing it would touch every consumer of a spot for no change in behaviour.

## Where this is going

Agreed direction, in the order things flow. Not all of it exists yet.

1. **Sources** poll and cache, each on its own cadence: local git every few seconds, the board once a
   minute, feeds and PR lists with conditional requests so an unchanged answer costs nothing, per-branch
   detail batched and only for branches that exist here or moved in the feed. A push, a feed event, a
   peer's fresher answer or a conflict re-asks that one entity at once. Three setups feed the same facts:
   a project board, plain GitHub pull requests, or local git with tags and homemade release scripts.
2. **Facts** are one entity-keyed map: offices by branch key, crates by repository and number, peers by
   name. Sources write deltas; each field has an authority (the remote for a branch's existence, the PR
   for its state, the board for its stage, the scanner for who works here) and freshness decides between
   copies of the same authority. A weaker source fills a field the authority has not spoken on, never
   overrides it. Disagreement is not an event; it schedules a re-ask of the authority. This is the peer
   boundary too: what goes over the LAN is facts.
3. **Diffing** happens on write, per entity: old value, new value, zero or one event. No sweeps. A
   source's first answer, per slice, is quiet.
4. **World state** applies events and holds intent: this office exists and is solid, this crate belongs on
   the deck. It is what gets persisted.
5. **Reconciliation** compares intent with **station truth**, the second state: which crate is on which
   slot, which office is delivered, who carries what. It issues **commands** as values: carry crate 5210
   from storage slot 3 to deck slot 1, deliver office X by shuttle. A command has phases, each marked
   interruptible or not (walking yes, holding mid-lift no, setting down no), and a "must be true by" after
   which the reconciler lets the change appear in place rather than lag the world.
6. **Actors** execute commands over time: minions, shuttles, rockets, crates. Animations live here. A
   new command replaces the old one at the next interruptible phase; a command whose target vanished
   cancels itself and the actor sets down what it holds.
7. **Completions** write station truth only, never facts: "5210 landed", "office X connected". That is
   what keeps a source snap from undoing what a minion just did.

Steps 4 to 7 exist for crates, described in the next section. `Commands.swift` holds `Command` (a kind, a
phase list with each phase marked interruptible or not, and words for humans) and
`StationTruth` (offices ordered and their deliveries, whose crates wait in the bay). Where
each crate is, on both the source's side and the station's, is its row in the station's `Ledger`. The
station issues carries (`Yard.swift`: `carryToDeck`, `carryToTested`, `carryToStorage`, `carryFromDecon`),
the scene glue in `Jobs.swift` passes them to the simulation, the order board (`Board.swift`) hands each to
the nearest free body by rank, and the scene keeps the crate's node by command id for the arms. Bodies
execute one command at a time:
a new one replaces the old at the next interruptible phase, at most one waits, a carry can only be redirected
to another destination for the crate already on the arms, and a command whose target vanished sets down what
it holds where it stands.

Every crate that moves by hand goes through one lift and one set-down (`Hands` in `Simulation.swift`, the
constants with `startLift`/`lift` and `startSetDown`/`setDown`/`release`): an arm's length away and facing
it, a crouch whose posture comes from how high the crate stands, the crate up past the chest and onto the
arms, and out of the arms onto its slot turned the way the layout will draw it. The office delivery uses the
same pair, so a new office's crate is set down on the far cell its package will occupy and only then does
the office fade in round it. The arcs are crate motions on the station clock (`CrateMotion`) and so are the
phases, both derived from the same durations, so the posture and the motion cannot drift apart. A crate on the arms is
drawn once, in the hands: the yard it left leaves it out, and the yard it is bound for holds its place
without drawing it.

Shuttles, rockets and the crew run commands too (`Shuttles.swift`, `Rockets.swift`). A `Flight` flies one
`.flight` command — `bringWorker`, `takeWorker` or `dropCrate` — through approach, descend, unload, rise and leave. Each phase is one
`FlightLeg`: the waypoints of that leg, its seconds and its easing, sampled as a rounded-off curve, so an
`Arrival` and a `Departure` drawn per ship are the whole of how it flies. The ship's heading is the tangent
of that curve, which is what the scene turns it onto. The unload writes truth:
the worker steps out, or the office crate stands in the bay, which is what lets a carrier's `deliverOffice`
go from approach to lift. A `RocketJob`, one per station and repository, runs `.rocket` stages: stand by,
load, steam, launch. They move forward, except that a rocket not yet launching stands by again when it is no
longer cleared. `World.applyReleases` (`Releases.swift`) reads the launch queue and the open releases and
hands out those stages as commands — untested stands by, cleared loads and steams, merged launches — and
gives each rocket a pad slot (`assignPads`). A rocket told to stand by sends whatever the ledger had aboard
back to its rows (`Ledger.unload`). The launch opens a vortex (`Vortex.swift`): the three pad drones ring a
point outside the pad field, and the release's crates are pulled off their rows one at a time, up, across
and spiralling into the rocket's hatch, each landing on the pad in the ledger as it goes in. The rocket
climbs when the vortex closes; a rocket with nothing to pull climbs at once. A repository that ships on
merge launches a rocket each time a crate lands in storage (`launchOnMerge`). A teammate's reaction
to a push, a review, a comment or a branch is a `.react` command with its own until-time, so a crew minion
runs the same machine as everyone else and says so on hover.

The drones (`Drones.swift`) do the pad's other work. Two of them ferry the kick stage in under a production
rocket and away again. A rocket that arrives while its repository's staging deploy is not yet live stands
with its tip unplated, and a drone welds it panel by panel at the pace of that deploy's usual length
(`stepTips`).

Debugging: hovering a minion pauses it and shows its current command in words, and the same words go
in the log when the command is issued.

## Station truth against a source that runs behind

Steps 4, 5 and 7 above, for crates. Every crate a station knows is one row in one ledger (`Ledger.swift`,
kept on the `Station` and saved with it). The row has the source's side, `wanted`, the yard the board or
git history says it belongs to, with the source's own time for that word; and the station's side, `placed`,
the yard the station has it in, `at`, where it physically is (a slot or someone's arms), `slot`,
the place it holds in its yard, and `bound`, the place spoken for ahead of it while a carry is under way.
Sources write only through `adopt`; completions write only through `landed` and the set-down, and a carry
records its own landing when it sets the crate down. The counts the HUD, the rockets and the rings read are
read off `placed` and kept nowhere; `Station.layout(of:)` (`Yard.swift`) draws from the rows and gives a
place to any crate that has none. Each repository piles in its own band of columns, the same band in
storage and on the staging rows. Saved slots drawn under another `Ledger.slotScheme` are forgotten on load
and drawn again, and Develop > Restack the Yard does the same on demand (`restackYard`). `StationTruth` is
what is left besides: the offices ordered and their deliveries.

A word from the source is news for a crate only if it is newer than the station's own move of it
(`movedAt`). A board item carries when it last moved, so an answer older than a landing is stale for
that crate however fresh the poll, and a word older than the one already held (a peer's lagging copy)
is not news either. A source with no times of its own, git history, is believed again the moment it
agrees with what the station did. Nothing decides by the clock.

Disagreement is a queue, not an event. Storage to deck is carried: a crate's QA transition orders one
carry per crate, by the number the source named, with whatever stands on it and is staying moved aside
first (`stationEvents`, `carryToDeck`); a staging release that merges carries every storage crate of its
repository to the staged rows, board or no board (`stagingMerged`, `stageCargo`). `reconcile`
(`Releases.swift`) takes the source's answer into the ledger, then redraws the crates the two sides still
disagree about where the source says, once, and never a deck crate while a release is under way
(`releaseUnderway`). A crate already under way is left to its carrier. A storage-to-deck carry whose
crate the board has since put back is cancelled (`callOffCarriesTakenBack`): not lifted yet, the crate
stays; on the arms, it walks back. It runs from `flushScene` and after each GitHub answer, never from the
drawing, and `rebuildMarkers` adopts what stands: only what is new is built and what is gone taken away.

A carry names a yard, nothing more (`Command.carry(crate:from:to: Yard)`). The job holds the aim: a
place asked for when the order is taken, which the yard then holds for the crate (`bound`); asked for
again with the crate up on the arms, against the stack as it stands that moment; grounded at set-down,
when `bound` becomes `slot`. One aside routine serves every planner. A carry that stalls is given up by
the body reconciler and goes back in the queue from where the crate lies; nothing is ever set down by a
clock. A carrier with carries of its repository queued behind it hurries, and says so. A carry carries
its own rank (`Cargo.rank`), and the order board hands out the highest-ranked opening first: a carry onto
the cleared rows outranks one into storage.

`--ledger-tests` feeds a ledger facts in every order, board before release, release before board, stale
after fresh, A then B then A, and holds it to: every crate in one yard at most, a move outranking any
older word from the source, wanted equal to placed once the source has said something newer.

Station time is one value, `StationController.now`: the wall clock in the app, the simulated clock in a
simulator. Everything on the station that judges freshness against "now", a session's idleness, a peer's
snapshot, a landing's time in the ledger, reads it, and the simulator stamps its facts with it. A frame
that takes long, a route that searches the whole floor say, can therefore never age a session or make a
landing look older than a board move. The route search itself reads the hall, the doorways between areas
and the room doors from caches built once per floor plan.

## Faster feedback from GitHub

Step 1 above, the first part of it. Three things make the station notice sooner, and one keeps it
honest. The **board delta**: every twenty seconds one small search asks for the board's items updated
since the newest change it knows of, less a minute for the index, and merges them into the board it
holds (`refreshProjectDelta`). A board grows, Shipped most of all, and reading all of it was four pages
of a hundred; the delta is a handful of items, and the whole read is the backstop on the five-minute
cadence. The **feed as doorbell**: each repository's activity feed is asked once a minute, the pace
GitHub asks for, on a conditional request with the ETag it gave last time, so a quiet repository
answers 304 and costs nothing against the budget; what the feed has that it did not have last time
names what to ask about next. **Expecting a change** (`GitHubResolver.expect`): a key is asked every
few seconds instead of on its cadence for a while when something says it is about to change: a
pull request seen opened, merged or closed in the feed, its number and branch; a push, whose checks
will run; a merge, the releases; a board item that moved, its linked pull requests; a local signal
in a transcript, `gh pr create` or `gh pr merge` or `git push`, which re-asks the authority at once
and never moves anything itself; an open pull request with checks pending or an approval standing.
The setting "Ask GitHub every N minutes" still governs the slow cadence of the heavy asks.

`--github-diag [seconds]` runs the poller alone against the real settings and checkouts and prints
every ask and every answer that changed, which is how this was checked: the whole board once, the
delta every twenty seconds, feeds once a minute answering 304, the rest on the backstop. The
environment variable `RUMKAPSEL_SUPPORT` points a second copy of the app at its own save folder.
Not done from step 1: conditional requests for the pull request lists, one GraphQL for a repository's
open pull requests and releases together, and the events an org-level feed would carry, which this
token does not see.

## Staging releases

A staging release (a pull request into the staging branch) is a fact of its own: `ReleasePR.isStaging`
sits beside `isProduction`, and `applyStaging` (`Releases.swift`) diffs each repository's release list into
`.stagingOpened`, `.stagingMerged` and `.stagingClosed`. The first answer per repository is quiet.

The simulation keeps one `StagingBatch` per station and repository (`Staging.swift`): the release's number,
whether it merged, and how its staging deploy stands, unheard, running, live or failed. A merge carries every
crate of the repository standing in storage to the staged rows, one carry each, whatever the board says
(`stageCargo`). A close without merging forgets the batch and moves nothing. While a merged batch's deploy
is not yet live, a rocket that stands up for the repository is welded rather than whole, and the
repository is put first for a pad slot.

## Carries know the stack

Done. `Station.layout(of:)` hands out slots with a `column` — one square of floor, half a cell wide — and a
`level` counted from the floor, and `Spot` carries that level and the slot's yaw along with the
position. Storage jitter is seeded per crate rather than per place in the pile, so a crate keeps its
own nudge and turn wherever it lands.

- A crate is picked from the top of its stack, and every carry names its crate by number. Where a
  crate lower in a stack must move, storage to the deck or the untested row to the tested one, whatever
  stands on it and is staying is moved aside first, one carry each to a fresh column of its
  repository's in the same yard (`aside`), and the wanted crate's carry waits on them: a command lists
  the commands that must finish before it (`after`), and the scheduler holds it back until they are
  gone.
- A crate on a back row, with no floor beside it, is reached across the row in front. Where that row
  is taken the minion stands in the aisle beyond and floats the crate over, on the way up and on the
  way down alike (`tossFrom`, `Hall.backRow`).
- Pickup and set-down are height-aware. The minion stands an arm's length away, facing the stack, and
  the posture follows the height: level 0 a crouch, level 1 a lean at waist height, level 2 and up a
  reach with the head back. A crate off the floor comes up past the chest; one taken off a stack goes
  straight overhead.
- Set-down lands on the exact slot the layout will draw: position, level and yaw, so the redraw after
  landing changes nothing. `grounded` keeps stacks bottom-up — a slot with air under it drops to the
  lowest free level of its column, counting a crate already on someone's arms as gone.
- The office package is picked off the office floor the same way and lands on the repository's next
  free slot in storage, top of a stack or a new one.

Still owed, the set-down by level as Mads wants it: level 0, crouch and set it down carefully;
level 1, waist height, almost a slide forward onto the top; level 2, raise it above the head and slide it
in; higher, a little jump up, then slide it on. Pickup mirrors each. Today's lean and reach are the
placeholder. Also owed: one crate size everywhere, office, yard and in hand (the office crate no longer
grows with the work in it; the cubes show that), and no spin on release: the crate keeps its world
rotation when it leaves the hands and turns to the slot's yaw over the set-down. And a crate is heavy:
it stays in the hands all the way down to the slot, the posture does the lowering, release is the last
thing, and nothing moves it afterwards, neither an action nor the redraw. Pickup the same in reverse.

## Closed, not merged

Done. Two different closes:

- **An issue's pull request closed without merging.** The work goes nowhere: not storage, not the deck.
  The crate in its office turns red and sits there for ten minutes, then fades out. After that the office
  clears the way a merged one does: a teammate's archives, one's own retires while the session lingers.
- **A staging release closed without merging.** Those crates are still merged work waiting for a release,
  and nothing has moved them yet: they stay in storage, and `.stagingClosed` only forgets the batch.

## Bodies

`Bodies.swift` is to minions what the ledger is to crates. Every half second, for every command in
hand, it asks: is this body moving, or waiting on a fact the command named this tick
(`Minion.waitingOn`)? A rest that has arrived, a lie-down, an act with time left, QA walking its
rows and the airlock's cycle are steady by definition. Anything else that keeps the same phase and
the same spot for ten station seconds is given up: `giveUp` says so in the log, puts down what is on
the arms an arm's length ahead, and frees the body. A carry keeps its order and its id in `cargo`
with no carrier, starting from where the crate now lies, and whoever gave it up is passed over
while anyone else is free. A new office's crate goes back on the bay list, and `queueDeliveries`
hands it to the next free minion, the session's own worker first; a pending office with no crate,
no ship and nobody fetching has its shuttle ordered again. The scenario runner fails any run in
which a minion gives up unless the scenario says it means to provoke one.

Ownership is enforced at one door: `send(_:to:)` refuses a body with anything but rest in hand.
The refresh, the floor flush and the panel all go through it, so none of them can move a body on
paper under a job or a visit; a visit's own end finishes it first, then sends the body back.

