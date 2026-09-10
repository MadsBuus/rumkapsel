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
- Minions have no explicit state machine; place, activity, errand and a few timers cooperate. A single owner
  of "what am I doing now" would remove the class of bug where two per-frame rules fight.
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

Debugging: hovering a minion pauses it and shows its current command in words, and the same words go
in the log when the command is issued.
