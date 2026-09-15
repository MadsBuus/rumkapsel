# Audit: commands and cues against STATION.md

Re-checked on 2026-09-15 against the simulation split: every row below is read against the code as it stands after `Simulation.swift`, `Carries.swift`, `Bodies.swift`, `Walk.swift`, `Idle.swift`, `Pallet.swift` and `Ships.swift` took over what `SceneTick.swift`, `Jobs.swift`, `Pallets.swift` and `SceneMarkers.swift` used to decide.

Read-only pass over `Commands.swift`, `Events.swift`, `Simulation.swift`, `Carries.swift`, `Bodies.swift`,
`Walk.swift`, `Idle.swift`, `Pallet.swift`, `Ships.swift`, `Body.swift`, `World.swift`, `Ledger.swift`,
`Station.swift`, `Scene.swift`, `Jobs.swift`, `SceneTick.swift`, `SceneMarkers.swift`, `SceneStatic.swift`,
`Pallets.swift`, `Actors.swift`, `CrateMotion.swift`, `Minion.swift`, `HUD.swift`, `Props.swift`,
`Invariants.swift`, `Scenarios.swift`, `Simulator.swift`.

A rule passes only where code enforces it. Where the rule holds because a duration happens to line up,
or because a comment says so, the verdict is partial. Evidence is cited by file and function or property,
not by line, since lines rot.

## Rules that apply to every command

These are checked once here and not repeated in every table below.

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| One thing at a time, with a name | pass | `Body.current` is one command; `Body.words` returns `current?.words`; `HUD.swift` puts `m.words` in the bubble on hover. | — |
| Every command issued goes to the log and the panel | pass | `Simulation.issue` calls `hooks?.onCommand`, writes the `command` line to `StationLog`, and `onLog` when announced. Every `begin`, every flight (`Ships.swift` `launch`) and every rocket stage (`take`) goes through it. | — |
| A change of orders is visible: a beat with the head up, cut short by a message | pass | `Simulation.begin` sets `wonderUntil` half a second ahead when a settled body's command changes kind, 0.15 s for `.work`; `stepWalk` returns `.wondering` and takes no step until it passes; `SceneTick.pose` tilts the head back for it. A redirected carry gets no beat, which is right. | — |
| An order is taken over only at an interruptible step | pass | `Simulation.start` is the one entry point and `begin` is private to it; `canInterrupt` reads `phaseKind.interruptible`, refuses a non-job over a job, and lets a haul take only a new destination for the same crate. `handOver` skips the check, but only for a command's own successor (the pallet's load to its wait). The scene's `Jobs.swift` `start`/`assign` are both the simulation's `start`. | — |
| A new order re-plans, it does not reset | pass | `Simulation.begin` keeps the load and jumps to `.haul` when redirected; `resettle` keeps settled and walking bodies; `replanBlockedWalks` and `replanDeliveries` re-route to the same destination when the floor changes. | — |
| Phases actually advance | pass | `Simulation.stepThere` advances `goTo`, `bath`, `exercise`, `chore`, `qa`, `sleep`, `work`, `react`, `leave`, `pack` and `stow` from `.walk` on arrival; `stepCrate` and `stepPallet` walk the carry, delivery and pallet phases; `Flight.advance` and `stepRockets` do the ships. `truth` no longer reports a settled body as walking. | — |
| Two never slide through each other; a walker drifts a third of a tile to its right, passes, and drifts back; nobody stops for anybody | partial | Standing bodies are solid to the planner: `Simulation.crowd` puts every body not on furniture into the grid, and `route` plans round them. In step, `Walk.step` never stops and never plans again, as the rule wants, but the body walks its line exactly: the `sidestep` of 0.16 is a shoulder, not a third of a tile, and it is drawing only (`Body.lean`, eased in `pose`). Two meeting where the planner found no side overlap for the length of the pass. `STATION.md`'s Rooms section still carries the older "never occupy the same spot, wait in a narrow place" bullet, which the Minions section replaced on 2026-09-15. | Move the drift onto the body's position in `Walk.step`, a third of a tile, and strike the stale Rooms bullet. |
| Right of way: one holds and the other goes round, a load before a job, a job before rest, names settle a tie | fail | Nothing holds and nothing ranks. `Walk.step` walks both through the pass; `Body.blockedBy` is kept for the log only. The rulebook's own Minions section says "nobody ever stops for anybody", which this rule in Bodies contradicts. | Settle the rulebook first; then either a hold with the ranking in `Walk.step`, or strike the Bodies bullet. |
| Speed by task: carrying is slow; a hurried carrier is quicker but still below a busy walk | pass | `Simulation.stepWalk`: hauling 1.1, hurried 1.7, hurrying to work 2.4, pacing 0.8, stroll 1.4, a forced stroll 1.0. `Body.isHauling` gives the carry, the delivery and the pallet errands the one loaded pace. | — |
| A stall is given up and said so; ten seconds standing on nothing named | pass | `Bodies.swift` `reconcileBodies` keeps a `stallMark` of command, phase, spot, path length and `waitingOn`; the same mark for `Patience.giveUpAfter` (10 s) calls `giveUp`, which logs why, puts the load down behind (`dropLoad`) and re-queues a carry from where the crate lies. `Scenarios.swift` fails any run with a " gives up " line unless the scenario allows it. | — |
| A wait on a named fact has its time, ninety seconds, except standing by a pallet | pass | `reconcileBodies` allows `Patience.waitLimit` (90 s) when `waitingOn` is set; `waitPallet`, QA, `leave`, a rest that has arrived, a lie-down and any timed phase are steady by definition. | — |
| Getting up from bed is slow, then quicker | partial | `Simulation.stepWalk` holds a lying body for 1.1 s (`wakeUntil`), then it walks at full speed. There is no slow first leg. | Ramp the speed over the first second after `wakeUntil` clears. |
| Nothing round | pass | `Scene.swift` `faceted` caps radial segments and every cylinder, cone and tube goes through it; `Invariants.swift` `scanShapes` flags a sphere or anything with more than eight sides. | — |

