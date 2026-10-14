"""Bake a plan into an activation order.

An office is not drawn until it is needed, so the hallway that reaches it must not be drawn either. Each
office carries the run of hallway that first makes it reachable: walk back from its door to whatever is
already lit, by the shortest route the plan allows. Light them in order and the lit floor is connected at
every step, because an office only ever adds a run that touches what is there.

The base — the plaza, the fixed arms, the runs to the yard and the bay, and the quarters — is lit before
a single office opens, so the station is whole from the start.
"""
import json, math, os, sys
from collections import deque
HERE = os.path.dirname(os.path.abspath(__file__))
ns = {'__file__': os.path.join(HERE, 'floorplan.py')}; exec(open(os.path.join(HERE, 'floorplan.py')).read(), ns)

def bake(theme, seed):
    hall, slots, quarters, fixed, mono, ring = ns['plan'](theme, seed)
    fixed = {k: v for k, v in fixed.items() if k != "bayMargin"}
    # Everything the base must reach, traced back to the plaza through the hallway, so the base is a tree
    # rooted there and is connected by how it is built rather than by luck.
    prev, q = {}, deque()
    for c in hall:
        if abs(c[0]) <= 1 and abs(c[1]) <= 1: prev[c] = None; q.append(c)
    while q:
        c = q.popleft()
        for a, b in ((1,0),(-1,0),(0,1),(0,-1)):
            n = (c[0]+a, c[1]+b)
            if n in hall and n not in prev: prev[n] = c; q.append(n)
    assert len(prev) == len(hall), f"{theme} {seed}: the hallway is not one piece"

    lit = set()
    # The yard is entered through the deck's doorway, not off the hallway: storage, the pad and decon
    # have no door of their own and are not meant to. So each block lights whatever hallway it does
    # touch, and the test afterwards is that every one of them is reachable, through the yard or not.
    for name, cells in list(fixed.items()) + list(quarters.items()):
        doors = [p for x, y in cells for p in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)) if p in hall]
        if not doors: continue
        c = min(doors, key=lambda p: math.hypot(*p))
        while c is not None and c not in lit: lit.add(c); c = prev[c]
    for c in hall:
        if abs(c[0]) <= 1 and abs(c[1]) <= 1: lit.add(c)

    blocks = {p for v in fixed.values() for p in v} | {p for v in quarters.values() for p in v}
    floor = lit | blocks
    seen, q = {mono}, deque([mono])
    while q:
        c = q.popleft()
        for a, b in ((1,0),(-1,0),(0,1),(0,-1)):
            n = (c[0]+a, c[1]+b)
            if n in floor and n not in seen: seen.add(n); q.append(n)
    for name, cells in list(fixed.items()) + list(quarters.items()):
        assert set(cells) & seen, f"{theme} {seed}: {name} cannot be walked to before any office opens"

    # Order the slots by how far they are on foot, not as the crow flies. A slot tucked behind the deck
    # is a few tiles from the monolith and a long walk round it, and opening it early puts an office
    # somewhere nobody can see and everybody has to walk to.
    walk = {}
    q = deque(c for c in hall if abs(c[0]) <= 1 and abs(c[1]) <= 1)
    for c in q: walk[c] = 0
    while q:
        c = q.popleft()
        for a, b in ((1,0),(-1,0),(0,1),(0,-1)):
            n = (c[0]+a, c[1]+b)
            if n in hall and n not in walk: walk[n] = walk[c] + 1; q.append(n)
    def steps(cells):
        d = [walk[p] for x, y in cells for p in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)) if p in walk]
        return min(d) if d else 10**6
    slots.sort(key=lambda cs: (steps(cs) // 3,
                               math.atan2(sum(y for _, y in cs)/len(cs), sum(x for x, _ in cs)/len(cs))))

    base = set(lit)
    out = []
    for cells in slots:
        doors = [p for x, y in cells for p in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)) if p in hall]
        hit = next((d for d in doors if d in lit), None)
        if hit is None:
            pv, q = {p: None for p in lit}, deque(lit)
            while q and hit is None:
                c = q.popleft()
                for a, b in ((1,0),(-1,0),(0,1),(0,-1)):
                    n = (c[0]+a, c[1]+b)
                    if n in hall and n not in pv:
                        pv[n] = c; q.append(n)
                        if n in doors: hit = n; break
            assert hit is not None, f"{theme} {seed}: an office cannot be reached"
            run, c = [], hit
            while c is not None and c not in lit: run.append(c); c = pv[c]
        else:
            run = []
        lit |= set(run)
        out.append({"cells": sorted(cells), "hall": sorted(run), "ring": steps(cells) // 3})
    quarters = dict(quarters, galley=[galley(theme, lit, slots, quarters, base)])
    return {"theme": theme, "seed": seed, "quarters": {k: sorted(v) for k, v in quarters.items()},
            "fixed": {k: sorted(v) for k, v in fixed.items()},
            "base": sorted(lit - {p for o in out for p in o["hall"]}), "offices": out}

# Which way each theme's camera looks across the plaza: Classic from +x+y, Kenney turned round.
FACING = {"classic": -1, "kenney": 1}

def galley(theme, hall, slots, quarters, lit):
    """The galley is one tile off the lounge, opening into it: a tile no office, hallway or room will ever
    take, so baking it in moves nothing else. Opening into the middle of a lounge wall keeps it clear of
    the couches and the door. Hallway beside it would be a wall with no door, so the fewer the better; then
out from behind the monolith as the theme's camera looks, then nearest the plaza."""
    _, _, hull = ns['load'](theme)
    lounge = set(quarters["lounge"])
    taken = set(hall) | lounge | {p for v in quarters.values() for p in v} | {p for cs in slots for p in cs}
    taken |= {tuple(p) for v in ns['load'](theme)[0].values() for p in v}
    xs, ys = [x for x, _ in lounge], [y for _, y in lounge]
    mid = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2)
    door = min((c for c in lounge if any((c[0]+a, c[1]+b) in lit for a, b in ((1,0),(-1,0),(0,1),(0,-1)))),
               key=lambda c: (c[1], c[0]))
    best = None
    for o in lounge:
        for a, b in ((1,0),(-1,0),(0,1),(0,-1)):
            c = (o[0]+a, o[1]+b)
            if c in taken or not ns['inside'](c, hull): continue
            side = (o[0] == mid[0]) != (o[1] == mid[1])
            toward = FACING[theme]
            behind = c[0] * toward >= 0 and c[1] * toward >= 0 and abs(c[0]) + abs(c[1]) <= 4
            open_to = sum((c[0]+x, c[1]+y) in hall for x, y in ((1,0),(-1,0),(0,1),(0,-1)))
            score = (open_to, behind, not side, o == door, abs(c[0]) + abs(c[1]), c)
            if best is None or score < best[0]: best = (score, c)
    assert best, f"{theme}: no tile beside the lounge for the galley"
    return best[1]

def write(plans):
    """BakedPlans.swift, its header kept, a plan per seed in the order picked."""
    path = os.path.join(HERE, '..', 'Sources', 'Rumkapsel', 'State', 'BakedPlans.swift')
    src = open(path).read()
    head = src[:src.index('enum BakedPlans {')]
    def cs(cells): return ';'.join(f'{x},{y}' for x, y in sorted(map(tuple, cells)))
    def block(p):
        q = '|'.join(f'{k}:{cs(v)}' for k, v in sorted(p['quarters'].items()))
        offices = '|'.join(f"{cs(o['cells'])}/{cs(o['hall'])}/{o['ring']}" for o in p['offices'])
        return f'        """\n        seed={p["seed"]}\n        quarters={q}\n        base={cs(p["base"])}\n        offices={offices}\n        """'
    by = {}
    for p in plans: by.setdefault(p['theme'], []).append(block(p))
    open(path, 'w').write(head + 'enum BakedPlans {\n    static func forTheme(_ theme: Theme) -> [String] {\n        switch theme {\n'
        + "        // The Kingdom turns no knob the plan can see, so it is laid out on Classic's.\n"
        + '        case .classic, .kingdom: return [\n' + ',\n'.join(by['classic']) + '\n        ]\n'
        + '        case .kenney: return [\n' + ',\n'.join(by['kenney']) + '\n        ]\n        }\n    }\n}\n')

def check(p):
    """Light them one at a time and prove the floor is whole at every step."""
    lit = set(map(tuple, p["base"]))
    rooms = {tuple(c) for v in p["quarters"].values() for c in v}
    for i, o in enumerate(p["offices"]):
        lit |= {tuple(c) for c in o["hall"]}
        floor = lit | rooms | {tuple(c) for v in p.get("fixed", {}).values() for c in v}
        seen, q = {next(iter(lit))}, deque([next(iter(lit))])
        while q:
            c = q.popleft()
            for a, b in ((1,0),(-1,0),(0,1),(0,-1)):
                n = (c[0]+a, c[1]+b)
                if n in floor and n not in seen: seen.add(n); q.append(n)
        assert not (lit - seen), f"hallway broke at office {i}"
        assert any((c[0]+a, c[1]+b) in lit for c in map(tuple, o["cells"])
                   for a, b in ((1,0),(-1,0),(0,1),(0,-1))), f"office {i} opens with no door"
        assert all(tuple(c) not in lit and tuple(c) not in rooms for c in o["cells"]), f"office {i} overlaps"
    return len(lit)

if __name__ == "__main__":
    plans = []
    picked = json.load(open(os.path.join(HERE, 'picked.json')))
    for theme, seeds in picked.items():
        for seed in seeds:
            p = bake(theme, seed); n = check(p); plans.append(p)
            print(f"{theme} {seed}: {len(p['offices'])} offices, base {len(p['base'])} hall, {n} lit at full")
    write(plans)
