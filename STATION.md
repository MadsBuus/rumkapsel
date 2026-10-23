# The station

What things are, what they may do, and what may move them. Every behaviour is read against this. If
something is not allowed here, it is a bug, however pretty. Where the facts come from is
[WIRING.md](WIRING.md); how the code is cut is [ARCHITECTURE.md](ARCHITECTURE.md); what is still to
build is [ROADMAP.md](ROADMAP.md).

## Things

These are the words, in code, docs, settings and the log. A theme may draw them differently and call
them what it likes on screen (`Vocabulary` in `State/Theme.swift`), but underneath they are these.

| Thing | What it is |
|---|---|
| **minion** | a session at work, a teammate, or a neighbour's session |
| **probe** | a session's subagent: a small hovering machine, launched from its minion and docking back with it |
| **work** | one piece of work, with one id and every name it goes by: its branch, its checkout folder, `repo#PR`, `repo#issue` |
| **office** | the room where one piece of work takes place: one office per work |
| **shuttle** | brings a new office, or a new minion, to the bay |
| **bay** | the hangar where shuttles land |
| **cone** | the message a minion is working on |
| **cube** | a commit; a ghost cube is uncommitted work |
| **crate** | a pull request, or the issue it closes |
| **yard** | the room merged work crosses on its way out: storage, the staging area and the cleared rows |
| **storage** | the waiting rows: merged crates wait here for a release; `waiting` in code |
| **staging area** | the testing rows, where crates are tested; `testing` in code, `deck` in places |
| **cleared rows** | tested crates, ready to ship |
| **decon** | where pull requests from outside wait to be screened |
| **launchpad** | outside the pad wall: five pad slots and the drones' rack |
| **rocket** | a release to production; a hotfix gets its own |
| **drone** | one of three on the pad: welds a rocket's tip, and rings the vortex |
| **vortex** | at a launch, pulls the rocket's crates off their rows into the rocket |

## Facts first, the picture catches up

- What the station knows changes the moment it hears it. A merged pull request's crate is in storage
  then, not when a minion gets there. The counts in the hover and the log lines in the corner read what
  is known, so they say it at once.
- Everything that moves on screen is the picture catching up to what is known: a carry, a shuttle, an
  office unfolding, a rocket docking. It never shows a step that is not on the way, and never ends
  anywhere else.
- The picture never changes what is known. A minion setting a crate down tells nobody anything.
- A first answer from any source is history, not news. It is shown as it stands, at once, and nothing
  is said. Only changes after it are news.
- The picture is skipped, shown as it is known at once, when the app starts, when a frame comes more
  than five station seconds after the last (a sleep), for anything a first answer placed, and from
  Develop › Skip to the Facts.
- A crate, office or rocket whose catching up has not moved for ninety station seconds is shown where
  it belongs, and `station.log` says so. A rocket waits as long as its deploy usually takes, when that
  is longer.
- Holding space plays the picture four times as fast. What is known keeps the wall clock.

## The place

A station is a hallway one tile wide with rooms snapped against it, like the game's: a plaza three by
three round the **monolith**, arms out of it that wander in runs and jogs with short alleys off them,
and rooms on both sides. The floor is drawn offline per theme (`floor/`) and lit slot by slot as offices
arrive, so it never re-plans and two machines that share a station draw the same one. Hallway that no
office needs is taken up again from its far end once nobody is on it, so a quiet station shrinks back.

The monolith is the ancient artefact the game's minions researched. Here it stands for the outside
world: a session or a probe searching the web goes to it, and it answers with cones of light, never
lightning.

The **bay** at the end of the south arm is a hangar under the hull, open to space at its mouth behind
the **field**: a sheet of light that holds the air in and lets ships through. Shuttles fly in through
the field and land in the bay and nowhere else, on a honeycomb of berths; the berth a ship is flying
into burns in its repository's colour until its crate has been carried in. Everyone who arrives steps
off a shuttle there and everyone who leaves boards one. Nobody goes to the bay for any other reason.

