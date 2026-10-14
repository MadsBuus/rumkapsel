# Themes: how to design one

How a theme should draw the station, and how theme work is judged. What things are and may do is
[STATION.md](STATION.md); the code is [ARCHITECTURE.md](ARCHITECTURE.md). The themes are Classic, Kenney
Space Center and Kenney Kingdom (`State/Theme.swift`).

## What a theme is

A theme changes what the station is drawn as. It never changes what happens: the facts, the rules,
playback, the walks and the pipelines are the same under every theme. A theme may bend the plan only
through a knob on `Theme`:

| Knob | What it does |
|---|---|
| `padGap` | how far the pad stands out past the yard (Kenney's causeway); the floor plans are baked per theme for it |
| `kickRises` | whether the pad lift is drawn and a docking takes its time; elsewhere a rocket docks at once |
| `repoColors` | the palette repositories are handed colours from |
| `vocabulary` | the words for signs, hovers, orders and log lines; a theme overrides only the words it redraws |

Two neighbours on different themes may see a shared station's yard laid out differently; that is
accepted.

## The layers of a place

Every theme draws the same six layers. Design them in this order.

1. **The input: the bay.** Where new minions and new offices arrive. It never grows and never moves, so
   it is a set piece: designed once, whole, in the best spot the setting has. A space dock, a harbour in a
   cove, a gate on a road in.
2. **The output: decon, storage, the staging area and the pad.** The stepped way work leaves: screened,
   stored, tested, shipped. A set piece too, ending on something that visibly leads away: a launch pad
   under open sky, a road out of the map, a quay for outbound ships.
3. **The center.** The monolith. It is the first thing the eye finds and must say what kind of place this
   is: an artefact on a plaza, a keep, a lighthouse. A generic tower says nothing.
4. **The idle areas: the lounge, the dorm, the bath and the gym.** Scenery for minions between orders. A
   theme may reinterpret them freely (a tavern, an inn, a bathhouse, a training yard).
5. **The growth zone: offices and the hallway between them.** The only part that grows and shrinks with
   the work. It must look right with three offices and with forty, and while it changes.
6. **The world: terrain, water, forest, weather.** Designed round the set pieces, giving way to the
   growth zone as it spreads.

## Design for change

- **Nothing natural is a rectangle.** Coastlines, forest edges, fields and paths are soft shapes. The plan
  is a grid; the drawing must not show it.
- **Fixed areas are set pieces, not tinted tiles.** Keep the walkable spots the simulation uses (berths,
  carrier stands, the hatch) exactly where they are, and draw the rest as one designed piece.
- **The world is keyed to position.** Where a tree stands follows from where it is, never from a random
  sequence over the whole station, so one new office changes the world only where the growth zone moved.
- **The growth zone yields gracefully.** Forest thins, fields open, paths extend; nothing pops.
- **Scale follows the minion.** A minion is about half a tile tall. Props and plants are sized against it.
- **Motion belongs to the theme too.** Ships may sail rather than descend (`shipPose`), releases may roll
  out rather than lift off (`launch(at:)`). The simulation keeps the clock and the spots; the look draws
  the path. A launch must be over within the climb (`launchSeconds`), which `--look-tests` holds.
- **What stands is what walks round.** Furniture a minion must walk round has a footprint per theme in
  `Station.furniture(theme:offices:)` (`State/Obstacles.swift`), and the cone one in `Theme.cone`.
  `--look-tests` holds what a look draws equal to them, so a look that changes a couch's size changes its
  footprint in the same commit.

## The `Look` protocol

`Scene/Looks/Look.swift`, ordered by the layers. Every requirement has a default, the classic piece, so a
look overrides only what it changes.

| Layer | Requirements |
|---|---|
| the world | `sharesTiles`, `background`, `viewYaw`, `backdrop(into:)`, `ground(under:into:)` |
| the input | `input(_:)` (the bay as a `SetPiece`), `shuttle(color:)`, `shipPose(_:)`, `drawsBerthHexes`, `berthHexHeight`, `hangarField`, `hullWall(...)` |
| the output | `output(_:deckInUse:)` (decon, storage, the staging area and the pad as a `SetPiece`), `doorFrame(facing:)`, `rocket(color:tall:cargo:)`, `launch(at:)`, `launchSeconds`, `rocketFollowsLoad` |
| the center | `monolith()` |
| the idle areas | `furnishLounge`, `furnishBath`, `furnishGym` (a `Furnishing` whose towel, bar and bag the scene still moves by name), `bed(level:)` |
| the growth zone | `floorTop`, `dotsHallway`, `drawsBorders`, `rimsOffices`, `drawsPlane(_:)`, `floorColor(_:floor:)`, `tileDetail(_:)` (a `Tile`: its floor, open and walled edges, which neighbours share its owner), `tint(tile:_:)`, `planet(...)`, `dress(office:in:sign:)` |
| people and the rest | `figure`, `pose`, `dress(station:)`, `crate(color:)`, `hold(tall:)`, `jetpack`, `padDrone()`, `writesOnFloor`, `tool(_:height:depth:)`, `workSparks`, `detailsFloors`, `message(color:floor:)` |

What each look claims to draw itself, and what it leaves to the classic piece, is a row in
`LookTests.claims`, with whether it letters its floor and rims its offices. A new look needs a row.

Where the rest lives:

- `Looks/ClassicLook.swift`, `Looks/ClassicFurniture.swift`: the defaults, as `Classic`, which a look can
  fall back on.
- `Looks/KingdomLook.swift`: the worked example of every layer, with a `Site` that reads a station's plan
  and builds its world once per floor.
- `Looks/KenneyLook.swift`: the Space Center, from Kenney's kits.
- `Looks/Shapes.swift`: soft shapes. `Shapes.sample` and `Shapes.fill` turn a field into one mesh wherever
  it is at or over a level; sample once and cut several bands. `Shapes.patch` is a tile's soft patch that
  runs on into its owner's neighbours. `Noise` is keyed to position.
- `Looks/Kit.swift`: the model loader. A model is loaded once and cloned with its own materials; kits with
  named materials are tinted by name, atlas-textured kits through `multiply`. Merge placed props into one
  node with `flattenedClone()`.
- `Resources/Kenney/<kit>`: only the models a theme uses, as OBJ with their MTL, the kit's atlas and
  licence. Every asset is CC0 or made for the theme; say where it came from.
- The floor plans: `floor/README.md`. A theme that moves the yard or the bay needs plans baked for it.

## How theme work is judged

- **Against the references, side by side.** Keep the images the theme is meant to evoke next to every
  screenshot, and list what fails before saying what works. Better than the last screenshot is not the
  bar.
- **Across growth.** A station with a few offices, about ten and about forty (`RK_DEMO_OFFICES`), not
  only the demo.
- **Up close and far out.** The bay, the center and the output close up, and the whole station.
- **Within budget.** The toy draws at 30 frames a second when watched and should cost little. A snapshot
  prints the scene's node count; `RK_FRAMES=1` prints every slow frame.
- **The gate still holds.** The layout tests run the yard and bay checks for every theme, the look tests
  its claims and footprints, and every test run pins Classic's words.

To look at a theme without touching the running app, give a run its own support folder with a full copy
of the config (a config holding only `themeName` falls back to Classic):

```bash
mkdir -p /tmp/look/Rumkapsel
jq '. + {themeName:"kingdom", shareOnLAN:false}' ~/Library/Application\ Support/Rumkapsel/config.json > /tmp/look/Rumkapsel/config.json
RUMKAPSEL_SUPPORT=/tmp/look .build/debug/Rumkapsel --demo --snapshot /tmp/look/demo.png --delay 14
RUMKAPSEL_SUPPORT=/tmp/look .build/debug/Rumkapsel --demo --focus work --zoom 2.4 --snapshot /tmp/look/close.png --delay 14
```

Keep the pointer off the window: its hover shows in a snapshot.

## What a look cannot do

- Place the idle areas: their rooms are placed by the plan; a look only furnishes them.
- Draw the office overlays: failing checks, dust and the provisional frame are the scene's.

## Mistakes that look like progress

- Tinted grid cells with kit props scattered over them: hard slabs, not places.
- Water, beaches and cliffs laid as long rectangles: stripes and fences, not coast.
- A prop with no job: the picture gets worse, not richer.
- Crops a full tile wide on every office cell: a bulky growth zone.
- A center that could stand anywhere: it says nothing about the place.
- A change judged against the previous screenshot instead of the references.
