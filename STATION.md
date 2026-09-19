# The station

What things are, what they may do, and what may move them. This is the checklist every command is
read against. If a behaviour is not allowed here, it is a bug, however pretty.

## The place

A station is a hallway one tile wide with rooms snapped against it, like the game's: a plaza three by
three round the **monolith**, four arms out of it, the two long ones wandering in runs and jogs with
short alleys off them, every other alley looping back into its arm so there is a way round as well as a
way out, and rooms on both sides of every stretch. The hallway is drawn whole from the
station's name and built outward as rooms need it, so it never re-plans and two machines that share a
station draw the same one. The monolith is the ancient artefact the game's minions researched for new
skills. Here it stands for the outside world: sessions that search the web or talk to other systems send
their subagents to it, and it answers with cones of light, never lightning. The **bay** at the south
arm's end is outside: shuttles land there and nowhere else. The **airlock** sits in the arm's own line
between its end and the bay, a chamber one wide and two deep with a rectangular inner door and a
rectangular hatch, so hallway, chamber and bay read as one straight way out. Everyone who arrives or leaves goes through it, and a leaver waits
inside for the cycle before stepping out. Nobody goes to the bay for any other reason: it is outside. Space walks, visits to other stations and other ships docking are its future. The **yard** along the west side is three
blocks: **storage** (merged work waiting for a release), the **deck** (work on staging, tested on the
row nearest the pad, untested on the far row) and the **pad** (rockets). Blocks connect by doorways and
have aisles down the middle; crates stack against the far walls, aisles stay clear. Nobody stands on a
crate row, however empty the spot: two repositories share a row cell as two columns half a tile apart,
and a body between them is inside one of them. A carrier works from the aisle beside the row.

**Offices** are where work happens. One office per branch. A hexagon crate delivered by shuttle
becomes an office: it lands squarely on the bay's hexagon, aligned with it; a minion carries it to
the doorway of the empty plot and sets it down just inside, by the hallway. The floor is not there
yet. The crate folds open and the office unfolds from it, tile by tile away from the doorway until
the plot is filled, then the name fades in. Until that moment there is nothing on the plot. Closing
is the reverse: whoever is inside steps out to the doorway, the name fades, the floor rolls up tile
by tile toward the door into a hex, and the hex drops away through the floor. Offices belong to whoever has the branch checked out; teammates' offices are darker
and carry their name on the floor, mine carry mine. An office's hover says how old the work in it is
and, when it has gone quiet, for how long: the age counts from the pull request or issue where GitHub
says when that began, otherwise from when the office first stood here. The **dorm**, **lounge** and **bath** stand
together off the corridor, as living quarters would; a galley and an exercise corner belong there too,
since real stations mandate both.

## Shapes mean things

- hexagon: a packed office, on its way to being built
- cube: a piece of work (a commit); ghost cubes are uncommitted work
- square strapped crate: a pull request. The plate on its side is a light: blinking while checks run,
  red when they fail, green when all is well; the whole crate turns red when the PR is closed unmerged.
  In storage and on the deck the light is off; a tested crate on the deck shows green and a sticker on
  the lid, put on as it comes off the row rather than when it is set down again. A crate of your own
  work is strapped in white, so yours pick out of a row of everyone's. Storage looks a little
  unorganised, the deck ordered.
- pyramid: the message a session is working on, one per session, on the cell nearest the door. Messages
  queued behind it stand in a row inward, translucent. A new message shrinks the old cone away; a session
  that waits for you has none.
- pallet: a staging release being assembled
- rocket: a production release; the service tower stands beside it from the moment it is on the pad until
  it goes, its beacon red while the release is untested and dark once cleared; cargo goes up the tower and in
  through the hatch high on the payload section; steam means loaded and waiting
- nothing is round; everything has flat sides

## Things are heavy

- A crate moves only in a minion's hands, on a pallet, or by the wand while loading a pallet. Never
  by itself. Never through a wall, a crate, a minion or a piece of furniture.
- A crate that has been set down does not move again until someone picks it up. The layout is
  drawn around what stands there; it never shoves.
- A crate keeps its slot until it leaves. Stacks are taken from the top and built from the floor. When
  a lower crate is taken, the ones above settle down one, slowly, not in a blink: the yard is low
  gravity, and a crate with nothing under it takes its time coming down.
- Lifting and setting down take time and a posture: crouch on the floor, a slide at waist height,
  over the head for the third level, a hop above that. The crate stays in the hands until it is on
  its slot.
- A carrier with carries queued behind it hurries: quicker on its feet, the same lift and the same
  set-down, and it says so.
- A pallet is pushed, from behind, along one axis at a time, slowly, and only where a pallet fits.
- A shuttle lands only in the bay and leaves before anyone walks under it. A rocket leaves only
  with its cargo aboard.
- A rocket is loaded at its foot: the carrier walks up to the hull, an arm's length off, and sets
  the crate down on the loading hatch at its base; the hatch takes the crate up into the hold, the
  crate shrinking as it goes since the rocket is far too small for it, and the hatch closes. The
  rocket grows a little with what it holds. Nothing is thrown, nothing goes in from a corner of the pad.