## carry

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| A crate moves only in hands | pass | `Carries.swift` `stepCrate` sets `m.load` in `.lift` and writes `world.pickedUp`; `SceneTick.mirrorLoad` lifts the node onto the figure when the load appears and nowhere else. | — |
| Never through a wall, crate, minion or furniture | partial | The walk is planned on the fine grid round the props (`Station.path`), round the other bodies (`Simulation.crowd`) and round the ground a ship holds; `replanBlockedWalks` re-plans when something lands in the way. The crate on the arms still has no footprint of its own. | Inflate the walker's clearance while carrying. |
| Arm's length and facing before taking hold | pass | `Simulation.atArmsLength` walks to `standCell` beside the spot, then shuffles to `Hands.arm` (0.34) facing it; the carry's `.approach`, the delivery and both set-downs go through it. | — |
| Lifting takes time and a posture | pass | `Simulation.startLift` sets `handsAt` from the crate's height and holds `phaseUntil` for `Hands.liftSeconds`; `liftDue` puts the load on the arms after the crouch; `Body.posture` maps the level to crouch, waist, reach or jump. One implementation for every crate move. | — |
| Setting down takes time and the right posture | partial | `Carries.swift` `startSetDown` sets `handsAt` to the slot's level and holds `Hands.setDownSeconds`; `SceneTick.setDown` draws three arcs, floor, waist and overhead. Level 3 and up share the overhead arc with a hop (`pose`, `.jump`), and levels 1 and 2 are a lean and a reach rather than the slide and the overhead slide the rulebook asks for. ARCHITECTURE.md lists this as owed. | Implement the four set-down postures separately. |
| The crate stays in the hands until it is on its slot | pass | `mirrorLoad` keeps the node a child of the figure until `putDown` sets `landing`; `release` reparents it exactly at the landing. Both arcs are `CrateMotion` legs on the station clock (`tickCrateMotions`). | — |
| Nothing moves it after set-down | pass | `release` pins the node at the aim and `world.setDown` writes the row; `rebuildMarkers` adopts a node by name and moves it only if its slot changed. No clock sets a crate down: the old patience deadline is gone and a stalled carry is given up by the body reconciler instead. | — |
| Taken from the top, built from the floor | pass | `World.carryToDeck`, `palletCargo` and `carryToPad` order by level, highest first; `aside` moves whatever stands above a wanted crate first; `World.grounded` drops a landing slot to the lowest free level of its column. | — |
| A lower crate taken: the ones above settle down one, slowly | pass | Levels rank by `Ledger.Slot.order` within the column (`yardLayout`); `rebuildMarkers` keeps the node and moves it down over `Hands.settleSeconds` (2 s), only downwards and only through vacated air (`vacated`). | — |
| A crate keeps its slot until it leaves | pass | The place is on the ledger row (`slot`), given at set-down or first draw and saved with the station; a crate bound for a yard holds a place ahead (`bound`, `setBound`). | — |
| Two never share a crate | pass | `Simulation.carry` calls `world.claim`; `yardLayout` marks carried crates and every planner filters `!carried`; `carryToTested` refuses a carried crate; `begin` stands a second body down if a carry already has a carrier. | — |
| Counts follow the source through hands | pass | The counts are read off the ledger's `placed`; `pickedUp` moves a crate onto the arms and `setDown` onto its slot, so storage and the deck are each one crate lighter or heavier exactly when the hands say so. `yardLayout` leaves carried crates out of the rows. | — |
| A carry nobody takes waits; a stalled carry goes back in the queue from where the crate lies | pass | `scheduleCarries` leaves a carry with no free body in `cargo` untouched; nothing sets it down by a deadline. `giveUp` re-queues it with `Command.from(spot)` from an arm's length behind the body, with the same id and the giver-up passed over (`gaveUp`). | — |
| A carrier with carries queued behind it hurries, and says so | pass | `scheduleCarries` sets `Cargo.hurry` when carries of the same repository wait, rewords the command with `reworded` and logs it once; `stepWalk` reads it for the pace. | — |
| A command whose target vanished sets down what it holds | pass | `stepCrate` calls `dropLoad` when the carry's `cargo` entry is gone; `cancelCarries` and `forget` free the carrier and drop the load. | — |

