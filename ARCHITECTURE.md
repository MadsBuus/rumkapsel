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
