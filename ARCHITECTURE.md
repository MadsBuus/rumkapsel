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

Each fresh answer is compared with what was known and the difference becomes a `WorldEvent`
(`Events.swift`): a board column change, a pull request opened or closed, a peer arriving. Counts in the yard
are reconciled, not snapped: crates the board says moved to staging are carried across by minions
(`reconcileYard`), and only what cannot be carried is redrawn.

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
a haul, a fade, a log line. The tick moves minions along their paths and plays their poses. It never re-derives
"what just happened" from raw data.

Shapes mean things: a hexagon is a packed office, a cube is a piece of work, a square strapped crate is a pull
request, a pyramid is a session input. Nothing is round.

## Debts

- `Scene.swift` is still one file. The next cut is moving the crew/board diff and the yard reconciliation into
  the model layer so the scene only ever sees events and counts.
- Minions have no explicit state machine; place, activity, errand and a few timers cooperate. A single owner
  of "what am I doing now" would remove the class of bug where two per-frame rules fight.
- The session-scan cues (a new office's shuttle) still branch on `firstRun` rather than emitting an event.
