# Audit: commands and cues against STATION.md

Read-only pass over `Commands.swift`, `Events.swift`, `Actors.swift`, `World.swift`, `Station.swift`,
`Scene.swift`, `Jobs.swift`, `SceneTick.swift`, `SceneMarkers.swift`, `SceneStatic.swift`,
`Pallets.swift`, `Minion.swift`, `HUD.swift`, `Props.swift`, `Simulator.swift`.

A rule passes only where code enforces it. Where the rule holds because a duration happens to line up,
or because a comment says so, the verdict is partial. Line numbers are from this worktree.

## Rules that apply to every command

These are checked once here and not repeated in every table below.

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| One thing at a time, with a name | pass | `Minion.current` is one command; `Minion.swift:191` returns `current?.words`; `HUD.swift:53` shows it on hover. | — |
| Every command issued goes to the log and the panel | pass | `Jobs.swift:62` `issue` calls `sim?.onCommand` and `logEvent`. | — |
| A change of orders is visible: a beat with the head up, cut short by a message | fail | No such state exists. `Jobs.swift:67-78` `start` sets the command and walks in the same frame; grep finds no beat, pause or hesitation anywhere. | Add a `wonderUntil` on the actor, set in `start` when a command replaces another, held in `tickMinions` before the walk, and skipped for `.prompt`-driven commands. |
| An order is taken over only at an interruptible step | partial | `Jobs.swift:44-58` `assign`/`canInterrupt` do it right, but only `scheduleCarries` (`Jobs.swift:504`) and `startDelivery` (`Jobs.swift:300`) go through `assign`. `send` (`Jobs.swift:184`), `servicePallets` (`Pallets.swift:41`), `react` (`Jobs.swift:579`), `assignTester` (`Jobs.swift:613`), `addPyramid` (`Jobs.swift:392`) and `adopt` (`Pallets.swift:395-401`) call `start` directly. They are guarded by `!onJob`, not by the phase. | Make `start` private to `assign` and route every caller through it. |
| A new order re-plans, it does not reset | partial | `Jobs.swift:70-77` keeps the crate and jumps to `.haul` when redirected; `Jobs.swift:138-152` `resettle` keeps walkers' destinations. Any `start` that bypasses `assign` resets `phase` to 0 (`Jobs.swift:72`). | Same fix: one entry point. |
| Phases actually advance | partial | Only `carry`, `deliverOffice`, `react` and the pallet commands advance (`SceneTick.swift:142-294`, `Pallets.swift:68-151`). `goTo`, `bath`, `chore`, `qa`, `sleep`, `work`, `leave` fall into `default: break` (`SceneTick.swift:295-296`), so `truth.jobs` reports phase 0 (`.walk`) forever, even settled. | Advance `.walk` to `.settle` for these in the tick, as the pallet commands do. |
| Minions never occupy the same spot; they wait in a narrow place | fail | `Station.obstacles` is built from markers, static furniture, cones and pallets only (`SceneMarkers.swift:8-45`). Minions are absent from it, and `tickMinions` (`SceneTick.swift:125-130`) steps along the path with no neighbour check. Two minions walk through each other. | Add live minion positions as soft obstacles, or a per-step separation push with a yield rule in doorways. |
| Speed by task: carrying is slow | pass | `SceneTick.swift:233`: hauling 1.1, hurrying to work 2.4, pacing 0.8, stroll 1.4. One hauling pace for carry, `deliverOffice` and the pallet push (`Minion.swift:33-38`), below the stroll. | — |
| Getting up from bed is slow, then quicker | partial | `SceneTick.swift:119-124` holds the minion for 1.1 s (`wakeUntil`), then it walks at full speed. There is no slow first leg. | Ramp the speed over the first second after `wakeUntil` clears. |
| Nothing round | pass | `Scene.swift:43-48` `faceted` caps radial segments, and every cylinder/cone/tube goes through it (`Props.swift:70,202-253`, `SceneStatic.swift:123-262`, `SceneMarkers.swift:377,441`). | — |