## deliverOffice

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| The crate exists before it is fetched | pass | `stepCrate` `.approach` waits on `order.landed` with `waitingOn` set; the flight's `onUnload` writes `truth.crateLanded`. | — |
| The shuttle leaves before anyone walks under it | partial | `Ships.swift` `shipStillOver` holds the carrier until `.rise` begins, and `crowd` keeps walks half a tile off the slot while the ship is down (`groundHeldByShips`). At the start of `.rise` the ship is still 0.55 over the slot and climbs for 2.5 s while the carrier walks in. An arriving worker steps out at the unload, `wakeUntil = clock + 8.1` (`arriveByShuttle`), a literal that matches the flight's approach, descent and `unloadAt`, and walks out from under a ship that lifts a second later. | Hold until `.leave`, or until the ship is above head height, and derive the arrival's hold from the flight's phase, not from 8.1. |
| Lift takes time and a posture | pass | `stepCrate` `.deliverOffice` stands an arm's length from the bay crate (`bayCrate`), then the shared `startLift`/`liftDue`, load on the arms after the crouch. | — |
| The crate stays in the hands until it is on its slot | pass | `officeCrateSlot` is the doorway tile just inside the plot; the crate walks there on the arms and goes down with the shared `startSetDown`/`putDown`. | — |
| Nothing appears or disappears without a cue | pass | `putDown` then `Cue.reveal`; `Jobs.swift` `reveal` folds the crate away and fades the tiles in from the doorway outward, then the name. | — |
| An office nobody can carry still shows up | partial | `Scene.flushDeliveries` calls `reveal` when no free minion is there for a peer's or the crew's office, which is now the unfold and a cue. `Scene.apply` still marks an office with no order and no ship delivered and lets `rebuildStatic` draw it with nothing but a `.fade` at best. | Route that last case through `reveal` too. |
| A delivery is picked up, period | pass | `Bodies.swift` `queueDeliveries` hands a landed crate nobody is fetching to the next free body, its own session first, whoever gave it up last; a pending office with no order and no ship has `startDelivery` called again; an order whose room is gone folds its crate where it lies (`Cue.foldCrate`). | — |
| A bay slot is free only when nothing lies on it and no ship is bound for it | pass | `StationTruth.freeSlots` reads the open delivery orders, which stand until `officeDelivered`; `startDelivery` takes the first free slot. | — |
| A renamed office keeps its delivery | pass | The order is the identity (`DeliveryOrder`); `StationTruth.renameOffice` moves the room key and `stepCrate` reads it every frame. | — |
| The office went away mid-carry | pass | `stepCrate` walks the crate to the corridor outside and sets it down when the slot is gone, else `loseLoad` and `reveal`; `cancelCarries` frees carriers into the room. | — |

## goTo

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Somewhere to be, with words | pass | `Command.rest`; words from `Place.words`. | — |
| Two never share a couch or a bed | pass | `Simulation.send` picks an unused bed or couch and gives up a seat someone else holds. | — |
| Walks round things | partial | `Simulation.route` plans round props and bodies, then without the bodies, and `Station.path` falls back to the coarse grid. `send` still sets a straight line to the target when no path is found and the target is far, through whatever stands between. | Stand still, or take the coarse path only. |
| Nobody settles in a doorway | pass | `send` filters the room's `doorCell` out of the targets; the wander in `stepThere` does the same. | — |
| Re-plan, not reset, when the floor changes | pass | `resettle` keeps settled and walking bodies; `replanBlockedWalks` re-routes only a path that now crosses an obstacle, at most once a second. | — |
| Rules of the day | pass | `restPlace` and `Place.forActivity` with `isNight`. | — |

## bath

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| A visit lasts its whole time; nobody wanders off mid-shower | pass | `bath` has phases `[.walk, .act]` and `.act` is not interruptible, so `start` parks a new order in `pending`; `stepThere` ends the visit only at `clock >= phaseUntil && settled`, the old `\|\| m.busy` escape is gone; `finish` then begins whatever waited. `send` refuses a body with a visit in hand. | — |
| A visit's time starts on arrival, not when it sets off | pass | `begin` copies `visitSeconds` into `actFor`; `stepThere` sets `phaseUntil` and `actStartedAt` when the walk ends; `visitLog` records lasted against planned under `--sim-tests`. | — |
| Ten seconds of water, pixels where they belong | partial | Drops fall from the nozzle for the whole visit (`SceneTick.pose`) and `setStatic` covers the body. `visitBath` gives a shower two to three minutes and the bowl one, where the rulebook says ten seconds. The two numbers disagree; the code is consistent with itself. | Pick one number and put it in both places. |
| Two never share a shower or a bowl | pass | `visitBath` reads every other bather's `fixture` and takes the free one, the other kind if its first choice is held, or returns false; `fixture` is cleared when the visit ends or is given up. | — |
| A pee is a sit: turn, down, a shuffle now and then, up as the time runs out, the bowl flushes | pass | `stepThere` seats the body square on the bowl (`seated`, `seatOffset`), cues `fidget` every few seconds, stands it 0.7 s before the end and cues `flush`. | — |
| A shower after long work, a pee after short | pass | `stepThere`: a stretch over twenty minutes owes a shower, over three minutes every second stretch owes a pee (`shortStretches`). The delay is random, the rule is not. | — |
| Back to where it was after | pass | `stepThere` reads `back` out of the command and `finish(m, to: back)` is one order, not a rest and then another. | — |

## chore

