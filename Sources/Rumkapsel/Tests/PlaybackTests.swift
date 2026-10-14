import Foundation

enum PlaybackTests {
    private static var failures = 0
    private static let staged = RepoFacts(hasStaging: true, hasCleared: true)

    static func run() -> Never {
        test("one carry: an office's crate goes to storage in one body's hands, then stands on its row") {
            let (sim, station, m) = fixture()
            station.ensureRoom(key: "task:web#5", name: "#5", repo: "web", color: RGB(r: 0.4, g: 0.6, b: 0.9), lastActive: Date())
            put(station, sim, "web", [5], .ready, office: "task:web#5")
            sim.play()
            expect(shown(sim, 5) == .office("task:web#5"), "packed in its office: \(sim.describe(shown(sim, 5)))")
            settle(sim, m)
            put(station, sim, "web", [5], .stored, office: "task:web#5")
            unchanged(sim, station) {
                var held = false
                let done = step(sim, seconds: 90, until: {
                    if shown(sim, 5) == .hands(m.id) { held = true }
                    return held && sim.cargo.isEmpty
                })
                expect(held, "in the body's hands on the way")
                expect(done && caughtUp(sim, station), "on its row in storage: \(sim.lag() ?? "")")
                expect(m.current?.crate == nil && !m.hasLoad, "and the body is free again: \(m.words)")
            }
        }

        test("top first: a buried crate's blocker is carried off before it, and every stack is built from the floor") {
            let (sim, station, a) = fixture()
            let b = body("b", sim: sim, station: station)
            put(station, sim, "web", Array(1...6), .qa, quiet: true)
            sim.play()
            settle(sim, a, b)
            put(station, sim, "web", [2], .cleared)
            unchanged(sim, station) {
                var liftedAt: [Int: Double] = [:]
                var floating: [String] = []
                let done = step(sim, seconds: 120, until: {
                    for n in [2, 6] where liftedAt[n] == nil { if case .hands? = shown(sim, n) { liftedAt[n] = sim.clock } }
                    floating += unsupported(sim)
                    return liftedAt.count == 2 && sim.cargo.isEmpty
                })
                expect(done && caughtUp(sim, station), "both moved: \(sim.lag() ?? "")")
                expect((liftedAt[6] ?? .infinity) < (liftedAt[2] ?? -1), "#6 off the top before #2 is lifted: \(liftedAt)")
                expect(floating.isEmpty, "no crate ever stood on nothing: \(Set(floating).sorted())")
            }
        }

        test("a fact that changes before the lift calls the move off; after the lift the crate lands where the fact now says") {
            let (sim, station, m) = fixture()
            put(station, sim, "web", [440, 441], .stored, quiet: true)
            sim.play()
            settle(sim, m)
            let was = shown(sim, 440)
            put(station, sim, "web", [440], .qa)
            unchanged(sim, station) {
                sim.play()
                sim.assignOrders()
                expect(m.current?.crate?.number == 440 && !m.hasLoad, "the carry is taken, not lifted yet: \(m.words)")
            }
            put(station, sim, "web", [440], .stored)
            unchanged(sim, station) {
                sim.play()
                expect(sim.cargo.isEmpty, "called off: \(sim.cargo.count)")
                expect(m.current?.crate == nil, "the carrier is let go: \(m.words)")
                expect(shown(sim, 440) == was && caughtUp(sim, station), "still in storage where it stood: \(sim.describe(shown(sim, 440)))")
            }
            put(station, sim, "web", [441], .qa)
            unchanged(sim, station) {
                expect(step(sim, seconds: 60, until: { shown(sim, 441) == .hands(m.id) }), "#441 up on the arms")
            }
            put(station, sim, "web", [441], .cleared)
            unchanged(sim, station) {
                expect(step(sim, seconds: 90, until: { sim.cargo.isEmpty }), "set down")
                guard case .row(let s)? = shown(sim, 441) else { return expect(false, "on a row: \(sim.describe(shown(sim, 441)))") }
                expect(s.zone == .cleared && caughtUp(sim, station), "on the cleared rows, where the fact is now: \(sim.lag() ?? "")")
            }
        }

        test("a skip mid-carry: everything shown where the facts say, no carry left, the carrier free") {
            let (sim, station, m) = fixture()
            put(station, sim, "web", [440, 441, 442], .stored, quiet: true)
            sim.play()
            settle(sim, m)
            put(station, sim, "web", [440, 441, 442], .qa)
            unchanged(sim, station) {
                expect(step(sim, seconds: 60, until: { m.hasLoad }), "a crate on the arms")
                sim.skip()
                expect(caughtUp(sim, station), "shown is the facts: \(sim.lag() ?? "")")
                expect(sim.cargo.isEmpty && m.current?.crate == nil && !m.hasLoad, "no carry, empty hands: \(m.words)")
            }
        }

        test("step(dt: 600) is a skip: the clock moves by 600 and the picture is the facts") {
            let (sim, station, m) = fixture()
            put(station, sim, "web", [440, 441, 442], .stored, quiet: true)
            sim.play()
            settle(sim, m)
            put(station, sim, "web", [440, 441, 442], .qa)
            unchanged(sim, station) {
                expect(step(sim, seconds: 60, until: { m.hasLoad }), "a crate on the arms")
                let start = sim.clock
                sim.step(dt: 600)
                expect(abs(sim.clock - start - 600) < 1e-6, "the clock moved by 600: \(sim.clock - start)")
                expect(caughtUp(sim, station), "shown is the facts: \(sim.lag() ?? "")")
                expect(sim.cargo.isEmpty && m.current?.crate == nil && !m.hasLoad, "no carry, empty hands: \(m.words)")
            }
        }

        test("a give-up parks the crate where it fell, and someone else finishes the carry from there") {
            let (sim, station, a) = fixture()
            put(station, sim, "web", [440], .stored, quiet: true)
            sim.play()
            settle(sim, a)
            put(station, sim, "web", [440], .qa)
            unchanged(sim, station) {
                expect(step(sim, seconds: 60, until: { a.hasLoad && a.phaseKind == .haul }), "up on a's arms")
                a.wedged = true
                expect(step(sim, seconds: 15, until: { !a.hasLoad }), "a gives up")
                guard case .parked(let p)? = shown(sim, 440) else { return expect(false, "parked where it fell: \(sim.describe(shown(sim, 440)))") }
                expect(sim.cargo.values.first.map { if case .carry(_, let from, _) = $0.command.kind { return from == p }; return false } == true,
                       "the carry starts again from there")
                let b = body("b", sim: sim, station: station)
                var carrier: String?
                let done = step(sim, seconds: 90, until: {
                    if case .hands(let who)? = shown(sim, 440) { carrier = who }
                    return sim.cargo.isEmpty
                })
                expect(carrier == b.id, "b picks it up: \(carrier ?? "nobody")")
                expect(done && caughtUp(sim, station), "and sets it down on the deck: \(sim.lag() ?? "")")
            }
        }

        test("preemption: a release carry takes the body off a yard carry it has not lifted, which goes back on the board") {
            let (sim, station, m) = fixture()
            put(station, sim, "web", [440], .stored, quiet: true)
            put(station, sim, "web", [441], .qa, quiet: true)
            sim.play()
            settle(sim, m)
            put(station, sim, "web", [440], .qa)
            unchanged(sim, station) {
                sim.play()
                sim.assignOrders()
                expect(m.current?.crate?.number == 440 && !m.hasLoad, "the yard carry is taken: \(m.words)")
            }
            put(station, sim, "web", [441], .cleared)
            unchanged(sim, station) {
                sim.play()
                let release = sim.cargo.values.first { $0.crate.number == 441 }
                let yard = sim.cargo.values.first { $0.crate.number == 440 }
                expect(release?.rank == .release && yard?.rank == .yard, "a carry into the cleared rows is release work")
                sim.assignOrders()
                expect(m.current?.crate?.number == 441, "taken off the yard carry for the release: \(m.words)")
                expect(sim.cargo.values.first { $0.crate.number == 440 }?.carrier == nil, "the yard carry is back on the board, nobody on it")
                expect(m.wonderUntil > sim.clock, "a beat, head up, before it goes")
            }
        }

        test("an office by shuttle: delivered, carried to its door, unfolded, built; one gone mid-delivery folds where it lies") {
            let (sim, station, m) = fixture()
            sim.play()
            settle(sim, m)
            station.ensureRoom(key: "task:web#7", name: "#7", repo: "web", color: RGB(r: 0.4, g: 0.6, b: 0.9), lastActive: Date())
            office(station, sim, .opened("task:web#7", repo: "web", via: .shuttle(for: m.id)))
            unchanged(sim, station) {
                var seen: [String] = []
                var carried = false
                let done = step(sim, seconds: 180, until: {
                    if let p = sim.shown["work"]?.offices["task:web#7"]?.phase, seen.last != phase(p) { seen.append(phase(p)) }
                    if case .office? = m.load { carried = true }
                    return sim.shown["work"]?.offices["task:web#7"]?.phase == .built
                })
                expect(done && seen == ["ordered", "unfolding", "built"], "ordered, unfolded, built: \(seen)")
                expect(carried, "on a's arms from the bay to the door")
                expect(sim.deliveries.isEmpty && !m.hasLoad && sim.lag() == nil, "nothing left of the delivery: \(sim.lag() ?? "")")
            }
            station.ensureRoom(key: "task:web#8", name: "#8", repo: "web", color: RGB(r: 0.9, g: 0.5, b: 0.3), lastActive: Date())
            office(station, sim, .opened("task:web#8", repo: "web", via: .shuttle(for: m.id)))
            unchanged(sim, station) {
                expect(step(sim, seconds: 120, until: { m.hasLoad }), "the second office on a's arms")
            }
            station.removeRoom(key: "task:web#8")
            office(station, sim, .gone("task:web#8"))
            unchanged(sim, station) {
                let gone = step(sim, seconds: 5, until: { sim.shown["work"]?.offices["task:web#8"] == nil })
                expect(gone && sim.deliveries.isEmpty, "the office and its delivery are gone at once")
                expect(!m.hasLoad && m.landing?.dropped == true, "the crate is set down where a stood, to fold there")
                expect(sim.lag() == nil && sim.snapped == 0, "caught up by itself: \(sim.lag() ?? "")")
            }
        }

        test("a delivery that lands with nobody free waits on the bay floor, and is fetched once someone is") {
            let (sim, station, a) = fixture()
            sim.bodies = [:]
            sim.play()
            station.ensureRoom(key: "task:web#7", name: "#7", repo: "web", color: RGB(r: 0.4, g: 0.6, b: 0.9), lastActive: Date())
            office(station, sim, .opened("task:web#7", repo: "web", via: .shuttle(for: nil)))
            unchanged(sim, station) {
                expect(step(sim, seconds: 120, until: { sim.deliveries.first?.landed == true }), "the crate is set down on the bay")
                _ = step(sim, seconds: 30)
                expect(sim.deliveries.count == 1 && sim.shown["work"]?.offices["task:web#7"].map { phase($0.phase) } == "ordered", "it waits there, the office still ordered")
                sim.bodies[a.id] = a
                let built = step(sim, seconds: 180, until: { sim.shown["work"]?.offices["task:web#7"]?.phase == .built })
                expect(built && sim.deliveries.isEmpty && !a.hasLoad, "fetched, carried and built: \(sim.lag() ?? "")")
            }
        }

        test("an office that ends with its crate inside: the crate is carried out to storage first, then the office folds") {
            let (sim, station, m) = fixture()
            station.ensureRoom(key: "task:web#5", name: "#5", repo: "web", color: RGB(r: 0.4, g: 0.6, b: 0.9), lastActive: Date())
            office(station, sim, .opened("task:web#5", repo: "web", via: .appear))
            put(station, sim, "web", [5], .ready, office: "task:web#5")
            sim.play()
            settle(sim, m)
            put(station, sim, "web", [5], .stored, office: "task:web#5")
            station.removeRoom(key: "task:web#5")
            office(station, sim, .gone("task:web#5"))
            unchanged(sim, station) {
                sim.play()
                var atFold: Shown.At??
                let done = step(sim, seconds: 120, until: {
                    if atFold == nil, case .folding? = sim.shown["work"]?.offices["task:web#5"]?.phase { atFold = .some(shown(sim, 5)) }
                    return sim.shown["work"]?.offices["task:web#5"] == nil && sim.cargo.isEmpty
                })
                expect(done && caughtUp(sim, station), "the crate in storage, the office gone: \(sim.lag() ?? "")")
                let out: Bool
                switch atFold {
                case .some(.some(.hands)), .some(.some(.row)): out = true
                default: out = false
                }
                expect(out, "in hands or on its row when the fold begins: \(sim.describe(atFold ?? nil))")
            }
        }

        test("an office that goes keeps its floor until its fold ends, and whoever is inside steps out before it folds") {
            let (sim, station, m) = fixture()
            sim.play()
            station.ensureRoom(key: "task:web#9", name: "#9", repo: "web", color: RGB(r: 0.4, g: 0.6, b: 0.9), lastActive: Date())
            office(station, sim, .opened("task:web#9", repo: "web", via: .appear))
            sim.play()
            sim.send(m, to: .room("task:web#9"))
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            expect(station.rooms["task:web#9"]?.cells.contains(m.cell) == true, "a stands in the office")
            station.removeRoom(key: "task:web#9")
            office(station, sim, .gone("task:web#9"))
            unchanged(sim, station) {
                sim.play()
                var foldedWithSomeoneIn = false
                let done = step(sim, seconds: 30, until: {
                    guard let o = sim.shown["work"]?.offices["task:web#9"] else { return true }
                    if case .folding = o.phase, Set(o.cells).contains(m.cell) { foldedWithSomeoneIn = true }
                    expect(station.lingering["task:web#9"] != nil && station.walkable.isSuperset(of: o.cells), "the shown floor stays walkable")
                    return false
                })
                expect(done && !foldedWithSomeoneIn, "a stepped out first, then it folded away")
                expect(station.lingering.isEmpty && m.place != .room("task:web#9") && sim.restPlace(m) != .room("task:web#9"), "nothing lingers and nobody is sent back in")
            }
        }

        test("a crate set down off its row is walked round, except in a lane, which it never closes") {
            let (sim, station, _) = fixture()
            sim.play()
            guard let row = station.hall.storageCells.first, let lane = station.hall.aisleCells.first else { return expect(false, "a yard") }
            func park(_ n: Int, _ c: Cell) {
                let pos = SIMD3(station.offset.x + Double(c.x), 0, station.offset.y + Double(c.y))
                sim.shown["work"]?.crates[CrateID(repo: "web", number: n)] = .parked(Spot(area: .storage, station: "work", owner: "web", label: "web", cell: c, pos: pos))
            }
            park(1, row)
            park(2, lane)
            sim.refreshObstacles()
            expect(station.obstacles.contains(Cell(x: row.x * Station.fine, y: row.y * Station.fine)), "the one on the rows is an obstacle")
            expect(!station.obstacles.contains(Cell(x: lane.x * Station.fine, y: lane.y * Station.fine)), "the one in the aisle is not")
        }

        test("a release merged: the vortex pulls every aboard crate in, one after another, and only then does the rocket climb") {
            let (sim, station, _) = fixture()
            put(station, sim, "web", [430, 431, 432], .cleared, quiet: true)
            _ = Rules.apply([.release(repo: "web", production: true, label: "")], at: sim.now, to: &station.facts, yard: station.yard)
            sim.play()
            guard let id = station.facts.rockets.keys.first else { return expect(false, "a rocket in the facts") }
            expect(sim.shown["work"]?.rockets[id]?.dock == 1, "a first sight is history: docked at once")
            _ = Rules.apply([.launched(repo: "web")], at: sim.now, to: &station.facts, yard: station.yard)
            unchanged(sim, station) {
                sim.play()
                guard let v = sim.vortices["work|" + id] else { return expect(false, "the merge opens a vortex") }
                expect(v.waiting.count == 3 && v.flying.isEmpty, "three crates wait their turn: \(v.waiting.count)")
                expect([430, 431, 432].allSatisfy { shown(sim, $0) == .vortex(id) }, "off the rows from the start: the vortex draws them")
                var aboard: [Int: Double] = [:]
                var climbedAt: Double?
                let gone = step(sim, seconds: 40, until: {
                    for n in [430, 431, 432] where aboard[n] == nil && shown(sim, n) == .aboard(id) { aboard[n] = sim.clock }
                    if climbedAt == nil, let c = sim.shown["work"]?.rockets[id]?.climbing { climbedAt = c }
                    return sim.shown["work"]?.flown.contains(id) == true
                })
                let times = aboard.values.sorted()
                expect(times.count == 3 && zip(times, times.dropFirst()).allSatisfy { $1 - $0 > 0.3 }, "pulled in one after another: \(times)")
                expect(climbedAt.map { c in times.count == 3 && times.allSatisfy { $0 <= c } } == true, "the climb waits for every crate: \(String(describing: climbedAt))")
                expect(gone && climbedAt.map { sim.clock - $0 >= ShownRocket.climbSeconds - 0.1 } == true, "gone a while after the climb")
                expect(caughtUp(sim, station), "and the picture is the facts: \(sim.lag() ?? "")")
            }
        }

        test("a go rocket waits with its crates on their rows; stood down, the tip comes up, and with nothing to wait for it goes, never in a blink") {
            let (sim, station, _) = fixture()
            put(station, sim, "web", [440, 441], .cleared, quiet: true)
            sim.play()
            _ = Rules.apply([.release(repo: "web", production: true, label: "")], at: sim.now, to: &station.facts, yard: station.yard)
            guard let id = station.facts.rockets.keys.first else { return expect(false, "a rocket in the facts") }
            unchanged(sim, station) {
                _ = step(sim, seconds: RocketGeometry.dockSeconds + 2)
                let r = sim.shown["work"]?.rockets[id]
                expect(r?.dock == 1 && r?.venting == true, "it appeared, docked over the lift's time and vents: \(String(describing: r))")
                expect(sim.cargo.isEmpty && sim.vortices.isEmpty, "nothing moves before the merge")
            }
            _ = Rules.apply([.release(repo: "web", production: nil, label: "")], at: sim.now, to: &station.facts, yard: station.yard)
            unchanged(sim, station) {
                _ = step(sim, seconds: 1)
                expect(sim.shown["work"]?.rockets[id].map { $0.dock > 0 && $0.dock < 1 && !$0.venting } == true, "the tip comes up slowly")
                _ = step(sim, seconds: RocketGeometry.dockSeconds)
                expect(sim.shown["work"]?.rockets[id]?.dock == 0 && caughtUp(sim, station), "standing on its legs: \(sim.lag() ?? "")")
                expect([440, 441].allSatisfy { if case .row(let s)? = shown(sim, $0) { return s.zone == .cleared }; return false }, "the crates still on their rows")
            }
            _ = Rules.apply([.policy(repo: "web", RepoFacts(hasStaging: true, hasCleared: true, ships: false)), .release(repo: "web", production: nil, label: "")],
                            at: sim.now, to: &station.facts, yard: station.yard)
            unchanged(sim, station) {
                var faded = false
                let gone = step(sim, seconds: 5, until: {
                    if let r = sim.shown["work"]?.rockets[id], r.leaving != nil { faded = true }
                    return sim.shown["work"]?.rockets[id] == nil
                })
                expect(gone && faded && caughtUp(sim, station), "it fades away, then is gone: \(sim.lag() ?? "")")
            }
        }

        for seed in PlaybackTests.busySeeds {
            test("a busy yard, seed \(seed): 400 rounds of news between short steps; the picture catches up by itself, never on air") {
                busy(seed: UInt64(seed), rounds: 400)
            }
        }

        say(failures == 0 ? "playback: all passed" : "playback: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static var busySeeds = [3]

    private static func busy(seed start: UInt64, rounds: Int) {
        let (sim, station, a) = fixture()
        let b = body("b", sim: sim, station: station), c = body("c", sim: sim, station: station)
        settle(sim, a, b, c)
        var seed = start
        func roll(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
        var floating: [String] = []
        var next = 1
        for _ in 0..<rounds {
            let repos = ["web", "api", "ios"], repo = repos[roll(3)]
            let mine = station.facts.crates.values.filter { $0.id.repo == repo }.sorted { $0.id < $1.id }
            let pick = mine.isEmpty ? nil : mine[roll(mine.count)]
            switch roll(7) {
            case 0, 1: put(station, sim, repo, [next], .stored); next += 1
            case 2: if let p = pick { put(station, sim, repo, [p.id.number], .qa) }
            case 3: if let p = pick { put(station, sim, repo, [p.id.number], .cleared) }
            case 4: if let p = pick { put(station, sim, repo, [p.id.number], .stored) }
            case 5: if let p = pick { put(station, sim, repo, [p.id.number], .shipped) }
            default: _ = Rules.apply([.restack], at: sim.now, to: &station.facts, yard: station.yard)
            }
            unchanged(sim, station, bytewise: false) { _ = step(sim, seconds: 0.5 + Double(roll(4)) * 0.5, every: 15, until: { floating += unsupported(sim); return false }) }
        }
        unchanged(sim, station) {
            let done = step(sim, seconds: 1800, every: 15, until: { floating += unsupported(sim); return caughtUp(sim, station) })
            expect(done, "caught up: \(sim.lag() ?? "")")
            if !done {
                for job in sim.cargo.values { say("        move \(job.command.words) kind \(job.kind) rank \(job.rank) carrier \(job.carrier ?? "-") blocked \(job.blockedBy.sorted())") }
                for (id, at) in (sim.shown["work"]?.crates ?? [:]).sorted(by: { $0.key < $1.key }) { say("        \(id): \(sim.describe(at)) · fact \(sim.describe(sim.targets(station)[id]?.at))") }
            }
        }
        expect(sim.snapped == 0, "the watchdog never had to snap: \(sim.snapped)")
        expect(floating.isEmpty, "no crate ever stood on nothing: \(Set(floating).sorted())")
    }

    private static func put(_ station: Station, _ sim: Simulation<Body>, _ repo: String, _ numbers: [Int], _ stage: Stage,
                            office: String? = nil, quiet: Bool = false) {
        let news = numbers.map { Event.work(WorkNews(crate: CrateID(repo: repo, number: $0), office: office, stage: stage, quiet: quiet)) }
        _ = Rules.apply([.policy(repo: repo, staged)] + news, at: sim.now, to: &station.facts, yard: station.yard)
    }

    private static func office(_ station: Station, _ sim: Simulation<Body>, _ news: OfficeNews) {
        _ = Rules.apply([.office(news)], at: sim.now, to: &station.facts, yard: station.yard)
    }

    private static func phase(_ p: ShownOffice.Phase) -> String {
        switch p {
        case .ordered: return "ordered"
        case .unfolding: return "unfolding"
        case .fading: return "fading"
        case .built: return "built"
        case .folding: return "folding"
        }
    }

    private static func shown(_ sim: Simulation<Body>, _ number: Int) -> Shown.At? {
        sim.shown["work"]?.crates[CrateID(repo: "web", number: number)]
    }

    private static func caughtUp(_ sim: Simulation<Body>, _ station: Station) -> Bool {
        sim.cargo.isEmpty && sim.shown[station.name]?.crates == sim.targets(station).mapValues(\.at)
    }

    private static func unsupported(_ sim: Simulation<Body>) -> [String] {
        let rows = (sim.shown["work"]?.crates ?? [:]).compactMap { id, at -> (CrateID, YardSpot)? in if case .row(let s) = at { return (id, s) }; return nil }
        let standing = Set(rows.map(\.1.slot))
        let bad = rows.filter { $0.1.level > 0 && !standing.contains(Slot(zone: $0.1.zone, column: $0.1.column, level: $0.1.level - 1)) }
        return bad.map { "\($0.0)" }
    }

    private static func unchanged(_ sim: Simulation<Body>, _ station: Station, bytewise: Bool = true, _ body: () -> Void) {
        for _ in 0..<64 {
            let was = station.facts
            _ = Rules.apply([.tick], at: sim.now, to: &station.facts, yard: station.yard)
            if station.facts == was { break }
        }
        let facts = station.facts, before = bytewise ? bytes(facts) : Data()
        body()
        expect(station.facts == facts && (!bytewise || bytes(station.facts) == before), "playback never writes a fact")
    }

    private static func bytes(_ f: Facts) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return (try? e.encode(f)) ?? Data()
    }

    private static func settle(_ sim: Simulation<Body>, _ bodies: Body...) {
        for m in bodies { sim.send(m, to: .lounge) }
        _ = step(sim, seconds: 30, until: { bodies.allSatisfy { $0.path.isEmpty } })
    }

    private static func fixture() -> (Simulation<Body>, Station, Body) {
        let world = World(demo: true)
        let station = world.fleet.station("work")
        let sim = Simulation<Body>(world: world)
        sim.idleRoll = { 0.99 }
        return (sim, station, body("a", sim: sim, station: station))
    }

    private static func body(_ id: String, sim: Simulation<Body>, station: Station) -> Body {
        let m = Body(id: id, station: "work", home: Home(key: "kind:lounge", name: id, repo: "r", issue: nil), cwd: "",
                     toolCount: 0, isSubagent: false, start: station.coreCenter)
        m.state = .settled
        m.activity = .waiting
        sim.bodies[m.id] = m
        return m
    }

    private static func step(_ sim: Simulation<Body>, seconds: Double, every: Int = 1, until done: () -> Bool = { false }) -> Bool {
        var left = seconds, k = 0
        while left > 0 {
            sim.step(dt: Tempo.substep)
            left -= Tempo.substep
            k += 1
            if k % every == 0, done() { return true }
        }
        return false
    }

    private static func test(_ name: String, _ body: () -> Void) {
        let before = failures
        body()
        say((failures == before ? "PASS  " : "FAIL  ") + name)
    }
    private static func expect(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; say("      not so: \(what)") }
    }
    private static func say(_ text: String) { FileHandle.standardError.write((text + "\n").data(using: .utf8)!) }
}