## carry

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| A crate moves only in hands | pass | `lift` (`SceneTick.swift:162-181`) reparents the node to the minion and `SceneTick.swift:344` writes `truth.pickedUp`. | — |
| Never through a wall, crate, minion or furniture | partial | The walk is planned round props on the fine grid (`Station.swift:455-523`), and obstacles cover markers and furniture (`SceneMarkers.swift:19-33`). The crate on the arms has no footprint of its own, and minions are not obstacles. | Inflate the walker's clearance while carrying, and include minions in the grid. |
| Arm's length and facing before taking hold | pass | `atArmsLength` (`SceneTick.swift:140-149`) shuffles to 0.34 and faces the crate before advancing; the carry (`SceneTick.swift:336-341`), the office delivery and the set-down all use it. | — |
| Lifting takes time and a posture | pass | `startLift`/`lift` (`SceneTick.swift:151-181`) set `handsAt` from the crate's height and hold `phaseUntil` for `Hands.liftSeconds`; `Minion.swift:181-189` maps that to crouch/waist/reach/jump. One implementation, used by every crate move. | — |
| Setting down takes time and the right posture | partial | `SceneTick.swift:255-280` mirrors the lift, but `Minion.posture` for level 3+ is `.jump` with a hop on the way *down* (`SceneTick.swift:550-552`), and levels 1 and 2 share one lean/reach placeholder rather than the slide and the overhead slide the rulebook asks for. | Implement the four set-down postures separately; ARCHITECTURE.md already lists this as owed. |
| The crate stays in the hands until it is on its slot | pass | `setDown` (`SceneTick.swift:191-204`) animates the node inside the minion's space and `release` only reparents it after `phaseUntil`. | — |
| Nothing moves it after set-down | partial | `release` (`SceneTick.swift:206-215`) pins the node at `to.pos` and `to.yaw`. The `onDone` still removes that node and the next redraw draws it again from the layout at the same slot; every other crate on the rows now keeps its node across a redraw (`rebuildMarkers` adopts by name). | Hand the landed node back to the marker layer instead of removing it. |
| Taken from the top, built from the floor | pass | `World.swift:816-817` orders storage by level, highest first; `World.swift:786-799` `grounded` drops a landing slot to the lowest free level. | — |
| A lower crate taken: the ones above settle down one, slowly | pass | `rebuildMarkers` remembers where each numbered crate stood (`crateStood`, `Scene.swift:176-178`) and, when a crate comes back on the same column at a lower level with the levels between it vacated, draws it where it stood and moves it down over `Hands.settleSeconds` (0.6 s) (`SceneMarkers.swift:184-213`). Only downwards, and never through a crate that is still there. | — |
| A crate keeps its slot until it leaves | partial | `World.swift:672-711` keeps a per-crate slot map keyed on `repo#number`. Unnumbered crates key on `i<index>` (`World.swift:690`), so they reshuffle whenever the pile's order changes. | Key unnumbered crates on something stable, or refuse to draw them until a number is known. |
| Two never share a crate | pass | `Jobs.swift:415` `claimed` marks it; `World.swift:825`, `World.swift:880`, `World.swift:846` all skip carried crates. | — |
| Counts follow the source through hands | pass | Counts still move in `onDone` (`Jobs.swift:472-479`, `SceneMarkers.swift:363-372`), and `yardLayout` now leaves out every crate station truth says is carried, storage and deck alike, and shortens the pile by that many (`World.swift:683-690`). A crate on someone's arms is drawn once, in the hands. | — |
| A carry nobody takes lands where it stands | partial | `Jobs.swift:496-501` drops the node and calls `onDone` on deadline. The crate is removed, not set down anywhere; the redraw puts it back on a slot. | Set it down where it stands and let the layout draw round it. |
| A command whose target vanished sets down what it holds | pass | `SceneTick.swift:192-196` and `Jobs.swift:100-109` `dropWhereStanding`. | — |

## deliverOffice

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| The crate exists before it is fetched | pass | `SceneTick.swift:150` waits for `truth.isInBay(key)`, which the shuttle's unload writes (`Jobs.swift:297`). | — |
| The shuttle leaves before anyone walks under it | partial | `SceneTick.swift:95-99` waits while `s.phase < 3`, i.e. until `.rise` *begins*. The ship is still on its slot at that instant and rises for 2.5 s (`Actors.swift:41-45`) while the carrier walks in under it. | Wait for `.leave`, or for the ship's height to clear the minion. |
| Lift takes time and a posture | pass | `SceneTick.swift:270-292` stands the carrier an arm's length from the bay crate, then uses the carry's own `startLift`/`lift`: `handsAt` from the crate's height, the crouch held for `Hands.liftSeconds`, the crate up past the chest and onto the arms. | — |
| The crate stays in the hands until it is on its slot | pass | The office crate has a slot — the far cell its package will stand on, level 0 (`officeCrateSlot`, `SceneTick.swift:217-222`) — and `SceneTick.swift:296-317` walks it there on the arms, sets it down with the shared `startSetDown`/`setDown` and releases it exactly there. | — |
| Nothing appears or disappears without a cue | pass | The crate is set down on its slot first, and `reveal` (`Jobs.swift:339-345`) fades it out over 0.6 s while the office's own package fades in on the same cell: a cue for the crate as well as for the office. | — |
| An office nobody can carry still shows up | partial | `Scene.swift:612-619` and `Scene.swift:739` reveal undelivered offices with no carry at all. Documented fallback, but the office appears with no cue. | Fade those in explicitly rather than flipping opacity in the rebuild. |
| A renamed office keeps its delivery | pass | `Scene.swift:797-804` rebuilds the command with the new key and rewrites `truth.jobs`. | — |
| The office went away mid-carry | pass | `SceneTick.swift:172-173` reveals and finishes when the door is gone; `Jobs.swift:421-428` `cancelCarries` frees the carrier. | — |

