// Model-only tests of the floor plan: `.build/debug/Rumkapsel --layout-tests`.
//
// The plan is meant to be a pure function of shared facts, so that a station shared across machines
// looks the same on every one of them. These hold it to that: two stations built from nothing and given
// the same rooms in the same order lay them out identically, and a room's shape follows its key.

import Foundation
import simd

enum LayoutTests {
    private static var failures = 0

    static func run() -> Never {
        Theme.pinnedForPlan = .classic   // the plan as Classic lays it out, whatever the config says
        OfficePlacement.pinned = .rings
        let keys = ["task:web#455", "task:api#5158", "task:ios#298", "branch:web/feature-x", "task:web#460", "task:api#5140"]

        test("two stations given the same rooms in the same order lay them out cell for cell the same") {
            let a = fresh(), b = fresh()
            for k in keys { place(k, on: a); place(k, on: b) }
            for k in keys + ["kind:lounge", "kind:quarters", "kind:bath", "kind:gym"] {
                expect(a.rooms[k]?.cells == b.rooms[k]?.cells && a.rooms[k] != nil, "\(k): \(cells(a, k)) against \(cells(b, k))")
            }
            expect(a.dug == b.dug, "and the same hallway was dug: \(a.dugCount) and \(b.dugCount) cells")
        }

        test("a room's shape is its slot's, not its key's: the same key on an empty station takes the same cells twice") {
            let a = fresh(), b = fresh()
            place("task:web#455", on: a); place("task:web#455", on: b)
            expect(a.rooms["task:web#455"]?.cells == b.rooms["task:web#455"]?.cells, "\(cells(a, "task:web#455")) against \(cells(b, "task:web#455"))")
            // The plan holds the shapes, so a key no longer picks one — but the plan's own are varied.
            let shapes = Set(Floorplan.forStation("work").slots.prefix(40).map { s -> [Cell] in
                let mx = s.cells.map(\.x).min() ?? 0, my = s.cells.map(\.y).min() ?? 0
                return s.cells.map { Cell(x: $0.x - mx, y: $0.y - my) }.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
            })
            expect(shapes.count > 4, "and the plan draws more than one shape: \(shapes.count) in the first forty slots")
        }

        test("every room touches the corridor and none stands on reserved floor") {
            let a = fresh()
            for k in keys { place(k, on: a) }
            for (k, r) in a.rooms {
                expect(r.cells.contains { c in c.neighbours.contains { a.isCorridor($0) } }, "\(k) has a door on the corridor")
                expect(!r.cells.contains { a.isReserved($0) }, "\(k) keeps off the corridor and the yard")
            }
        }

        test("offices fill from the nearest free slot, and a slot comes back when its office goes") {
            let a = fresh()
            for i in 0..<12 { place("task:repo\(i % 3)#\(200 + i)", on: a) }
            let plan = a.floor
            let taken = a.rooms.values.compactMap { r in r.cells.first.flatMap { plan.slotOf[$0] } }.sorted()
            expect(taken == Array(taken.indices), "the first twelve offices took the first twelve slots: \(taken)")

            // A slot freed by an office closing is the next one handed out, not one further along.
            let middle = a.rooms.values.first { r in r.cells.first.flatMap { plan.slotOf[$0] } == 4 }
            expect(middle != nil, "an office stands in slot 4")
            let cells = middle!.cells
            a.removeRoom(key: middle!.key)
            place("task:repo0#999", on: a)
            expect(a.rooms["task:repo0#999"]?.cells == cells, "the new office took the freed slot back")
        }

        test("hallway dug for offices that have gone is given back, and the rest stays whole") {
            let a = fresh()
            for i in 0..<16 { place("task:repo\(i % 3)#\(300 + i)", on: a) }
            let full = a.dugCount
            expect(full > 0 && a.spareHallway().isEmpty, "with every office standing nothing is spare, of \(full) cells dug")
            // The inner offices close and the outermost stays: only the way to it is kept.
            let plan = a.floor
            let offices = a.rooms.values.filter { $0.key.hasPrefix("task:") }
            let outer = offices.max { ($0.cells.first.flatMap { plan.slotOf[$0] } ?? 0) < ($1.cells.first.flatMap { plan.slotOf[$0] } ?? 0) }!
            let door = a.doorCell(of: outer.key)
            for r in offices where r.key != outer.key { a.removeRoom(key: r.key) }
            a.giveBack(a.spareHallway())
            expect(a.dugCount < full, "hallway was given back: \(a.dugCount) of \(full) cells kept")
            expect(a.doorCell(of: outer.key) == door, "the office left keeps its door")
            expect(whole(a), "and the hallway is one piece with every room's door on it")
            // Offices opening in the freed slots find their way back along the plan's hallway.
            for i in 0..<5 { place("task:between\(i)#\(500 + i)", on: a) }
            expect(whole(a), "offices opening between are reached: \(a.dugCount) cells dug")
            for i in 0..<5 { a.removeRoom(key: "task:between\(i)#\(500 + i)") }
            a.giveBack(a.spareHallway())
            // The last one goes: nothing dug is needed, and offices opening again find their way.
            a.removeRoom(key: outer.key)
            a.giveBack(a.spareHallway())
            expect(a.dugCount == 0, "with no offices no dug hallway is left: \(a.dugCount)")
            for i in 0..<16 { place("task:again\(i % 3)#\(400 + i)", on: a) }
            expect(whole(a), "offices opening again are reached: \(a.dugCount) cells dug")
        }

        test("every baked plan is whole: the essentials are joined before any office, and lighting the slots in order never breaks the floor") {
            expect(!Floorplan.all().isEmpty, "there are baked plans: \(Floorplan.all().count)")
            for plan in Theme.allCases.flatMap({ Floorplan.all($0) }) {
                // Loading ran `check()`, which is where a bad bake stops the process. This states what it
                // covers, and adds what a plan is for: a hundred slots, in order of their distance out.
                expect(plan.slots.count >= 100, "plan \(plan.seed) has \(plan.slots.count) office slots")
                // Slots open in rings out from the monolith, each ring sweeping round before the next
                // begins — so the ring never goes back, though a slot's bearing does.
                let rings = plan.slots.map(\.ring)
                expect(zip(rings, rings.dropFirst()).allSatisfy { $0 <= $1 },
                       "plan \(plan.seed) opens ring by ring outward, \(rings.first ?? 0) to \(rings.last ?? 0)")
                for name in ["lounge", "quarters", "bath", "gym"] {
                    expect(plan.quarters[name] != nil, "plan \(plan.seed) places the \(name)")
                }
                let hall = Set(plan.base) .union(plan.slots.flatMap(\.hall))
                let rooms = Set(plan.slots.flatMap(\.cells)).union(plan.quarters.values.joined())
                expect(hall.isDisjoint(with: rooms), "plan \(plan.seed): no office stands on hallway")
            }
        }

        test("a station's plan follows its name, so two machines sharing a station draw the same floor") {
            let a = Floorplan.forStation("work"), b = Floorplan.forStation("work")
            expect(a.seed == b.seed, "the same name gives the same plan: \(a.seed) and \(b.seed)")
            let names = ["work", "private", "team", "solo", "lab", "desk"]
            expect(Set(names.map { Floorplan.forStation($0).seed }).count > 1, "and different names do not all get one plan")
        }

        test("the hallway is one piece: every built cell is reached from the plaza, and the arms keep apart") {
            let a = fresh()
            let hall = Set(a.corridorCells + a.coreCells).subtracting([a.monolithCell])
            let unreached = hall.filter { a.hallDistance(of: $0) == nil }
            expect(unreached.isEmpty, "unreached hallway: \(unreached.map { "\($0.x),\($0.y)" })")
            expect(a.floor.allHall.isDisjoint(with: Set(a.floor.slots.flatMap(\.cells))),
                   "and no office of the plan stands where hallway will run")
        }

        test("two stations that placed one room differently agree once the lower name's cells are taken") {
            let a = fresh(), b = fresh()
            for k in keys.prefix(3) { place(k, on: a); place(k, on: b) }
            place("task:web#900", on: b)             // b heard of one more room first
            place("task:api#901", on: a); place("task:api#901", on: b)   // then both placed the same room, against different floors
            place("task:web#900", on: a)
            let differ = a.rooms["task:api#901"]!.cells != b.rooms["task:api#901"]!.cells || a.rooms["task:web#900"]!.cells != b.rooms["task:web#900"]!.cells
            expect(differ, "the two disagree before the tie-break")
            // a has the lower name: b takes a's cells for every room they disagree on, all at once.
            expect(b.replaceRooms(["task:api#901", "task:web#900"].map { ($0, a.rooms[$0]!.cells) }), "the disputed rooms are taken as a placed them")
            for k in ["task:api#901", "task:web#900"] { expect(a.rooms[k]?.cells == b.rooms[k]?.cells, "\(k): \(cells(a, k)) against \(cells(b, k))") }
            let hall = Set(b.corridorCells + b.coreCells).subtracting([b.monolithCell])
            expect(hall.allSatisfy { b.hallDistance(of: $0) != nil }, "b's hallway is still one piece")
            for (k, r) in b.rooms { expect(r.cells.contains { c in c.neighbours.contains { b.isCorridor($0) } }, "\(k) still has a door on the hallway") }
        }

        test("forty rooms: the station builds outward along the hallway, every room on it, none on the plan") {
            let a = fresh()
            let before = a.dugCount
            for i in 0..<40 { place("task:repo\(i % 5)#\(100 + i)", on: a) }
            for (k, r) in a.rooms {
                expect(r.cells.contains { c in c.neighbours.contains { a.isCorridor($0) } }, "\(k) has a door on the hallway")
                expect(!r.cells.contains { a.isReserved($0) }, "\(k) keeps off the hallway and the yard")
            }
            expect(a.dugCount > before, "hallway was dug for them: \(a.dugCount) cells")
            let hallway = Set(a.corridorCells + a.coreCells)
            for (k, r) in a.rooms { expect(!r.cells.contains(where: hallway.contains), "\(k) does not stand on the hallway") }
            // An office takes a slot; the quarters take the places the plan keeps for them.
            let kept = Set(a.floor.quarters.values.joined())
            expect(a.rooms.values.allSatisfy { r in
                r.cells.contains { a.floor.slotOf[$0] != nil } || r.cells.allSatisfy(kept.contains)
            }, "every room took a place the plan holds; none was parked unplaced")
            let hall = Set(a.corridorCells + a.coreCells).subtracting([a.monolithCell])
            let unreached = hall.filter { a.hallDistance(of: $0) == nil }
            expect(unreached.isEmpty, "and every dug cell is reached from the plaza: \(unreached.count) are not")
            var edges = 0
            for c in hall { for n in c.neighbours where hall.contains(n) && (n.x, n.y) > (c.x, c.y) { edges += 1 } }
            expect(edges >= hall.count, "the hallway has links, so there are ways round: \(edges) edges over \(hall.count) cells")
            let walks = a.rooms.values.compactMap { r in r.cells.flatMap(\.neighbours).compactMap { a.hallDistance(of: $0) }.min() }
            FileHandle.standardError.write("mean steps from a door to the plaza: \(walks.reduce(0, +) / max(1, walks.count)), farthest \(walks.max() ?? 0)\n".data(using: .utf8)!)
            draw(a)
        }

        test("by repository: an office opens beside its repository's others, and a new repository starts clear of them") {
            OfficePlacement.pinned = .byRepo
            defer { OfficePlacement.pinned = .rings }
            let order = (0..<24).map { "task:repo\($0 % 4)#\(300 + $0)" }
            let a = fresh(), b = fresh()
            for k in order { place(k, on: a); place(k, on: b) }
            expect(order.allSatisfy { a.rooms[$0]?.cells == b.rooms[$0]?.cells }, "two stations given the same rooms in the same order still agree")
            expect(whole(a), "the hallway is one piece and every office has its door on it")
            let rings = fresh()
            OfficePlacement.pinned = .rings
            for k in order { place(k, on: rings) }
            OfficePlacement.pinned = .byRepo
            let together = neighbourly(a), apart = neighbourly(rings)
            expect(together >= 0.8, "most offices' nearest office is their own repository's: \(Int(together * 100))%")
            expect(together > apart, "and more than in rings: \(Int(together * 100))% against \(Int(apart * 100))%")
            draw(a, byRepo: true)
        }

        test("a station laid out afresh on load takes the placement it is set to, and keeps every office") {
            let order = (0..<24).map { "task:repo\($0 % 4)#\(300 + $0)" }
            let before = fresh()
            for k in order { place(k, on: before) }
            let saved = before.saved
            OfficePlacement.pinned = .byRepo
            defer { OfficePlacement.pinned = .rings }
            let after = Station(name: "work")
            after.restore(saved, relayout: true)
            for place in [Place.quarters, .lounge, .bath, .gym] { after.ensureFixedRoom(place) }
            expect(Set(after.rooms.keys) == Set(before.rooms.keys), "the same rooms stand: \(after.rooms.count) against \(before.rooms.count)")
            expect(whole(after), "the hallway is one piece and every office has its door on it")
            expect(neighbourly(after) >= 0.8, "the offices stand by repository: \(Int(neighbourly(after) * 100))%")
            let kept = Station(name: "work")
            kept.restore(saved)
            expect(order.allSatisfy { kept.rooms[$0]?.cells == before.rooms[$0]?.cells }, "and without a relayout every office keeps its cells")
        }

        test("Classic's pad stands right north of the deck, as it always has") {
            let a = fresh()
            expect(Set(a.deckCells.map { Cell(x: $0.x, y: $0.y - 4) }) == Set(a.padCells), "pad \(cells(a.padCells)) against the deck moved north")
        }

        test("the hull is over everything but the pad and the bay, meets the floor where its pieces stand, and lets you through its doorways") {
            let a = fresh()
            for i in 0..<20 { place("task:repo\(i % 5)#\(100 + i)", on: a) }
            let hull = StationHull(a)
            let out = (a.padCells + a.hangarCells).filter { hull.inside.contains($0) }
            expect(out.isEmpty, "the pad and the bay are under open space: \(cells(out))")
            let indoors = a.storageCells + a.deckCells + a.deconCells + a.airlockCells + a.coreCells
            let missed = indoors.filter { !hull.inside.contains($0) }
            expect(missed.isEmpty, "storage, the deck, decon, the airlock and the hallway are indoors: \(cells(missed))")
            // Where the station's view draws its pieces: across the airlock's outer door, and along the pad's east side.
            if let door = a.airlockCells.max(by: { $0.y < $1.y }) {
                let foot = SIMD2(Double(door.x), Double(door.y) + 0.5)
                expect(hull.reach(foot).distance < 0.01 && hull.reach(foot).door, "the airlock's outer door is a doorway in the hull's foot")
            }
            if let east = a.padCells.map(\.x).max(), let y = a.padCells.map(\.y).min() {
                let foot = SIMD2(Double(east) + 0.5, Double(y) + 0.5)
                expect(hull.reach(foot).distance < 0.01, "the hull meets the floor along the pad's east side")
            }
            for (deck, pad) in a.gateDoorway {
                let through = (SIMD2(Double(deck.x), Double(deck.y)) + SIMD2(Double(pad.x), Double(pad.y))) / 2
                let roof = hull.roof(over: through + SIMD2(0, Double(deck.y - pad.y)) * 0.01, top: 0.5) ?? .infinity
                expect(roof > 0.5, "a body walks through the gate under the hull: roof \(roof)")
            }
            let crown = StationHull.height(atDistance: 99)
            expect(abs(crown - StationHull.section.rise) < 1e-9 && StationHull.height(atDistance: 0) == 0,
                   "upright from the floor to a crown \(StationHull.section.rise) up, got \(crown)")
        }

        test("signs say one thing each, stand apart, hang on real walls and point the way a minion would walk") {
            let a = fresh()
            for i in 0..<20 { place("task:repo\(i % 5)#\(100 + i)", on: a) }
            let signs = Signs.plan(a)
            expect(!signs.isEmpty, "a station with a hallway has signs")
            let places = Signs.places(a)
            let hall = Set(a.corridorCells + a.coreCells)
            for s in signs {
                let beyond = Cell(x: s.cell.x + s.wall.x, y: s.cell.y + s.wall.y)
                expect(hall.contains(s.cell), "a sign stands in the hallway: \(s.cell)")
                expect(!a.walkable.contains(beyond) || !a.canStep(from: s.cell, to: beyond), "a sign hangs on a wall, not in a doorway: \(s.cell)")
                let named = s.ways.flatMap(\.places)
                expect(Set(named).count == named.count, "each place once on a sign: \(named)")
                for p in places where p.cells.contains(s.cell) { expect(!named.contains(p.name), "no sign points to where it stands: \(p.name)") }
                // A step the way an arrow points, for whoever faces the sign, is a step nearer each place it names.
                for way in s.ways {
                    let d = s.wall
                    let w = [Signs.Turn.left: SIMD2(d.y, -d.x), .right: SIMD2(-d.y, d.x), .back: SIMD2(-d.x, -d.y)][way.turn]!
                    let next = Cell(x: s.cell.x + w.x, y: s.cell.y + w.y)
                    for name in way.places {
                        guard let p = places.first(where: { $0.name == name }) else { continue }
                        let far = walked(a, to: p.cells)
                        expect(a.canStep(from: s.cell, to: next) && far[next].map { $0 + 1 == far[s.cell] } == true,
                               "the \(way.turn) arrow at \(s.cell) facing \(d) leads toward \(name)")
                    }
                }
            }
            let core = Set(a.coreCells)
            let home = Words.current.monolith.prefix(1).uppercased() + Words.current.monolith.dropFirst()
            for s in signs where s.ways.map(\.places) == [[home]] && !core.contains(s.cell) {
                for t in signs where t.cell != s.cell {
                    expect(abs(t.cell.x - s.cell.x) + abs(t.cell.y - s.cell.y) >= Signs.spacing, "signs stand apart: \(s.cell) and \(t.cell)")
                }
            }
        }

        test("the yard has room for a pallet: a lane through its doorway, and a body's width of aisle past each end") {
            let a = fresh()
            let rows = Set(a.storageCells.map(\.y)).sorted()
            expect(Set(a.storageCells.map(\.x)).count == Station.yardWide && rows.count == 4,
                   "storage is \(Station.yardWide) wide and four deep: \(cells(a.storageCells))")
            // The lane is two columns of the crate rows either side of the aisle the pallet floats in.
            let lane = a.palletLane
            expect(lane.count == 4, "the lane is four cells: \(cells(Array(lane)))")
            expect(lane.allSatisfy { a.storageCells.contains($0) }, "all of it storage floor")
            expect(Set(lane.map(\.y)) == [a.storageNearRow, a.storageAisleRow + 1], "on the rows either side of the aisle")
            // The doorway to the deck takes the lane and a column either side, so a body can walk past a
            // pallet standing in it.
            let gate = Set(a.yardDoorways.filter { a.storageCells.contains($0.0) && a.deckCells.contains($0.1)
                                                || a.storageCells.contains($0.1) && a.deckCells.contains($0.0) }
                .flatMap { [$0.0.x, $0.1.x] })
            expect(Set(a.palletLaneColumns).isSubset(of: gate) && gate.count == Set(a.palletLaneColumns).count + 2,
                   "the doorway is the lane with a column either side: \(gate.sorted())")
            // And the aisle it stands in is wide enough to get round: a body needs a third of a tile.
            let xs = a.storageCells.map { Double($0.x) }
            let home = Double(a.palletLaneColumns.reduce(0, +)) / 2
            let past = (xs.max()! + 0.5) - (home + PalletGeometry.width / 2 + 0.2)
            expect(past >= 0.34 && abs(past - ((home - PalletGeometry.width / 2 - 0.2) - (xs.min()! - 0.5))) < 0.01,
                   "\(past) of clear aisle at each end of it")
        }

        for theme in Theme.allCases {
            Theme.pinnedForPlan = theme
            test("\(theme.title): forty rooms keep off the yard, and no hallway is dug through it") {
                let a = fresh()
                for i in 0..<40 { place("task:repo\(i % 5)#\(100 + i)", on: a) }
                let yard = Set(a.padCells + a.deckCells + a.storageCells + a.deconCells)
                for (k, r) in a.rooms { expect(!r.cells.contains(where: yard.contains), "\(k) keeps off the yard") }
                expect(yard.isDisjoint(with: a.corridorCells), "the hallway keeps off the yard")
            }
            test("\(theme.title): the bay's berths are a honeycomb on its floor, each with a lane cell to wait in") {
                let a = fresh()
                for i in 0..<40 { place("task:repo\(i % 5)#\(100 + i)", on: a) }
                let berths = a.hangarSlots, bay = Set(a.hangarCells)
                expect(berths.count >= 5, "the bay takes a row of ships and more: \(berths.count) berths")
                for (i, at) in berths.enumerated() {
                    let onFloor = bay.contains(Cell(x: Int(at.x.rounded()), y: Int(at.y.rounded())))
                    expect(onFloor, "berth \(i) stands on the bay's own floor: \(at.x),\(at.y)")
                    for (j, other) in berths.enumerated() where j > i {
                        expect(simd_distance(at, other) > Station.hive - 0.01, "berths \(i) and \(j) keep a ship's width apart: \(simd_distance(at, other))")
                    }
                    let stand = a.bayStand(slot: i)
                    expect(bay.contains(stand), "berth \(i)'s carrier waits on the bay floor: \(stand.x),\(stand.y)")
                    let p = SIMD2(Double(stand.x), Double(stand.y))
                    expect(simd_distance(p, at) < 1.3, "berth \(i)'s carrier waits within reach of its crate: \(simd_distance(p, at))")
                    for (j, other) in berths.enumerated() {
                        expect(simd_distance(p, other) > Station.bayKeepOff, "berth \(i)'s carrier stands out from under berth \(j): \(simd_distance(p, other))")
                    }
                }
            }
            test("\(theme.title): the airlock runs through the hull and the bay hangs outside, touching the station only at the hatch") {
                let a = fresh()
                for i in 0..<40 { place("task:repo\(i % 5)#\(100 + i)", on: a) }
                let lock = Set(a.airlockCells), bay = Set(a.hangarCells)
                expect(lock.count == Station.airlockLength, "the passage is \(lock.count) tiles")
                var inside = Set(a.corridorCells + a.coreCells + a.padCells + a.deckCells + a.storageCells + a.deconCells)
                for r in a.rooms.values { inside.formUnion(r.cells) }
                expect(lock.isDisjoint(with: inside), "nothing else stands in the airlock: \(cells(Array(lock.intersection(inside))))")
                expect(bay.isDisjoint(with: inside), "nothing else stands in the bay: \(cells(Array(bay.intersection(inside))))")
                let hatch = Set(a.airlockHatches.map(\.inside))
                let touching = bay.flatMap(\.neighbours).filter { !bay.contains($0) && (inside.contains($0) || (lock.contains($0) && !hatch.contains($0))) }
                expect(touching.isEmpty, "the bay touches the station only at the hatch: \(cells(touching))")
            }
        }
        Theme.pinnedForPlan = .classic

        if ProcessInfo.processInfo.environment["RK_FILL"] != nil {
            for placement in OfficePlacement.allCases { for n in [40, 80] {
                OfficePlacement.pinned = placement
                FileHandle.standardError.write("=== \(placement.title)\n".data(using: .utf8)!)
                let a = fresh()
                for i in 0..<n { place("task:repo\(i % 5)#\(100 + i)", on: a) }
                let hall = Set(a.corridorCells + a.coreCells).subtracting([a.monolithCell])
                var edges = 0
                for c in hall { for nb in c.neighbours where hall.contains(nb) && (nb.x, nb.y) > (c.x, c.y) { edges += 1 } }
                let walks = a.rooms.values.compactMap { r in r.cells.flatMap(\.neighbours).compactMap { a.hallDistance(of: $0) }.min() }
                let b = a.bounds
                FileHandle.standardError.write("--- \(n) rooms: mean walk \(walks.reduce(0, +) / max(1, walks.count)), farthest \(walks.max() ?? 0), loops \(edges - hall.count + 1), hallway \(hall.count) cells, footprint \(b.max.x - b.min.x + 1)x\(b.max.y - b.min.y + 1), beside their own \(Int(neighbourly(a) * 100))%\n".data(using: .utf8)!)
                draw(a, byRepo: true)
            } }
            OfficePlacement.pinned = .rings
        }
        if failures > 0 { print("layout: \(failures) failed"); exit(1) }
        print("layout: all passed")
        exit(0)
    }

    /// The floor as text, one character a cell, for a look without a window: `#` the monolith, `.` hallway,
    /// letters the rooms, `L D B G` the lounge, dorm, bath and gym, `=` yard, `~` bay, `^` airlock.
    static func draw(_ s: Station, byRepo: Bool = false) {
        var chars: [Cell: Character] = [:]
        for c in s.corridorCells + s.coreCells { chars[c] = "." }
        chars[s.monolithCell] = "#"
        for c in s.padCells + s.deckCells + s.storageCells + s.deconCells { chars[c] = "=" }
        for c in s.hangarCells { chars[c] = "~" }
        for c in s.airlockCells { chars[c] = "^" }
        let letters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        var next = 0
        let repos = Array(Set(s.rooms.values.compactMap(\.repo))).sorted()
        for key in s.rooms.keys.sorted() {
            let ch: Character
            switch key {
            case "kind:lounge": ch = "L"
            case "kind:quarters": ch = "D"
            case "kind:bath": ch = "B"
            case "kind:gym": ch = "G"
            default:
                if byRepo, let i = s.rooms[key]!.repo.flatMap(repos.firstIndex) { ch = letters[i % letters.count] }
                else { ch = letters[next % letters.count]; next += 1 }
            }
            for c in s.rooms[key]!.cells { chars[c] = ch }
        }
        let b = s.bounds
        var out = ""
        for y in b.min.y...b.max.y {
            var line = ""
            for x in b.min.x...b.max.x { line.append(chars[Cell(x: x, y: y)] ?? " ") }
            out += line + "\n"
        }
        FileHandle.standardError.write(out.data(using: .utf8)!)
    }

    /// The hallway is one piece from the plaza, and every room has its door on it.
    private static func whole(_ s: Station) -> Bool {
        var hall = Set(s.corridorCells + s.coreCells); hall.remove(s.plan.monolith)
        guard let start = s.coreCells.first(where: { $0 != s.plan.monolith }) else { return false }
        var seen: Set<Cell> = [start], queue = [start], head = 0
        while head < queue.count { let c = queue[head]; head += 1; for n in c.neighbours where hall.contains(n) && !seen.contains(n) { seen.insert(n); queue.append(n) } }
        return seen == hall && s.rooms.values.allSatisfy { r in r.cells.contains { c in c.neighbours.contains(where: s.isCorridor) } }
    }

    /// Steps from each walkable cell to the nearest of `cells`.
    private static func walked(_ s: Station, to cells: Set<Cell>) -> [Cell: Int] {
        var far: [Cell: Int] = [:], frontier = Array(cells)
        for c in cells { far[c] = 0 }
        while !frontier.isEmpty {
            var next: [Cell] = []
            for c in frontier {
                for n in [Cell(x: c.x + 1, y: c.y), Cell(x: c.x - 1, y: c.y), Cell(x: c.x, y: c.y + 1), Cell(x: c.x, y: c.y - 1)]
                where far[n] == nil && s.walkable.contains(n) && s.canStep(from: n, to: c) {
                    far[n] = far[c]! + 1; next.append(n)
                }
            }
            frontier = next
        }
        return far
    }

    private static func fresh() -> Station {
        let world = World(demo: true)
        return world.fleet.station("work")
    }

    /// An office of the repository its key names: `task:web#455` is web's.
    private static func place(_ key: String, on s: Station) {
        let repo = key.split(separator: ":").last.map { String($0.prefix { $0 != "#" && $0 != "/" }) } ?? "r"
        _ = s.ensureRoom(key: key, name: key, repo: repo, color: Colors.repos[0], lastActive: Date(timeIntervalSince1970: 0))
    }

    /// The share of offices whose nearest other office is of their own repository.
    private static func neighbourly(_ s: Station) -> Double {
        let offices = s.rooms.values.filter { !$0.key.hasPrefix("kind:") }
        func gap(_ a: Room, _ b: Room) -> Int { a.cells.flatMap { c in b.cells.map { abs($0.x - c.x) + abs($0.y - c.y) } }.min() ?? .max }
        let same = offices.filter { r in
            offices.filter { $0 !== r }.min { (gap(r, $0), $0.key) < (gap(r, $1), $1.key) }?.repo == r.repo
        }
        return Double(same.count) / Double(max(1, offices.count))
    }

    private static func cells(_ list: [Cell]) -> String { list.map { "\($0.x),\($0.y)" }.joined(separator: " ") }

    private static func cells(_ s: Station, _ key: String) -> String {
        (s.rooms[key]?.cells ?? []).map { "\($0.x),\($0.y)" }.joined(separator: " ")
    }

    private static func test(_ name: String, _ body: () -> Void) {
        let before = failures
        body()
        print(failures == before ? "PASS  \(name)" : "FAIL  \(name)")
    }

    private static func expect(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; print("  not so: \(what)") }
    }
}
