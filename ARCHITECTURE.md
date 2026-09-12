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
rooms (`kind:...`), the yard, doorways, and pathfinding on a 3x3 grid per cell around props. `Fleet` arranges
stations and saves the layout.

`World.swift` owns that floor plan and the diffs. `applyScan`, `applyGitHub`, `applyPeer` and `dropPeer` take
one fresh answer each, compare it with what was known, change the model, and hand back `WorldEvent`s
(`Events.swift`): an office opened or archived, a board column change, a pull request opened or closed, a peer
arriving. Counts in the yard are reconciled, not snapped: crates the board says moved to staging are carried
across by minions (`reconcile`), and only what cannot be carried is redrawn.

A few things the model cannot see for itself — a crate already on someone's arms, a rocket mid-load — the
scene lends it as closures.

Rules that keep the place steady:

- An update re-plans, it never resets. After the floor changes, `resettle` leaves settled minions alone and
  lets walkers keep their destination.
- The yard layout is a pure function of the counts (`yardLayout`), so a carrier is sent to the slot its crate
  will occupy and nothing jumps when the layout redraws.
- Offices exist because of a checkout, a pushed branch, or a pull request. The board column only says how
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

The scene is split by reason to change, all of it one `StationController` in extensions: `Scene.swift` holds the
shared helpers, every stored property, `buildScene`, the scan and event glue and the outer tick; `StationView.swift`
the input view and the camera it moves; `SceneStatic.swift` the floor, walls and the names written on it;
`SceneMarkers.swift` the crates, cones, rockets and power; `SceneTick.swift` the per-frame worker loop and the demo
clock; `Jobs.swift` what a worker is told to do; `HUD.swift` the overlay; `Minion.swift` one worker's body;
`Actors.swift` the props that run commands of their own, a shuttle's flight, a rocket's stages and a pallet's
load; `Pallets.swift` the dispatcher's errand from the console to the deck.

## Debts

- Every actor runs one `Command` at a time with a phase index (`Commands.swift`), so "what am I doing now"
  has a single owner: minions, the crew, the shuttles and the rockets alike. What is left outside it:
  `place`, `activity` and the wander timers still steer a worker's day.
- What is still on a timer is pure decoration, nothing the model can read: the steam emitter puffing off a
  loaded rocket, the flame and the twelve-second climb of a lift-off, the shower drops, the weld light, the
  ghost of an archived room sinking through the floor. None of it decides anything.
- `makeSnapshot` still lives in the scene, because what goes on the wire includes box counts and lit rooms
  that only the scene knows. The ingest side (`applyPeer`) is in the model, where compatibility matters most.

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

Steps 5, 6 and 7 exist as of this commit. `Commands.swift` holds `Command` (a kind, a phase list with each
phase marked interruptible or not, a "must be true by" deadline, and words for humans) and `StationTruth`
(crates by slot or on someone's arms, offices delivered or pending, per-minion command and phase, crates
landed by hand the source has not counted yet, carries in flight to the deck). `World` owns the truth and
issues carries — `reconcile`, `carryToDeck`, `carryToStorage`, `carryToTested`, `carryToPad` — and the scene
binds each command to the crate's node and hands it to a minion. Minions execute one command at a time:
a new one replaces the old at the next interruptible phase, at most one waits, a carry can only be redirected
to another destination for the crate already on the arms, and a command whose target vanished sets down what
it holds where it stands.

Every crate that moves by hand goes through one lift and one set-down (`SceneTick.swift`, the `Hands`
constants with `startLift`/`lift` and `startSetDown`/`setDown`/`release`): an arm's length away and facing
it, a crouch whose posture comes from how high the crate stands, the crate up past the chest and onto the
arms, and out of the arms onto its slot turned the way the layout will draw it. The office delivery uses the
same pair, so a new office's crate is set down on the far cell its package will occupy and only then does
the office fade in round it. The arcs are `SCNAction`s and the phase clock is the station's, but both are
derived from the same durations, so the posture and the motion cannot drift apart. A carried crate is left
out of `yardLayout` altogether, storage as well as the deck, so it is drawn once — in the hands.