The roam, the gym turn and the book are the idle picks; they are checked here together.

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| One idle clock per lounger, two to five minutes, kept while away, dropped by work | pass | `Idle.swift` `IdleClock` arms on the couch, holds while away, disarms on busy; `stepThere` ticks it only for a settled lounger with nothing to do. `--idle-tests`. | — |
| When it runs out one thing is picked: a look round most often, the gym by day, the bath, or a book | pass | `IdlePick.pick` by weight, gym only by day and never for the crew; `pickIdle` falls back to a roam when the pick has nowhere to go. | — |
| Chores when bored, then back to the couch | pass | `startRoam` issues `.chore` with a time; `stepThere` calls `finish(m, to: .lounge)` when it runs out. | — |
| Idle drift toward a loaded rocket | pass | `startRoam` takes the pad-side deck row when a rocket is steaming or launching, and `RoamSpots.choose` allows company there. | — |
| Roamers keep apart | pass | `RoamSpots.choose` filters spots within three tiles of anyone standing or headed there, unless company is fine. | — |
| A chore never stands in a doorway | pass | `startRoam` filters the yard doorways and every room's `doorOutside` out of the clear spots, and never the bay. | — |
| A turn in the gym on a free fixture, one to each, lasting its whole time | pass | `freeGymFixture` reads other bodies' `workout`; `takeTurnInGym` issues `.exercise` with a time and walks to `gymStand`; `stepThere` ends it on the clock and sends the body back where it came from. | — |
| Idle time, never work | pass | `chore` and `exercise` are not `isJob` and leave `busy` false. | — |
| Where it goes is a cue | partial | `RoamSpots.choose` picks at random among the clear spots: random decides where, though not whether. Flavour, but the destination carries no meaning. | Prefer spots with something to look at. |

## qa

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Paces the rows like a foreman | pass | `stepThere` steps stack by stack along the untested row, faces each, hops when impatient (`Cue.hop`); `pose` sweeps the scanner and ticks. | — |
| Arm's length and facing | pass | `stepThere` stands in the aisle cell beside the stack and faces it. | — |
| QA is work, not idle | pass | `Jobs.swift` `assignTester` sets `busy` and issues `.qa` with words. | — |
| Ends when there is nothing to test | pass | `assignTester` sends the walker to the lounge when the deck is clear or a rocket is steaming. | — |
| One QA walker | pass | `assignTester` checks for a current one first. | — |

## leave

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Leave through the airlock | pass | `Simulation.dismiss` paths to a hatch's inside cell, then out through the hatch to the bay. | — |
| Gone only with a cue | pass | `stepThere` `.leaving` fades the body at 1.2 a second before it goes. | — |
| The hatch it uses | partial | `dismiss` picks `airlockHatches.randomElement()`; random picks the door, harmless. | — |
| Anything on the arms goes down | pass | `Carries.swift` `forget` drops the load and frees the carries; `despawn` calls it. | — |
| A leaver waits inside for the cycle before stepping out | partial | `.leave` is `[.walk, .stepOut]` and the phase advances, but not where meant: the path runs straight through the inner cell to the bay, `stepThere` only runs with an empty path, and the general arrival advance fires first, so the `.leaving` branch that would advance at `airlockInner` and hold `wonderUntil` for the cycle is never reached. The body advances on the bay and fades there, with no wait inside. | Break the path at the inner cell so the walk ends there, advance and hold the cycle, then walk on. |

## sleep

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Sleep in the dorm by night | pass | `Command.rest`; `restPlace` with `isNight`. | — |
| Two never share a bed | pass | `send` reserves a bed, with the lounge as the overflow. | — |
| Getting up is slow | partial | `stepWalk` holds 1.1 s, then full speed. | Ramp the first leg. |
| The bunk's own height | pass | `pose` lifts the body 0.36 onto an upper bunk. | — |

## work

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Work at the office, with words | pass | `Command.rest` gives `.work`; `Jobs.swift` `addPyramid` names the message being worked. | — |
| A routine per activity | pass | `SceneTick.pose` gives each activity its own pose and tool. | — |
| Stands at the cone, facing it | pass | `pose` places up to three workers round the cone at 0.4 and faces each to it. | — |
| Cones land on clear floor, nearest the door | pass | `coneCells` filters crated and written cells and sorts by distance to the door; `addPyramid` takes the first, queued ones the next in the row. No random. | — |
| A commit's cube is carried in under a command | pass | `rebuildMarkers` hands the newest cube to a worker in the room and issues `.stow`, phases `[.walk, .act]`, words and a crouch (`Body.posture`); `stepCrate` times it and cues `stow`, which lowers the cube onto the box's own place and hands over. | — |
| The cube lands where the box goes | pass | `Cue.stow` moves the cube to the box's position on the clock; the box takes over at full opacity as it lands. | — |
| A pull request just opened is packed by the worker, cones cleared first | pass | `Scene.handle(.pullRequestOpened)` hides the package, clears the cones and issues `.pack`; `stepCrate` kneels over it and cues `packed`, which grows the crate on its slot. | — |

## react

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| A teammate does one named thing until its time | pass | `Simulation.react` issues `.react` with words and minutes; `stepThere` sets `phaseUntil` on arrival and `crewRested` at the end. | — |
| Only for news, never history | pass | `Events.swift` `ready`; `playCrew` logs only when the repository has answered before. | — |
| A reaction never cuts a job | pass | `playCrew` and `.pullRequestClosed` guard on `!m.onJob`. | — |
| Back to the quarters after | pass | `crewRested` clears the cones and sends the body to the quarters. | — |
| Walk phase advances properly | pass | `stepThere` `.react` case. | — |