## goTo

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Somewhere to be, with words | pass | `Commands.swift:280-286` `rest`; words from `Place.words`. | — |
| Two never share a couch or a bed | pass | `Jobs.swift:158-171` picks an unused bed or couch and gives up a seat someone else holds. | — |
| Walks round things | partial | `Jobs.swift:185-187`: when no path is found and the target is far, the minion is sent in a straight line, through whatever stands between. | Fall back to the coarse path only, and stand still if even that fails. |
| Re-plan, not reset, when the floor changes | pass | `Jobs.swift:138-152` `resettle` keeps settled and walking minions. | — |
| Rules of the day | pass | `Jobs.swift:132-134` and `Place.forActivity` with `isNight` (`Jobs.swift:125-129`). | — |

## bath

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| A visit lasts its whole time; nobody wanders off mid-shower | fail | `SceneTick.swift:377`: `if (clock >= m.phaseUntil && settled) || m.busy` — work arriving ends the shower on the spot. `bath` is also not `isJob` (`Commands.swift:174-180`), so `assign` and `send` may cut in at `.settle`. | Make `bath` a job for its duration, and drop the `|| m.busy` escape. |
| Ten seconds of water, pixels where they belong | partial | `SceneTick.swift:389` sets 10 s for a shower; drops fall from the nozzle (`SceneTick.swift:365-375`) and `setStatic` covers the body (`Minion.swift:102-119`). The 10 s only holds if nothing interrupts, which the line above allows. | As above. |
| Two never share a shower | fail | Nothing reserves the fixture. `SceneTick.swift:383-400` sends anyone whose `bathDue` came due to the same corner cell and the same nozzle spot. Beds and couches have a reservation; the bath has none. | Reserve the shower and the bowl the way `send` reserves beds. |
| A shower after long work, a pee after short | partial | `SceneTick.swift:324-328` picks by stretch length, but the short case is gated on `Bool.random()`, and both delays are random. Random decides whether a rule fires, not just its flavour. | Make the short-stretch case deterministic, keep the delay random. |
| Back to where it was after | pass | `SceneTick.swift:380` reads `back` out of the command. | — |

## chore

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Chores when bored, then back to the couch | pass | `SceneTick.swift:337-354`; `Commands.swift:223-225` gives it words. | — |
| Idle drift toward a loaded rocket | pass | `SceneTick.swift:343-345` prefers the pad-side deck row when a rocket is steaming or launching. | — |
| Idle time, never work | pass | The chore keeps `busy` false and `isJob` is false (`Commands.swift:174-180`). | — |
| Where it goes is a cue | partial | `SceneTick.swift:346` picks `spots.randomElement()` across corridor, storage, deck and bay: random decides where, though not whether. Acceptable as flavour, but the destination carries no meaning. | Prefer spots with something to look at. |

## qa

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Paces the rows like a foreman | pass | `SceneTick.swift:302-319` steps stack by stack, stands in the aisle, faces the stack, sweeps the scanner, hops when impatient. | — |
| Arm's length and facing | pass | `SceneTick.swift:309-312` stands in the aisle cell beside the stack and faces it. | — |
| QA is work, not idle | pass | `Jobs.swift:610-614` sets `busy` and issues `.qa` with words. | — |
| Ends when there is nothing to test | pass | `Jobs.swift:615-620` sends the walker to the lounge when the deck is clear or a rocket is steaming. | — |
| One QA walker | pass | `Jobs.swift:608-609` checks for a current one first. | — |

## leave

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Leave through the airlock | pass | `Jobs.swift:112-122` paths to a hatch's inside cell, then out to the bay. | — |
| Gone only with a cue | pass | `SceneTick.swift:409-411` fades over about 0.7 s before `despawn`. | — |
| The hatch it uses | partial | `Jobs.swift:116` picks `airlockHatches.randomElement()`; random picks the door, harmless. | — |
| Anything on the arms goes down | pass | `Jobs.swift:20-33` `despawn` calls `dropWhereStanding` and `truth.dropped`. | — |
| `stepOut` is never reached | partial | `.leave` has phases `[.walk, .stepOut]` (`Commands.swift:159`) but nothing advances it (`SceneTick.swift:295`), so the non-interruptible step never protects the exit. | Advance the phase at the hatch. |

