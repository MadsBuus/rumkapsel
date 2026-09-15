// Model-only tests of the floor plan: `.build/debug/Rumkapsel --layout-tests`.
//
// The plan is meant to be a pure function of shared facts, so that a station shared across machines
// looks the same on every one of them. These hold it to that: two stations built from nothing and given
// the same rooms in the same order lay them out identically, and a room's shape follows its key.

import Foundation

enum LayoutTests {
    private static var failures = 0

    static func run() -> Never {
        Theme.pinnedForPlan = .classic   // the plan as Classic lays it out, whatever the config says
        let keys = ["task:web#455", "task:api#5158", "task:ios#298", "branch:web/feature-x", "task:web#460", "task:api#5140"]

        test("two stations given the same rooms in the same order lay them out cell for cell the same") {
            let a = fresh(), b = fresh()
            for k in keys { place(k, on: a); place(k, on: b) }
            for k in keys + ["kind:lounge", "kind:quarters", "kind:bath", "kind:gym"] {
                expect(a.rooms[k]?.cells == b.rooms[k]?.cells && a.rooms[k] != nil, "\(k): \(cells(a, k)) against \(cells(b, k))")
            }
            expect(a.dug == b.dug, "and the same hallway was dug: \(a.dugCount) and \(b.dugCount) cells")
        }

        test("a room's shape follows its key, not the launch: the same key on an empty station takes the same cells twice") {
            let a = fresh(), b = fresh()
            place("task:web#455", on: a); place("task:web#455", on: b)
            expect(a.rooms["task:web#455"]?.cells == b.rooms["task:web#455"]?.cells, "\(cells(a, "task:web#455")) against \(cells(b, "task:web#455"))")
            let shapes = Set(keys.map { Station.shape(forKey: $0).count })
            expect(shapes.count > 1, "and different keys draw different shapes: sizes \(shapes)")
        }

        test("every room touches the corridor and none stands on reserved floor") {
            let a = fresh()
            for k in keys { place(k, on: a) }
            for (k, r) in a.rooms {
                expect(r.cells.contains { c in c.neighbours.contains { a.isCorridor($0) } }, "\(k) has a door on the corridor")
                expect(!r.cells.contains { a.isReserved($0) }, "\(k) keeps off the corridor and the yard")
            }
        }

        test("the hallway is one piece: every built cell is reached from the plaza, and the arms keep apart") {
            let a = fresh()
            let hall = Set(a.corridorCells + a.coreCells).subtracting([a.monolithCell])
            let unreached = hall.filter { a.hallDistance(of: $0) == nil }
            expect(unreached.isEmpty, "unreached hallway: \(unreached.map { "\($0.x),\($0.y)" })")
            let p = a.plan
            let armsTouch = p.north.contains { n in p.east.contains { e in abs(n.x - e.x) <= 1 && abs(n.y - e.y) <= 1 } }
            expect(!armsTouch, "the north and east arms never touch")
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
            let far = Cell(x: (a.plan.east.last?.x ?? 0) + 3, y: 2)
            expect(!a.rooms.values.contains { $0.cells.contains(far) }, "nothing was parked unplaced")
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

        test("Classic's pad stands right north of the deck, as it always has") {
            let a = fresh()
            expect(Set(a.deckCells.map { Cell(x: $0.x, y: $0.y - 4) }) == Set(a.padCells), "pad \(cells(a.padCells)) against the deck moved north")
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
            for n in [40, 80] {
                let a = fresh()
                for i in 0..<n { place("task:repo\(i % 5)#\(100 + i)", on: a) }
                let hall = Set(a.corridorCells + a.coreCells).subtracting([a.monolithCell])
                var edges = 0
                for c in hall { for nb in c.neighbours where hall.contains(nb) && (nb.x, nb.y) > (c.x, c.y) { edges += 1 } }
                let walks = a.rooms.values.compactMap { r in r.cells.flatMap(\.neighbours).compactMap { a.hallDistance(of: $0) }.min() }
                let b = a.bounds
                FileHandle.standardError.write("--- \(n) rooms: mean walk \(walks.reduce(0, +) / max(1, walks.count)), farthest \(walks.max() ?? 0), loops \(edges - hall.count + 1), hallway \(hall.count) cells, footprint \(b.max.x - b.min.x + 1)x\(b.max.y - b.min.y + 1)\n".data(using: .utf8)!)
                draw(a)
            }
        }
        if failures > 0 { print("layout: \(failures) failed"); exit(1) }
        print("layout: all passed")
        exit(0)
    }

    /// The floor as text, one character a cell, for a look without a window: `#` the monolith, `.` hallway,
    /// letters the rooms, `L D B G` the lounge, dorm, bath and gym, `=` yard, `~` bay, `^` airlock.
    static func draw(_ s: Station) {
        var chars: [Cell: Character] = [:]
        for c in s.corridorCells + s.coreCells { chars[c] = "." }
        chars[s.monolithCell] = "#"
        for c in s.padCells + s.deckCells + s.storageCells + s.deconCells { chars[c] = "=" }
        for c in s.hangarCells { chars[c] = "~" }
        for c in s.airlockCells { chars[c] = "^" }
        let letters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        var next = 0
        for key in s.rooms.keys.sorted() {
            let ch: Character
            switch key {
            case "kind:lounge": ch = "L"
            case "kind:quarters": ch = "D"
            case "kind:bath": ch = "B"
            case "kind:gym": ch = "G"
            default: ch = letters[next % letters.count]; next += 1
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

    private static func fresh() -> Station {
        let world = World(demo: true)
        return world.fleet.station("work")
    }

    private static func place(_ key: String, on s: Station) {
        _ = s.ensureRoom(key: key, name: key, repo: "r", color: Colors.repos[0], lastActive: Date(timeIntervalSince1970: 0))
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
