// Model-only tests of the floor plan: `.build/debug/Rumkapsel --layout-tests`.
//
// The plan is meant to be a pure function of shared facts, so that a station shared across machines
// looks the same on every one of them. These hold it to that: two stations built from nothing and given
// the same rooms in the same order lay them out identically, and a room's shape follows its key.

import Foundation

enum LayoutTests {
    private static var failures = 0

    static func run() -> Never {
        let keys = ["task:web#455", "task:api#5158", "task:ios#298", "branch:web/feature-x", "task:web#460", "task:api#5140"]

        test("two stations given the same rooms in the same order lay them out cell for cell the same") {
            let a = fresh(), b = fresh()
            for k in keys { place(k, on: a); place(k, on: b) }
            for k in keys + ["kind:lounge", "kind:quarters", "kind:bath", "kind:gym"] {
                expect(a.rooms[k]?.cells == b.rooms[k]?.cells && a.rooms[k] != nil, "\(k): \(cells(a, k)) against \(cells(b, k))")
            }
            expect(a.spineHalfLength == b.spineHalfLength, "and the arms are the same length: \(a.spineHalfLength) and \(b.spineHalfLength)")
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
            for al in p.alleys {
                let others = p.everyHallwayCell.subtracting(al.cells)
                let base = al.base
                let body = al.joins ? Array(al.cells.dropLast()) : al.cells
                let crowded = body.contains { c in others.contains { o in o != base && abs(o.x - c.x) + abs(o.y - c.y) <= 1 } }
                expect(!crowded, "alley at step \(al.step) of arm \(al.arm) keeps clear of other hallway along its length")
            }
        }

        test("the hallway is a web, not a tree: shortcuts join it into loops") {
            let a = fresh()
            let p = a.plan
            expect(p.alleys.contains { $0.joins }, "at least one alley runs on to meet other hallway")
            let all = p.everyHallwayCell.union(p.plaza).subtracting([p.monolith])
            var edges = 0
            for c in all { for n in c.neighbours where all.contains(n) && (n.x, n.y) > (c.x, c.y) { edges += 1 } }
            expect(edges >= all.count, "more ways than cells, so there are loops: \(edges) edges over \(all.count) cells")
        }

        test("forty rooms: the station builds outward along the hallway, every room on it, none on the plan") {
            let a = fresh()
            let before = a.spineHalfLength
            for i in 0..<40 { place("task:repo\(i % 5)#\(100 + i)", on: a) }
            for (k, r) in a.rooms {
                expect(r.cells.contains { c in c.neighbours.contains { a.isCorridor($0) } }, "\(k) has a door on the hallway")
                expect(!r.cells.contains { a.isReserved($0) }, "\(k) keeps off the hallway and the yard")
            }
            expect(a.spineHalfLength > before && a.spineHalfLength < a.plan.horizon, "the arms were built on: \(before) to \(a.spineHalfLength) of \(a.plan.horizon)")
            let far = Cell(x: (a.plan.east.last?.x ?? 0) + 3, y: 2)
            expect(!a.rooms.values.contains { $0.cells.contains(far) }, "nothing was parked unplaced")
            draw(a)
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