The **dorm**, **lounge**, **bath** and **gym** stand together off the hallway, as living quarters would. The
**galley** is one tile off the lounge and opens into it, not onto the hallway: a counter along its back wall
with a coffee machine, a food printer and two spare mugs. It takes a tile no office or hallway ever would,
away from the hallway where the plan allows, and where the monolith does not hide it.

Each of these fixed rooms has its own tiles in the plan and stands on them; an office in the way moves to
a free slot, and a fixed room is never put anywhere else. If its tiles cannot be had, it waits and
nothing moves for it.

**Mission control** stands by the pad, its far wall a window onto it. Three consoles face the boards
raised on a steel gantry along the north wall, and a holo table in the middle shows the station's little
system turning above it at eye height. There is room to walk in round the table; **M** walks you in.
The boards are an annunciator with a row of lamps per repository (deploy, checks, waiting, release,
errors, alarm), two old monitors with live feeds of the pad and the bay, and a screen for errors and
alarms that shows no signal until a source feeds it. The feeds refresh often only when you are close.

## Air and weight

The hull is the line between air and none. Inside there is air and a low gravity, and work is done by
hands: minions, who stand for the sessions and the people, for whatever still needs judgement. Outside
there is neither, and work is done by **drones**: small faceted machines that fly on puffs of thrust,
never propellers, and stand for what machines do on their own. Nobody works outside and no drone comes
in. The pad wall's field is the hand-off: up to it a person is still needed, past it nobody is.

- Inside, things fall slowly: a crate with nothing under it settles rather than drops.
- Outside, nothing falls and nothing is let go of. The pad holds the rocket.
- The bay is inside: a shuttle lands there and minions walk to it. Space is only past the field.
- Idle drones wait in their rack at the walkway's end of the pad, and that is all they do when the
  pad is quiet.

## The yard

The yard is one room beside the station, five tiles wide and eight deep, with no wall inside it. Work
moves through it one way: in from the hallway at the back, out through the field to the pad at the front.

- **The walkway** runs down one side from the hallway to the field. **Aisles** cross between the zones.
  Nothing stands on either.
- **Three zones**, two rows of four tiles each, an aisle between them, the floor telling them apart:
  **cleared** by the field, **testing** in the middle, **waiting** (storage) at the back. A repository
  with no staging keeps its merged work in storage until it ships. Each zone's word is painted on the
  walkway beside it.
- **A repository has a home lane**, the same in every zone, kept for as long as it has crates in the
  yard and given up when it has none. The first repository takes the lane by the walkway, the next a
  lane further out, and the lanes between fill only when the yard is busy. With every lane held, a new
  repository shares the least loaded one.
- **A pile grows from its first crate**: beside it, in front of it, then on top, never above three.
  One that outgrows its lane borrows the nearest room, never above three either.
- **A stray goes home.** A crate standing outside its home lane is moved home as soon as the lane has
  room, one at a time, at the lowest priority: real work always comes first.
- **On the rows, the crates above go first.** Before a lower crate is taken, the crates on it are
  moved aside, each to its own place; a crate with nowhere to go is set down nearby and brought back.
- **A crate's light** says where it is: off in storage, amber on the testing rows, green on the
  cleared rows.
- **Carriers** work the near row from the aisle at arm's length. A tile on the row behind is reached
  across the near one, with a toss when a crate stands there: the gravity is low, so it drifts over.
- **A repository that doesn't ship** keeps a merged crate in storage for a day; then it fades where it
  stands, carried by nobody (`Rules.unshippedFor`, on the tick).
- **A staging release** that merges sends its repository's stored crates across to the testing rows,
  whether or not the board has moved their cards: what git finds on staging is on staging.
  A tester's tick sends a crate to the cleared rows.
- **The pad wall** is a field, the same sheet the ships fly through: glass until a vortex forms, then
  striped while it runs.
