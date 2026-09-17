"""Bake a plan into an activation order.

An office is not drawn until it is needed, so the corridor that reaches it must not be drawn either.
Each office therefore carries the hallway cells that first make it reachable: walk back from its door to
whatever is already lit, by the shortest route the full plan allows. Light them in order and the lit
floor is connected at every step, because each office only ever adds a run that touches what is there.
The essentials are all lit from the start, so the station is whole before a single office opens.
"""
import json, math
from collections import deque
ns = {}; exec(open('/tmp/claude-502/floor/radial.py').read(), ns)
plan, CX, CY, W, H = ns['plan'], ns['CX'], ns['CY'], ns['W'], ns['H']

def bake(seed):
    hall, slots, fixed = plan(seed)
    lit = set()
    # The base: the hub ring and every run that reaches an essential. Grown from the hub through the
    # corridor until each block has its door, so nothing in the fixed half waits on an office.
    want = {n: {p for x, y in cs for p in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)) if p in hall}
            for n, cs in fixed.items() if n != "core"}
    start = min(hall, key=lambda c: math.hypot(c[0]-CX, c[1]-CY))
    prev, q = {start: None}, deque([start])
    while q:
        c = q.popleft()
        for a, b in ((1,0),(-1,0),(0,1),(0,-1)):
            n = (c[0]+a, c[1]+b)
            if n in hall and n not in prev: prev[n] = c; q.append(n)
    assert len(prev) == len(hall), "the plan's corridor is not one piece"
    # Every cell the base wants is traced back to the hub, so the base is a tree rooted there and is
    # connected because of how it is built, not because the pieces happened to meet.
    seeds = {c for c in hall if math.hypot(c[0]-CX, c[1]-CY) <= ns['HUB'] + 0.5}
    for name, doors in want.items():
        assert doors, f"{name} has no door"
        seeds.add(min(doors, key=lambda p: math.hypot(p[0]-CX, p[1]-CY)))
    for c in seeds:
        while c is not None and c not in lit: lit.add(c); c = prev[c]

    out = []
    for cells, _ in slots:                      # slots already come in radial order
        doors = [p for x, y in cells for p in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)) if p in hall]
        pv, q = {p: None for p in lit}, deque(lit)
        hit = next((d for d in doors if d in lit), None)      # already reachable: it costs no hallway
        while q and hit is None:
            c = q.popleft()
            for a, b in ((1,0),(-1,0),(0,1),(0,-1)):
                n = (c[0]+a, c[1]+b)
                if n in hall and n not in pv:
                    pv[n] = c; q.append(n)
                    if n in doors: hit = n; break
        assert hit is not None, "an office cannot be reached through the corridor"
        run, c = [], hit
        while c is not None and c not in lit: run.append(c); c = pv[c]
        lit |= set(run)
        cx = sum(x for x, _ in cells)/len(cells); cy = sum(y for _, y in cells)/len(cells)
        out.append({"cells": sorted(cells), "hall": sorted(run),
                    "ring": round(math.hypot(cx-CX, cy-CY)/3)})
    return {"seed": seed, "size": [W, H], "centre": [CX, CY],
            "fixed": {n: sorted(cs) for n, cs in fixed.items()},
            "base": sorted(lit - {p for o in out for p in o["hall"]}),
            "offices": out}

def check(p):
    """Light them one at a time and prove the floor is whole at every step."""
    lit = set(map(tuple, p["base"]))
    blocks = {tuple(c) for cs in p["fixed"].values() for c in cs}
    for i, o in enumerate(p["offices"]):
        lit |= {tuple(c) for c in o["hall"]}
        walk = lit | blocks
        seen, q = {next(iter(lit))}, deque([next(iter(lit))])
        while q:
            c = q.popleft()
            for a, b in ((1,0),(-1,0),(0,1),(0,-1)):
                n = (c[0]+a, c[1]+b)
                if n in walk and n not in seen: seen.add(n); q.append(n)
        assert not (lit - seen), f"hallway broke at office {i}"
        assert any((c[0]+a, c[1]+b) in lit for c in map(tuple, o["cells"])
                   for a, b in ((1,0),(-1,0),(0,1),(0,-1))), f"office {i} has no door when it opens"
        assert all(tuple(c) not in lit for c in o["cells"]), f"office {i} sits on the hallway"
    for n, cs in p["fixed"].items():
        if n == "core": continue
        base = set(map(tuple, p["base"]))
        assert any((c[0]+a, c[1]+b) in base for c in map(tuple, cs) for a, b in ((1,0),(-1,0),(0,1),(0,-1))), \
            f"{n} is not connected before any office opens"
    return len(lit)

plans = []
for seed in (25, 27, 4, 16):
    p = bake(seed); n = check(p); plans.append(p)
    print(f"seed {seed}: {len(p['offices'])} offices, base {len(p['base'])} hall cells, "
          f"{n} lit at full, {sum(1 for o in p['offices'] if not o['hall'])} offices needing no new hallway")
json.dump(plans, open('/tmp/claude-502/floor/plans.json','w'))
