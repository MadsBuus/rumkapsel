# The station

What things are, what they may do, and what may move them. This is the checklist every command is
read against. If a behaviour is not allowed here, it is a bug, however pretty.

## The place

A station is a corridor cross with rooms snapped against it, like the game's. The **monolith** at the
north end is the station's computer; standing at it is how you talk to it. The **bay** at the south
end is outside: shuttles land there and nowhere else. The **airlock** is the only door to the bay;
everyone who arrives or leaves goes through the hatch. The **yard** along the west side is three
blocks: **storage** (merged work waiting for a release), the **deck** (work on staging, tested on the
row nearest the pad, untested on the far row) and the **pad** (rockets). Blocks connect by doorways and
have aisles down the middle; crates stack against the far walls, aisles stay clear.

**Offices** are where work happens. One office per branch. A hexagon crate delivered by shuttle
becomes an office. Offices belong to whoever has the branch checked out; teammates' offices are darker
and carry their name on the floor, mine carry mine. The **dorm**, **lounge** and **bath** stand
together off the corridor, as living quarters would.

## Shapes mean things

- hexagon: a packed office, on its way to being built
- cube: a piece of work (a commit); ghost cubes are uncommitted work
- square strapped crate: a pull request; the plate on its side is its state, a sticker on the lid means tested
- pyramid: something you said to a session, waiting to be worked
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
- A pallet is pushed, from behind, along one axis at a time, slowly, and only where a pallet fits.
- A shuttle lands only in the bay and leaves before anyone walks under it. A rocket leaves only
  with its cargo aboard.

## Minions

- A minion does one thing at a time, and it is always something with a name: "carrying #5210 to
  the deck". Hover it and it tells you.
- An order is taken over only at a step where it can be: while walking, yes; mid-lift, no. A new
  order does not reset an old one; it re-plans from where the minion stands.
- Minions walk around things, never through, and stand an arm's length from what they work on,
  facing it. Two never share a couch, a bed, a shower or a crate.
- A visit lasts its whole time: a shower is ten seconds of water from the nozzle over the shoulders,
  with the pixels where they belong. Nobody wanders off mid-shower.
- Speed is what the task needs, not who you are: carrying is one pace, pacing another, a stroll a third.
- Rules of the day: work at the office; hop for a minute when done; pace while waiting; read on the
  couch when quiet by day, sleep in the dorm by night; a shower after long work, a pee after short,
  chores when bored; leave through the airlock when there is nothing left to do.

## The world and the station

- Sources are truth about the world. The station is truth about the floor. They may disagree for
  as long as it takes a minion to carry something.
- A first answer from any source is never news. Only changes after it are.
- Nothing appears or disappears without a cue: a shuttle, a carry, a fade, a red crate that sits ten
  minutes before it goes. Offices are held for those who left before they clear.
- Counts follow the source through the minions' hands. What cannot be carried is redrawn, once,
  and only if nobody is holding it.

## Humour, kept dry

The station takes its work seriously and itself not at all. Minions pee with the door open and a
pixel patch. The QA walker paces the rows like a foreman. The dispatcher gets impatient. The log
speaks plainly: "web: a pallet floats out in storage". Jokes live in the words and the routines,
never in the shapes.
