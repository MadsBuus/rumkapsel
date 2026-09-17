"""Draw a station's hallway and offices around the fixed floor the app already owns.

The one generator. The fixed floor is not described here: it is dumped out of the app, so there is no
second copy of the yard to drift from the first.

The yard, the bay, the airlock and the plaza's two fixed arms are not ours to move: they are dumped out
of the app (`--dump-floor`) with all their doorways and lanes, and everything here grows around them. So
a plan belongs to a theme, because a theme's yard is not in the same place.
"""
import json, math, random, sys
from collections import deque

R = 4                      # rings of the web, out from the plaza
SPAN = 30                  # how far from the monolith a plan may reach

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
# Which of the seven a rotation came from. An I fits a one-cell strip beside a corridor and the fat
# pieces do not, so left to itself the floor fills with bars: two thirds of what is left over after a
# room is placed is a strip. The counting below is per family, not per rotation, and it is what keeps
# the mix even — a rotation of the T is still a T.
FAMILY = [i for i, s in enumerate(TETRO) for _ in rots(s)]
FAT = {i for i, f in enumerate(FAMILY) if f != 0}      # everything but the I
# The quarters keep the sizes the station already gives them, so nothing downstream has to change.
QUARTERS = [("lounge", 3, 3), ("quarters", 2, 4), ("bath", 2, 2), ("gym", 3, 2)]

def load(theme):
    d = json.load(open(f'/tmp/claude-502/floor/{theme}.json'))
    fixed = {k: [tuple(c) for c in v] for k, v in d.items() if k != "monolith"}
    # The airlock pierces the hull and the bay floats outside it, where the shuttles put down. The hull
    # is the line the airlock starts at: past it there is no floor to build on, only space, so nothing
    # this generator lays may go there.
    hull = min(y for _, y in fixed["airlock"])
    return fixed, tuple(d["monolith"]), hull

def inside(p, hull):
    return p[1] < hull

def rim(r):
    d = {(x, y) for x in range(-r-1, r+2) for y in range(-r-1, r+2) if math.hypot(x, y) <= r + 0.4}
    return {c for c in d if any((c[0]+a, c[1]+b) not in d for a, b in ((1,0),(-1,0),(0,1),(0,-1)))}

def arc(r, a0, a1, blocked, hull):
    """One contiguous span of a ring, between two spokes. Whole spans, never a ring with holes punched
    through it: holes leave fragments, and welding fragments back together lays long straight runs the
    plan never asked for."""
    out = set()
    for c in rim(r):
        if c in blocked or not inside(c, hull): continue
        a = math.degrees(math.atan2(c[1], c[0])) % 360
        if (a0 <= a <= a1) if a0 <= a1 else (a >= a0 or a <= a1): out.add(c)
    return out

def spoke(bearing, r0, r1, rnd, blocked, hull):
    ux, uy = math.cos(math.radians(bearing)), math.sin(math.radians(bearing))
    cells, x, y = set(), ux*r0, uy*r0
    px, py = round(x), round(y)
    drift = 0.0
    for _ in range(int((r1-r0) * 1.6)):
        drift += rnd.uniform(-0.45, 0.45)
        x += ux; y += uy
        tx, ty = round(x - uy*drift), round(y + ux*drift)
        while (px, py) != (tx, ty):
            if px != tx and (py == ty or rnd.random() < 0.5): px += 1 if tx > px else -1
            else: py += 1 if ty > py else -1
            if (px, py) in blocked or math.hypot(px, py) > SPAN or not inside((px, py), hull): return cells
            cells.add((px, py))
    return cells

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

def gen(theme, seed, want=100):
    fixed, mono, hull = load(theme)
    rnd = random.Random(seed)
    reserved = set().union(*fixed.values())
    # The plaza and the two fixed arms are hallway from the start; nothing else is, yet.
    hall = set(fixed["plaza"]) | set(fixed["west"]) | set(fixed["south"])
    hall.discard(mono)
    blocked = reserved - hall

    bearings = [b + rnd.uniform(-12, 12) for b in range(0, 360, 60)]
    for b in bearings:
        hall |= spoke(b, R, rnd.randint(14, 22), rnd, blocked, hull)
    for r in (rnd.choice((10, 12)), rnd.choice((17, 20))):
        for i in range(len(bearings)):
            if rnd.random() < 0.35: continue          # a ring is partial: some spans are simply not there
            hall |= arc(r, bearings[i] % 360, bearings[(i+1) % len(bearings)] % 360, blocked, hull)

    # A block sitting across an arc cuts it; every fragment is welded to the plaza's piece or dropped.
    for _ in range(40):
        comps = parts(hall)
        main = next(c for c in comps if mono in {(p[0]+a, p[1]+b) for p in c for a, b in ((1,0),(-1,0),(0,1),(0,-1))} or any(math.hypot(*p) <= 2 for p in c))
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
            if run & blocked or any(not inside(p, hull) for p in run): continue
            hall |= run; joined = True
        if not joined:
            hall = main; break
    else:
        hall = parts(hall)[0]
    return rnd, fixed, mono, reserved, blocked, hall, hull

