# Roadmap

What is open, so any session can pick it up. Each item says what and why, not how. Take an item out when
it is done; put a new one in when it is agreed. **Next** is agreed and in order; **Ideas** were floated
and are not started unasked.

## Next

1. **The playbook snaps its setup.** An entry lays its floor straight to the facts, so only the moment it
   is about animates.
2. **The launch cam.** A fixed pad and one launch clock, taken from the climb. A patch exists.
3. **The tip's colour band** at the thruster belt, and dark legs. A patch exists.
4. **A crate-focused replay.** One crate's story from the event log, played back in the scene.
5. **One `Source` protocol** for intake, so every source reports the same way.
6. **The last scene glue into playback.** Office floor labels give way to the model's office cells;
   neighbours' minions driven by playback.
7. **A give-up never drops a crate in the yard's lanes.** Then crates in the lanes can be obstacles.
8. **Later: neighbours share facts and events** instead of offices and GitHub answers.

## Walking and bodies

- **Right of way.** Of two who meet, one holds and the other goes round, always the same one: a load before
  a job, a job before rest, names settle a tie. Passing is a lean on the walker's own line, so two meeting
  head-on overlap.
- **A crate in the hands has no footprint**, so a carrier is planned as if empty-handed.
- **The shuttle clears before anyone walks under it.** A carrier waits only until the ship starts to rise
  (`shipStillOver`), and an arriving minion's hold is a fixed 8.1 s matching the flight's phases
  (`arriveByShuttle`) rather than read from them.
- **Teammates hidden leave properly.** Turning teammates off despawns them at once, with no shuttle out.
- **Getting up from bed** is a hold, then full speed; it should start slow and quicken.
- **Set-downs by level**: a careful crouch at the floor, a slide onto the top at waist height, over the
  head and slide in at the third level, a hop above that; the pickup mirrors each. The postures exist; the
  slides do not.
- **Roam spots with something to look at**, rather than any clear spot.

## The order board

- **A minimum headcount**: enough bodies always free to take orders, so nothing deadlocks or starves.
- **The playbook posts orders.** An entry starts with an empty board and posts its one order, so the
  simulator's "Hands: one free on the deck" press and its use in the playbook can go.

## Sources and stages

- **Deployments as stages**: QA when a staging deploy lands, Shipped when the production deploy succeeds,
  environment approvals as Cleared, and deploys outside GitHub Actions. Deployments are in every workflow
  answer but report nothing.
- **Who counts as outside**: only bots go to decon; a stranger's pull request could too. Settings had an
  answer for it that nothing read, so it went.
- **Ticket systems** (Jira, Linear) in the board's place; incoming bugs (Sentry and the like) as something
  arriving at the station; the state of the infrastructure.

## The deploy flight

The flight is `Scene/FlightCraft.swift`, `Scene/Plating.swift` and the cameras in `Scene/Mission.swift`;
`--look-dev` renders a still. Judge looks against references and Mads' eyes, not alone.

- **The opening shot.** Onboard, the flight starts from the old lifter's down cam; the undock wants its
  own shot.
- **Colonies as spaceports.** The colony should read like a Star Wars planet's spaceport. The camera stays
  simple; the colony carries the shot.
- **Stay at the colony after touchdown**: the gases slowly dispersing, a slow zoom toward the rocket.
- **A better landed overlay.** "web is live / Landed after 39s" is not cool enough.
- **Stars** that read at every zoom of the long lens.
- **A camera during `release.sh`**: tag-shipped repositories have no flight; the station could fly along
  through notarisation.

## Walking the station

- **Small things** along the hallways and in the rooms, for the walk to find.
- **Up close, everything matches the walls**: floors, rockets, crates at the walls' level of detail, kept
  soft so the top view still reads the same.
- **Windows** in the outer walls.
- **An invisible block in new hallway**, seen once after offices arrived; `station.log` has a `walk` line
  saying what stopped the walker if it comes back.

## Themes

- **A look places its idle areas and draws its office overlays** (failing checks, dust, the provisional
  frame); both are the plan's and the scene's.
- **Stations as worlds**: moving between stations under a theme, each drawn as a world of its own, and
  what the whole view becomes.
- **Themes as installable packs**, listed from what is on disk, Classic the fallback.
- **The game's palette, switchable**: rymdkapsel's space `#0E1117`, hallway `#81655B`, unbuilt `#434242`
  and its six room hues as a second palette beside ours.
- **A smaller minion**, about 0.85 of the size, behind a setting, watched for what it breaks in the poses,
  the hands and the crate arcs.

## Ideas

- **Spacewalks**: a minion suited, on its jetpack, out through the field. What for is open.
- **Visits** to other stations, and other ships docking at the bay.
- **A galley** in the quarters, since real stations mandate one.
- **Social life**: two talking, a game, a party, sports, all of it idle time.
- **Names** for minions, or ridiculous job titles in the manner of The Office or Severance.
- **Weightlessness** when the station loses gravity.
- **Abandoned offices** that deteriorate rather than only go dark.
- **A crate relay**: a carrier meeting a free walker hands the crate over and they swap orders.
- **One session, several pull requests, one office**: crates stack in the office that made them.
- **Smaller offices** relative to the work in them.
- **A common workplace across teams** on the same network: neighbours share the building, not their work
  or names. Needs a team key first.
- **Builds that say what they are**: the worktree, branch and commit in a corner, so it is clear which copy
  is running.
