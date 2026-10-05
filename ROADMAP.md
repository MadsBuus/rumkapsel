# Roadmap

What is open, so any session can pick it up. Each item says what it is and why, not how. When something is
done, take it out; when a new thing is agreed, put it in. *Next* is agreed and wanted soon; *Ideas* were floated
and deliberately not started.

## Next

### The deploy flight
The flight is `FlightCraft.swift` (the rocket), `Plating.swift` (its hull, baked into `Resources/Plating` by
`--bake-plating`) and the cameras in `Mission.swift`. `rumkapsel --look-dev <png> [shot]` renders a still in a
couple of seconds; judge looks against references and Mads' eyes, not alone.

- **Colonies as spaceports.** The colony at landing looks like a cheap Roblox game. It should read like a Star
  Wars planet spaceport. The camera stays simple; the colony carries the shot.
- **Stay at the colony after touchdown.** Hold the colony camera a while longer: the gases slowly dispersing,
  a slow zoom toward the rocket.
- **A better landed overlay.** "web is live / Landed after 39s" is not cool enough.
- **Stars.** The flight has its own point-star sky all round; Mads only saw it now and then. Check it reads at
  every zoom of the long lens.
- **The station's rocket and the flight's rocket have drifted apart.** Undecided. Proposed: the flight rocket
  stouter (about 7:1); the station rocket a little slimmer, same height, with the flight's look (nose and band in
  the repository's colour, slim fins, the six black flaps, the engine cluster), still faceted and untextured.

### The order board (`Board.swift`)
Agreed design: every piece of work is an order with a rank, taken at safe points, put back when preempted; idle
is the empty board. Slices 1–6 are done.

- **Minimum headcount.** The station always keeps enough bodies free to take orders, so nothing deadlocks or
  starves.
- **The playbook posts orders.** An entry lays its floor, starts with an empty board and posts its one order,
  replacing the "Hands: one free" teleport.

## Bugs and loose ends
- **0.55 is not notarised.** `release.sh` found no `rumkapsel` keychain profile when run from a Claude session,
  so a fresh download may meet Gatekeeper's warning. Release from Mads' own terminal, or store the profile where
  the session can reach it.
- **An office that flaps.** The old `claude/launch-flight` office (worktree `release-strategies-detection`) opens
  and archives every few seconds in the station log. Its branch is merged.
- **A ghost crate on the conveyor**, seen once in the real station. Waiting to see it again; a playbook entry with
  two crates queued at the belt may show it.
- **Gate placements typed in by hand** (belt ends, operator and monitor offsets, the tested stack, rocket foot and
  tower) should be measured from the things they belong to, like the welder now is.
- **The security robot** at the gate does not work the right way; a separate thread was started for it.
- **Frame cost**, from 0.41: the session scan (89 ms in one frame) and `gh.crew` (44 ms worst) on the main thread.
- **`proj:rumkapsel`**: the main checkout's office never folds. Ask whether a project should hold a desk with
  nothing running in it.

## Ideas
Floated, not asked for. Offer them when they fit; don't start them unasked.

- **A camera during `release.sh`.** Tag-shipped repositories have no flight; the station could watch for
  `release.sh` running locally and fly along through notarisation.
- **Builds that say what they are.** The app shows its worktree, branch and commit in a corner, so it is clear
  which copy is running.
- **Hallways one tile wide**, and **offices smaller** relative to the work in them.
- **A crate relay**: a carrier meeting a free walker hands the crate over and they swap orders.
- **One session, several PRs, one office**: crates stack in the office of the session that made them.
- **Themes as installable packs**, listed from what is on disk, with Classic as the fallback.
- **A common workplace across teams** on the same LAN: neighbours share the building, not their work or names.
  Needs a team key first.
- **A pillow on the beds**, once it is known which end the head goes.