def plan(theme, seed, want=100):
    rnd, fixed, mono, reserved, blocked, hall, hull = gen(theme, seed, want)
    taken = set(reserved) | hall
    slots, quarters = [], {}
    used = {f: 0 for f in range(len(TETRO))}
    near = lambda c: (abs(c[0]) + abs(c[1]), c)
    door = lambda cs: any((x+a, y+b) in hall for x, y in cs for a, b in ((1,0),(-1,0),(0,1),(0,-1)))

    # The quarters go first and nearest: they are lit before any office, so they cannot be left to
    # whatever floor is spare once a hundred offices have taken theirs.
    for name, w, h in QUARTERS:
        best = None
        for c in sorted(hall, key=near):
            for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                for ox in range(-w+1, 1):
                    for oy in range(-h+1, 1):
                        base = (c[0]+dx+ox, c[1]+dy+oy)
                        cs = [(base[0]+i, base[1]+j) for i in range(w) for j in range(h)]
                        if any(p in taken for p in cs) or not door(cs): continue
                        if any(not inside(p, hull) for p in cs): continue
                        # Kept together: each one beside what is already placed, once there is any.
                        pull = min((abs(p[0]-q[0]) + abs(p[1]-q[1]) for p in cs
                                    for q in [q for v in quarters.values() for q in v]), default=0)
                        score = (near(c)[0] + 3 * pull, sorted(cs))
                        if best is None or score < best[0]: best = (score, cs)
            if best is not None and best[0][0] <= near(c)[0] + 1: break
        assert best, f"{theme} {seed}: nowhere for the {name}"
        quarters[name] = best[1]; taken.update(best[1])

    def attach(around, only=None):
        pool = range(len(SHAPES)) if only is None else sorted(only)
        for c in rnd.sample(list(around), len(around)):
            if len(slots) >= want: return
            for ax, ay in rnd.sample([(1,0),(-1,0),(0,1),(0,-1)], 4):
                base = (c[0]+ax, c[1]+ay)
                if base in taken: continue
                # Least-used family first, so no one piece does all the work.
                for i in sorted(pool, key=lambda k: (used[FAMILY[k]], rnd.random())):
                    cs = [(base[0]+dx, base[1]+dy) for dx, dy in SHAPES[i]]
                    if any(p in taken for p in cs) or any(math.hypot(*p) > SPAN for p in cs): continue
                    if any(not inside(p, hull) for p in cs): continue
                    if not door(cs): continue
                    slots.append(cs); taken.update(cs); used[FAMILY[i]] += 1; break
                if len(slots) >= want: return

    for _ in range(6):
        if len(slots) >= want: break
        attach(sorted(hall, key=near), only=FAT)
    for _ in range(4):
        if len(slots) >= want: break
        attach(sorted(hall, key=near))

    # Corridor with nothing on it is wasted floor: arms are cut outward and offices hung off them, and
    # any arm that came back empty is taken straight up again.
    for _ in range(900):
        if len(slots) >= want: break
        bare = [c for c in hall if any((c[0]+a, c[1]+b) not in taken and math.hypot(c[0]+a, c[1]+b) <= SPAN
                                       for a, b in ((1,0),(-1,0),(0,1),(0,-1)))]
        if not bare: break
        rnd.shuffle(bare)
        for c in bare[:14]:
            if len(slots) >= want: break
            for d in rnd.sample([(1,0),(-1,0),(0,1),(0,-1)], 4):
                arm, x, y = [], c[0], c[1]
                for _ in range(rnd.randint(2, 4)):
                    x, y = x + d[0], y + d[1]
                    if (x, y) in taken or math.hypot(x, y) > SPAN or not inside((x, y), hull): break
                    arm.append((x, y))
                if len(arm) < 2: continue
                before = len(slots)
                hall.update(arm); taken.update(arm)
                attach(arm, only=FAT)
                if len(slots) == before: attach(arm)
                if len(slots) == before:
                    hall.difference_update(arm); taken.difference_update(arm); continue
                break

    def reach(h):
        src = [p for p in h if math.hypot(*p) <= 2] or [min(h, key=near)]
        d, q = {p: 0 for p in src}, deque(src)
        while q:
            c = q.popleft()
            for a, b in ((1,0),(-1,0),(0,1),(0,-1)):
                n = (c[0]+a, c[1]+b)
                if n in h and n not in d: d[n] = d[c] + 1; q.append(n)
        return d
    rooms_all = lambda: slots + list(quarters.values())
    doorsof = lambda cs, h: {p for x, y in cs for p in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)) if p in h}

    # Two corridors near in space but far apart on foot: the gap is punched through, and an office in
    # the way loses. A room is worth less than the walk it costs everyone else.
    for _ in range(8):
        dist = reach(hall); cut, drop = set(), set()
        for c in sorted(hall, key=lambda p: dist.get(p, 0)):
            if c not in dist: continue
            for d in ((1,0),(-1,0),(0,1),(0,-1)):
                gap = []
                for k in range(1, 4):
                    p = (c[0]+d[0]*k, c[1]+d[1]*k)
                    if p in blocked or math.hypot(*p) > SPAN or not inside(p, hull): break
                    if p in hall:
                        if gap and dist.get(p, 0) - dist[c] > 4 + 2*len(gap):
                            cut |= set(gap)
                            drop |= {i for i, cs in enumerate(slots) if set(cs) & set(gap)}
                        break
                    if any(p in cs for cs in quarters.values()): break   # the quarters are not moved
                    gap.append(p)
        if not cut: break
        slots = [s for i, s in enumerate(slots) if i not in drop]
        hall |= cut
        taken = set(reserved) | hall | {p for cs in rooms_all() for p in cs}

    # One tile wide, but only where the width costs nothing: the cell in a 2x2 is often the corner two
    # corridors cross at, and taking it sends everyone the long way round. The walk is the test.
    keep = set(fixed["plaza"]) | set(fixed["west"]) | set(fixed["south"])
    wide = lambda c, h: any(all((c[0]+dx, c[1]+dy) in h for dx in (0, ox) for dy in (0, oy))
                            for ox in (1,-1) for oy in (1,-1))
    base_d = reach(hall)
    for c in sorted(hall, key=near, reverse=True):
        if c in keep or not wide(c, hall): continue
        trial = hall - {c}
        d = reach(trial)
        if len(d) != len(trial) or any(d[p] > base_d[p] for p in trial): continue
        if any(doorsof(cs, hall) and not doorsof(cs, trial) for cs in rooms_all()): continue
        hall, base_d = trial, d

    taken = set(reserved) | hall | {p for cs in rooms_all() for p in cs}
    for _ in range(4):
        if len(slots) >= want: break
        attach(sorted(hall, key=near))

    # Corridor that earns nothing goes: a spoke is laid long so offices have something to hang off, and
    # wherever the end of one came back empty the station should not draw it.
    rooms = {p for cs in rooms_all() for p in cs}
    touch = lambda c, s: any((c[0]+a, c[1]+b) in s for a, b in ((1,0),(-1,0),(0,1),(0,-1)))
    while True:
        dead = {c for c in hall
                if sum(1 for a, b in ((1,0),(-1,0),(0,1),(0,-1)) if (c[0]+a, c[1]+b) in hall) <= 1
                and c not in keep and not touch(c, rooms) and not touch(c, reserved)}
        if not dead: break
        hall -= dead

    # A cell on a loop is never a dead end, so the sweep above leaves whole rings of corridor that no
    # room ever opens onto. Those go too — but only where the walk can spare them: a ring that is
    # carrying nothing is waste, and a ring that is somebody's short way round is not.
    base_d = reach(hall)
    for c in sorted(hall, key=near, reverse=True):
        if c in keep or touch(c, rooms) or touch(c, reserved): continue
        trial = hall - {c}
        d = reach(trial)
        if len(d) != len(trial): continue
        if any(d[p] > base_d[p] + 2 for p in trial): continue
        hall, base_d = trial, d

    outside_hull = [p for p in hall | rooms if not inside(p, hull)]
    assert not outside_hull, f"{len(outside_hull)} cells were laid outside the hull, in space"
    assert not (hall & rooms), "a room stands on the hallway"
    assert not (rooms & reserved), "a room stands on the yard"
    assert len(parts(hall)) == 1, "the hallway is in pieces"
    ring = lambda cs: round(math.hypot(sum(x for x,_ in cs)/len(cs), sum(y for _,y in cs)/len(cs)) / 3)
    slots.sort(key=lambda cs: (ring(cs), math.atan2(sum(y for _,y in cs)/len(cs), sum(x for x,_ in cs)/len(cs))))
    return hall, slots, quarters, fixed, mono, ring
