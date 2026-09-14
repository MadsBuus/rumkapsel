// Model-only tests of the simulation: `.build/debug/Rumkapsel --sim-tests`.
//
// A station of the fleet's own making, bare bodies, no scene: the clock stepped by hand a thirtieth
// of a second at a time. A body sent somewhere walks there and settles; a visit to the bath lasts
// its whole time from arrival, with the sitter sat, up again and the flush behind; a turn in the
// gym ends back where it began; nothing but rest moves a body that has a visit in hand; and the way
// out is through the airlock, faded and gone.

import Foundation

enum SimulationTests {
    private static var failures = 0

    static func run() -> Never {
        test("sent to the lounge, a body walks there, settles with a name, and takes a couch") {
            let (sim, station, m) = fixture()
            sim.send(m, to: .lounge)
            expect(!m.path.isEmpty, "a walk was planned")
            expect(step(sim, seconds: 30, until: { m.path.isEmpty && m.phaseKind == .settle }), "arrived and settled")
            expect(m.place == .lounge && station.cells(of: .lounge).contains(m.cell), "in the lounge at \(m.cell.x),\(m.cell.y)")
            expect(m.couch != nil, "on a couch")
            expect(!m.words.isEmpty && m.current?.isRest == true, "doing something with a name: \(m.words)")
        }

        test("a visit to the bowl lasts its minute from arrival: sat, then up with the flush, then back") {
            let (sim, station, m) = fixture()
            sim.hooks = SimHooks()   // visits are logged only for the checks
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            m.showering = false
            expect(sim.visitBath(m, station: station), "the bowl was free")
            expect(m.bathing && m.place == .bath && m.fixture == 0, "off to the bowl")
            var arrivedAt = 0.0, sat = false, flushed = false
            _ = step(sim, seconds: 30, until: {
                if m.phaseKind == .act, arrivedAt == 0 { arrivedAt = sim.clock }
                return arrivedAt > 0 && m.fetchSpot == nil
            })
            expect(arrivedAt > 0, "the visit began on arrival")
            expect(abs(m.phaseUntil - (arrivedAt + 60)) < 0.05, "and lasts sixty seconds from then: until \(m.phaseUntil), arrived \(arrivedAt)")
            _ = step(sim, seconds: 70, until: {
                if m.seated { sat = true }
                if sim.drainCues().contains(where: { if case .flush = $0 { return true }; return false }) { flushed = true }
                return !m.bathing
            })
            expect(sat, "sat on the bowl")
            expect(flushed, "and the bowl flushed as it stood")
            expect(!m.seated, "up off the seat")
            expect(sim.clock - arrivedAt >= 60 - 0.05, "lasted its whole time: \(sim.clock - arrivedAt) s")
            expect(m.place == .lounge, "back to where it came from: \(m.place.words)")
            expect(sim.visitLog.count == 1 && sim.visitLog[0].kind == "bath" && sim.visitLog[0].lasted >= 59.9, "logged: \(sim.visitLog)")
        }

        test("a turn in the gym lasts its time on the fixture and ends back where the body was") {
            let (sim, station, m) = fixture()
            sim.hooks = SimHooks()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            guard let gym = station.rooms["kind:gym"] else { return expect(false, "a gym on the station") }
            expect(sim.takeTurnInGym(m, station: station, gym: gym), "a fixture was free")
            let kind = m.workout
            expect(kind != nil && m.place == .gym && m.exercising, "off to the gym for \(kind.map(\.words) ?? "nothing")")
            _ = step(sim, seconds: 30, until: { m.phaseKind == .act && m.fetchSpot == nil })
            let planned = m.actFor
            expect(planned >= 240 && planned <= 480, "four to eight minutes: \(planned)")
            if kind == .bench {
                _ = step(sim, seconds: 1)
                expect(m.onBench && m.lying, "flat on the back along the bench")
            }
            _ = step(sim, seconds: planned + 5, until: { !m.exercising })
            expect(!m.exercising && !m.onBench && m.place == .lounge, "the turn over, back to the lounge; on the bench: \(m.onBench)")
            expect(sim.visitLog.first.map { $0.kind == "gym" && $0.lasted + 0.25 >= $0.planned } == true, "lasted its whole time: \(sim.visitLog)")
        }

        test("nothing but rest moves a body with a visit in hand: a send during the bath changes nothing") {
            let (sim, station, m) = fixture()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            expect(sim.visitBath(m, station: station), "off to the bath")
            let path = m.path
            sim.send(m, to: .quarters)
            expect(m.bathing && m.place == .bath && m.path == path, "the visit kept the body: \(m.words)")
            sim.resettle(station)
            expect(m.bathing && m.place == .bath, "and a floor change leaves it alone")
        }

        test("a lounger's idle clock is armed on the couch and dropped by work") {
            let (sim, _, m) = fixture()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            _ = step(sim, seconds: 1)
            expect(m.idle.armed, "armed once settled")
            m.busy = true
            _ = step(sim, seconds: 1)
            expect(!m.idle.armed, "dropped by work")
        }

        test("dismissed, a body goes out through the airlock and is gone") {
            let (sim, station, m) = fixture()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            sim.dismiss(m)
            expect(m.state == .leaving && m.place == .airlock && !m.path.isEmpty, "off to the airlock")
            expect(step(sim, seconds: 60, until: { sim.bodies[m.id] == nil }), "gone within a minute; last at \(m.cell.x),\(m.cell.y) in \(m.phaseKind), \(m.path.count) waypoints left")
            expect(m.opacity <= 0, "faded out")
            expect(station.airlockCells.contains(m.cell) || station.hangarCells.contains(m.cell), "inside the airlock or on the bay: \(m.cell.x),\(m.cell.y)")
        }

        test("a carry: the crate is lifted onto the arms, walked to the deck and set down, the ledger keeping step") {
            let (sim, station, m) = fixture()
            station.ledger.adopt(Ledger.Word(storage: [440], deck: []), repo: "web")
            let crate = CrateRef(station: "work", repo: "web", number: 440)
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            let commands = sim.world.carryToDeck(station: station, repo: "web", numbers: [440])
            expect(commands.count == 1, "one carry for one crate: \(commands.count)")
            var landedCalled = false
            for c in commands { expect(sim.carry(c, onDone: { landedCalled = true }), "the deck had a place for it") }
            expect(sim.world.isCarried(crate), "spoken for from the order")
            sim.scheduleCarries()
            expect(m.current?.crate == crate && !m.path.isEmpty, "handed to the one free body, who sets off: \(m.words)")
            var lifted = false, arms: String?
            _ = step(sim, seconds: 60, until: {
                if m.load == .crate(crate) { lifted = true; arms = sim.world.crate(crate)?.carrier }
                return m.current?.crate == nil
            })
            expect(lifted && arms == m.id, "on the arms, and the ledger says whose: \(String(describing: arms))")
            expect(!m.hasLoad && m.landing != nil && !m.landing!.dropped, "set down on its slot")
            expect(sim.world.crate(crate)?.area == .deck && sim.world.crate(crate)?.heading == .deck, "the ledger has it down on the deck, the landing still to be written by what the scene meant to do: \(String(describing: sim.world.crate(crate)?.at))")
            expect(sim.cargo.isEmpty, "the carry is over")
            let landed = sim.drainCues().contains { if case .landed = $0 { return true }; return false }
            expect(landed && !landedCalled, "the landing is a cue for the scene, which runs what it meant to do")
            expect(m.current?.isRest == true, "and the body is back to rest: \(m.words)")
        }

        test("a wedged carrier gives up after ten seconds: the crate lies behind it and the carry is queued again") {
            let (sim, station, m) = fixture()
            station.ledger.adopt(Ledger.Word(storage: [440], deck: []), repo: "web")
            let crate = CrateRef(station: "work", repo: "web", number: 440)
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            for c in sim.world.carryToDeck(station: station, repo: "web", numbers: [440]) { sim.carry(c, onDone: {}) }
            sim.scheduleCarries()
            expect(step(sim, seconds: 60, until: { m.load == .crate(crate) && m.phaseKind == .haul }), "up on the arms and hauling")
            m.wedged = true
            var gaveUp = false
            let was = sim.onEvent
            sim.onEvent = { if case .log(let t) = $0, t.contains(" gives up ") { gaveUp = true }; was($0) }
            _ = step(sim, seconds: 12, until: { gaveUp }, beat: { sim.reconcileBodies() })
            expect(gaveUp, "said so in the log")
            expect(!m.hasLoad && m.landing?.dropped == true, "the crate is down behind it")
            expect(sim.world.crate(crate)?.carrier == nil && sim.world.isCarried(crate) == false, "off the arms in the ledger: \(String(describing: sim.world.crate(crate)?.at))")
            let job = sim.cargo.values.first
            expect(job?.carrier == nil && job?.gaveUp.contains(m.id) == true, "queued again, this carrier passed over while there is anyone else")
            if case .carry(_, let from, _)? = job?.command.kind {
                let behind = SIMD2(m.pos.x - sin(m.facing) * Hands.arm, m.pos.y - cos(m.facing) * Hands.arm)
                expect(abs(from.pos.x - station.offset.x - behind.x) < 0.01 && abs(from.pos.z - station.offset.y - behind.y) < 0.01, "from where the crate now lies: \(from.cell.x),\(from.cell.y)")
            } else { expect(false, "the carry is still a carry") }
        }

        say(failures == 0 ? "simulation: all passed" : "simulation: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// A station with the fixed rooms, and one body settled in it with nothing to do.
    private static func fixture() -> (Simulation<Body>, Station, Body) {
        let world = World(demo: true)
        let station = world.fleet.station("work")
        let sim = Simulation<Body>(world: world)
        let m = Body(id: "a", station: "work", home: Home(key: "kind:lounge", name: "a", repo: "r", issue: nil), cwd: "",
                     toolCount: 0, isSubagent: false, start: station.coreCenter)
        m.state = .settled
        m.activity = .waiting
        sim.bodies[m.id] = m
        return (sim, station, m)
    }

    /// Steps station time until the condition holds or the seconds run out; true when it held.
    private static func step(_ sim: Simulation<Body>, seconds: Double, until done: () -> Bool = { false }, beat: () -> Void = {}) -> Bool {
        let dt = 1.0 / 30
        var left = seconds
        var sinceBeat = 0.0
        while left > 0 {
            sim.clock += dt
            sinceBeat += dt
            if sinceBeat >= 0.5 { sinceBeat = 0; beat() }   // the half-second pass: the reconcilers
            sim.stepBodies(dt: dt)
            left -= dt
            if done() { return true }
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
