# Drawing the floor

The station's floor is drawn here, offline, and baked into `Sources/Rumkapsel/BakedPlans.swift`. Nothing in
the app plans a floor at run time any more: it reads a baked plan and lights slots as offices arrive.

    python3 floor/radial.py     # nothing on its own — the generator, imported by the others
    python3 floor/bake.py       # bakes the chosen seeds into plans.json, checking each step
    python3 floor/export.py     # turns plans.json into BakedPlans.swift
    python3 floor/drawr.py 25 27 4 16     # a sheet of finished plans
    python3 floor/stages.py 25            # one plan at 0, 6, 18, 40, 70 and 100 offices

`radial.py` grows a plan: the monolith in a plaza, a hallway ring round it with the living quarters on it,
the deck west and the bay south, and offices filling outward wherever they fit. The southwest is kept clear
past the first ring, because the deck run and the bay need that ground and crate traffic should not queue.
Corridor is grown only where an office actually lands, and any arm that came back empty is taken up again.

`bake.py` turns a plan into an activation order. Each office carries the run of hallway that first reaches
it, so lighting them in order leaves the floor connected at every step — checked there, and again in Swift
when a plan loads (`Floorplan.check`).

Seeds 25, 27, 4 and 16 are the ones baked. They were picked out of forty on offices placed, corridor per
office, loops, and the walk from the bay.