- A moving pallet is as solid as a standing one. When the floor changes under a walk, the walk is
  re-planned; nobody finishes a leg through something that arrived in the way.

## Minions

- A minion does one thing at a time, and it is always something with a name: "carrying #5210 to
  the deck". Hover it and it tells you.
- An order is taken over only at a step where it can be: while walking, yes; mid-lift, no. A new
  order does not reset an old one; it re-plans from where the minion stands.
- A change of orders is visible: the minion stops, stands a beat with its head up, as if wondering,
  then goes. The same beat everywhere. A message from you cuts the beat short and it hurries.
- Minions walk around things, never through, and stand an arm's length from what they work on,
  facing it. Two never share a couch, a bed, a shower or a crate.
- Minions keep to the middle of the hallway, never brushing the walls, and never cut a corner
  through a room. With something in their hands they need even more room.
- Two never slide through each other: a body is solid at the middle of its tile, standing or lying.
  A walker who finds someone in its way, standing or coming, drifts a third of a tile to its own
  right, passes, and drifts back onto its line; the other does the same, so two meeting
  head-on pass without either stopping or planning again, in a doorway as anywhere. Nobody ever
  stops for anybody: where the floor leaves no side to step to, two may overlap for a moment. The
  pass is for somebody in the way, so somebody standing well off the line is walked past squarely,
  and a pass that never resolves — somebody standing where the walker is going, somebody keeping
  station alongside — is given up on after a stride or two rather than held the whole walk. Someone
  on a couch or in bed is on the furniture, off the walkway, and in nobody's way. Nobody settles in
  a doorway. Every timing on the station runs on the station clock, so holding space speeds all of
  it up alike.
- A chore never stands in a doorway, the yard's or a room's: a body standing there shuts it.

## Tasks and work

- A closed issue is finished work, whatever column the board left it in: it never makes an office.
- An issue is a task; a pull request is work done for it. A crate is a task: with a board, the issue
  the pull request closes, the pull request's own number when it closes none. One crate per task,
  however many pull requests it took; the crate's hover names the task, what it is called and whose
  work it is, and its click opens the task.
- Every repository has its own way to production, and nobody sets it up. It is read from what the
  repository did: the branch most work merges into is the trunk, the branch releases end in is
  production, and a branch released onward into production is staging. Where there is no history, the
  branch names decide: develop, else main or master; staging where it exists; production, else master
  or main. A file .github/rumkapsel.json on the repository's default branch overrides both, for everyone.
  Releases come from the trunk, from staging, or from a release or hotfix branch. A repository with no
  releases and a workflow deploying on every push to its trunk ships on merge: the merged crate goes to
  storage and straight up in a small rocket of its own. One with no release branch and no such workflow,
  but which tags what it ships, ships on tags: what the trunk has that the newest tag has not is waiting
  in storage, and a tag nobody has seen before launches it. The newest tag is the newest by date, never
  by name, and a tag that is not a version is not a release. With staging a
  repository's rocket loads from the deck, without from storage. The board fills its yard only if it
  moves work through the storage and QA columns, or its file says so; otherwise its yard comes from git.
- Releases are made of pull requests. What git says a release carries is translated to tasks on the
  floor where the link is known, and stays a pull request where it is not.

## Decon

- A bot's pull request (dependabot and friends) is not work: it gets no office and nobody on the
  floor. It is an object of unknown origin, and it waits in **decon**, the chamber at the back of
  storage with a hatch in its back wall. Objects come in through the hatch, never by shuttle and never
  through the airlock: the hatch light flashes, and that is all the fuss an update gets. They stack
  by repository like storage does, a dozen at most, small and dark with the unscreened green on the
  plate, one pile per repository; the rest are counted in the tooltip. A floor that fills is the point: unscreened updates are meant to be seen.
- An object whose pull request merges is cleared: whoever is free pulls it straight out, wherever it
  is in its stack, and whatever was on top drops; nobody is careful with unscreened things. They carry
  it through the doorway into storage next door, and from there it is a crate like any other. It waits for the release, rides the
  pallet and the rocket, and counts in the rocket's cargo, since a release that ships six bumps and a
  feature ships seven things. It stays grey wherever it goes, so storage still reads as "two real,
  five bumps". Nothing from decon is ever QA's business: on the deck it counts as tested from the start.
- An object whose pull request closes unmerged is ejected and forgotten. Nothing is carried.

## Bodies

- One owner per body. The command in hand owns a minion's place, path and pose. Nothing else
  writes them: a session's refresh, a floor change or the panel may only ask, and an ask waits
  its turn behind whatever is in hand.
- Every command is either moving or waiting on a fact it names: the crate to come down, the ship
  to lift off, the release to merge. Standing still in the same phase for ten seconds, waiting on
  nothing named, is a stall.
- A stall is given up, and said so in the log. Giving up loses nothing, because the work is not
  kept in the body: a carry goes back into the queue from where the crate now lies, an office's
  crate stays on the floor for the next free hands, a visit ends. Truth then re-issues what it
  still wants, to someone else first. What conditions took away is not retried; the body is free.
