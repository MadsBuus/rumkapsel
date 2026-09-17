# Drawing the floor

The station's floor is drawn here, offline, and baked into `Sources/Rumkapsel/BakedPlans.swift`. Nothing in
the app plans a floor at run time any more: it reads a baked plan and lights slots as offices arrive.

    .build/debug/Rumkapsel --dump-floor classic > floor/classic.json
    .build/debug/Rumkapsel --dump-floor kenney  > floor/kenney.json
    python3 floor/bake.py                  # bakes the picked seeds and writes BakedPlans.swift
    python3 floor/draws.py classic 42 43 41 37    # a sheet of finished plans

`floorplan.py` grows a plan around a floor it does not own. The yard, the airlock, the bay and the plaza's
two fixed arms are dumped out of the app itself, so there is no second copy of them here to drift from the
first — and because a theme moves them (Kenney stands its pad out on a causeway), a plan belongs to a theme.

Around that it lays spokes and partial rings out from the plaza, places the quarters first and nearest, and
fills with tetromino offices. Hallway is grown only where an office actually lands, and an arm that came
back empty is taken up again. Nothing is laid past the hull: the airlock pierces it and the bay floats
outside in space, so the whole southern quadrant is not floor to build on.

`bake.py` turns a plan into an activation order. Each office carries the run of hallway that first reaches
it, so lighting them in order leaves the floor connected at every step — checked there, and again in Swift
when a plan loads (`Floorplan.check`).

Four seeds are baked per theme, picked out of fifty-odd on offices placed, hallway per office, loops, the
walk from the plaza, and striping — hallway cells sitting in a straight run of eight or more, which is what
makes a plan read as a grid rather than a station.