- **Decon** is a room behind storage, entered from the walkway's back end: see **Decon**.
- **The pad** is outside, under open space: five pad slots and the drones' rack.

## Shapes mean things

- hexagon: a packed office, on its way to being built
- cube: a commit; ghost cubes are uncommitted work
- square strapped crate: a pull request. The plate on its side is a light: blinking while checks run,
  red when they fail, green when all is well; the whole crate turns red when the pull request is
  closed unmerged. In the yard the light says the zone instead; a tested crate wears a sticker on the
  lid. A crate of your own work is strapped in white, so yours pick out of a row of everyone's.
- pyramid: the message a session is working on, one per session, on the cell nearest the door.
  Messages queued behind it stand in a row inward, translucent. A new message shrinks the old cone away;
  a session that waits for you has none.
- drone: a machine at work outside the hull; never in a repository's colour.
- rocket: a release on its way down to production, the planet below where the users live (see
  **Rockets**).
- nothing is round; everything has flat sides.

## Crates

- A crate moves only in a minion's hands, tossed by one across a row, or pulled by the vortex. Never by
  itself, never through a wall, a crate, a minion or a piece of furniture.
- A crate that has been set down stays until someone picks it up. Nothing shoves it.
- Stacks are taken from the top and built from the floor. When a lower crate goes, the ones above settle
  down one, slowly: the yard is low gravity.
- Lifting and setting down take time and a posture, from a crouch at the floor to a hop above the
  third level. The crate stays in the hands until it is on its place.
- A carrier with carries queued behind it hurries: quicker on its feet, the same lift and set-down,
  and it says so.
- Moving a crate to the cleared rows outranks moving one into or out of storage; tidying a stray
  comes last.
- A crate closed unmerged turns red in its office and goes ten minutes later.

## Offices

- One office per piece of work. It belongs to whoever has the branch checked out; teammates' offices are
  darker and carry their name on the floor.
- A workspace holds one office at a time: the one for the branch checked out there, decided by its own
  session, never by a subagent or an older transcript in the same folder. A workspace's office without a
  branch becomes the branch's office when one is checked out; one for another branch ends.
- A piece of work belongs to one repository. Branches with the same name in two repositories are two
  pieces of work, and an office never changes repository.
- An office arrives in one of three ways. By **shuttle**, for a new session or a teammate's new work: the
  shuttle lands a hexagon on its berth, a minion carries it to the doorway of the empty plot and sets it
  down just inside, the hexagon folds open and the floor unfolds from it tile by tile away from the door,
  then the name fades in. Until then there is nothing on the plot. A neighbour's office **fades** in where
  the neighbour put it, unless it is under three minutes old, when it too comes by shuttle. Offices that
  were already there when the app starts are simply **there**.
- A delivery is picked up, always. The shuttle, the crate on the bay floor and the carrier share one
  order, whatever the office is called by the time it lands. A crate nobody is fetching goes to the next
  free hands, its own session's minion first. If the office is gone by then, the crate folds away where
  it lies.
- An office ends on the facts alone: a teammate's or a stray office once its work is merged, any office
  ten minutes after its pull request closed unmerged. One in your own open checkout, or held by a
  neighbour, stays.
- An office that has ended still shows until its crate has been hauled out and whoever is inside has
  stepped out. Then the name goes, the floor rolls up tile by tile toward the door into a hexagon, and
  the hexagon sinks through the floor.
- Packing and stowing are the picture catching up: when a pull request opens, the office's own minion
  packs its crate; each new commit is a cube its minion stows, one at a time.
- An office's hover says how old the work in it is and, when it has gone quiet, for how long.

## Rockets

- One shape, `RocketShape`, for the station and the flight: a 1950s rocket, one streamlined body, a long
  point, three swept fins to the ground with pods on their tips. Flat and six-sided on the station, plated
  and twelve-sided in flight. Its repository's colour is on the fins, the pods and the legs, and its name
  runs down the side.
