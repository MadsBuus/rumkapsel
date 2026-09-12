# The station

What things are, what they may do, and what may move them. This is the checklist every command is
read against. If a behaviour is not allowed here, it is a bug, however pretty.

## The place

A station is a corridor cross with rooms snapped against it, like the game's. The **monolith** at the
north end is the ancient artefact the game's minions researched for new skills. Here it stands for the
outside world: sessions that search the web or talk to other systems send their subagents to it, and
it answers with cones of light, never lightning. The **bay** at the south end is outside: shuttles land
there and nowhere else. The **airlock** sits in the corridor's own line between its south end and the
bay, a 2x2 chamber with a rectangular inner door and a rectangular hatch, so corridor, chamber and
bay read as one straight way out. Everyone who arrives or leaves goes through it, and a leaver waits
inside for the cycle before stepping out. Nobody goes to the bay for any other reason: it is outside. Space walks, visits to other stations and other ships docking are its future. The **yard** along the west side is three
blocks: **storage** (merged work waiting for a release), the **deck** (work on staging, tested on the
row nearest the pad, untested on the far row) and the **pad** (rockets). Blocks connect by doorways and
have aisles down the middle; crates stack against the far walls, aisles stay clear.

**Offices** are where work happens. One office per branch. A hexagon crate delivered by shuttle
becomes an office: it lands squarely on the bay's hexagon, aligned with it; a minion carries it to
the doorway of the empty plot and sets it down just inside, by the hallway. The floor is not there
yet. The crate folds open and the office unfolds from it, tile by tile away from the doorway until
the plot is filled, then the name fades in. Until that moment there is nothing on the plot. Closing
is the reverse: whoever is inside steps out to the doorway, the name fades, the floor rolls up tile
by tile toward the door into a hex, and the hex drops away through the floor. Offices belong to whoever has the branch checked out; teammates' offices are darker
and carry their name on the floor, mine carry mine. The **dorm**, **lounge** and **bath** stand
together off the corridor, as living quarters would; a galley and an exercise corner belong there too,
since real stations mandate both.

## Shapes mean things

- hexagon: a packed office, on its way to being built
- cube: a piece of work (a commit); ghost cubes are uncommitted work
- square strapped crate: a pull request. The plate on its side is a light: blinking while checks run,
  red when they fail, green when all is well; the whole crate turns red when the PR is closed unmerged.
  In storage and on the deck the light is off; a tested crate on the deck shows green and a sticker on
  the lid. Storage looks a little unorganised, the deck ordered.
- pyramid: the message a session is working on, one per session, on the cell nearest the door. Messages
  queued behind it stand in a row inward, translucent. A new message shrinks the old cone away; a session
  that waits for you has none.
- pallet: a staging release being assembled
- rocket: a production release; steam means loaded and waiting, a hold ring means untested
- nothing is round; everything has flat sides

## Things are heavy

- A crate moves only in a minion's hands, on a pallet, or by the wand while loading a pallet. Never
  by itself. Never through a wall, a crate, a minion or a piece of furniture.
- A crate that has been set down does not move again until someone picks it up. The layout is
  drawn around what stands there; it never shoves.
- A crate keeps its slot until it leaves. Stacks are taken from the top and built from the floor. When
  a lower crate is taken, the ones above settle down one, slowly, not in a blink.
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
  facing it. Two never share a couch, a bed, a shower or a crate. Two never stand on the same spot,
  not even at the start of the day: they arrive one by one, or spread before they set off.
- Minions keep to the middle of the hallway, never brushing the walls, and never cut a corner
  through a room. With something in their hands they need even more room.
- A visit lasts its whole time: a shower is ten seconds of water from the nozzle over the shoulders,
  with the pixels where they belong. Nobody wanders off mid-shower.
- Speed is what the task needs, not who you are: carrying is slow, it is heavy; pacing is another
  pace, a stroll a third; getting up from bed is slow, then quicker.
- Minions never occupy the same spot and wait for each other to pass in a narrow place.
- Social life exists: two talking, a game, a party, sports. All of it is idle time, never work.
- When a rocket stands loaded and steaming, the idle drift toward the pad to watch.
- Rules of the day: work at the office; hop for a minute when done; pace while waiting; read on the
  couch when quiet by day, sleep in the dorm by night; a shower after long work, a pee after short,
  chores when bored, a turn in the gym when the lounge gets dull; leave through the airlock when
  there is nothing left to do.
- The gym is one room off the living cluster with four fixtures, a treadmill, a bench with a barbell,
  a bag and a mat, one minion to each, a turn lasting its whole time. Loungers who stand near each
  other talk; the rest stretch, look round, shuffle and yawn now and then.

## The world and the station

- Sources are truth about the world. The station is truth about the floor. They may disagree for
  as long as it takes a minion to carry something.
- A first answer from any source is never news. Only changes after it are. History is for GitHub
  and other boring tools; the station shows now.
- Nothing appears or disappears without a cue: a shuttle, a carry, a fade, a red crate that sits ten
  minutes before it goes. Offices are held for those who left before they clear.
- Counts follow the source through the minions' hands. What cannot be carried is redrawn, once,
  and only if nobody is holding it.
- Truth before the picture. A carry that has not landed within its patience is set down where its
  order says, whoever was carrying it, and the log says the station caught up. The ledger is never
  more than one patience behind the source; the picture is right whenever the floor can manage it.

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