## flight (shuttle)

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| A shuttle lands only in the bay | pass | `arriveByShuttle` and `startDelivery` use `hangarSlots` off the hangar anchor only. | — |
| It leaves before anyone walks under | partial | As in `deliverOffice`: the hold ends at the start of `.rise`, and the arriving worker's hold is a literal 8.1 s that must match the flight's phases. | Hold until `.leave`; derive the hold from the phase. |
| Phases run on the command, on the station clock | pass | `Flight.advance` steps the phases on `until`; `Flight.place` interpolates the position from `startedAt` and the phase's duration; `Actors.swift` `drawShuttles` only places the node. No `SCNAction`. | — |
| The cargo appears only on the unload cue | pass | `startDelivery`'s `onUnload` writes `crateLanded` and cues `crateDropped`; `Flight.ready` holds the ship over the slot until the carrier stands there. | — |
| Where it comes from and goes | partial | `skyCorner` and the resting yaw and drift are random; flavour only. | — |

## rocket

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Stages only move forward | pass | `Simulation.rocket` refuses a stage with a lower `rank`; `RocketStage.rank`. | — |
| A rocket leaves only with its cargo aboard | pass | `loadCrates` remembers every crate ordered aboard (`assigned`, `pending`); `stepRockets` advances only when `padClear`, `pending` is empty and the ledger counts them all aboard. A release with no cargo goes at once. No timer decides it. | — |
| Loading is done by hand, from the top down | pass | `loadCrates` issues `World.carryToPad`, ordered by level, highest first, chained with `after`. | — |
| Loaded at its foot: an arm's length off the hull, on the hatch | pass | `World.padSpot` puts the slot a tile before the hull and the carrier on the tile before that; the set-down is the shared one. | — |
| Crates go into the hold through the hatch, shrinking | pass | `Cue.intoHold` on set-down: the hatch opens, the crate lifts and shrinks into the hull (`Actors.swift` `play(rocket:)`); `clearPad` at the climb. The rulebook now describes exactly this. | — |
| Steam means loaded and waiting | pass | `beginRocketPhase` cues `steam` on the steam stage only. | — |
| A hold ring means untested | pass | `rocketNode` adds it for `untested`; `Cue.rocketLoading` takes it down. | — |
| The prop is only redrawn when standing by | pass | `drawRockets` returns once `rank > 0` or while actions run. | — |
| Nothing on a timer decides anything | pass | The 15 s climb (`RocketJob.until`) runs after `clearPad`; the lift-off action is decoration over a pad truth has cleared. | — |
| A first answer is not news | pass | `World.applyReleases` seeds `announcedReleases` on the first answer per root (`releasesSeen`); the rocket stands, nothing is said. | — |
| A repository that ships on merge goes straight up in a small rocket | pass | `launchOnMerge` issues `.launch` with `tall: false` once the crate lands in storage; `stepRockets` launches the next merge after the climb; `forgetShipped` strikes the rows since no source will. | — |

## dispatch

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Clipboard out, to the console, with words | pass | `Pallet.swift` `servicePallets`; `Command.dispatch`; `Pallets.swift` `errandTool`. | — |
| One errand per repository | pass | `servicePallets` skips a repository somebody is already on (`palletErrand`). | — |
| It stands at the console, facing it | pass | `faceConsole` uses the console's own facing. | — |
| The console blinks while an order stands | pass | `drawPallets` flashes the panel while `palletQueue` is non-empty. | — |
| Nobody free: the crates stand still | partial | `servicePallets` breaks out; `World.reconcile` returns `.waiting` for that repository until the pallet is out and emptied. Known and written down in ARCHITECTURE.md. | Time the wish out and fall back to hand carries. |
| The dispatcher is chosen, not drawn | pass | `servicePallets` takes the nearest free worker, never the crew, QA or a subagent. | — |

## loadPallet

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| A crate may move by the wand while loading a pallet | pass | `loadOne` puts a `PalletJob.Flight` in the air; `drawPallets` lights the wand while one flies (`setWand`). | — |
| One crate at a time, off the top of its stack | pass | `loadOne` takes one every 3 s; `World.palletCargo` orders by level, highest first, and skips carried crates. | — |
| The crate in the air rides the station clock | pass | `PalletJob.Flight.position(at:)`, read by `stepPallets` for the landing and by `drawPallets` for the picture. | — |
| Never through a wall or another crate | fail | The arc is an eased line with a 0.7 hop (`Flight.position`); nothing checks what stands between the stack and the slot. | Route the arc over the tallest thing between, or check the line. |
| Counts follow the hands | pass | `loadOne` calls `world.putOnPallet` as the crate leaves the ground, so the row says pallet the moment it is off the stack, and `Cue.palletLift` redraws the rows one crate lighter. | — |
| Nothing else moves those crates | pass | `World.reconcile` returns `.waiting` from the moment a pallet is queued; `yardLayout` keeps pallet crates out of the rows. | — |
| Nothing in storage for that repository | pass | `beginPallet` ends the pallet at once and clears the wish. | — |

