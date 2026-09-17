import random, math
from collections import deque

W = H = 86
CX = CY = 43
HUB = 5                  # the hub ring's radius: corridor on the outside of it, the core within

TETRO = [[(0,0),(1,0),(2,0),(3,0)], [(0,0),(1,0),(0,1),(1,1)], [(0,0),(1,0),(2,0),(1,1)],
         [(0,0),(1,0),(1,1),(2,1)], [(1,0),(2,0),(0,1),(1,1)],
         [(0,0),(0,1),(0,2),(1,2)], [(1,0),(1,1),(1,2),(0,2)]]
def rots(s):
    out, cur = [], s
    for _ in range(4):
        cur = [(y, -x) for x, y in cur]
        mn = (min(x for x,_ in cur), min(y for _,y in cur))
        out.append(tuple(sorted((x-mn[0], y-mn[1]) for x,y in cur)))
    return [list(t) for t in set(out)]
SHAPES = [r for s in TETRO for r in rots(s)]

def disc(r, cx=CX, cy=CY):
    return {(x, y) for x in range(cx-r-1, cx+r+2) for y in range(cy-r-1, cy+r+2)
            if math.hypot(x-cx, y-cy) <= r + 0.4}

def rim(r):
    """The outermost layer of a disc — four-connected, and round enough to read as a circle."""
    d = disc(r)
    return {c for c in d if any((c[0]+a, c[1]+b) not in d for a, b in ((1,0),(-1,0),(0,1),(0,-1)))}

def arc(r, a0, a1):
    """The part of a rim between two bearings, so a concentric road can be partial."""
    out = set()
    for c in rim(r):
        a = math.degrees(math.atan2(c[1]-CY, c[0]-CX)) % 360
        if (a0 <= a <= a1) if a0 <= a1 else (a >= a0 or a <= a1): out.add(c)
    return out

def spoke(bearing, r0, r1, rnd):
    """A corridor out from the hub along a bearing. Diagonals come out as a staircase, and every spoke
    is given a couple of jogs, so none of them is a ruled line."""
    ux, uy = math.cos(math.radians(bearing)), math.sin(math.radians(bearing))
    cells, x, y = set(), CX + ux*r0, CY + uy*r0
    px, py = round(x), round(y)
    drift = 0.0
    for _ in range(int((r1-r0) * 1.6)):
        drift += rnd.uniform(-0.45, 0.45)
        x += ux; y += uy
        tx, ty = round(x - uy*drift), round(y + ux*drift)
        while (px, py) != (tx, ty):                       # four-way steps only, never a diagonal hop
            if px != tx and (py == ty or rnd.random() < 0.5): px += 1 if tx > px else -1
            else: py += 1 if ty > py else -1
            if 2 <= px < W-2 and 2 <= py < H-2: cells.add((px, py))
            else: return cells
    return cells

# The deck runs out west and the bay hangs due south, and the runs that serve them need that ground.
# Offices are kept out of the wedge between the two past the first ring, so the station grows north and
# east instead of crowding the freight.
def outside(p, r=13, a0=112, a1=203):
    a = math.degrees(math.atan2(p[1]-CY, p[0]-CX)) % 360
    return math.hypot(p[0]-CX, p[1]-CY) < r or not (a0 <= a <= a1)