Shuttles, rockets and the crew are actors too (`Actors.swift`). A `Shuttle` flies one `.flight` command —
`bringWorker` or `dropCrate` — through approach, descend, unload, rise and leave, and the unload writes truth:
the worker steps out, or the office crate stands in the bay, which is what lets a carrier's `deliverOffice`
go from approach to lift. A `Rocket`, one per station and repository, runs `.rocket` stages that only ever
move forward: stand by, load, steam, launch. `World.applyReleases` reads the launch queue and the open
releases and hands out those stages as commands — untested stands by, cleared loads, merged launches, and a
launch loads first if it has to. The load phase issues the same `carryToPad` carries as before, remembers
every crate it ordered aboard, and ends only when station truth counts all of them on the pad and nothing of
the repository is left on the rows or on anyone's arms. A load that is taking its time is waited out and said
out loud; a rocket with no cargo at all still goes at once. A teammate's reaction
to a push, a review, a comment or a branch is a `.react` command with its own until-time, so a crew minion
runs the same machine as everyone else and says so on hover.

What still does not: the crate a merged office sends to storage is still found by node name in the scene, so
the command's `from` spot is the office door rather than the exact package position; `Spot` carries a world
position, which means the scene's geometry leaks a little into the model side.

Debugging: hovering a minion pauses it and shows its current command in words, and the same words go
in the log when the command is issued.

## Station truth against a source that runs behind

Steps 4, 5 and 7 above, for crates. Every crate a station knows is a row in one ledger (`Ledger.swift`,
kept on the `Station` and saved with it): `wanted`, the source's word on which yard it belongs to, with
the source's own time for that word; and `placed`, the station's word, which yard it stands in or belongs
to while on someone's arms or the pallet. Sources write `wanted`, only through `adopt`; completions write
`placed`, only through `landed`, whenever a minion, the pallet or the rocket's hatch sets a crate down.
The counts the HUD, the rockets and the rings read (`Station.stored`, `staged`) are read off `placed`
and kept nowhere; `yardLayout` draws from the same rows.