## waitPallet

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Standing by, with words | pass | `stepPallet` `.waitPallet`; `Command.waitPallet` carries its words. | — |
| Standing by a pallet is the errand and exempt from the stall | pass | `stepPallet` sets `waitingOn` to the command's words; `reconcileBodies` treats `waitPallet` as steady. | — |
| The dispatcher gets impatient | pass | `impatient`: a hop or a step along the wall, every 5 to 9 s. | — |
| A release that moved while it waited | pass | `stepPallet` reads `wantsPush`/`wantsBack` as soon as the pallet exists; `beginPallet` takes the wish left in `palletWishes`. | — |
| It waits beside the pallet, not through it | pass | The pallet's footprint is in `obstacles` (`refreshObstacles`), and `adopt` walks to `standCell` beside it. | — |
| The wait is idle, not work | partial | `waitPallet` is `isJob`, so the waiter is never handed a carry even while it only fidgets at the console. | Let a dispatcher waiting at the console take a carry and come back. |

## pushPallet

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Pushed from behind | pass | `pushSpot` puts the pusher squarely behind on the leg's axis; `stepPallets` locks it a step behind while moving. | — |
| One axis at a time | pass | `palletRoute` builds axis-aligned legs; `pushSpot` snaps the direction to one axis. | — |
| Slowly, easing in | pass | `stepPallets`: 0.45 a second with a one-second ramp. | — |
| Only where a pallet fits | pass | `clampToYard` keeps the whole footprint on the block's tiles; every leg end goes through it. | — |
| Never through a crate or a minion | fail | Nothing checks the swept footprint. The route aims at the aisle, clear by convention, but a body standing there is run over. | Check the swept rectangle against obstacles and bodies and hold the leg while it is blocked. |
| Round the back at every corner | pass | `stepPallet` resets the phase and walks round to the next leg's `pushSpot`. | — |
| The push has a posture | pass | `drawPusher`: a 0.35 lean plus a small shove. | — |
| One owner of the pusher's body | pass | `stepPallets` writes the pusher's `pos`, `path` and `facing`; `drawPusher` only draws. `stepPallet` returns `.spent` so `pose` does not draw it twice. | — |

## unloadPallet

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Crates float off one at a time | pass | `unloadOne`, one per 3 s, on the station clock. | — |
| Onto their slots, or back onto their stacks | pass | `unloadOne` orders each crate to its yard and asks `World.slotNow` for the place, grounded against the stack as it stands. | — |
| A closed release puts them back | pass | `palletClosed` sets `wantsBack`; `unloadOne` aims at storage and `land` writes `setDown` and `landed` there. | — |
| The empty pallet leaves with a cue | pass | `drawPallets` fades slab and shadow over 0.9 s once the simulation drops the job. | — |
| A pallet caught half way | pass | `adopt` sets the truth to unloading and hands whoever is free `.unloadPallet` where it stands. | — |
| Never through a wall or a crate | fail | Same arc as the load. | Same fix. |
| Deck counts follow the hands | pass | `land` writes `world.setDown` and `landed` as the crate comes down. | — |

## The event cues in `handle(_:)`

| Path | Verdict | Evidence | Fix |
|---|---|---|---|
| `.worldLoaded` | pass | `Scene.handle` does nothing: the first answer is not news. | — |
| `.log`, `.chime` | pass | `logEvent`; `ringBell` rate-limits to 4 a second. | — |
| `.layoutChanged` / `.markersChanged` | pass | Only mark dirty; `flushScene` redraws once, after the caller has placed its workers. | — |
| `.officeOpened` with `.shuttle` | pass | Records the pending office and queues the delivery by source. | — |
| `.officeOpened` with `.appear` | partial | Nothing happens, the office is simply there. Used on the first run (`World.applyScan`), the right exception, but the case would swallow a later `.appear`. | Assert that `.appear` only reaches here on the first run. |
| `.officeOpened` with `.fade` | pass | Recorded in `fadeIn` for the fade-in. | — |
| `.officeRenamed` | pass | Moves truth, outlines, boxes and the minion's place; a delivery under way follows by its order. | — |
| `.officeArchived` | pass | `Jobs.swift` `archive`: carries cancelled, boxes shrunk, the name first, tiles rolled up toward the door into a hex that drops through the floor, occupants walked out. | — |
| `.officeMerged` | pass | `haulMergedBoxes` builds the carry `from` the package's own position (`Command.from(exact)`), so the carrier walks to the crate, not the door. | — |
| `.carryToDeck` | pass | `stageCargo` hands each command a node; the job asks for its aim and the landing writes the ledger. | — |
| `.crateCleared` | pass | `carryAcrossDeck` into `carryToTested`, which moves what is stacked above first. | — |
| `.deconArrived` | pass | `hatchBlink` and `incoming`: the object is drawn at hatch height and floats down onto its pile. No shuttle, no airlock. | — |
| `.deconCleared` | pass | `haulCleared` carries the object from where it stands into storage (`carryFromDecon`, no aside, whatever was on top drops together in `rebuildMarkers`); one never drawn is put down in storage by the rows. | — |
| `.crewRoster` | pass | `setCrewRoster` adds and removes crew minions. | — |
| `.crewActivity` | pass | `playCrew`: one `react` per kind, never while on a job. | — |
| `.stagingOpened` | pass | `orderPallet` queues the pallet and says so. | — |
| `.stagingMerged` / `.stagingClosed` | pass | `palletMerged`/`palletClosed`: a wish on the pallet if it is out, remembered otherwise. | — |
| `.releaseOpened` / production `.releaseMerged` | pass | Deliberately nothing: the rocket command is the cue. | — |
| non-production `.releaseMerged` | partial | Calls `stageCargo` directly when there is no board and no pallet. A second, older way of moving the same crates. | Route it through the reconciler. |
| `.rocketCommand` | pass | `simulation.rocket`: a new job, or a forward-only stage. | — |
| `.prompt` | pass | `promptLanded`: one cone per message, a queued cone lit as it is picked up. | — |
| `.crewHidden` | partial | Despawns crew minions at once, no fade, no airlock. | Send them out through the airlock. |
| `.boardMoved` | pass | Logs, hands the cleared case to `.crateCleared`, leaves the deck case to the reconciler. | — |
| `.pullRequestOpened` / `.issueStarted` | pass | Log lines; my own office's worker packs the crate under a `.pack` command. | — |
| `.pullRequestClosed` | pass | A `react` when the author is around and free. | — |
| `.peerArrived` / `.peerLeft` | pass | Log lines; the offices are held by the model. | — |