## sleep

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Sleep in the dorm by night | pass | `Commands.swift:281`; `Jobs.swift:125-134`. | — |
| Two never share a bed | pass | `Jobs.swift:158-162`, with the lounge as the overflow. | — |
| Getting up is slow | partial | `SceneTick.swift:119-124` holds 1.1 s, then full speed. | Ramp the first leg. |
| The bunk's own height | pass | `SceneTick.swift:420-424` lifts the body onto the upper bunk. | — |

## work

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Work at the office, with words | pass | `Commands.swift:282-284`; `Jobs.swift:392` names the message being worked. | — |
| A routine per activity | pass | `SceneTick.swift:509-544` gives each activity its own pose and tool. | — |
| Stands at the cone, facing it | pass | `SceneTick.swift:444-456` places up to three workers round the cone at 0.4 and faces each one to it. | — |
| Cones land on clear floor | pass | `Jobs.swift:358-365` filters obstacles and label cells, nearest the door. | — |
| A commit box carried in has no command | fail | `SceneMarkers.swift:169-179`: a redraw hands a minion a box, sets `carried` and `commitDrop`, and walks it off with no `Command`, no words and no truth entry. It contradicts "one thing at a time, and it is always something with a name". | Make it a real `carry` command, or drop it. |
| The box then fades out | partial | `SceneTick.swift:132-141` lowers it, thuds and fades. The fade is a cue, but the crate never had a slot. | As above. |

## react

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| A teammate does one named thing until its time | pass | `Jobs.swift:574-580`, `SceneTick.swift:187-190`; `Commands.swift:275-277` carries the words. | — |
| Only for news, never history | pass | `Events.swift:96` `ready`; `Jobs.swift:555` logs only when the repository has answered before. | — |
| A reaction never cuts a job | pass | `Jobs.swift:550` guards on `!m.onJob`. | — |
| Back to the quarters after | pass | `Jobs.swift:518-523` `crewRested`. | — |
| Walk phase advances properly | pass | `SceneTick.swift:189`. | — |

## flight (shuttle)

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| A shuttle lands only in the bay | pass | `Jobs.swift:201-213` and `Jobs.swift:263-286` use `hangarSlots` off the hangar anchor only. | — |
| It leaves before anyone walks under | partial | Enforced only for the office carry, and only to the start of `.rise` (`SceneTick.swift:95-99`). An arriving worker steps out at 8.1 s (`Actors.swift:81`, `Jobs.swift:207`) and walks out from under a ship that leaves the slot at 9.1 s. | Hold the walk until `.leave`, and derive the hold from the phase, not from 8.1. |
| Phases run on the command | partial | `Actors.swift:33-87` follows the command's phases, but each phase's motion is an `SCNAction` (`Actors.swift:50-77`), which ARCHITECTURE.md says does not advance in a headless run. The unload writing truth is on the clock, so it still lands. | Move the flight path onto the station clock, as the pallet flight already is. |
| The cargo appears only on the unload cue | pass | `Jobs.swift:291-298` sets opacity and drops the crate inside `onUnload`, then writes `truth.crateInBay`. | — |
| Where it comes from and goes | partial | `Jobs.swift:210-211,279-283` pick corners with `randomElement`; flavour only. | — |

## rocket

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Stages only move forward | pass | `SceneMarkers.swift:219` compares `stage.rank`; `Commands.swift:104-112`. | — |
| A rocket leaves only with its cargo aboard | pass | Every crate the reconciler orders aboard is remembered on the rocket (`SceneMarkers.swift:369-371`, `Actors.swift:107-113`), and the load ends only when `truth.aboard` counts all of them, no carry of them is outstanding, and the rows and everyone's arms are empty (`SceneMarkers.swift:318-331`). The 90 s mark now only makes the station say it is still holding. A release with no cargo at all still goes at once. | — |
| Loading is done by hand, from the top down | pass | `SceneMarkers.swift:330-347` issues `carryToPad` commands; `World.swift:911-934` orders by level, highest first, chaining with `after`. | — |
| Crates leave the station only with the rocket | partial | `SceneMarkers.swift:344` shrinks the node away on set-down; `truth.clearPad` (`Commands.swift:492-496`) is called at the climb. The shrink is the disappearance cue, and it happens before lift-off. | Keep the crate visible on the pad until the climb. |
| Steam means loaded and waiting | pass | `SceneMarkers.swift:287` adds steam on the steam stage only. | — |
| A hold ring means untested | pass | `SceneMarkers.swift:235-239` adds it, `SceneMarkers.swift:279` takes it down when cleared. | — |
| The prop is only redrawn when standing by | pass | `SceneMarkers.swift:251-257` refuses to redraw once `rank > 0` or while actions run. | — |
| Nothing on a timer decides anything | pass | The 90 s mark only logs now (`SceneMarkers.swift:322-328`); the 15 s climb (`SceneMarkers.swift:284`) is decoration over a pad truth has already cleared. | — |
| A first answer is not news | partial | `World.swift:367-377`: `announcedReleases` starts empty, so the first GitHub answer announces an open release and, if cleared, immediately issues `.load`. The rocket starts hauling on start-up. | Seed `announcedReleases` on the first answer per repository, as `stagingSeen` does. |