def block(cx, cy, w, h):
    return {(x, y) for x in range(cx-w//2, cx-w//2+w) for y in range(cy-h//2, cy-h//2+h)}

# The essentials are placed, not searched for. Bearings and distances are read off the sketch: the deck
# out west on its own, the bay due south, the living quarters ringing the hub close in. Everything else
# is grown around them.
def essentials():
    f = {"core": disc(HUB-2)}
    f["deck"] = block(CX-24, CY, 6, 20)
    f["bay"]  = block(CX, CY+25, 12, 6)
    for i, (bear, dist) in enumerate(((132, 11), (18, 11), (250, 11), (310, 12))):
        f[f"living{i}"] = block(round(CX + math.cos(math.radians(bear))*dist),
                                round(CY + math.sin(math.radians(bear))*dist), 5, 5)
    f["storage"] = block(CX-13, CY-1, 5, 6)
    f["decon"]   = block(CX+2, CY+18, 6, 4)
    f["pad"]     = block(CX-4, CY-19, 6, 5)
    return f

def link(block_cells, hall, reserved, n=1):
    """Join a block to the corridor by the shortest run that misses every other block. Laid after the
    corridor is one piece, so a run can never end up attached to a fragment that is later dropped."""
    got = 0
    for _ in range(n):
        src = [p for x, y in block_cells for p in ((x+1,y),(x-1,y),(x,y+1),(x,y-1))
               if p not in block_cells and p not in reserved]
        if not src: return got
        prev, q = {p: None for p in src}, deque(src)
        end = None
        while q:
            c = q.popleft()
            if c in hall: end = c; break
            for a, b in ((1,0),(-1,0),(0,1),(0,-1)):
                nb = (c[0]+a, c[1]+b)
                if nb in prev or nb in reserved: continue
                if not (1 <= nb[0] < W-1 and 1 <= nb[1] < H-1): continue
                prev[nb] = c; q.append(nb)
        if end is None: return got
        run = set()
        while end is not None: run.add(end); end = prev[end]
        hall |= run; got += 1
    return got

def gen(seed, want=100):
    rnd = random.Random(seed)
    fixed = essentials()
    reserved = set().union(*fixed.values())
    hall = rim(HUB)

    # The monolith sits in the middle, a hallway ring around it, and the living quarters on that ring.
    # Everything past it is grown, not drawn: a few spokes to hang the first offices on, and the rest
    # cut outward only where an office actually lands.
    bearings = [b + rnd.uniform(-12, 12) for b in range(0, 360, 60)]
    for b in bearings:
        far = rnd.randint(14, 21) if outside((CX + math.cos(math.radians(b))*20,
                                              CY + math.sin(math.radians(b))*20)) else 9
        hall |= {c for c in spoke(b, HUB, far, rnd) if c not in reserved}
    for i in range(len(bearings)):
        if rnd.random() < 0.35: continue
        a0, a1 = bearings[i] % 360, bearings[(i+1) % len(bearings)] % 360
        hall |= {c for c in arc(rnd.choice((11, 14)), a0, a1) if c not in reserved}

    # The essentials are joined to whatever corridor is nearest: the deck and bay get two ways in, since
    # everything the station carries goes through one or the other.
    hall -= reserved

    # A block sitting on an arc cuts it, so what was drawn as one web is not one yet. Every fragment is
    # welded to the piece the hub is on, by the shortest run that misses the blocks; anything that cannot
    # reach is not floor the station can use, and is dropped.
    def parts(h):
        out, left = [], set(h)
        while left:
            src = next(iter(left)); comp, q = {src}, deque([src])
            while q:
                c = q.popleft()
                for a, b in ((1,0),(-1,0),(0,1),(0,-1)):
                    n = (c[0]+a, c[1]+b)
                    if n in left and n not in comp: comp.add(n); q.append(n)
            out.append(comp); left -= comp
        return sorted(out, key=len, reverse=True)

    for _ in range(40):
        comps = parts(hall)
        main = next(c for c in comps if any(math.hypot(p[0]-CX, p[1]-CY) <= HUB + 1 for p in c))
        rest = [c for c in comps if c is not main]
        if not rest: break
        joined = False
        for comp in rest:
            a = min(comp, key=lambda p: min(abs(p[0]-q[0]) + abs(p[1]-q[1]) for q in main))
            b = min(main, key=lambda q: abs(a[0]-q[0]) + abs(a[1]-q[1]))
            run, x, y = set(), a[0], a[1]
            while (x, y) != b:
                if x != b[0]: x += 1 if b[0] > x else -1
                else: y += 1 if b[1] > y else -1
                run.add((x, y))
            if run & reserved: continue
            hall |= run; joined = True
        if not joined:
            hall = main
            break
    else:
        hall = parts(hall)[0]
    # Only now, with the corridor one piece, is each essential joined to it.
    keep = set(rim(HUB)) & hall
    for name, cells in fixed.items():
        if name == "core": continue
        before = set(hall)
        link(cells, hall, reserved, 2 if name in ("deck", "bay") else 1)
        keep |= hall - before
    return rnd, fixed, reserved, hall, keep

def plan(seed, want=100):
    rnd, fixed, reserved, hall, keep = gen(seed, want)
    taken, slots = set(reserved) | hall, []
    used = {i: 0 for i in range(len(SHAPES))}

    def attach(around):
        for c in rnd.sample(list(around), len(around)):
            if len(slots) >= want: return
            for ax, ay in rnd.sample([(1,0),(-1,0),(0,1),(0,-1)], 4):
                base = (c[0]+ax, c[1]+ay)
                if base in taken: continue
                for i in sorted(range(len(SHAPES)), key=lambda k: (used[k], rnd.random())):
                    cells = [(base[0]+dx, base[1]+dy) for dx, dy in SHAPES[i]]
                    if any(not (1 <= x < W-1 and 1 <= y < H-1) for x, y in cells): continue
                    if any(p in taken for p in cells): continue
                    if not all(outside(p) for p in cells): continue
                    if not any((x+a, y+b) in hall for x, y in cells for a, b in ((1,0),(-1,0),(0,1),(0,-1))):
                        continue                      # a room you cannot walk into is not a room
                    slots.append((cells, c)); taken.update(cells); used[i] += 1; break
                if len(slots) >= want: return

    near = lambda c: (abs(c[0]-CX) + abs(c[1]-CY), c)
    for _ in range(6):
        if len(slots) >= want: break
        attach(sorted(hall, key=near))

    def reach(h, frm=None):
        src = frm or [min(h, key=near)]
        d, q = {p: 0 for p in src}, deque(src)
        while q:
            c = q.popleft()
            for a, b in ((1,0),(-1,0),(0,1),(0,-1)):
                n = (c[0]+a, c[1]+b)
                if n in h and n not in d: d[n] = d[c] + 1; q.append(n)
        return d
    def doorsof(cs, h):
        return {p for x, y in cs for p in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)) if p in h}

    # A corridor with nothing on it is wasted floor: cross corridors are cut outward into whatever space
    # is left and offices hung off those, and any arm that came back empty is taken straight back up.
    # This is what fills the station out, rather than drawing a web and hoping rooms find it.
    for _ in range(900):
        if len(slots) >= want: break
        bare = [c for c in hall
                if any((c[0]+a, c[1]+b) not in taken and 2 <= c[0]+a < W-2 and 2 <= c[1]+b < H-2
                       for a, b in ((1,0),(-1,0),(0,1),(0,-1)))]
        if not bare: break
        rnd.shuffle(bare)
        for c in bare[:14]:
            if len(slots) >= want: break
            for d in rnd.sample([(1,0),(-1,0),(0,1),(0,-1)], 4):
                arm, x, y = [], c[0], c[1]
                for _ in range(rnd.randint(2, 4)):
                    x, y = x + d[0], y + d[1]
                    if not (2 <= x < W-2 and 2 <= y < H-2) or (x, y) in taken: break
                    if not outside((x, y)): break
                    arm.append((x, y))
                if len(arm) < 2: continue
                before = len(slots)
                hall.update(arm); taken.update(arm)
                attach(arm)
                if len(slots) == before:
                    hall.difference_update(arm); taken.difference_update(arm); continue
                break

    # Corridors close in space but far apart on foot get the gap punched through; an office in the way
    # loses, because a room is worth less than the walk it costs everyone else.
    for _ in range(8):
        dist = reach(hall); cut, drop = set(), set()
        for c in sorted(hall, key=lambda p: dist.get(p, 0)):
            if c not in dist: continue
            for d in ((1,0),(-1,0),(0,1),(0,-1)):
                gap = []
                for k in range(1, 4):
                    p = (c[0]+d[0]*k, c[1]+d[1]*k)
                    if not (1 <= p[0] < W-1 and 1 <= p[1] < H-1) or p in reserved: break
                    if p in hall:
                        if gap and dist.get(p, 0) - dist[c] > 4 + 2*len(gap):
                            cut |= set(gap)
                            drop |= {i for i, (cs, _) in enumerate(slots) if set(cs) & set(gap)}
                        break
                    gap.append(p)
        if not cut: break
        slots = [sl for i, sl in enumerate(slots) if i not in drop]
        hall |= cut
        taken = set(reserved) | hall | {p for cs, _ in slots for p in cs}

    # One tile wide, but only where the width costs nothing: the cell in a 2x2 is often the corner two
    # corridors cross at, and taking it sends everyone the long way round. The walk is the test.
    wide = lambda c, h: any(all((c[0]+dx, c[1]+dy) in h for dx in (0, ox) for dy in (0, oy))
                            for ox in (1,-1) for oy in (1,-1))
    base = reach(hall)
    for c in sorted(hall, key=near, reverse=True):
        if c in keep or not wide(c, hall): continue
        trial = hall - {c}
        d = reach(trial)
        if len(d) != len(trial) or any(d[p] > base[p] for p in trial): continue
        if any(doorsof(cs, hall) and not doorsof(cs, trial) for cs, _ in slots): continue
        hall, base = trial, d

    taken = set(reserved) | hall | {p for cs, _ in slots for p in cs}
    for _ in range(4):
        if len(slots) >= want: break
        attach(sorted(hall, key=near))

    # Corridor that earns nothing goes. A spoke is laid long so offices have something to hang off, but
    # wherever the end of one came back empty it is just floor, and the station should not draw it.
    rooms = {p for cs, _ in slots for p in cs}
    touch = lambda c, s: any((c[0]+a, c[1]+b) in s for a, b in ((1,0),(-1,0),(0,1),(0,-1)))
    while True:
        dead = {c for c in hall
                if sum(1 for a, b in ((1,0),(-1,0),(0,1),(0,-1)) if (c[0]+a, c[1]+b) in hall) <= 1
                and c not in keep and not touch(c, rooms) and not touch(c, reserved)}
        if not dead: break
        hall -= dead

    rooms = {p for cs, _ in slots for p in cs}
    assert not (hall & rooms) and not (rooms & reserved)
    for name, cells in fixed.items():
        if name == "core": continue
        assert any((x+a, y+b) in hall for x, y in cells for a, b in ((1,0),(-1,0),(0,1),(0,-1))), \
            f"{name} has no way in"
    assert rim(HUB) - reserved <= hall, "the hub ring is broken"
    return hall, sorted(slots, key=lambda it: (round(math.hypot(sum(x for x,_ in it[0])/4-CX,
                                                                sum(y for _,y in it[0])/4-CY)/3),
                                               math.atan2(sum(y for _,y in it[0])/4-CY,
                                                          sum(x for x,_ in it[0])/4-CX))), fixed