- It comes in two pieces. The **tip** is the staging release: while staging deploys, a drone welds it
  panel by panel at the pace that deploy usually takes. The **kick stage** is the production release.
- Clicking a rocket opens its release: the release pull request when one is open, else what the next
  release would carry: production against staging, or against the trunk where there is no staging, or
  the trunk since the last tag.
- A rocket stands on a pad slot wherever a repository has work waiting to ship. A fresh launch, a
  docked rocket, a hotfix and a rocket being welded come first; a rocket only standing by gives its slot
  to them.
- **The pad lift.** Under each slot is an iris over a shaft whose deck holds the kick stage. When the
  production release opens, the iris opens under the standing tip, the tip goes down onto the kick
  stage, its legs fold, and the deck raises the stack flush with the pad. When the release closes
  unmerged the same runs backwards. Classic draws the lift; the other looks dock at once.
- **The ring** under a rocket is always its repository's colour. While the tip is welded it is the
  staging build's clock: a bright strip fills round the hex towards the time that deploy usually takes,
  and blinks once it is over, faster when it is half as long again late; the rocket's hover and the pad
  feed in mission control say how long is left. While what it would ship is untested it breathes.
- **The nose lamp** blinks amber while the tip is welded. When staging is live and the last panel is on,
  the ring flashes, steam rings out, the lamp turns green, a short chime rises, the log says how long it
  took against the usual, and the tester and anyone at the holo table hop. A failed build thuds, smokes,
  and its lamp stays red.
- **It vents** thin jets of boil-off only when docked and go: everything it ships tested, waiting only
  for the merge. A bare tip never vents.
- **The launch.** At the merge, the release's crates are aboard at once in what is known, and the log
  says so. On screen, the three drones form a ring outside the field, a vortex opens from the ring to
  the hatch, and it pulls the crates off their rows one after another, through the field, spiralling
  and shrinking into the hold. The rocket climbs only once every crate it carries is in. It does not
  lift off: the pad lets go, its thrusters puff it clear, and only well away does the kick stage light.
  After it, the empty deck sinks and the iris closes.
- **A hotfix** (a pull request into production from anything but the trunk, staging or a release
  branch) stands by as an express rocket with a red tip, on a slot of its own. Merged, its crate is
  carried from its office into storage and pulled into the express rocket, which goes up alone. The
  release rocket keeps its cargo.
- **A repository that ships on every merge** sends each merged crate up in a rocket of its own.
- A production deploy is flown: an onboard camera rides the rocket to its repository's planet and
  lands it at the colony, timed on how long its deploys usually take. Every rocket that lifts off gets
  its own flight and screen at once, whatever else is in the air: screens stack at the side, up to three,
  and the oldest landed one gives way.

## Decon

- A bot's pull request (dependabot and friends) is not work: it gets no office and nobody on the floor.
  It is an object of unknown origin and waits in **decon**, a sealed room behind storage with a hatch in
  its far wall. Objects drop in through the hatch, never by shuttle, and the hatch light blinks. They
  stack by repository, twelve drawn at most, small and dark; the rest are counted in the hover. A floor
  that fills is the point: unscreened updates are meant to be seen.
- An object whose pull request merges is cleared: a carrier pulls it straight out, wherever it is in
  its stack, and whatever was on top settles. It is carried into storage and from there it is a crate
  like any other, counted in the rocket's cargo, since a release that ships six bumps and a feature
  ships seven things. It stays dark wherever it goes. It counts as tested from the start.
- An object whose pull request closes unmerged is ejected and forgotten. Nothing is carried.

## Minions

- A minion does one thing at a time, and it is always something with a name: "carrying #5210 to the
  deck". Hover it and it stops and tells you; the bubble above it carries its callsign.
- An order is taken over only at a step where it can be: while walking, yes; mid-lift, no. A new order
  re-plans from where the minion stands.
- A change of orders is visible: the minion stops and stands a beat with its head up, then goes. A
  message from you cuts the beat short.