## dispatch

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Clipboard out, to the console, with words | pass | `Pallets.swift:41-43`; `Commands.swift:252-255`. | — |
| One errand per repository | pass | `Pallets.swift:31` skips repositories somebody is already on. | — |
| It stands at the console, facing it | pass | `Pallets.swift:478-481` `faceConsole` uses the console's own facing. | — |
| The console blinks while an order stands | pass | `Pallets.swift:314-315`, `Pallets.swift:467-476`. | — |
| Nobody free: the crates stand still | partial | `Pallets.swift:37` `break`s out; `World.swift:750-751` then returns `.waiting` for that repository forever. Known and written down in ARCHITECTURE.md. | Time the wish out and fall back to hand carries. |
| The dispatcher is chosen, not drawn | pass | `Pallets.swift:37` takes the nearest free worker. | — |

## loadPallet

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| A crate may move by the wand while loading a pallet | pass | `Pallets.swift:98`, `Pallets.swift:410-435`; the wand tip lights while a crate flies (`Pallets.swift:356`). | — |
| One crate at a time, off the top of its stack | pass | `Pallets.swift:411-413` takes one every 3 s; `World.swift:841-849` orders by level, highest first, and skips carried crates. | — |
| The crate in the air rides the station clock | pass | `Pallets.swift:358-367`, deliberately not an `SCNAction`. | — |
| Never through a wall or another crate | fail | The arc is a straight interpolation with a sine hop (`Pallets.swift:361-362`); nothing checks what is between the stack and the slot. | Route the arc over the tallest thing between, or check the line. |
| Counts follow the hands | partial | `Pallets.swift:418` decrements `stored` as the crate leaves the ground, before it lands. `rebuildMarkers` is called in the same breath (`Pallets.swift:434`), so the row is right, but truth leads the picture by 2.4 s. | Decrement in the flight's `land` closure. |
| Nothing else moves those crates | pass | `World.swift:750-751` returns `.waiting` from the moment a pallet is queued; `World.swift:683` keeps pallet crates out of the rows. | — |
| Nothing in storage for that repository | pass | `Pallets.swift:158-165` ends the pallet at once and clears the wish. | — |

## waitPallet

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Standing by, with words | pass | `Pallets.swift:78,104`, `Commands.swift:261-263`. | — |
| The dispatcher gets impatient | pass | `Pallets.swift:484-493`: a hop or a step along the wall, every 5 to 9 s. | — |
| A release that moved while it waited | pass | `Pallets.swift:83-87` picks up `wantsPush` / `wantsBack` as soon as the pallet exists; `Pallets.swift:193` reads the wish left by `palletWishes`. | — |
| It waits beside the pallet, not through it | pass | The pallet's footprint is in `obstacles` (`SceneMarkers.swift:35-43`), so the walk goes round. | — |
| The wait is idle, not work | partial | `waitPallet` is `isJob` (`Commands.swift:177`), so the waiter is never given a carry even when it is only fidgeting at the console. | Let a waiting-at-the-console dispatcher take a carry and come back. |

## pushPallet

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Pushed from behind | pass | `Pallets.swift:227-231` `pushSpot` puts the pusher squarely behind on the leg's axis; `Pallets.swift:331` locks it a step behind while moving. | — |
| One axis at a time | pass | `Pallets.swift:250-279` `palletRoute` builds axis-aligned legs; `Pallets.swift:229` snaps the direction to one axis. | — |
| Slowly, easing in | pass | `Pallets.swift:327-330`: half a cell a second with a one-second ramp. | — |
| Only where a pallet fits | pass | `Pallets.swift:237-245` `clampToYard` keeps the whole 1.8 by 1.4 footprint on the block's tiles, and every leg end goes through it. | — |
| Never through a crate or a minion | fail | Nothing checks the swept footprint. The route aims at the aisle (`Pallets.swift:258-263`), which is clear by convention, but a minion standing there is simply run over. | Check the swept rectangle against obstacles and hold the leg while it is blocked. |
| Round the back at every corner | pass | `Pallets.swift:126-136` resets to `.approach` and walks round for the next leg. | — |
| The push has a posture | pass | `Pallets.swift:337`: a 0.35 lean plus a small shove. | — |
| The tick owns the pusher's body | partial | `SceneTick.swift:184-186` skips pallet errands and `placePusher` does it instead (`Pallets.swift:283-288`). Two places now place a minion's node. | Fold the pusher's placement back into one body update. |

