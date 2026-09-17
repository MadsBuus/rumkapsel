"""Bake a plan into an activation order.

An office is not drawn until it is needed, so the hallway that reaches it must not be drawn either. Each
office carries the run of hallway that first makes it reachable: walk back from its door to whatever is
already lit, by the shortest route the plan allows. Light them in order and the lit floor is connected at
every step, because an office only ever adds a run that touches what is there.

The base — the plaza, the fixed arms, the runs to the yard and the bay, and the quarters — is lit before
a single office opens, so the station is whole from the start.
"""
import json, math, sys
from collections import deque
ns = {}; exec(open('/tmp/claude-502/floor/floorplan.py').read(), ns)

def bake(theme, seed):
    hall, slots, quarters, fixed, mono, ring = ns['plan'](theme, seed)
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
    return {"theme": theme, "seed": seed, "quarters": {k: sorted(v) for k, v in quarters.items()},
            "fixed": {k: sorted(v) for k, v in fixed.items()},
            "base": sorted(lit - {p for o in out for p in o["hall"]}), "offices": out}

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
    picked = json.load(open('/tmp/claude-502/floor/picked.json'))
    for theme, seeds in picked.items():
        for seed in seeds:
            p = bake(theme, seed); n = check(p); plans.append(p)
            print(f"{theme} {seed}: {len(p['offices'])} offices, base {len(p['base'])} hall, {n} lit at full")
    json.dump(plans, open('/tmp/claude-502/floor/plans.json', 'w'))