## The yard reconciliation

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Carried, not snapped, wherever a haul can carry it | pass | `World.reconcile` adopts the word into the ledger, then walks the disagreements by number: storage to deck is `carryToDeck`, blockers aside first; the rest is snapped. | — |
| A crate under way is left to its carrier | pass | `Ledger.snap` refuses a crate with a `heading`; `yardLayout` and every planner filter carried crates. | — |
| A pallet is the hand carry for its repository | pass | `reconcile` returns `.waiting` from the moment a pallet is queued until it is gone. | — |
| Redrawn only if nobody is holding it | pass | `snap` skips a heading crate; `yardLayout` draws carried crates nowhere but leaves their place held. | — |
| A launch is not undone by a snap | pass | `reconcile` skips deck crates while `rocketBusy`, a launch is pending or a production release is open. | — |
| The layout is a pure function of the rows | pass | `yardLayout` draws from the ledger's rows and their held slots, so nothing jumps between redraws. | — |
| Storage unorganised, the deck ordered | pass | `yardLayout`: `neat` off for storage, `jitter` seeded per crate from `stableHash`. | — |
| A first answer is quiet | pass | `readyRepos`, `stagingSeen`, `releasesSeen`, `sessionPrompts`. | — |
| The board changed its mind mid-carry | pass | `reconcileYards` cancels a storage-to-deck carry whose row went back to storage; `cancelCarry` walks a lifted crate back and leaves an unlifted one standing. | — |
| Reconciliation runs from the tick, not the redraw | pass | `Scene.reconcileYards` runs from `flushScene` and the half-second beat in `stepStation`; `rebuildMarkers` adopts what stands and decides nothing about the yard. The one order still issued from inside the redraw is the `.stow` for a fresh commit's cube, which ARCHITECTURE.md lists as a debt. | — |

## Cross-cutting findings

**The same rule implemented twice, differently.**

- ~~Two lift and set-down implementations~~: one each now, `startLift`/`liftDue` and
  `startSetDown`/`putDown` in the simulation, with the arcs the scene draws and the phases the
  simulation times both derived from `Hands`, so they cannot drift.
- ~~Two ways a crate moves through the air, one on actions~~: the hands' arcs are `CrateMotion` legs and
  the pallet's flight is `PalletJob.Flight`, both on the station clock.
- Two ways crates reach the deck: `stageCargo` from the reconciler (`.carryToDeck`) and `stageCargo`
  called straight off a non-production `.releaseMerged` when there is no board and no pallet.
- Two obstacle sources: `refreshObstacles` builds the set from marker nodes, furniture, cones, rockets and
  pallets, and `Simulation.crowd` adds the bodies; `send` still has a straight-line fallback that
  ignores all of it when no path is found.
- ~~Two places place a minion's body~~: the simulation owns every body's position, the pusher's included
  (`stepPallets`); `drawPusher` and `pose` only draw.
- ~~Two carried-crate filters~~: one, in `yardLayout`.

**State outside station truth that belongs in it.**

- ~~`Pallet` the actor duplicates `StationTruth.Pallet`~~: `PalletJob` reads and writes the truth's state
  and keeps only what is in the air or being shoved.
- ~~`station.stored` / `station.staged` written from five places~~: the counts are read off the ledger's
  `placed`; sources write through `adopt`, completions through `pickedUp`, `setDown` and `landed`.
- `haulingRooms`, `boxes`, `outlines`, `lastBoxCount`, `fadingProps`, `roomPower`, `packing` are scene
  dictionaries that decide what is drawn and, for `boxes` and `packing`, what may be carried or packed.
- A body's `place`, `activity`, `bathDue`, `busySince`, `shortStretches`, `qaStop`, `handsAt`, `fetchSpot`
  and the wander timers are the day's actual state, on the `Body` and not in truth. ARCHITECTURE.md names
  `place`, `activity` and the wander timers as the debt.
- ~~`Rocket.since`, `Rocket.cargoShown` and `Shuttle.phase` as actor-local copies~~: `RocketJob` and
  `Flight` are the simulation's; `RocketView.cargoShown` only says what the node was drawn for.