## unloadPallet

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Crates float off one at a time | pass | `Pallets.swift:438-462`, one per 3 s, on the station clock. | — |
| Onto their slots, or back onto their stacks | pass | `Pallets.swift:443-444` uses `storageSlot` or `deckSlot`; `World.swift:854-860` grounds the storage slot. | — |
| A closed release puts them back | pass | `Pallets.swift:53`, `Pallets.swift:85`, `Pallets.swift:455` re-registers them as landed in storage. | — |
| The empty pallet leaves with a cue | pass | `Pallets.swift:301-307` fades slab and shadow over 0.9 s. | — |
| A pallet caught half way | pass | `Pallets.swift:385-403` `adopt` unloads where it stands. | — |
| Never through a wall or a crate | fail | Same straight arc as the load (`Pallets.swift:451-452`). | Same fix. |
| Deck counts follow the hands | pass | `Pallets.swift:456` bumps `staged` in the landing closure. | — |

## The event cues in `handle(_:)`

| Path | Verdict | Evidence | Fix |
|---|---|---|---|
| `.worldLoaded` | pass | `Scene.swift:764-765` does nothing: the first answer is not news. | — |
| `.log`, `.chime` | pass | `Scene.swift:766-769`; `ringBell` rate-limits to 4 a second (`Jobs.swift:403-407`). | — |
| `.layoutChanged` / `.markersChanged` | pass | `Scene.swift:770-773` only marks dirty; `flushScene` (`Scene.swift:721-731`) redraws once, after the caller has placed its workers. | — |
| `.officeOpened` with `.shuttle` | pass | `Scene.swift:779-785` records the pending office and queues the delivery by source. | — |
| `.officeOpened` with `.appear` | partial | `Scene.swift:777`: nothing happens, the office is simply there. Used on the first run (`World.swift:209`), which is the right exception, but the case would also swallow a later `.appear`. | Assert that `.appear` only reaches here on the first run. |
| `.officeOpened` with `.fade` | pass | `Scene.swift:778` records it for the fade-in. | — |
| `.officeRenamed` | pass | `Scene.swift:787-804` moves truth, outlines, boxes, the delivery command and the minion's place. | — |
| `.officeArchived` | pass | `Jobs.swift:308-337`: carries cancelled, boxes shrunk, tiles sunk and faded, occupants walked out to the hall. A cue for everything that leaves. | — |
| `.officeMerged` | partial | `Jobs.swift:447-461` hauls the package by a real carry. The `from` spot is the office door, not the package's position (`World.swift:870-872`), so the carrier walks to the door and picks up a crate that stands elsewhere in the room. Known debt in ARCHITECTURE.md. | Take the `from` spot from the package node. |
| `.carryToDeck` | pass | `Scene.swift:810-812` into `stageCargo`, which hands each command a node and adjusts counts on landing. | — |
| `.crateCleared` | pass | `Jobs.swift:584-595` into `carryToTested`, which moves what is stacked above first (`World.swift:888-901`). | — |
| `.crewRoster` | pass | `Jobs.swift:526-545` adds and removes crew minions. | — |
| `.crewActivity` | pass | `Jobs.swift:549-571`: one `react` per kind, never while on a job. | — |
| `.stagingOpened` | pass | `Pallets.swift:20-24` queues the pallet and says so. | — |
| `.stagingMerged` / `.stagingClosed` | pass | `Pallets.swift:50-62`: a wish on the pallet if it is out, remembered otherwise. | — |
| `.releaseOpened` / production `.releaseMerged` | pass | `Scene.swift:831-832` deliberately does nothing: the rocket command is the cue. | — |
| non-production `.releaseMerged` | partial | `Scene.swift:833-836` calls `stageCargo` directly when there is no board and no pallet. A second, older way of moving the same crates. | Route it through the reconciler. |
| `.rocketCommand` | pass | `SceneMarkers.swift:213-230`: a new actor, or a forward-only stage. | — |
| `.prompt` | pass | `Scene.swift:752-758`: one cone per message, queued cones lit as they are picked up. | — |
| `.crewHidden` | partial | `Scene.swift:841-842` despawns crew minions at once, with no fade or airlock. | Send them out through the airlock. |
| `.boardMoved` | pass | `Scene.swift:843-861` logs, and hands the cleared case to `.crateCleared`. The deck case leaves the move to the reconciler. | — |
| `.pullRequestOpened` / `.issueStarted` | pass | `Scene.swift:862-865`, log lines only. | — |
| `.pullRequestClosed` | pass | `Scene.swift:866-869`, a `react` when the author is around and free. | — |
| `.peerArrived` / `.peerLeft` | pass | `Scene.swift:870-873`, log lines; the offices are held by the model. | — |

## The yard reconciliation