- Minions walk around things, never through, and stand an arm's length from what they work on, facing
  it. Two never share a couch, a bed, a shower, a bowl or a crate.
- A standing body is solid: walks are planned round it. Someone close ahead on the way is passed with
  a lean to the walker's own right; the walker slows as it closes and never leaves its line, so two
  meeting head-on may overlap for a moment. Nobody stops for anybody, and a pass that does not resolve is
  given up after a stride or two.
- When the floor changes under a walk, the walk is re-planned.
- Nobody settles in a doorway, and a chore never stands in one.
- Speed is what the task needs: carrying is slow, hurrying carriers less so; pacing is another pace, a
  stroll a third; getting up from bed takes a moment.
- Every timing runs on the station clock.

## Probes

- A session's subagents are probes: small hovering machines with flat sides, its repository's colour
  on a stripe and one eye. A probe lifts off its session's minion when the subagent starts and flies back
  to dock with it, beside it, when the subagent is done. Nothing appears at the plaza.
- Reading code, a probe hovers about its own office, sweeping a fan of light over the floor.
- Researching the web, it shuttles: out to the monolith and its cone of light, home to its minion with a
  shard of that light, out again, for as long as the research runs.
- A probe settles only where nobody stands or is heading, and buzzes off to a free tile when someone
  takes its own.

## Bodies

- One owner per body. The order in hand owns a minion's place, path and pose. Nothing else writes them:
  a session's refresh, a floor change or a panel may only ask, and the ask waits its turn.
- Every order is either moving or waiting on a fact it names: the crate to come down, the ship to lift
  off. Standing still in the same step for ten seconds, waiting on nothing named, is a stall; a wait on
  a named fact gets ninety.
- A stall is given up, and said so in the log. Nothing is lost, because the work is not kept in the
  body: a carry goes back on the board from where the crate now lies and goes to someone else first, an
  office's crate stays for the next free hands, a visit ends.

## Rooms

- A room opens to the hallway through one doorway: the room tile that touches the hallway. Nothing sits
  in it and nobody settles there. The galley alone opens into the lounge instead, and nobody settles on the
  lounge tile in front of it.
- Fixtures stand along the walls away from the door, one minion to each: a bed, a couch, the bowl, the
  shower, a piece of gym gear. The room's name is cut into the far corner and nothing covers it. The galley
  is too small for a name; its machines say what it is.
- The middle of a room stays clear to walk through. Mission control alone keeps its holo table there, with
  a way round it on every side.
- A fixture says where a body uses it: a seat to sit on, a rim to stand at or a spot to stand on, in its own measurements, and
  wherever the fixture stands the body lands exactly there. A console's chair turns out to the minion,
  takes it, and swivels it in to the console; getting up runs the other way. The holo table takes three,
  standing an arm's length from its rim.
- A bed is got into from the long side that faces into the dorm. The sleeper walks the aisle to that side,
  turns its back on the bed, sits on the edge, and swings round into the bed's line as it lies down, head
  on the pillow. Getting up runs the other way: it swings back out onto the edge and stands up beside the
  bed, and only then walks. Nobody walks over a bed; the aisles between them stay open.
- What a body wears, holds or is covered by is worked out again every frame from what is true of it now.
  A prop that belongs to a room is drawn for a body in that room, not for one still on its way there.
- A visit lasts its whole time. A shower is two to three minutes of water over the shoulders, then a few
  seconds at the rail with the towel. A pee is a sit: turn round, down onto the bowl, a shuffle on the
  seat now and then, up as the time runs out, and the bowl flushes behind.
- The gym has four fixtures, a treadmill, a bench with a barbell, a bag and a mat, one minion to each, a
  turn lasting its whole time. The treadmill, the bag and the mat each have a spot to stand on; the bench is
  a seat the minion backs onto and lies down along, the bar over its chest.
