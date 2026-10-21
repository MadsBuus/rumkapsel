import Foundation
import simd

enum LayoutTests {
    private static var failures = 0

    static func run() -> Never {
        Theme.pinnedForPlan = .classic
        OfficePlacement.pinned = .rings
        let keys = ["task:web#455", "task:api#5158", "task:ios#298", "branch:web/feature-x", "task:web#460", "task:api#5140"]

        test("two stations given the same rooms in the same order lay them out cell for cell the same") {
            let a = fresh(), b = fresh()
            for k in keys { place(k, on: a); place(k, on: b) }
            for k in keys + ["kind:lounge", "kind:quarters", "kind:bath", "kind:gym", "kind:galley"] {
                expect(a.rooms[k]?.cells == b.rooms[k]?.cells && a.rooms[k] != nil, "\(k): \(cells(a, k)) against \(cells(b, k))")
            }
            expect(a.dug == b.dug, "and the same hallway was dug: \(a.dugCount) and \(b.dugCount) cells")
        }

        test("a room's shape is its slot's, not its key's: the same key on an empty station takes the same cells twice") {
            let a = fresh(), b = fresh()
            place("task:web#455", on: a); place("task:web#455", on: b)
            expect(a.rooms["task:web#455"]?.cells == b.rooms["task:web#455"]?.cells, "\(cells(a, "task:web#455")) against \(cells(b, "task:web#455"))")
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
                expect(a.doorOutside(of: k) != nil, "\(k) has a doorway")
                expect(!r.cells.contains { a.isReserved($0) }, "\(k) keeps off the corridor and the yard")
            }
        }

        test("offices fill from the nearest free slot, and a slot comes back when its office goes") {
            let a = fresh()
            for i in 0..<12 { place("task:repo\(i % 3)#\(200 + i)", on: a) }
            let plan = a.floor
            let taken = a.rooms.values.compactMap { r in r.cells.first.flatMap { plan.slotOf[$0] } }.sorted()
            expect(taken == Array(taken.indices), "the first twelve offices took the first twelve slots: \(taken)")

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
            let plan = a.floor
            let offices = a.rooms.values.filter { $0.key.hasPrefix("task:") }
            let outer = offices.max { ($0.cells.first.flatMap { plan.slotOf[$0] } ?? 0) < ($1.cells.first.flatMap { plan.slotOf[$0] } ?? 0) }!
            let door = a.doorCell(of: outer.key)
            for r in offices where r.key != outer.key { a.removeRoom(key: r.key) }
            a.giveBack(a.spareHallway())
            expect(a.dugCount < full, "hallway was given back: \(a.dugCount) of \(full) cells kept")
            expect(a.doorCell(of: outer.key) == door, "the office left keeps its door")
            expect(whole(a), "and the hallway is one piece with every room's door on it")
            for i in 0..<5 { place("task:between\(i)#\(500 + i)", on: a) }
            expect(whole(a), "offices opening between are reached: \(a.dugCount) cells dug")
            for i in 0..<5 { a.removeRoom(key: "task:between\(i)#\(500 + i)") }
            a.giveBack(a.spareHallway())
            a.removeRoom(key: outer.key)
            a.giveBack(a.spareHallway())
            expect(a.dugCount == 0, "with no offices no dug hallway is left: \(a.dugCount)")
            for i in 0..<16 { place("task:again\(i % 3)#\(400 + i)", on: a) }
            expect(whole(a), "offices opening again are reached: \(a.dugCount) cells dug")
        }

        test("every baked plan is whole: the essentials are joined before any office, and lighting the slots in order never breaks the floor") {
            expect(!Floorplan.all().isEmpty, "there are baked plans: \(Floorplan.all().count)")
            for plan in Theme.allCases.flatMap({ Floorplan.all($0) }) {
                expect(plan.slots.count >= 100, "plan \(plan.seed) has \(plan.slots.count) office slots")
                let rings = plan.slots.map(\.ring)
                expect(zip(rings, rings.dropFirst()).allSatisfy { $0 <= $1 },
                       "plan \(plan.seed) opens ring by ring outward, \(rings.first ?? 0) to \(rings.last ?? 0)")
                for name in ["lounge", "quarters", "bath", "gym", "galley"] {
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
            place("task:web#900", on: b)
            place("task:api#901", on: a); place("task:api#901", on: b)
            place("task:web#900", on: a)
            let differ = a.rooms["task:api#901"]!.cells != b.rooms["task:api#901"]!.cells || a.rooms["task:web#900"]!.cells != b.rooms["task:web#900"]!.cells
            expect(differ, "the two disagree before the tie-break")
            expect(b.replaceRooms(["task:api#901", "task:web#900"].map { ($0, a.rooms[$0]!.cells) }).count == 2, "the disputed rooms are taken as a placed them")
            for k in ["task:api#901", "task:web#900"] { expect(a.rooms[k]?.cells == b.rooms[k]?.cells, "\(k): \(cells(a, k)) against \(cells(b, k))") }
            let hall = Set(b.corridorCells + b.coreCells).subtracting([b.monolithCell])
            expect(hall.allSatisfy { b.hallDistance(of: $0) != nil }, "b's hallway is still one piece")
            for k in b.rooms.keys { expect(b.doorOutside(of: k) != nil, "\(k) still has a doorway") }
        }

        test("forty rooms: the station builds outward along the hallway, every room on it, none on the plan") {
            let a = fresh()
            let before = a.dugCount
            for i in 0..<40 { place("task:repo\(i % 5)#\(100 + i)", on: a) }
            for (k, r) in a.rooms {
                expect(a.doorOutside(of: k) != nil, "\(k) has a doorway")
                expect(!r.cells.contains { a.isReserved($0) }, "\(k) keeps off the hallway and the yard")
            }
            expect(a.dugCount > before, "hallway was dug for them: \(a.dugCount) cells")
            let hallway = Set(a.corridorCells + a.coreCells)
            for (k, r) in a.rooms { expect(!r.cells.contains(where: hallway.contains), "\(k) does not stand on the hallway") }
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

        test("laying the offices out afresh keeps every office, in the order they opened, on one hallway") {
            let order = (0..<16).map { "task:repo\($0 % 4)#\(400 + $0)" }
            let s = fresh()
            for k in order { place(k, on: s) }
            for k in order where k.hasSuffix("1") || k.hasSuffix("4") || k.hasSuffix("7") { s.removeRoom(key: k) }
            for k in (0..<5).map({ "task:late#\(500 + $0)" }) { place(k, on: s) }
            let before = Set(s.rooms.keys)
            s.relayOffices()
            expect(Set(s.rooms.keys) == before, "the same rooms stand: \(s.rooms.count) against \(before.count)")
            expect(whole(s), "the hallway is one piece and every office has its door on it")
            let again = fresh()
            for k in s.rooms.values.filter({ !$0.key.hasPrefix("kind:") }).sorted(by: { ($0.openedAt, $0.key) < ($1.openedAt, $1.key) }) { place(k.key, on: again) }
            expect(s.rooms.keys.allSatisfy { s.rooms[$0]?.cells == again.rooms[$0]?.cells }, "and stand where a station opening them afresh would put them")
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
            for place in [Place.quarters, .lounge, .bath, .gym, .galley] { after.ensureFixedRoom(place) }
            expect(Set(after.rooms.keys) == Set(before.rooms.keys), "the same rooms stand: \(after.rooms.count) against \(before.rooms.count)")
            expect(whole(after), "the hallway is one piece and every office has its door on it")
            expect(neighbourly(after) >= 0.8, "the offices stand by repository: \(Int(neighbourly(after) * 100))%")
            let kept = Station(name: "work")
            kept.restore(saved)
            expect(order.allSatisfy { kept.rooms[$0]?.cells == before.rooms[$0]?.cells }, "and without a relayout every office keeps its cells")
        }

        test("Classic's pad stands right beyond the hall's field, the whole width of it") {
            let a = fresh()
            let top = a.hall.cells.map(\.y).min()!
            let field = Set(a.hall.cells.filter { $0.y == top }.map { Cell(x: $0.x, y: top - 1) })
            expect(field.isSubset(of: Set(a.hall.padCells)), "the pad runs along the field: \(cells(a.hall.padCells))")
            expect(a.hall.padCells.allSatisfy { $0.y < top }, "the pad is all beyond the glass")
        }

        test("the hull is over everything but the pad, the bay's hangar included, meets the floor where its pieces stand, and lets you through its doorways") {
            let a = fresh()
            for i in 0..<20 { place("task:repo\(i % 5)#\(100 + i)", on: a) }
            let hull = StationHull(a)
            let out = a.hall.padCells.filter { hull.inside.contains($0) }
            expect(out.isEmpty, "the pad is under open space: \(cells(out))")
            let indoors = a.hall.cells + a.hall.deconCells + a.coreCells + a.hangarCells
            let missed = indoors.filter { !hull.inside.contains($0) }
            expect(missed.isEmpty, "the hall, decon, the bay and the hallway are indoors: \(cells(missed))")
            for c in a.hangarCells where c.y == a.hangarCells.map(\.y).max() {
                let foot = SIMD2(Double(c.x), Double(c.y) + 0.5)
                expect(hull.reach(foot).distance < 0.01 && hull.reach(foot).door, "the bay's mouth is open in the hull's foot at \(c.x)")
            }
            if let east = a.hall.padCells.map(\.x).max(), let y = a.hall.padCells.map(\.y).min() {
                let foot = SIMD2(Double(east) + 0.5, Double(y) + 0.5)
                expect(hull.reach(foot).distance < 0.01, "the hull meets the floor along the pad's east side")
            }
            for (hall, out) in a.hall.padWall {
                let through = (SIMD2(Double(hall.x), Double(hall.y)) + SIMD2(Double(out.x), Double(out.y))) / 2
                let roof = hull.roof(over: through + SIMD2(0, Double(hall.y - out.y)) * 0.01, top: 0.5) ?? .infinity
                expect(roof > 0.5, "the hall's pad wall stands under the hull: roof \(roof)")
            }
            let crown = StationHull.height(atDistance: 99)
            expect(abs(crown - StationHull.section.rise) < 1e-9 && StationHull.height(atDistance: 0) == 0,
                   "upright from the floor to a crown \(StationHull.section.rise) up, got \(crown)")
        }

        test("a workspace that moved on from its merged office gets an office of its own, once, beside it") {
            let world = World(demo: true)
            let a = world.fleet.station("work")
            let cwd = FileManager.default.temporaryDirectory.appendingPathComponent("rk-workspace-\(getpid())").path
            try? FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(atPath: cwd) }
            let now = Date()
            func scan(_ branch: String) -> [WorldEvent] {
                let s = SessionInfo(id: "s", cwd: cwd, repo: "web", repoRoot: nil, owner: nil, lastModified: now, activity: .waiting,
                                    area: nil, title: nil, branch: branch, toolCount: 0, isSubagent: false, cwdExists: true,
                                    promptCount: 0, queuedCount: 0, eventMarkers: [:])
                return world.applyScan(ScanResult(sessions: [s]), now: now, minionHomes: [:])
            }
            for _ in 0..<20 where world.settling { _ = world.applyScan(ScanResult(), now: now, minionHomes: [:]) }
            let merged = world.works.note(repo: "web", branch: "feature/old", pull: 85, pullState: "MERGED")
            world.works.report(merged, .ready, by: .pulls, at: now)
            world.works.report(merged, .stored, by: .pulls, at: now)
            let old = "task:web#85"
            _ = a.ensureRoom(key: old, name: "#85", repo: "web", color: Colors.repos[0], lastActive: now)
            a.rooms[old]?.worktree = cwd
            a.rooms[old]?.branch = "feature/old"
            expect(world.stage(office: old, repo: "web") == .stored, "merged, waiting for its haul")
            _ = scan("feature/new")
            let again = scan("feature/new") + scan("feature/new")
            let flips = again.filter { if case .office(_, .opened, _) = $0 { return true }; if case .office(_, .gone, _) = $0 { return true }; return false }
            expect(flips.isEmpty, "no office opened and dropped scan after scan: \(flips.count)")
            expect(a.rooms[old] != nil && a.rooms.keys.contains { $0.hasSuffix("feature/new") }, "both stand: \(a.rooms.keys.sorted())")
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

        test("a station keeps its facts across a save, and an older save brings its facts over from the ledger") {
            let a = fresh()
            let news: [Event] = [(1, Stage.stored), (2, .stored), (4, .qa), (5, .stored)].map { .work(WorkNews(crate: CrateID(repo: "web", number: $0.0), stage: $0.1)) }
            _ = Rules.apply([.policy(repo: "web", RepoFacts(hasStaging: true, hasCleared: true))] + news + [.launched(repo: "web", hotfix: 5)],
                            at: Date(timeIntervalSince1970: 0), to: &a.facts, yard: a.yard)
            guard let json = try? JSONEncoder().encode(a.saved), let saved = try? JSONDecoder().decode(Station.Saved.self, from: json) else {
                return expect(false, "the save round-trips")
            }
            expect(saved.ledger == nil, "no ledger is written any more")
            let b = Station(name: "work")
            b.restore(saved)
            var want = a.facts
            want.rockets = want.rockets.filter { !$0.value.launched }
            want.crates[CrateID(repo: "web", number: 5)] = nil
            expect(b.facts == want, "the same facts but what flew: \(b.facts.crates.keys.sorted())")
            var old = saved
            old.facts = nil
            old.ledger = LegacyLedger(crates: [
                "web|1": .init(repo: "web", number: 1, wanted: "storage", placed: "storage"),
                "web|2": .init(repo: "web", number: 2, wanted: "storage", placed: "storage"),
                "web|3": .init(repo: "web", number: 3, wanted: "deck", placed: "deck", cleared: true),
            ])
            let c = Station(name: "work")
            c.restore(old)
            expect(c.facts.crates.mapValues(\.place) == [CrateID(repo: "web", number: 1): .waiting, CrateID(repo: "web", number: 2): .waiting,
                                                         CrateID(repo: "web", number: 3): .cleared], "from the ledger: \(c.facts.crates.mapValues(\.place))")
            var both = saved
            both.ledger = old.ledger
            guard let bothJSON = try? JSONEncoder().encode(both) else { return expect(false, "the old save encodes") }
            let broken = String(decoding: bothJSON, as: UTF8.self).replacingOccurrences(of: "\"place\"", with: "\"placeOld\"")
            let d = Station(name: "work")
            if let s = try? JSONDecoder().decode(Station.Saved.self, from: Data(broken.utf8)) { d.restore(s) } else { expect(false, "unreadable facts keep the save readable") }
            expect(d.facts.crates.count == 3 && Set(d.rooms.keys) == Set(b.rooms.keys), "unreadable facts come over from the ledger, the rooms as saved")
            var trimmed = String(decoding: json, as: UTF8.self)
            for key in ["homes", "launches", "staging", "alien"] { trimmed = trimmed.replacingOccurrences(of: "\"\(key)\"", with: "\"\(key)Gone\"") }
            let e = Station(name: "work")
            if let s = try? JSONDecoder().decode(Station.Saved.self, from: Data(trimmed.utf8)), s.unreadable == nil { e.restore(s) } else { expect(false, "fields a save lacks take their defaults") }
            expect(e.facts.crates.mapValues(\.place) == b.facts.crates.mapValues(\.place), "a save missing newer fields keeps its crates")
        }

        test("the yard is one hall: three zones of eight tiles, each beside an aisle or behind one, a walkway to the field") {
            let a = fresh()
            expect(a.hall.cells.count == Hall.wide * Hall.deep, "the hall is \(Hall.wide) by \(Hall.deep): \(cells(a.hall.cells))")
            for (name, zone) in [("cleared", a.hall.clearedCells), ("staged", a.hall.stagedCells), ("storage", a.hall.storageCells)] {
                expect(zone.count == 8 && Set(zone).count == 8, "\(name) is eight tiles: \(cells(zone))")
                expect(zone.allSatisfy(a.hall.cells.contains), "\(name) is in the hall")
                let reach = Set(a.hall.aisleCells + a.hall.walkwayCells)
                for c in zone {
                    let near = c.neighbours.contains(where: reach.contains)
                    let behind = c.neighbours.contains { n in zone.contains(n) && n.neighbours.contains(where: reach.contains) }
                    expect(near || behind, "\(name) tile \(c) is reached from an aisle")
                }
            }
            let zones = Set(a.hall.clearedCells + a.hall.stagedCells + a.hall.storageCells)
            expect(zones.isDisjoint(with: a.hall.aisleCells) && zones.isDisjoint(with: a.hall.walkwayCells), "nothing stands on the aisles or the walkway")
            expect(Set(a.hall.cells) == zones.union(a.hall.aisleCells).union(a.hall.walkwayCells), "the hall is the zones, the aisles and the walkway")
            if let arm = a.plan.west.last {
                expect(a.hall.walkwayCells.contains(Cell(x: arm.x - 1, y: arm.y)), "the west arm comes onto the walkway")
            }
            let top = a.hall.cells.map(\.y).min()!, bottom = a.hall.cells.map(\.y).max()!
            expect(a.hall.clearedCells.allSatisfy { $0.y <= top + 1 } && a.hall.storageCells.allSatisfy { $0.y >= bottom - 1 },
                   "cleared at the pad end, storage at the back")
        }

        for theme in Theme.allCases {
            Theme.pinnedForPlan = theme
            test("\(theme.title): forty rooms keep off the yard, and no hallway is dug through it") {
                let a = fresh()
                for i in 0..<40 { place("task:repo\(i % 5)#\(100 + i)", on: a) }
                let yard = Set(a.hall.padCells + a.hall.cells + a.hall.deconCells)
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
            test("\(theme.title): the bay meets the end of the south hallway and touches the station only at its door") {
                let a = fresh()
                for i in 0..<40 { place("task:repo\(i % 5)#\(100 + i)", on: a) }
                let bay = Set(a.hangarCells)
                guard let door = a.bayDoor else { return expect(false, "a door into the bay") }
                expect(bay.contains(door.bay) && a.corridorCells.contains(door.inside), "the door joins the hallway's end to the bay")
                var inside = Set(a.corridorCells + a.coreCells + a.hall.padCells + a.hall.deckCells + a.hall.storageCells + a.hall.deconCells)
                for r in a.rooms.values { inside.formUnion(r.cells) }
                expect(bay.isDisjoint(with: inside), "nothing else stands in the bay: \(cells(Array(bay.intersection(inside))))")
                let touching = bay.flatMap(\.neighbours).filter { !bay.contains($0) && inside.contains($0) && $0 != door.inside }
                expect(touching.isEmpty, "the bay touches the station only at its door: \(cells(touching))")
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

    static func draw(_ s: Station, byRepo: Bool = false) {
        var chars: [Cell: Character] = [:]
        for c in s.corridorCells + s.coreCells { chars[c] = "." }
        chars[s.monolithCell] = "#"
        for c in s.hall.padCells + s.hall.deckCells + s.hall.storageCells + s.hall.deconCells { chars[c] = "=" }
        for c in s.hangarCells { chars[c] = "~" }
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
            case "kind:galley": ch = "K"
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

    private static func whole(_ s: Station) -> Bool {
        var hall = Set(s.corridorCells + s.coreCells); hall.remove(s.plan.monolith)
        guard let start = s.coreCells.first(where: { $0 != s.plan.monolith }) else { return false }
        var seen: Set<Cell> = [start], queue = [start], head = 0
        while head < queue.count { let c = queue[head]; head += 1; for n in c.neighbours where hall.contains(n) && !seen.contains(n) { seen.insert(n); queue.append(n) } }
        return seen == hall && s.rooms.values.allSatisfy { s.doorOutside(of: $0.key) != nil }
    }

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

    private static func place(_ key: String, on s: Station) {
        let repo = key.split(separator: ":").last.map { String($0.prefix { $0 != "#" && $0 != "/" }) } ?? "r"
        _ = s.ensureRoom(key: key, name: key, repo: repo, color: Colors.repos[0], lastActive: Date(timeIntervalSince1970: 0))
    }

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