- The stow for a fresh commit's cube is ordered from inside `rebuildMarkers`, and the `landed` of a
  carry is written by the scene's landing closures. Both named in ARCHITECTURE.md's debts.

**Timers and `SCNAction`s still deciding.**

- ~~The 90 s rocket load timeout~~: the load ends on station truth alone.
- `wakeUntil = clock + 8.1` (`arriveByShuttle`) decides when an arriving worker becomes visible, a
  number that must match the flight's approach, descent and `unloadAt`. The unload closure clears it
  too, so the two agree today by construction rather than by reading the phase.
- ~~A carry's patience per leg~~: gone. Nothing sets a crate down by a clock; a stalled carry is given
  up by `reconcileBodies` and re-queued.
- ~~The shuttle's whole path is `SCNAction`s~~: `Flight.place` interpolates on the station clock.
- ~~The carry's arcs are `SCNAction`s~~: `CrateMotion`, ticked from `stepStation`.
- Decoration that decides nothing, correctly: steam, the lift-off climb, the shower drops, the weld
  light, the archived ghost, the console blink, the hop cue, the cone's rise and shrink.

**`random` deciding behaviour rather than flavour.**

- ~~`Bool.random()` decides whether a short work stretch earns a bath~~: every second short stretch does
  (`shortStretches`).
- `Bool.random()` decides whether an impatient dispatcher paces or hops (`impatient`): flavour, but it
  is the routine, not the look.
- ~~`addPyramid` places a cone at random~~: the cell nearest the door, queued ones behind it.
- `pickIdle` rolls the idle pick by weight and the shower against the bowl; the weights are the rule
  (`IdlePick`), the roll is the flavour.
- `skyCorner`, the office ship's resting yaw and drift, `dismiss`'s hatch, the roam spot among the clear
  ones, the wander cell and every delay range: flavour.

## Fix list, most visible first

1. ~~**Make a change of orders visible.**~~ Done: `wonderUntil` in `Simulation.begin`, held in `stepWalk`,
   cut to 0.15 s for a message.
2. ~~**Fix the carrying speed.**~~ Done: hauling is 1.1, below the 1.4 stroll (`stepWalk`).
3. ~~**Let stacks settle instead of blinking.**~~ Done: a crate whose level dropped is moved down over
   `Hands.settleSeconds` (`rebuildMarkers`).
4. ~~**Give `deliverOffice` a real lift and set-down.**~~ Done: the shared lift and set-down, onto the
   doorway tile, before the reveal.
5. ~~**Stop drawing carried storage crates twice.**~~ Done: `yardLayout` leaves them out.
6. ~~**Do not launch without cargo.**~~ Done: the load ends when everything ordered aboard is on the pad.
7. ~~**Let a visit last its whole time.**~~ Done: `bath` and `exercise` are `[.walk, .act]`, `.act` is not
   interruptible, and the `\|\| m.busy` escape is gone.
8. ~~**Reserve the shower and the bowl.**~~ Done: `visitBath` reads the other bathers' `fixture`.
9. **Make the pass the rulebook's.** Bodies are solid to the planner now (`crowd`), but the drift past
   someone is a shoulder in the drawing, not a third of a tile on the body (`Walk.step`), and the
   Bodies section's right of way has no implementation and contradicts the Minions section. Settle the
   text, then the code.
10. **Stop pushing pallets and floating crates through things.** Check the pallet's swept footprint
    (`stepPallets`) and the wand arc's line (`PalletJob.Flight`).
11. ~~**One entry point for orders.**~~ Done: `Simulation.start`, with `begin` private.
12. ~~**Advance the phases of the quiet commands.**~~ Done: `stepThere`.
13. ~~**Move the carry's arcs and the shuttle's flight onto the station clock**~~ Done: `CrateMotion` and
    `Flight.place`.
14. ~~**Give the commit-box carry a command**~~ Done: `stow`, and `pack` for a pull request just opened.
15. ~~**Take the reconciler out of the redraw**~~ Done: `reconcileYards` from `flushScene` and the tick;
    the ledger holds every crate.
16. ~~**Quiet the first release answer**~~ Done: `releasesSeen`.
17. ~~**Take the randomness out of the routines**~~ Done: every second short stretch earns a pee, and the
    cone lands nearest the door.
18. **Let the shuttle clear before anyone walks under it.** Hold `shipStillOver` until `.leave`, and derive
    the arriving worker's hold from the flight's phase rather than 8.1 (`arriveByShuttle`).
19. **Give the leaver its airlock cycle.** The `.leaving` branch in `stepThere` that holds inside is
    unreachable because the path runs straight through the inner cell (`dismiss`).
20. **The four set-down postures by level** (`SceneTick.setDown`, `Body.posture`), still owed in
    ARCHITECTURE.md.
21. **Small ones, in one pass**: a ramp after `wakeUntil`; the crate's footprint while carrying; the
    straight-line fallback in `send`; `.appear` asserted first-run only; the non-production
    `.releaseMerged` through the reconciler; `.crewHidden` through the airlock; a dispatcher with nobody
    free falling back to hand carries; a console-waiting dispatcher free to take a carry; the shower's
    length agreed between `visitBath` and the rulebook; the stale Rooms bullet struck from STATION.md.
