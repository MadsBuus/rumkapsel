# Themes: how to design one

A guide, not a description of the code. Written 2026-09-15, after the first attempts at a medieval theme went
wrong in instructive ways. ARCHITECTURE.md says how the station works; STATION.md says what things are and
may do; this says how a theme should draw them, and how theme work is judged.

## What a theme is

A theme changes what the station is drawn as. It never changes what happens. The simulation, the walks, the
jobs, the ledger, the pipelines and every node name the scene reads stay the same under every theme. A
theme may bend the floor plan only through a knob on `Theme`, today `padGap`, and Classic's plan stays cell
for cell what it was. Two peers on different themes may see a shared station's yard laid out differently;
that is accepted.

## The layers of a place

Every theme draws the same six layers. Design them in this order.

1. **The input: the bay.** Where new workers and new offices arrive. It never grows and never moves, so it
   is a set piece: designed once, whole, in the best spot the setting has. A space dock, a harbour in a
   cove, a gate on a road in.
2. **The output: decon, storage, the deck and the pad.** The stepped way work leaves: screened, stored,
   tested, shipped. It never grows either, so it is a set piece too, ending on something that visibly leads
   away: a launch pad under open sky, a road out of the map, a quay for outbound ships.
3. **The center.** The monolith today. It is the first thing the eye finds and it must say what kind of
   place this is: an artefact on a plaza, a keep, a chapel, a lighthouse. A generic tower says nothing.
4. **The idle areas: the lounge, the dorm, the bath and the gym.** Scenery for minions between jobs, not
   part of what the station does. A theme may reinterpret them freely (a tavern, an inn, a well, a training
   yard) and place their look near the center.
5. **The growth zone: offices and the paths between them.** The only part that grows and shrinks with the
   workload. It must look right with three offices and with forty, and while it changes.
6. **The world: terrain, water, forest, weather.** Designed around the fixed set pieces, and giving way to
   the growth zone as it expands.

## Stations are worlds

Each station owns its own bay, yard, ledger and rockets, so under a theme each station is its own **world**:
the same site template, with the input and the output in their designed spots and the landscape composed
round it, shown one at a time. The private station is a world of its own, not a second site beside work in
one landscape and not a quarter of one place (decided 2026-09-15). This keeps every set piece in its best
spot without composing a landscape between stations. Moving between worlds, and what the whole-fleet view
becomes under a theme, is still to design; one place with quarters stays possible later, at the cost of
sharing the input and output between work and private repositories and keeping the private quarter out of
what is shared with peers.

## Design for change

- **Nothing natural is a rectangle.** Coastlines, forest edges, fields and paths are organic shapes. The
  plan is a grid; the drawing must not show it.
- **Fixed areas are set pieces, not tinted tiles.** A grid of coloured cells with props on top can never
  read as a harbour. Keep the walkable spots the simulation uses (landing slots, carrier stands, the hatch)
  exactly where they are, and draw the rest as one designed piece.
- **The world is keyed to position.** Where a tree or a rock stands must follow from where it is, not from
  a random sequence over the whole fleet, so adding one office changes the world only where the growth zone
  moved. A theme that reshuffles its forest when an office opens is broken.
- **The growth zone yields gracefully.** Forest thins, fields open, paths extend; nothing pops or jumps.
- **Scale follows the minion.** A minion is about half a tile tall. Props, crops and trees are sized
  against it, not against the tile.
- **Motion belongs to the theme too.** Ships may sail rather than descend (`shipPose`); releases may roll
  out rather than lift off. The simulation keeps the clock and the landing spots; the look draws the path.

## How theme work is judged

- **Against the references, side by side.** Keep the reference images the theme is meant to evoke next to
  every screenshot, and list what fails before saying what works. Better than the last screenshot is not
  the bar.
- **Across growth.** Snapshot a station with a few offices, with about ten and with about forty, not only the
  demo, and check that the world responds sensibly at each.
- **Up close and far out.** A close-up of the bay, the center and the output, and the whole fleet.
- **Within budget.** The desk toy runs at 30 frames a second when watched and should cost little CPU. Note
  the geometry node count a snapshot prints (the demo is about 1,050 in Classic) and the frame rate
  `RK_FPS=1` prints, and keep both in mind as a theme adds detail.
- **The gate still holds.** The layout tests pin Classic's plan and run the yard and airlock checks for
  every theme; every test run pins Classic's words, since the scenarios expect log lines by what they say.

