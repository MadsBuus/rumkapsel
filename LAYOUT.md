# The next floor plan: alleys instead of the cross

A plan, not a description of the code. Written 2026-09-15 against the layout as it stands (the 2-wide cross,
`spineHalfLength`, the yard on the west arm). ARCHITECTURE.md says how the current one works; this says what
replaces it and in what order.

## What the game does, read off its screens

- **One hallway, one tile wide.** It wanders: straight runs of two to four tiles, a jog of one to the side,
  on again. Never a grid, never a cross. Rooms hang off it on both sides and never off each other.
- **The monolith sits in a 3x3 plaza** of hallway floor, in the middle tile, and the one-wide hallway leaves
  the plaza from its sides. The plaza is the only wide floor there is.
- **Rooms are four to seven tiles**, polyominoes, flat side to the hallway. A room's contents (cubes, cones,
  crates) stand one per tile with air round them. Nothing is furnished the way our lounge is.
- **A minion is about a third of a tile** across. Ours is 0.22 of a cell wide and 0.5 tall: close already.
- **The palette**, sampled from screen01.png (the shot pasted in the chat):

  | Use | Hex |
  |---|---|
  | space | `#0E1117` |
  | hallway floor | `#81655B` |
  | unbuilt room / dark room | `#434242` |
  | wall strips, tile borders | `#2A2929` |
  | room hues: blue, orange, yellow, magenta, green, teal | `#2C76B4` `#D36B25` `#E0A11C` `#B55383` `#7CA82E` `#4EA9A0` |
  | resources: cyan cube, pink crate, yellow cone | `#5ED3C4` / `#99E9EA`, `#ED7CB3`, `#FFD65C` |
  | minion | `#ADBBCE` |

  Ours today: void `(0.055, 0.067, 0.125)` is bluer and darker than their space; corridor `(0.47, 0.37, 0.31)`
  is a touch darker and greyer than `#81655B`; our twelve repo colours are brighter and more pastel than their
  six. Proposal: take their space, hallway and unbuilt greys as ours, and put their six hues first in
  `Colors.repos` with our remaining six after, so the first six repositories look like the game and the rest
  stay distinct. The homage lives in the floor; the shapes stay ours.

## What changes

### 1. The corridor is a wandering line, one tile wide, generated from a seed

- The hallway is a **pre-generated plan**, not something grown by need. A deterministic walk from the plaza
  produces each arm as a list of cells: run 2 to 4, jog 1, run again, drifting in its arm's compass direction.
  Two arms never come within three cells of each other, so rooms fit on both sides of each.
- **Alleys**: off each arm, every third or fourth run, a stub one tile wide and two to three tiles long,
  dead-ending. Alleys are what give more room frontage per step walked: a room on an alley is one turn from
  the arm, and an arm with alleys on both sides carries eight to ten rooms in the length that carries four today.
- The plan is infinite in principle and **revealed as needed**: a cell of hallway exists once a room has been
  placed that needs it (or a fixed block sits beyond it). The fade-in by ring that `rebuildStatic` does today
  becomes a fade-in by hallway distance from the plaza. Nothing is ever re-planned when the station grows.
- The seed is the station's name (`work`, `private`), through `stableHash`, so every machine that has a
  station called `work` draws the same hallway. This is the first half of "shared stations look the same".

### 2. The plaza replaces the core

- A **3x3 plaza** of hallway floor with the monolith on the middle tile, standing 2.3 high as now. Arms leave
  from the middle of each side. `Place.core` becomes the eight tiles round the monolith: subagents and
  researchers stand round it, which is also what the game shows (the beams from the monolith to the minions).
- The monolith's obstacle footprint is the middle tile's 3x3 sub-spots; the walk goes round it on the plaza.

### 3. Where the fixed blocks go

The compass: **south** to the airlock and bay, **west** to the yard, **north and east** free for rooms and
alleys. Same roles as today, so the sources, the ledger and the scenarios keep their meaning.

- **Airlock**: a 1x2 chamber at the south arm's end; one hatch, not a random one of two. **Bay**: 3 wide
  by 2 deep beyond it, three shuttle slots on cell centres instead of tile boundaries.
- **Yard**: pad, deck, storage and decon keep their 4x4 (decon 4x2) and their order along the west arm, and
  the yard's internal aisle stays **two wide**: the pallet is 1.8 by 1.4 and is pushed from storage across
  the deck, and that route never touches the hallway. The one place the hallway meets the yard, the deck
  doorway, becomes a single door. So `yardDoorways` keeps its pairs inside the yard and loses them on the
  corridor side.
- **Lounge, dorm, bath, gym**: placed by the same deterministic placement as offices, from the seed, in a
  fixed order (lounge first, the others beside it as `clusterQuarters` wants), on the north arm's first
  alley. Sizes: lounge 3x3 stays, dorm 2x3 (six beds, enough for the crew we have seen), bath 2x2, gym 3x2.
  They stop being placed by a per-machine search and become part of the plan.

### 4. Rooms: shapes, sizes and placement

- **Shapes 3 to 7 tiles**, the game's range, chosen by `stableHash(key)` rather than `key.hashValue` (which
  Swift reseeds per process, so today an office has a different shape on every launch and every machine).
  Rectangles 1x3, 2x2, 2x3, 3x2 and three polyominoes: an L of 4, an L of 5, a T of 5. `flatTowardsCorridor`
  stays: the flat side faces the hallway.
