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

## Debts

- `Scene.swift` is still one file: nodes, minions, HUD, camera and input share it. Minions are the next thing
  to lift out.
- Minions run one `Command` at a time with a phase index (`Commands.swift`), so "what am I doing now" has a
  single owner. What is left outside it: `place`, `activity` and the wander timers still steer the day, and
  crew minions and shuttles are not actors in the same sense.
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

What still does not: shuttles, rockets and the crew are driven by SceneKit actions and timers rather than
commands; the crate a merged office sends to storage is still found by node name in the scene, so the command's
`from` spot is the office door rather than the exact package position; `Spot` carries a world position, which
means the scene's geometry leaks a little into the model side.

Debugging: hovering a minion pauses it and shows its current command in words, and the same words go
in the log when the command is issued.

## Next: the staging pallet

A staging release (a pull request into the staging branch) needs a picture again now that the staging
rocket is gone. The sequence, all of it commands on one minion, the dispatcher:

1. **The PR opens.** A free minion takes a clipboard and walks to storage. It stops at the storage
   console, a small panel on the wall by the door, and the panel flashes: the order has been placed.
2. **A hover pallet fades in** on the storage floor by the near wall, the side toward the deck. Crates
   stack against the far wall, so the near rows are the pallet's space. If there is no room, or a pallet is
   already out, the dispatcher waits by the console and gets impatient: hops and paces, like a minion
   waiting on you. One pallet per station at a time, the rest queue.
3. **Loading, by magic.** The dispatcher swaps the clipboard for a telekinesis tool and points it at the
   stack: one crate at a time lifts off, floats slowly across and settles on the pallet in neat rows and
   stacks, twelve at most, three rows of four. Only the manifested crates, the ones the PR's commits
   name; the rest stay put. The tool glows while a crate is in the air.
4. **Waiting.** Loaded, the pallet hovers by the near wall, bobbing slowly, the dispatcher beside it,
   until the PR merges. Those crates are station truth, "on pallet", and nothing else may move them.
5. **The PR merges.** The dispatcher pushes the pallet, hands on its edge, out through the storage
   doorway, down the aisle and through the deck doorway, until it stands beside the repository's
   group on the untested row.
6. **Unloading, by magic again.** Crates float off the pallet one by one, slowly, onto their slots on the
   untested row next to any crates of the same colour already there. The empty pallet fades out and the
   dispatcher returns to the lounge.

Facts needed: which crates a staging PR carries (its commits' PR numbers), when it opens, when it merges.
Station truth: a pallet per station, its crates, its position. Commands: `dispatch(pr)`, `loadPallet`,
`pushPallet(to:)`, `unloadPallet`. A closed-without-merge PR unloads back into storage the same way.
The telekinesis tool joins the tool set (goggles, tablet, scanner, hammer, flashlight): a short wand
with a glowing tip, faceted like everything else.

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
placeholder.

## Closed, not merged

Two different closes:

- **An issue's pull request closed without merging.** The work goes nowhere: not storage, not the deck.
  The crate in its office turns red and sits there for ten minutes, then fades out. After that the office
  clears the way a merged one does: a teammate's archives, one's own retires while the session lingers.
- **A staging release closed without merging.** Those crates are still merged work waiting for a release:
  the loaded pallet unloads back into storage the same slow way it was loaded.