To look at a theme without touching the running app, give a run its own support directory with a full copy
of the config (a config holding only `themeName` fails to decode and falls back to Classic):

```bash
mkdir -p /tmp/look/Rumkapsel
jq '. + {themeName:"kingdom"}' ~/Library/Application\ Support/Rumkapsel/config.json > /tmp/look/Rumkapsel/config.json
RUMKAPSEL_SUPPORT=/tmp/look RK_FPS=1 .build/debug/Rumkapsel --demo --snapshot /tmp/look/demo.png --delay 14
RUMKAPSEL_SUPPORT=/tmp/look .build/debug/Rumkapsel --demo --focus work --zoom 2.4 --snapshot /tmp/look/close.png --delay 14
```

The pointer over the window shows its hover panel in a snapshot; keep it off the window.

## Where a theme lives

- **`Theme.swift`**: the case, its title and credit for the picker, `padGap`, and its
  `vocabulary`, the words for floor signs, hover text, orders and log lines. A theme overrides only the words
  it redraws.
- **`Looks/Look.swift`**: the `Look` protocol, ordered by the layers. Every requirement has a default, the
  classic piece, so a look overrides only what it changes:
  - the world: `background`, `viewYaw`, `backdrop`, `ground` (asked once per station under separate worlds)
  - the input: `input` (the bay and the airlock drawn whole as a `SetPiece`), `airlockFrame`, `shuttle`,
    `shipPose`
  - the output: `output` (decon, storage, the deck and the pad as a `SetPiece`), `hatchFrame`, `rocket`,
    `launch`
  - the center: `monolith`
  - the idle areas: `furnishLounge`, `furnishBath`, `furnishGym`, `bed`, handing back a `Furnishing` whose
    towel, bar and bag the scene still moves by name
  - the growth zone: `drawsPlane`, `floorColor`, `tileDetail` (given a `Tile`: its floor, its open and walled
    edges, and which of its eight neighbours share its owner), `tint`, `floorTop`, `dotsHallway`,
    `drawsBorders`, `dress(office:in:)`
  - people and the rest: `figure`, `pose`, `dress(station:)`
- **`Looks/Shapes.swift`**: flat organic shapes. `Shapes.sample` and `Shapes.fill` turn a field into one mesh
  wherever it is at or over a level, so coastlines, clearings, yards and roads are soft; sample a field once
  and cut several bands from it. `Shapes.patch` is a tile's soft patch that runs on into its owner's
  neighbours. `Noise` is keyed to position, so a world stays where it was as the growth zone moves.
- **`Looks/ClassicLook.swift` and `Looks/ClassicFurniture.swift`**: the defaults, as `Classic`, which a look
  can fall back on when its own model is missing.
- **`Looks/KingdomLook.swift`**: the worked example of every layer, with a `Site` that reads a station's plan
  (its floor, the bay's centre, the shoreline, the road) and builds its world once per floor.
- **`Looks/Kit.swift`**: the Kenney model loader. A model is loaded once and cloned with its own materials;
  kits with named materials are tinted by name, atlas-textured kits through `multiply`. Merge many props into
  one node with `flattenedClone()` once they are placed.
- **`Resources/Kenney/<kit>`**: only the models a theme uses, as OBJ with their MTL, the kit's colour atlas
  if it has one, and the kit's licence. Every asset is CC0 or generated for the theme; say where it came from.

A world is not drawn in a run with no window (the scenarios, the tests), so its cost never slows the gate.
The HUD reads the look's background and inks itself dark on a light ground.

## What a look cannot do yet

- **Own the work tools.** The scanner, tablet, torch and hammer minions hold are still the scene's.
- **Place the idle areas.** Their rooms are placed by the plan; a look only furnishes them.
- **Draw the office overlays.** Failing checks, dust and the provisional frame are still square.
- **Move between worlds by a control of its own.** The station keys and the menu switch worlds; there is no
  on-screen switcher yet.

## What the first medieval attempts taught

- Tinting grid cells and scattering kit props over them gave hard slabs, not places.
- Water, beaches and cliffs laid as long rectangles read as stripes and fences, not coast.
- A prop with no job (a pier nothing used) makes the picture worse, not richer.
- Crops a full tile wide on every office cell made the growth zone bulky; plants must be sized to the minion.
- The center was a tower that could have been anywhere; it said nothing about the place.
- Each change was judged against the previous screenshot, not the references, and passed.