- The galley takes one minion at a time, standing at the counter an arm's length from its machine. A coffee
  is twenty-odd seconds: a mug under the spout, the pour, the steam. Then the mug goes along in the hand, back
  to the couch or the desk, steaming, sipped now and then, for a few minutes; a carry, the bath or the gym
  drinks it up first. A bite is printed in ten seconds: the printer's window glows while a bowl of noodles
  grows inside, then slides out. The minion takes it to a couch and eats it there, a spoonful at a time,
  crumbs and all. The bowl is printed too, and eaten last.
- Nobody goes onto the pad. The field is as far as anyone walks. When a rocket stands venting or flies, the
  loungers take the consoles in mission control for the length of the launch, the pad screen shows the
  launch cam, and those roaming drift to the window to watch.

## A minion's day

- Work at the office. Hop for a minute when done. Pace the office while waiting. Quiet: read on a couch
  by day, sleep in the dorm by night (night is 22 to 07).
- A shower after twenty minutes or more of work, a pee after every second shorter stretch. Never while
  busy, carrying or in bed; if work calls mid-visit, the minion leaves at once.
- While untested crates stand on the testing rows and no rocket is go, one free minion walks them as
  the tester.
- Idle is not an order: it is what a minion does while the board has nothing for it, and any order takes
  it from there, out of the shower or off the bench if need be. When an order ends with nothing next,
  the time of day, the work it did and chance decide: rest by night; after hard work now and then the
  bath; now and then a look round; else rest.
- A lounger has one idle clock, two to five minutes. When it runs out one thing is picked: a look round
  the station most often, a turn in mission control by day at a free console or the holo table nearly as
  often, the galley by day when it is free, a turn in the gym by day, a book on the couch, or the bath. The
  crew take turns in mission control too, but not in the gym. The galley serves a bite from 11 to 14 and 18 to 20, a coffee otherwise; after
  desk work a minion now and then goes for one before it rests.
  Leaving the lounge does not reset it. A visit's time starts when the minion arrives. Roamers keep
  apart, except to watch a venting rocket.
- You may pick a lounger's next thing from its bubble: the gym, bed, a book, the shower, the bowl, a coffee
  or a bite. A busy minion's bubble says it is busy and what at, and offers nothing.
- A session that is over: lounge by day, dorm by night; when there is nothing left, a shuttle out from
  the bay.

## Tasks and work

- An issue is a task; a pull request is work done for it. A crate is a task: with a board, the issue the
  pull request closes, else the pull request's own number. One crate per task, however many pull
  requests it took; its hover names the task and whose work it is. Its click opens its story: each step
  from the event log with its time and what moved it, said as what happened (#5762 merged, staging release #5769 merged), and how long it took from the
  merge to production. The story's title, or a double click on the crate, opens the task.
- A closed issue is finished work, whatever column the board left it in: it never makes an office.
- Every repository has its own way to production, read from what it did (see
  [WIRING.md](WIRING.md#the-way-to-production)). With staging a rocket loads from the testing and
  cleared rows; without, from storage.

## Sharing

- With sharing on, stations on the same network share offices in the repositories ticked for it, those
  checked out and worked in within twelve hours. Each app shares only what it has checked out itself.
- A shared office carries its life: who is in it and what they are doing, their cones, its pull request
  with its checks. A neighbour's minion wears an orange suit with the repository's patch and does what
  its own minion does: the gym, the bath, a look round, the lounge. Teammates seen only on GitHub wear
  grey.
- An office only on a neighbour's machine is outlined while idle; an office its neighbour calls idle is
  dimmed.
- An office a neighbour stops claiming goes; one held by a neighbour who disconnects stays for a day, so
  their return does not move it.

## Humour, kept dry

The station takes its work seriously and itself not at all. The log is the station's computer speaking,
plainly and a little dry: "web: six crates across to the lab". Minions pee with the door open and a
pixel patch. Testers frown into crates and tick notepads. Jokes live in the words and the routines,
never in the shapes.