- A wait on a named fact has its time, not forever: ninety station seconds without the fact and it
  is given up like any stall. Standing by a pallet for a release is the errand itself and exempt.
- A delivery is picked up. Period. A new office's crate is an order with a number that the shuttle,
  the crate on the floor and the carrier all share, whatever the office is called by the time it
  lands. A crate on the bay floor with nobody fetching it goes to the next free hands, its own
  session's worker first; it goes into whatever room its order names now; if that room is gone it
  folds away where it lies. It is never left standing. A bay slot is free only when nothing lies on
  it and no ship is bound for it.
- Right of way. Of two who meet, one holds and the other goes round, always the same one: a load
  before a job, a job before rest, and names settle a tie. The one who holds steps round after a
  while in case the other is not moving at all.

## Sharing

- Only offices worked in within the last twelve hours are shared, and only in repositories ticked for it.
- A shared office carries its life: who is in it and whether they are working, waiting or asleep, their
  message cones, and its pull request with the checks. A peer's minion is a real minion in a teammate's grey.
- An office on GitHub is solid. One only on the peer's machine is outlined while idle, and solid with its
  outline kept as a mark while someone works in it. An office its peer calls idle is dimmed.
- An office a connected peer stops claiming goes on the next pass; a peer who disconnects has theirs held
  for a day, so their return does not move it.

## Rooms

- A room opens to the corridor through one doorway: the room tile that touches the hallway. Nothing
  sits in it, no bed, couch, shower, fixture or sign, and nobody settles there; a room with its
  door tile taken is shut to everyone else.
- Fixtures stand along the walls away from the door, one minion to each: a bed, a couch, the bowl,
  the shower, a piece of gym gear. The room's name is cut into the far corner and nothing covers it.
- The middle of a room stays clear to walk through; a room holds as many as it has free tiles.
- The dorm, lounge and bath touch each other off the corridor, the gym beside them; the yard blocks
  join by doorways of their own and keep their aisles clear.
- A visit lasts its whole time: a shower is two to three minutes of water from the nozzle over the shoulders,
  with the pixels where they belong, then a few seconds at the rail with the towel over the shoulders before going. Nobody wanders off mid-shower. A pee is a sit: turn round, down
  onto the bowl, back to the tank, a shuffle on the seat now and then, up again as the time runs out,
  and the bowl flushes behind.
- Speed is what the task needs, not who you are: carrying is slow, it is heavy; pacing is another
  pace, a stroll a third; getting up from bed is slow, then quicker.
- Minions never occupy the same spot and wait for each other to pass in a narrow place.
- Social life exists: two talking, a game, a party, sports. All of it is idle time, never work.
- When a rocket stands loaded and steaming, the idle drift toward the pad to watch.
- A rocket is loaded from the front: the carrier walks straight to the tile before its hatch, sets
  the crate down at its foot, and the crate goes in. Nobody walks through a rocket.
- Rules of the day: work at the office; hop for a minute when done; pace while waiting; read on the
  couch when quiet by day, sleep in the dorm by night; a shower after long work, a pee after short,
  chores when bored, a turn in the gym when the lounge gets dull; leave through the airlock when
  there is nothing left to do.
- The gym is one room off the living cluster with four fixtures, a treadmill, a bench with a barbell,
  a bag and a mat, one minion to each, a turn lasting its whole time. Loungers who stand near each
  other talk; the rest stretch, look round, shuffle and yawn now and then.
- A lounger has one idle clock, two to five minutes. When it runs out one thing is picked: a look round
  the station most often, a turn in the gym by day, the bath, or staying on the couch with a book.
  Leaving the lounge does not reset it; it starts again once the lounger is back. A visit's time starts
  when the minion arrives, never when it sets off. Roamers keep apart, except to watch a steaming rocket.
- You may pick a lounger's next thing from its bubble: the gym, bed, a book on the couch, the shower or
  the bowl, given the way the idle clock gives it. One with a job in hand, or at work, is not for picking.

## The world and the station

- Sources are truth about the world. The station is truth about the floor. They may disagree for
  as long as it takes a minion to carry something.
- A first answer from any source is never news. Only changes after it are. History is for GitHub
  and other boring tools; the station shows now.
- Nothing appears or disappears without a cue: a shuttle, a carry, a fade, a red crate that sits ten
  minutes before it goes. Offices are held for those who left before they clear.
- Counts follow the source through the minions' hands. What cannot be carried is redrawn, once,
  and only if nobody is holding it.

## Names

Minions may get names, or ridiculous job titles in the manner of The Office or Severance. Later.

## Ideas parked

Weightlessness when the station loses gravity. Enemy ships were the game's; this is not a game.

## Humour, kept dry

The station takes its work seriously and itself not at all. It has a voice: the log is the station's
computer speaking, plainly and a little dry. Minions pee with the door open and a
pixel patch. The QA walker paces the rows like a foreman. The dispatcher gets impatient. The log
speaks plainly: "web: a pallet floats out in storage". Jokes live in the words and the routines,
never in the shapes.
