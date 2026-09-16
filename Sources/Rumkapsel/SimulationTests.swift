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
            var arrivedAt = 0.0, satAt = 0.0, sat = false, flushed = false
            _ = step(sim, seconds: 30, until: {
                if m.phaseKind == .act, arrivedAt == 0 { arrivedAt = sim.clock }
                if m.seated, satAt == 0 { satAt = sim.clock }
                return arrivedAt > 0 && m.fetchSpot == nil && satAt > 0
            })
            expect(arrivedAt > 0, "the visit began on arrival")
            expect(satAt > 0 && satAt - arrivedAt < 1.5, "sat down within a moment of arriving: \(satAt - arrivedAt) s")
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

        test("a shower ends at the towel rail: a beat drying off, the towel taken and hung back") {
            let (sim, station, m) = fixture()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            m.showering = true
            expect(sim.visitBath(m, station: station) && m.fixture == 1, "the shower was free")
            _ = step(sim, seconds: 30, until: { m.phaseKind == .act && m.fetchSpot == nil })
            let planned = m.actFor
            expect(planned >= 120 && planned <= 180, "two to three minutes: \(planned)")
            var taken = false, hung = false
            func drain() { for c in sim.drainCues() { if case .towel(_, _, let t) = c { if t { taken = true } else { hung = true } } } }
            _ = step(sim, seconds: planned + 1, until: { drain(); return m.drying })
            expect(m.drying && taken, "out from under the water and over to the rail with the towel")
            expect(m.fixture == 1 && m.bathing, "the shower is still held while drying")
            _ = step(sim, seconds: 8, until: { drain(); return !m.bathing })
            expect(!m.drying && hung && m.place == .lounge, "the towel back on the rail, and back to the lounge")
        }

        test("a reaction that arrives mid-shower waits, then walks to its place once the visit is over") {
            let (sim, station, m) = fixture()
            m.isCrew = true
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            m.showering = true
            expect(sim.visitBath(m, station: station), "off to the shower")
            _ = step(sim, seconds: 30, until: { m.phaseKind == .act && m.fetchSpot == nil })
            sim.react(m, .coding("src"), place: .quarters, minutes: 2, words: "johan is shipping")
            expect(m.bathing && m.pending != nil, "the reaction waits behind the shower: \(m.words)")
            _ = step(sim, seconds: m.actFor + 10, until: { !m.bathing })
            expect(m.current.map { if case .react = $0.kind { return true }; return false } == true, "then the reaction is in hand: \(m.words)")
            expect(m.place == .quarters && (!m.path.isEmpty || station.cells(of: .quarters).contains(m.cell)), "and the body is on its way to its place, not standing in the bath: place \(m.place.words), path \(m.path.count)")
        }

        test("the shower and the bowl are each one body's for the whole visit: a third visitor is turned away") {
            let (sim, station, a) = fixture()
            let b = body("b", sim: sim, station: station), c = body("c", sim: sim, station: station)
            for m in [a, b, c] { sim.send(m, to: .lounge) }
            _ = step(sim, seconds: 30, until: { [a, b, c].allSatisfy { $0.path.isEmpty } })
            a.showering = true
            expect(sim.visitBath(a, station: station) && a.fixture == 1, "the first takes the shower")
            b.showering = true
            expect(sim.visitBath(b, station: station) && b.fixture == 0 && !b.showering, "the second wanted it too and gets the bowl instead")
            expect(!sim.visitBath(c, station: station) && !c.bathing, "the third finds both taken, while the first two are still walking")
            _ = step(sim, seconds: 30, until: { a.phaseKind == .act && b.phaseKind == .act })
            expect(a.fetchSpot != b.fetchSpot, "on different fixtures: \(String(describing: a.fetchSpot)) and \(String(describing: b.fetchSpot))")
            expect(!sim.visitBath(c, station: station), "still turned away with both in use")
            _ = step(sim, seconds: 70, until: { !b.bathing })
            expect(b.fixture == nil, "the bowl is given back when the visit ends")
            c.showering = false
            expect(sim.visitBath(c, station: station) && c.fixture == 0, "and the next visitor gets it")
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
            if case .carry(_, let from, _)? = job?.command.kind, let landing = m.landing {
                expect(abs(from.pos.x - landing.pos.x) < 0.01 && abs(from.pos.z - landing.pos.z) < 0.01, "from where the crate now lies: \(from.cell.x),\(from.cell.y)")
            } else { expect(false, "the carry is still a carry") }
        }

        test("a job that cuts in on the way to a visit takes the body clean: no spot, no fixture, no seat, place given back") {
            let (sim, station, m) = fixture()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            guard let gym = station.rooms["kind:gym"] else { return expect(false, "a gym on the station") }
            expect(sim.takeTurnInGym(m, station: station, gym: gym) && m.fetchSpot != nil && m.place == .gym, "off to the gym, a fixture spot in mind")
            _ = step(sim, seconds: 1)
            sim.start(m, .dispatch(station: station.name, repo: "web", number: 1))   // a job: it cuts in on the walk
            expect(!m.exercising && m.fetchSpot == nil && !m.onBench && m.place == .lounge, "the errand is in hand and the turn's leftovers are gone: \(m.words), place \(m.place.words), spot \(String(describing: m.fetchSpot))")
            sim.finish(m)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            m.showering = false
            expect(sim.visitBath(m, station: station) && m.fixture == 0, "then off to the bowl")
            _ = step(sim, seconds: 1)
            sim.start(m, .dispatch(station: station.name, repo: "web", number: 2))
            expect(!m.bathing && m.fixture == nil && !m.seated && m.fetchSpot == nil && m.place != .bath, "and again clean: fixture \(String(describing: m.fixture)), place \(m.place.words)")
        }

        test("a pallet ordered mid-workout waits for the turn to end: nobody runs on the spot by the console") {
            let (sim, station, m) = fixture()
            station.ledger.adopt(Ledger.Word(storage: [440], deck: []), repo: "web")
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            guard let gym = station.rooms["kind:gym"] else { return expect(false, "a gym on the station") }
            expect(sim.takeTurnInGym(m, station: station, gym: gym), "off to the gym")
            _ = step(sim, seconds: 30, until: { m.phaseKind == .act && m.fetchSpot == nil })
            sim.orderPallet(station: station, repo: "web", number: 9001)
            expect(m.exercising && m.path.isEmpty && sim.palletErrand(of: m) == nil, "the one body is mid-turn and is left to it: \(m.words), path \(m.path.count)")
            _ = step(sim, seconds: m.actFor + 30, until: { sim.palletErrand(of: m) != nil }, beat: { sim.servicePallets() })   // the half-second pass asks again
            expect(sim.palletErrand(of: m) != nil && !m.exercising, "once the turn is over it takes the errand: \(m.words)")
        }

        test("a crate reaching storage while the pallet still stands there is lifted aboard too") {
            let (sim, station, m) = fixture()
            station.ledger.adopt(Ledger.Word(storage: [440], deck: []), repo: "web")
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            sim.orderPallet(station: station, repo: "web", number: 9000)
            expect(step(sim, seconds: 60, until: { sim.pallets["work"] != nil }), "a pallet comes out")
            let spot = sim.pallets["work"]?.spot ?? .zero
            expect(abs(spot.y - Double(station.storageAisleRow)) < 0.01,
                   "it floats in the aisle nearest the deck, row \(station.storageAisleRow), not \(spot.y)")
            expect(step(sim, seconds: 30, until: { sim.world.truth.pallets["work"]?.state == .loaded }), "the one crate is aboard and the pallet stands loaded")
            // A second pull request merges and its crate is walked into storage while the pallet waits.
            station.ledger.adopt(Ledger.Word(storage: [440, 441], deck: []), repo: "web")
            expect(sim.palletLatecomer(station: station, repo: "web", number: 441), "the late crate is taken on")
            expect(sim.world.truth.pallets["work"]?.state == .loading, "the pallet goes back to loading")
            expect(step(sim, seconds: 30, until: { sim.pallets["work"]?.isSettled == true }), "and settles again")
            expect(sim.pallets["work"]?.aboard.count == 2 && sim.world.truth.pallets["work"]?.crates.count == 2, "both crates aboard: \(sim.pallets["work"]?.aboard.count ?? -1)")
            sim.palletMerged(station: station, repo: "web")
            expect(step(sim, seconds: 120, until: { sim.pallets["work"] == nil }), "pushed across, emptied and gone")
            let placed = station.ledger.crates(of: "web").map(\.placed)
            expect(placed == [.deck, .deck], "both crates on the deck: \(placed)")
        }

        test("the pusher walks round to the back and steps in at a walk, rather than sliding across the floor") {
            let (sim, station, m) = fixture()
            station.ledger.adopt(Ledger.Word(storage: [440, 441], deck: []), repo: "web")
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            sim.orderPallet(station: station, repo: "web", number: 9000)
            expect(step(sim, seconds: 90, until: { sim.world.truth.pallets["work"]?.state == .loaded }), "the pallet is loaded")
            guard let p = sim.pallets["work"] else { return expect(false, "a pallet out") }
            sim.palletMerged(station: station, repo: "web")
            // The most it covers in one tick while it has nowhere left to walk: the step onto the spot.
            var creep = 0.0, was = m.pos, hadNowhereToWalk = false
            _ = step(sim, seconds: 90, until: {
                // Only the ticks where it was already standing still at the start of them: the tick a walk
                // ends on is a walk's own last stride onto its waypoint, not a creep.
                if hadNowhereToWalk, m.path.isEmpty, case .pushPallet = m.current?.kind, !p.pushing {
                    let d = m.pos - was
                    creep = max(creep, (d.x * d.x + d.y * d.y).squareRoot())
                }
                hadNowhereToWalk = m.path.isEmpty
                was = m.pos
                return p.pushing
            })
            expect(p.pushing, "it has its hands on the pallet")
            expect(creep <= 1.4 / 30 + 0.001, "and stepped in at a walking pace rather than sliding: \(creep) in a tick")
            expect(p.pushAcross == 0, "squarely behind it: storage keeps the lane behind the pallet clear floor")
        }

        test("a pallet is walked round, never through") {
            let (sim, station, m) = fixture()
            station.ledger.adopt(Ledger.Word(storage: [440], deck: []), repo: "web")
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            sim.orderPallet(station: station, repo: "web", number: 9000)
            expect(step(sim, seconds: 60, until: { sim.pallets["work"] != nil }), "a pallet comes out")
            guard let p = sim.pallets["work"] else { return }
            // Another body crosses the aisle the pallet is floating in, from one end to the other.
            let b = body("b", sim: sim, station: station)
            let row = station.storageAisleRow
            let xs = station.storageCells.filter { $0.y == row }.map(\.x)
            guard let lo = xs.min(), let hi = xs.max() else { return expect(false, "an aisle to cross") }
            b.pos = SIMD2(Double(lo), Double(row))
            b.place = .room("kind:storage")
            sim.walk(b, to: Cell(x: hi, y: row))
            expect(!b.path.isEmpty, "it has a way across")
            var through: SIMD2<Double>?
            _ = step(sim, seconds: 60, until: {
                if through == nil, sim.insidePallet(p, b.pos) { through = b.pos }
                return false
            }, beat: { sim.replanBlockedWalks() })
            expect(through == nil, "it went round the slab, not through it: \(String(describing: through)) against \(p.spot)")
        }

        test("a pallet already moving leaves a late crate where it stands") {
            let (sim, station, m) = fixture()
            station.ledger.adopt(Ledger.Word(storage: [440], deck: []), repo: "web")
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            sim.orderPallet(station: station, repo: "web", number: 9000)
            expect(step(sim, seconds: 60, until: { sim.pallets["work"] != nil }), "a pallet comes out")
            expect(step(sim, seconds: 30, until: { sim.world.truth.pallets["work"]?.state == .loaded }), "loaded")
            sim.palletMerged(station: station, repo: "web")
            expect(step(sim, seconds: 30, until: { sim.world.truth.pallets["work"]?.state == .moving }), "and on its way across")
            station.ledger.adopt(Ledger.Word(storage: [440, 441], deck: []), repo: "web")
            expect(!sim.palletLatecomer(station: station, repo: "web", number: 441), "too late: it stays on the rows")
        }

        test("a staging release: the pallet is ordered, loaded, pushed to the deck on the merge and unloaded there") {
            let (sim, station, m) = fixture()
            sim.hooks = SimHooks()
            var commands: [String] = []
            sim.hooks?.onCommand = { c, _ in commands.append(c.kindName) }
            station.ledger.adopt(Ledger.Word(storage: [440, 441], deck: []), repo: "web")
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            sim.orderPallet(station: station, repo: "web", number: 9000)
            expect(commands.last == "dispatch", "the one free body is sent to the console: \(commands)")
            expect(step(sim, seconds: 60, until: { sim.pallets["work"] != nil }), "a pallet comes out once the dispatcher is at the console")
            expect(step(sim, seconds: 30, until: { sim.pallets["work"]?.isSettled == true }), "and is loaded, one crate at a time")
            expect(sim.pallets["work"]?.aboard.count == 2 && sim.world.truth.pallets["work"]?.crates.count == 2, "both crates aboard, on the pallet in truth")
            expect(commands.contains("loadPallet") && commands.last == "waitPallet", "then the dispatcher waits for the release: \(commands)")
            sim.palletMerged(station: station, repo: "web")
            expect(step(sim, seconds: 90, until: { sim.world.truth.pallets["work"]?.state == .unloading }), "merged: pushed across and unloading; state \(String(describing: sim.world.truth.pallets["work"]?.state))")
            let onDeck = station.deckCells.contains(sim.pallets["work"]?.cellUnder ?? Cell(x: 99, y: 99))
            expect(onDeck, "the pallet stands on the deck at \(String(describing: sim.pallets["work"]?.cellUnder))")
            expect(step(sim, seconds: 30, until: { sim.pallets["work"] == nil }), "emptied and gone")
            let placed = station.ledger.crates(of: "web").map(\.placed)
            expect(placed == [.deck, .deck], "both crates on the deck in the ledger: \(placed)")
            let errand = commands.filter { $0 != "goTo" }
            expect(errand == ["dispatch", "loadPallet", "waitPallet", "pushPallet", "unloadPallet"], "in order: \(commands)")
            expect(m.current?.isRest == true, "and the dispatcher is back to rest: \(m.words)")
        }

        test("a crowded yard: the pallet's way across is measured, never assumed") {
            let (sim, station, _) = fixture()
            // Both yards packed: a dozen of the pallet's own in storage, staging full of other work.
            station.ledger.adopt(Ledger.Word(storage: Array(300..<312), deck: []), repo: "web")
            station.ledger.adopt(Ledger.Word(storage: Array(100..<124), deck: Array(200..<248)), repo: "api")
            let from = sim.palletSpot(station: station)
            let route = sim.palletRoute(station: station, repo: "web", from: from)
            expect(!route.isEmpty, "a way across was found through a crowded yard")
            let standing = sim.palletStanding(station: station).crates
            expect(sim.palletClearance(from, among: standing) >= 0, "it floats out clear of the rows")
            var at = from, worst = 9.9, where_ = from
            for leg in route {
                let air = sim.palletClearance(at, to: leg, among: standing)
                if air < worst { worst = air; where_ = leg }
                at = leg
            }
            expect(worst >= 0, String(format: "no crate is inside the band it sweeps: %.3f short, on the leg to (%.2f, %.2f)",
                                      worst, where_.x, where_.y))
        }

        test("walled in by the rows, a pallet waits rather than passing through them") {
            let (sim, station, _) = fixture()
            station.ledger.adopt(Ledger.Word(storage: Array(300..<306), deck: []), repo: "web")
            let from = sim.palletSpot(station: station)
            // A body stood where the route was drawn is walked round; a crate in the aisle is not, so
            // an aisle with one in it must simply not be offered as a way across.
            let standing = sim.palletStanding(station: station).crates
            let route = sim.palletRoute(station: station, repo: "web", from: from)
            for leg in route {
                expect(sim.palletClearance(from, to: leg, among: standing) >= 0, "every leg offered is a clear one")
            }
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

    /// Another body on the same station, settled and waiting like the fixture's.
    private static func body(_ id: String, sim: Simulation<Body>, station: Station) -> Body {
        let m = Body(id: id, station: "work", home: Home(key: "kind:lounge", name: id, repo: "r", issue: nil), cwd: "",
                     toolCount: 0, isSubagent: false, start: station.coreCenter)
        m.state = .settled
        m.activity = .waiting
        sim.bodies[m.id] = m
        return m
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
            sim.stepPallets(dt: dt)
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