| Rule | Verdict | Evidence | Fix |
|---|---|---|---|
| Carried, not snapped, wherever a haul can carry it | pass | `World.swift:754-758` issues `carryToDeck` before touching any count. | — |
| Let the carriers land first | pass | `World.swift:747` returns `.waiting` while anything is in flight to the deck. | — |
| A pallet is the hand carry for its repository | pass | `World.swift:750-751`. | — |
| Redrawn only if nobody is holding it | pass | `yardLayout` drops every carried crate and shortens the pile by that many (`World.swift:683-690`), so the snap at `World.swift:766` may still count a crate that is on someone's arms without the rows drawing it twice. | — |
| A launch is not undone by a snap | pass | `World.swift:759-761` holds `staged` while a launch is pending or a production release is open. | — |
| The layout is a pure function of the counts | pass | `World.swift:653-727`, plus the per-crate slot map so nothing jumps. | — |
| Storage unorganised, the deck ordered | pass | `World.swift:656,720`: jitter in storage, none on the deck. | — |
| A first answer is quiet | pass | `readyRepos` (`World.swift:71`), `stagingSeen` (`World.swift:393`), `sessionPrompts` (`World.swift:216`). | — |
| Reconciliation runs inside a redraw | partial | `SceneMarkers.swift:51-57`: `rebuildMarkers` calls `world.reconcile` and re-enters `handle`, while `rebuildMarkers` is itself called from carry completions (`Jobs.swift:477`) and from `loadOne` (`Pallets.swift:434`). Drawing and deciding are tangled. | Run the reconciler from the tick, not from the redraw. |

## Cross-cutting findings

**The same rule implemented twice, differently.**

- ~~Two lift and set-down implementations~~: one each now, `startLift`/`lift` and
  `startSetDown`/`setDown`/`release` (`SceneTick.swift:110-215`), used by the carry and by the office
  delivery, with the phase durations derived from the arcs' own durations so they cannot drift.
- Two ways a crate moves through the air: the minion's hands and the pallet's wand flight
  (`Pallets.swift:358-367`). Only the second is clock-driven; the first still uses `SCNAction`s
  (`SceneTick.swift:238-277`), which the headless run does not advance.
- Two ways crates reach the deck: `stageCargo` from the reconciler (`Jobs.swift:464`) and `stageCargo`
  called straight off `.releaseMerged` (`Scene.swift:833-836`).
- Two obstacle sources: `refreshObstacles` builds one set from marker nodes, static furniture, cones and
  pallets (`SceneMarkers.swift:8-45`), while `path` has its own fallback that ignores all of it
  (`Jobs.swift:185-187`, `Station.swift:506-508`).
- Two places place a minion's body: `tickMinions` (`SceneTick.swift:429`) and `placePusher`
  (`Pallets.swift:283-288`).
- ~~Two carried-crate filters~~: one, in `yardLayout` (`World.swift:679-690`), covering pallet crates and
  carried crates for storage and the deck alike.

**State outside `StationTruth` that belongs in it.**

- `Pallet` the actor duplicates almost all of `StationTruth.Pallet`: `state`, `spot`, `wantsPush`,
  `wantsBack`, `dispatcher` (`Actors.swift:133-189`), each mirrored by hand on every change
  (`Pallets.swift:100-101,292-294`).
- `station.stored` / `station.staged` are the real crate counts and live on `Station`, written from
  five places (`Jobs.swift:474-475`, `Pallets.swift:418,456`, `SceneMarkers.swift:342-343`,
  `World.swift:760-761`, `World.swift:959`).
- `haulingRooms`, `boxes`, `outlines`, `undelivered`, `lastBoxCount`, `fadingProps`, `roomPower` are
  scene dictionaries that decide what is drawn and what may be carried.
- A minion's `place`, `activity`, `bathDue`, `nextChoreAt`, `nextBathAt`, `busySince`, `qaStop`,
  `handsAt`, `fetchSpot` are the day's actual state, none of it in truth (`Minion.swift:10-127`).
  ARCHITECTURE.md already names `place`, `activity` and the wander timers as the debt.
- `Rocket.since`, `Rocket.cargoShown` and `Shuttle.phase` are actor-local copies of what phase things
  are in.

**Timers and `SCNAction`s still deciding.**

- The 90 s rocket load timeout (`SceneMarkers.swift:299`) decides a launch.
- `wakeUntil = clock + 8.1` (`Jobs.swift:207`) decides when an arriving worker becomes visible, from a
  number that must match the flight's phase durations (`Actors.swift:39-47`).
- `hauledAt` plus 60 s (`World.swift:239`) decides when a merged office may clear.
- The shuttle's whole path is `SCNAction`s (`Actors.swift:50-77`); its phases advance on `until`, so
  the ship's position and its phase can drift apart in a headless run.