A word from the source is news for a crate only if it is newer than the station's own hand on it. A
board item carries when it last moved, so an answer older than a landing is stale for that crate
however fresh the poll, and a word older than the one already held (a peer's lagging copy) is not news
either. A source with no times of its own, git history, is believed again the moment it agrees with what
the station did. That is what lets the pallet's crates stay on the deck while the board still says
storage, and a crate in the rocket's hold stay there until the board says shipped; nothing decides by
the clock any more.

Disagreement is a queue, not an event. `reconcile` takes the source's answer into the ledger, then walks
the crates the two sides disagree about: storage to deck is one carry per crate, by number, blockers
moved aside first and never a crate pulled from under another; anything else is redrawn where the source
says, once, and never a deck crate while a rocket is loading from it. It runs from `flushScene` and the
half-second tick, never from the drawing, and never while somebody is carrying one of the repository's
crates or a pallet has them. `rebuildMarkers` adopts what stands: an office's boxes are left alone while
everything that shapes them reads the same, a numbered yard crate keeps its node and is moved only if
its slot changed, and only what is new is built and what is gone taken away. A peer's heartbeat asks for
a redraw only when it brought a difference.

A yard holds a slot for a crate on its way in from the moment the carry is ordered (`heading`), so two
carries never land on one slot; a crate that has left the rows, on the arms or the pallet, holds nothing,
the stack it was in settles, and it asks for a slot again when it comes back. That is the first half of
step 5's late binding; the second, a carry that names only the yard and takes its slot at set-down, is
still owed. `--ledger-tests` feeds a ledger facts in every order, board before release, release before
board, stale after fresh, A then B then A, and holds it to: every crate in one yard at most, a hand
outranking any older word, wanted equal to placed once the source has said something newer.

## The staging pallet

Done. A staging release (a pull request into the staging branch) is a fact of its own: `ReleasePR.isStaging`
sits beside `isProduction`, and `World.applyStaging` diffs each repository's release list into
`.stagingOpened`, `.stagingMerged` and `.stagingClosed`. The first answer per repository is quiet.

Station truth gains one pallet per station (`StationTruth.Pallet`: repo, number, the cell it hovers over,
its state — arriving, loading, loaded, moving, unloading — and its crates by pallet slot, three rows of
four counted from the pallet's floor up). Further requests queue in `palletQueue` in the order they came.
A crate on it is `Placement.pallet`, so `yardLayout` leaves it out of the rows and `reconcile` returns
`.waiting` for that repository: from the moment a pallet is ordered until it is empty, the pallet is the
hand carry for those crates and no `carryToDeck` is issued for them.

Five commands run it, all on one minion, the dispatcher: `dispatch` (clipboard out, to the storage console),
`waitPallet` (at the console with the hops and pacing of a minion waiting on you, or beside a loaded pallet
until the release moves), `loadPallet` (the wand out, one crate at a time off the top of its stack, through
an arc, onto its pallet slot), `pushPallet` (hands on the pallet, shoving it leg by leg out through the
storage doorway and across to the untested row) and `unloadPallet`
(the crates float off onto their deck slots, or back onto their stacks in storage when the release closed
unmerged, and the empty pallet fades). The `Pallet` actor in `Actors.swift` holds the node, what is aboard
and the crate in the air. Two new props: `Props.pallet`, a two-tier slab hovering 0.12 above the floor on a
cushion of light, bobbing on a sine, with twelve sunk fields matching the crate slots, rivets along the
rim, an amber corner light the tick blinks, and a floor shadow of its own that stays down and tightens as
the slab sinks; and `Props.console`, the small panel on the wall by the storage doorway,
which blinks while an order stands unanswered. Two new tools: `.clipboard` and `.telekinesis`, a short
faceted wand whose tip lights, with a small omni light, while a crate is in the air; and `.hands`, held
out in front for the push.

The push, leg by leg. The pallet is heavy and only ever moves along one axis. `palletRoute` cuts the way
to the deck into axis-aligned legs: line up on the two doorway columns without leaving storage, out
through the doorway onto the deck's aisle row (the crate rows are every other row; the aisles are the
rest), then along that aisle to the repository's group on the untested row. Every leg end is clamped so
the whole 1.8 by 1.4 footprint stays on the block's tiles. For each leg the minion walks round to the
back side on that leg's axis — the pallet's footprint is in `station.obstacles`, so the walk goes round
it, never through it — then leans in at a tilt of 0.35 and the pallet creeps forward at half a cell a
second, easing in, with the pusher locked a step behind it and a small forward-and-back shove in the
body. The minion tick skips anyone on a pallet errand, so the push places the pusher's own node.

What differs from the plan above:

- **Which crates it carries.** Every crate of that repository standing in storage, twelve at most, taken
  by yard order from the top of each stack — not the pull request's own commit list, which the sources do
  not break down per staging release.
- **A crate in the air is moved by the tick, not by an SCNAction.** Actions do not advance in a headless
  `--snapshot` run, so a load that depended on one never landed. The arc, the turn and the pallet's own
  fade all ride the station clock, like everything else that decides something.
- **The pallet is bigger than a cell** (1.8 by 1.4) so twelve crates at their one size fit on it. It
  hovers over the near row on the two columns of the deck doorway and overhangs the wall a little.
- **A release that ends while the dispatcher is still walking** is remembered (`palletWishes`) and handed
  to the pallet the moment it is out, because the simulator presses "opens" and "merges" two seconds apart
  and GitHub can answer just as fast.
- **A dispatcher that goes away mid-errand** is replaced: the pallet is adopted by whoever is free, and one
  caught half way across unloads where it stands.

Still owed: nothing queues behind a pallet in practice, because a station has one storage yard and one
console; a second repository's release simply waits. And while an order stands with nobody free to run it,
that repository's crates do not move at all — the reconciler is holding them for a pallet that has not
come out yet.

## Carries know the stack

Done. `yardLayout` hands out slots with a `column` — one square of floor, half a cell wide — and a
`level` counted from the floor, and `Spot` carries that level and the slot's yaw along with the
position. Storage jitter is seeded per crate rather than per place in the pile, so a crate keeps its
own nudge and turn wherever it lands.

- A crate is picked from the top of its stack. Where crates are interchangeable (storage to the deck)
  `carryToDeck` orders them by level, highest first. Where a named crate must move — a tested crate
  crossing to the tested row — `carryToTested` issues one carry per crate stacked above it, each to
  the slot the redraw will give it, and the wanted crate's carry waits on them: a command lists the
  commands that must finish before it (`after`), and the scheduler holds it back until they are gone.
  `carryToPad` empties stacks from the top down the same way.
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
- **A staging release closed without merging.** Those crates are still merged work waiting for a release:
  the loaded pallet unloads back into storage the same slow way it was loaded. `.stagingClosed` sets the
  pallet's wish, and `unloadPallet(back: true)` floats each crate onto the slot `storageSlot` gives it.