- **Placement is a walk along the hallway from the plaza outward**: the first free frontage where the shape
  fits with its door on the hallway, alleys before the next stretch of arm. That replaces the ring search
  round the centre. It is deterministic given the plan and the rooms already placed, and it fills near the
  plaza first, so the early station is compact and the walk to work stays short.
- **Never through another room**: unchanged. **Nothing fits**: reveal more hallway (the plan is infinite),
  never park a room unchecked at `(S+2, 2)` as `placeShape` does after forty rounds.
- Minion size: **0.85 of today** (0.19 wide, 0.43 tall) and crates, cubes and cones scaled with it, so a
  room of four tiles reads as a room and not a cupboard. One number, `Minion.scale`, read by the props that
  size themselves off the body. Not smaller than that: the poses, the pixel patch and the hover bubble are
  tuned to what is on screen now.

### 5. Walking one wide

- `Station.fine` stays 3. In a one-wide hallway the centre lane is open and the two wall lanes are `isEdge`,
  so the first `route` pass walks the middle and a pass between two bodies takes the wall lanes, which is
  exactly the shoulder lean `Walk.sidestep` already draws. Right of way is still not a rule (STATION.md,
  Minions), so two meeting in an alley squeeze past as they do in the corridor today; the plaza is where
  anyone waits.
- `canStep` keeps its one door per room; the deck door, the airlock door and the hatch become single pairs.
  `standCell` must not assume a free neighbouring aisle cell: on a one-wide hallway it steps along the
  hallway, not beside it.
- Carries and deliveries do not change: a crate on the arms has no footprint today and keeps none.

### 6. Shared stations look the same

The second half, and the reason to do the plan as a pure function:

- **Same seed, same hallway, same fixed blocks, same cluster.** Nothing on that list is decided per machine
  any more. `spineHalfLength` goes away with the cross.
- **Same room, same shape**: `stableHash(key)`.
- **Same room, same place, given the same rooms before it.** Placement walks the hallway in canonical order
  (`startedAt`, then key), both of which are shared facts. A snapshot keeps carrying `cells` and a receiver
  adopts them when free, as now, which covers the common case. When two machines placed the same new room
  differently (both had it before either heard the other), the **tie-break is the peer name**: the lower
  name's cells stand, the other re-places from its next free frontage and broadcasts the result. That
  converges in one round; today nothing ever converges because `fits` is best-effort and the shapes differ.
- The four fixed rooms are placed from the seed, so they need no sharing; the snapshot version bumps to 3
  regardless, because the cells it carries mean a different floor.
- The fleet file becomes `fleet-v21.json`; no migration, the old layout is not worth carrying.

### 7. What else moves with the cross

From the audit of the code: `Invariants.floor(of:)`, `Station.walkable`, `SceneStatic.owner` and
`rebuildLabels`'s `occupied` each enumerate the block list by hand and become one list. The station's name
is cut outside the south-west corner, which is only free today because the yard stops there; it moves to
the plaza's north side, on the floor, where the game's screens keep their eye. The yard and bay signs anchor
to each block's own corner already. `frame(for:)` reads `bounds` and does not care about the shape; its
margins get a look once the footprint is known. `Fleet.arrange` keeps work left and private below.

## Tests before pictures

A model-only suite, `--layout-tests`, in the shape of the ledger tests:

- Two `Station("work")` built from nothing produce identical hallways, plazas and fixed blocks.
- Placing the same set of rooms in the same order on two stations gives identical cells; placing them in
  different arrival orders and then applying the tie-break gives identical cells.
- Every room touches the hallway, every hallway cell is reachable from the plaza, every door is one
  `canStep`, no room is inside the three-cell margin between arms.
- Pallet route from storage across the deck still exists with the yard aisle two wide.
- `--sim-tests`: two bodies pass in a one-wide alley without either stopping; a carrier walks an alley with a
  crate; the leaver's single hatch. `--scenarios` unchanged in meaning; the ones that read positions read
  them from the new plan.

## Order of work

1. **Determinism first, on the cross**: `stableHash` for shapes, the fixed rooms in a fixed order, the peer
   tie-break. Ships on its own; it fixes the worst of "peers differ" before the floor changes at all.
2. **The plan generator**: hallway, plaza, alleys, fixed blocks, `--layout-tests`. Behind `fleet-v21`,
   no scene changes yet; `Invariants.floor` and `walkable` read the plan.
3. **Walking and doors one wide**: `isEdge`, `canStep`, `standCell`, `dismiss`, the deck door. Sim tests.
4. **Placement along the hallway** and the shape set; minion scale; camera margins; the name on the plaza.
5. **Palette**: the game's floor greys and its six hues first. Last, because it is a taste call and a
   one-line change once everything else stands.

Each step keeps the gate green on its own. Steps 1 and 2 touch no picture; the first visible change is step 3.

## Decisions taken (2026-09-15)

- **Palette**: try the game's floor greys and its six hues; keep ours in the code as a second palette,
  switchable, because they are liked too.
- **Minion scale**: try both, behind a setting. The poses, the hands, the pixel patch and the crate arcs are
  all sized off the body, so the smaller figure has to be watched for what it breaks.
- **Yard**: stays two wide inside, and may go wider if the pallet or the pushes want it.
- **Private station**: same treatment, same release.
- **Start with the shapes**: an office's shape from its key through `stableHash`, so a room looks the same
  on every launch and every machine. Done first, on the cross, before the floor changes.