- The carry's lift and set-down arcs are still `SCNAction`s while the phase timing is on the clock, but
  both now come from the `Hands` constants (`SceneTick.swift:110-137`), so a phase is exactly its arc plus
  the beat around it and the two cannot drift.
- Decoration that decides nothing, correctly: steam (`SceneMarkers.swift:390-406`), the lift-off climb
  (`SceneMarkers.swift:200-207`), shower drops, the weld light, the archived ghost, the console blink.

**`random` deciding behaviour rather than flavour.**

- `Bool.random()` decides whether a short work stretch earns a bath at all (`SceneTick.swift:327`).
- `Bool.random()` decides whether an impatient dispatcher paces or hops (`Pallets.swift:487`) — flavour,
  but it is the routine, not the look.
- `addPyramid` places a cone with `nearDoor.prefix(2).randomElement()` (`Jobs.swift:365`): which floor a
  message lands on is random.
- `arriveByShuttle` and `startDelivery` pick approach and exit corners randomly (`Jobs.swift:210-211`,
  `Jobs.swift:279-283`), and the office ship's resting yaw and drift too (`Jobs.swift:290`): flavour.
- `dismiss` picks the airlock hatch randomly (`Jobs.swift:116`): flavour.
- The chore destination is random across four areas (`SceneTick.swift:346`).
- Bath, chore and wander delays are random ranges (`SceneTick.swift:326-340,407`): flavour.

## Fix list, most visible first

1. **Make a change of orders visible.** The newest rule has no implementation at all, and it applies to
   every command. One `wonderUntil` beat in `start`, honoured in the tick, cut short by a prompt.
2. ~~**Fix the carrying speed.**~~ Done: hauling is 1.1, below the 1.4 stroll (`SceneTick.swift:233`).
3. ~~**Let stacks settle instead of blinking.**~~ Done: a crate whose level dropped is drawn where it
   stood and moved down over 0.6 s (`SceneMarkers.swift:184-213`).
4. ~~**Give `deliverOffice` a real lift and set-down.**~~ Done: it uses the carry's own lift and set-down
   and puts the crate on the office's far cell before the reveal (`SceneTick.swift:262-320`).
5. ~~**Stop drawing carried storage crates twice.**~~ Done: `yardLayout` filters them and shortens the
   pile (`World.swift:683-690`).
6. ~~**Do not launch without cargo.**~~ Done: the load ends when everything ordered aboard is on the pad;
   the 90 s mark only logs (`SceneMarkers.swift:318-331`).
7. **Let a visit last its whole time.** Drop the `|| m.busy` escape from the bath and make `bath` a job
   (`SceneTick.swift:377`, `Commands.swift:174-180`).
8. **Reserve the shower and the bowl.** Beds and couches are reserved; the bath is not
   (`Jobs.swift:158-171` versus `SceneTick.swift:383-400`).
9. **Make minions solid to each other.** Add them to the obstacle set and give a narrow place a yield
   rule (`SceneMarkers.swift:8-45`, `SceneTick.swift:125-130`).
10. **Stop pushing pallets and floating crates through things.** Check the pallet's swept footprint
    (`Pallets.swift:322-339`) and the wand arc's line (`Pallets.swift:361`).
11. **One entry point for orders.** Route every `start` through `assign` so the interruptible rule is not
    a convention (`Jobs.swift:44-78` and its six bypasses).
12. **Advance the phases of the quiet commands.** `goTo`, `bath`, `chore`, `qa`, `sleep`, `work` and
    `leave` never leave `.walk` (`SceneTick.swift:295`), so truth misreports every settled minion.
13. ~~**Move the carry's arcs and the shuttle's flight onto the station clock**~~ Done: the carry's arcs
    run through `moveCrate`, and the shuttle interpolates each leg from the clock (`Actors.swift`).
14. ~~**Give the commit-box carry a command**~~ Done: `stow`, with the newest cube hidden until it is set
    down; `pack` does the same for a pull request just opened.
15. ~~**Take the reconciler out of the redraw**~~ Done: `reconcileYards` runs from `flushScene` and the
    half-second tick, and `rebuildMarkers` decides nothing; it adopts the nodes that stand and only
    builds what is new. The world's own haul flags are gone too; a merged office's progress is read off
    its crate's placement in `StationTruth` (`officeCrates`, `haulLanded`). Still owed: fold the pallet
    actor's duplicated state into `StationTruth` (`Actors.swift:133-189`).
16. ~~**Quiet the first release answer**~~ Done: `releasesSeen` marks the first answer announced without
    saying it; the rocket still stands.
17. **Take the randomness out of the routines**: the short-stretch bath (`SceneTick.swift:327`) and the
    cone's landing cell (`Jobs.swift:365`).
