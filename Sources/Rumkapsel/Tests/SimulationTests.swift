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
            sim.hooks = SimHooks()
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

        test("a reaction that arrives mid-shower takes the teammate out of it, straight to its place") {
            let (sim, station, m) = fixture()
            m.isCrew = true
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            m.showering = true
            expect(sim.visitBath(m, station: station), "off to the shower")
            _ = step(sim, seconds: 30, until: { m.phaseKind == .act && m.fetchSpot == nil })
            sim.react(m, .coding("src"), place: .quarters, minutes: 2, words: "johan is shipping")
            expect(m.current.map { if case .react = $0.kind { return true }; return false } == true, "the reaction is in hand at once: \(m.words)")
            expect(m.fixture == nil && !m.drying, "and the shower is let go")
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

        test("a coffee: in through the lounge, made at arm's length facing the counter, then back to the couch with a mug") {
            let (sim, station, m) = fixture()
            sim.hooks = SimHooks()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            guard let galley = station.galley else { return expect(false, "a galley on the station") }
            expect(station.doorOutside(of: "kind:galley").map { station.room(at: $0)?.key } == "kind:lounge", "the galley opens into the lounge")
            expect(sim.visitGalley(m, station: station, fare: .coffee), "the galley was free")
            let other = body("b", sim: sim, station: station)
            expect(!sim.visitGalley(other, station: station, fare: .bite), "one at the counter at a time")
            expect(step(sim, seconds: 30, until: { m.atCounter }), "reached the counter")
            let reach = galley.machine(.coffee) - m.pos
            expect(abs((reach.x * reach.x + reach.y * reach.y).squareRoot() - Hands.arm) < 0.03, "an arm's length from the machine: \(reach)")
            expect(abs(atan2(sin(m.facing - galley.facing), cos(m.facing - galley.facing))) < 0.05, "facing the counter")
            let planned = m.actFor
            expect(Command.Fare.coffee.seconds.contains(planned), "a coffee takes \(planned) s")
            m.bathDue = sim.clock + 1
            expect(step(sim, seconds: planned + 5, until: { m.fare == nil || !m.atCounter }), "done")
            expect(!m.bathing && !m.atCounter && m.fetchSpot == nil, "a bath come due waits for the coffee")
            expect(m.place == .lounge && m.mugUntil > sim.clock, "back to the lounge, mug in hand")
            expect(sim.visitLog.first.map { $0.kind == "galley" && $0.lasted + 0.25 >= $0.planned } == true, "lasted its whole time: \(sim.visitLog)")
        }

        test("a probe researches in trips between the monolith and its office, and docks with its minion when done") {
            let (sim, station, _) = fixture()
            _ = station.ensureRoom(key: "task:web#455", name: "#455 booking", repo: "web", color: Colors.repos[0], lastActive: Date())
            guard let office = station.rooms["task:web#455"] else { return expect(false, "an office on the station") }
            let home = Home(key: office.key, name: office.name, repo: office.repo ?? "r", issue: nil)
            let parent = Body(id: "parent", station: "work", home: home, cwd: "", toolCount: 0, isSubagent: false, start: office.cells[0])
            parent.state = .settled; parent.activity = .coding("x"); parent.busy = true
            sim.bodies[parent.id] = parent
            let probe = Body(id: "probe", station: "work", home: home, cwd: "", toolCount: 0, isSubagent: true, start: office.cells[0])
            probe.state = .settled; probe.activity = .researching; probe.busy = true
            sim.bodies[probe.id] = probe
            sim.send(probe, to: sim.restPlace(probe))
            expect(step(sim, seconds: 40, until: { probe.place == .core && probe.path.isEmpty }), "out to the monolith")
            expect(step(sim, seconds: 40, until: { probe.place == .room(office.key) && probe.path.isEmpty }), "home with the answer: \(probe.place)")
            expect(step(sim, seconds: 40, until: { probe.place == .core && probe.path.isEmpty }), "and out again")
            probe.activity = .exploring
            sim.send(probe, to: sim.restPlace(probe))
            expect(step(sim, seconds: 40, until: { probe.place == .room(office.key) && probe.path.isEmpty }), "reading code, it stays in its office")
            parent.pos = probe.pos
            expect(step(sim, seconds: 5, until: { probe.cell != parent.cell && probe.path.isEmpty }), "someone on its tile: it buzzes off to a free one")
            probe.state = .leaving
            expect(step(sim, seconds: 40, until: { sim.bodies[probe.id] == nil }), "done, it docks and is gone")
            let distance = abs(probe.pos.x - parent.pos.x) + abs(probe.pos.y - parent.pos.y)
            expect(distance < 2, "it docked at its minion: \(distance) tiles off")
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

        test("dismissed, a body walks out to the bay, boards the shuttle that comes in for it, and goes with it") {
            let (sim, station, m) = fixture()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            sim.dismiss(m)
            sim.assignOrders()
            expect(m.state == .leaving && !m.path.isEmpty, "off to the bay")
            expect(sim.pickup(for: m) != nil, "a ship is on its way for it")
            var boarded = false
            expect(step(sim, seconds: 90, until: {
                if sim.bodies[m.id] != nil, m.opacity < 1, sim.pickup(for: m)?.phaseKind == .unload { boarded = true }
                return sim.bodies[m.id] == nil
            }), "gone within a minute and a half; last at \(m.cell.x),\(m.cell.y) in \(m.phaseKind), waiting on \(m.waitingOn ?? "nothing")")
            expect(boarded, "it went aboard while its ship stood on the berth")
            expect(station.hangarCells.contains(m.cell), "on the bay: \(m.cell.x),\(m.cell.y)")
            expect(step(sim, seconds: 30, until: { sim.flights.isEmpty }), "and the ship leaves with it")
        }

        test("the board: a body with a crate on its arms is not taken off its carry") {
            let (sim, station, m) = fixture()
            put(station, sim, "web", [440], .stored, quiet: true)
            put(station, sim, "web", [441], .qa, quiet: true)
            sim.play()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            let first = CrateRef(station: "work", repo: "web", number: 440)
            put(station, sim, "web", [440], .qa)
            expect(step(sim, seconds: 60, until: { m.load == .crate(first) }), "up on the arms")
            put(station, sim, "web", [441], .cleared)
            sim.play()
            sim.assignOrders()
            let release = sim.cargo.values.first { $0.crate.number == 441 }
            expect(m.current?.crate == first && m.load == .crate(first), "it keeps the crate it holds: \(m.words)")
            expect(release?.rank == .release && release?.carrier == nil, "the release waits for the next free hands")
        }

        test("the board: a message takes its body off a carry it has not lifted yet, which goes back on the board") {
            let (sim, station, m) = fixture()
            put(station, sim, "web", [440], .stored, quiet: true)
            sim.play()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            put(station, sim, "web", [440], .qa)
            sim.play()
            sim.assignOrders()
            guard let carry = m.current, carry.crate != nil else { return expect(false, "a carry in hand: \(m.words)") }
            expect(!m.hasLoad, "on its way to the crate: \(m.words)")
            let desk = station.cells(of: .room(m.home.key)).first ?? m.cell
            let message = Command(kind: .work(office: m.home.key), words: "working your message")
            sim.post(message, for: m, rank: .message, at: desk, place: .room(m.home.key))
            expect(m.current?.id == message.id, "off to the message: \(m.words)")
            expect(sim.cargo[carry.id]?.carrier == nil, "the carry is back on the board, nobody on it")
            _ = step(sim, seconds: 60, until: { m.phaseKind != .walk })
            expect(sim.ownOrders[message.id] == nil, "at the cone the message is worked, and off the board")
            sim.assignOrders()
            expect(m.current?.id == carry.id, "and the carry is picked up again from the desk: \(m.words)")
        }

        test("the board: packing waits for its worker's hands to be free, then it is the next thing done") {
            let (sim, station, m) = fixture()
            put(station, sim, "web", [440], .stored, quiet: true)
            sim.play()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            put(station, sim, "web", [440], .qa)
            let crate = CrateRef(station: "work", repo: "web", number: 440)
            expect(step(sim, seconds: 60, until: { m.load == .crate(crate) }), "up on the arms")
            guard let carry = m.current else { return expect(false, "a carry in hand") }
            let desk = station.cells(of: .room(m.home.key)).first ?? m.cell
            let pack = Command.pack(office: m.home.key)
            sim.post(pack, for: m, rank: .yard, at: desk, place: .room(m.home.key))
            expect(m.current?.id == carry.id && sim.ownOrders[pack.id]?.held == false, "the crate on the arms first; the pack waits: \(m.words)")
            expect(step(sim, seconds: 60, until: { m.current?.id == pack.id }), "then the pack, straight from the set-down: \(m.words)")
            expect(step(sim, seconds: 60, until: { sim.ownOrders[pack.id] == nil && m.current?.id != pack.id }), "packed, and off the board")
        }

        test("the board: a body keeps one of each kind of its own orders waiting, the newest") {
            let (sim, station, m) = fixture()
            put(station, sim, "web", [440], .stored, quiet: true)
            sim.play()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            put(station, sim, "web", [440], .qa)
            let crate = CrateRef(station: "work", repo: "web", number: 440)
            expect(step(sim, seconds: 60, until: { m.load == .crate(crate) }), "a crate on its arms, which no order takes it from")
            let desk = station.cells(of: .room(m.home.key)).first ?? m.cell
            let first = Command.stow(office: m.home.key), second = Command.stow(office: m.home.key)
            sim.post(first, for: m, rank: .yard, at: desk, place: .room(m.home.key))
            sim.post(second, for: m, rank: .yard, at: desk, place: .room(m.home.key))
            expect(sim.ownOrders[first.id] == nil && sim.ownOrders[second.id] != nil, "the second stow replaces the first")
            let dropped = sim.drainCues().contains { if case .ownDropped(_, let c) = $0 { return c.id == first.id }; return false }
            expect(dropped, "and the scene is told the first will not be done")
        }

        test("idle is no order: a carry takes a body out of the shower, and the bath is left as it was") {
            let (sim, station, m) = fixture()
            put(station, sim, "web", [440], .stored, quiet: true)
            sim.play()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            m.showering = true
            expect(sim.visitBath(m, station: station), "off to the shower")
            expect(step(sim, seconds: 30, until: { m.phaseKind == .act && m.fetchSpot == nil }), "in it")
            expect(!sim.start(m, .rest(place: .lounge, home: m.home.key, office: m.home.name, yours: true, asleep: false)) && m.bathing,
                   "a plain start does not cut into the visit, and nothing is left waiting on the body")
            put(station, sim, "web", [440], .qa)
            sim.play()
            sim.assignOrders()
            expect(m.current?.crate?.number == 440, "out of the shower for the carry: \(m.words)")
            expect(m.fixture == nil && !m.drying && m.place != .bath, "off the fixture, no towel, and the bath no longer its place")
        }

        test("dismissed with a crate on its arms, a body sets it down first, then leaves") {
            let (sim, station, m) = fixture()
            put(station, sim, "web", [440], .stored, quiet: true)
            sim.play()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            put(station, sim, "web", [440], .qa)
            let crate = CrateRef(station: "work", repo: "web", number: 440)
            expect(step(sim, seconds: 60, until: { m.load == .crate(crate) }), "up on the arms")
            guard let carry = m.current else { return expect(false, "a carry in hand") }
            sim.dismiss(m)
            expect(m.current?.id == carry.id && m.state == .leaving, "it keeps the carry in hand: \(m.words)")
            expect(step(sim, seconds: 60, until: { m.current.map { if case .leave = $0.kind { return true }; return false } ?? false }), "then it leaves: \(m.words)")
            expect(!m.hasLoad && shown(sim, 440)?.zone == .testing, "with the crate set down on the deck: \(sim.describe(shown(sim, 440)))")
            expect(m.place == .hangar && !m.path.isEmpty, "on its way out")
        }

        test("a wedged carrier gives up after ten seconds: the crate lies behind it and the carry is queued again") {
            let (sim, station, m) = fixture()
            put(station, sim, "web", [440], .stored, quiet: true)
            sim.play()
            let crate = CrateRef(station: "work", repo: "web", number: 440)
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            put(station, sim, "web", [440], .qa)
            expect(step(sim, seconds: 60, until: { m.load == .crate(crate) && m.phaseKind == .haul }), "up on the arms and hauling")
            m.wedged = true
            var gaveUp = false
            let was = sim.onEvent
            sim.onEvent = { if case .log(let t) = $0, t.contains(" gives up ") { gaveUp = true }; was($0) }
            _ = step(sim, seconds: 12, until: { gaveUp })
            expect(gaveUp, "said so in the log")
            expect(!m.hasLoad && m.landing?.dropped == true, "the crate is down behind it")
            if case .parked? = shown(sim, 440) {} else { expect(false, "shown parked where it fell: \(sim.describe(shown(sim, 440)))") }
            let job = sim.cargo.values.first
            expect(job?.carrier == nil && job?.gaveUp.contains(m.id) == true, "queued again, this carrier passed over while there is anyone else")
            if case .carry(_, let from, _)? = job?.command.kind, let landing = m.landing {
                expect(abs(from.pos.x - landing.pos.x) < 0.01 && abs(from.pos.z - landing.pos.z) < 0.01, "from where the crate now lies: \(from.cell.x),\(from.cell.y)")
            } else { expect(false, "the carry is still a carry") }
        }

        test("every way in and out of the bay threads its mouth: from outside, in through the field low and level, onto its berth, and out the same way") {
            let mouth = BayMouth(z: 11.5, height: Station.mouthHeight)
            for arrival in Arrival.allCases {
                for side in [1.0, -1.0] {
                    let at = SIMD3(3.0, 0, 9.0), rest = Station.restOverCrate
                    let legs = arrivalLegs(arrival, at: at, rest: rest, side: side, mouth: mouth)
                    let path = [legs.start] + legs.approach.points + legs.descend.points
                    expect(legs.start.z > mouth.z + 2, "\(arrival) comes in from outside the bay, not over the station: \(legs.start.z)")
                    let down = legs.descend.last
                    expect(abs(down.x - at.x) < 0.01 && abs(down.z - at.z) < 0.01 && abs(down.y - rest) < 0.01,
                           "\(arrival) ends over its berth: \(down.x),\(down.y),\(down.z)")
                    for p in path { expect(p.y >= rest - 0.01, "\(arrival) keeps its skids off the floor: \(p.y)") }
                    for (a, b) in zip(path, path.dropFirst()) {
                        expect(b.y <= a.y + 0.01, "\(arrival) only ever comes down: \(a.y) then \(b.y)")
                    }
                    for p in path where p.z < mouth.z { expect(p.y < Station.fieldTop, "\(arrival) stays under the hangar's roof: \(p.y)") }
                    let out = departureLegs(.climb, at: at, rest: rest, side: side, mouth: mouth)
                    let away = ([SIMD3(at.x, rest, at.z)] + out.rise.points + out.leave.points)
                    for (a, b) in zip(away, away.dropFirst()) {
                        expect(b.y >= a.y - 0.01, "a climb only ever goes up: \(a.y) then \(b.y)")
                    }
                }
            }
            for departure in Departure.allCases {
                let at = SIMD3(3.0, 0, 9.0)
                let out = departureLegs(departure, at: at, rest: Station.restOnSkids, side: 1, mouth: mouth)
                expect(out.leave.last.y > 5, "\(departure) leaves high: \(out.leave.last.y)")
                expect(out.leave.last.z > mouth.z, "\(departure) leaves outward, not over the station: \(out.leave.last.z)")
                let away = [SIMD3(at.x, Station.restOnSkids, at.z)] + out.rise.points + out.leave.points
                for p in away { expect(p.y >= Station.restOnSkids - 0.01, "\(departure) keeps its skids off the floor: \(p.y)") }
                for p in away where p.z < mouth.z { expect(p.y < Station.fieldTop, "\(departure) stays under the hangar's roof: \(p.y)") }
            }
        }

        test("a carrier left off the floor with a crate on its arms steps back onto it and delivers") {
            let (sim, station, m) = fixture()
            put(station, sim, "web", [440], .stored, quiet: true)
            sim.play()
            let crate = CrateRef(station: "work", repo: "web", number: 440)
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            put(station, sim, "web", [440], .qa)
            expect(step(sim, seconds: 60, until: { m.load == .crate(crate) && m.phaseKind == .haul }), "up on the arms and hauling")
            let north = station.walkable.map(\.y).min()! - 4
            m.pos = SIMD2(Double(station.walkable.filter { $0.y == north + 4 }.map(\.x).min()!), Double(north))
            m.path = []
            expect(!station.walkable.contains(m.cell), "off the floor at \(m.cell.x),\(m.cell.y)")
            var gaveUp = false
            let was = sim.onEvent
            sim.onEvent = { if case .log(let t) = $0, t.contains(" gives up ") { gaveUp = true }; was($0) }
            _ = step(sim, seconds: 90, until: { m.current?.crate == nil })
            expect(!gaveUp, "never gave up")
            expect(shown(sim, 440)?.zone == .testing, "down on the deck: \(sim.describe(shown(sim, 440)))")
            expect(station.walkable.contains(m.cell), "and back on the floor at \(m.cell.x),\(m.cell.y)")
        }

        test("a carrier giving up off the floor drops the crate on the nearest floor, not in space") {
            let (sim, station, m) = fixture()
            put(station, sim, "web", [440], .stored, quiet: true)
            sim.play()
            let crate = CrateRef(station: "work", repo: "web", number: 440)
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            put(station, sim, "web", [440], .qa)
            expect(step(sim, seconds: 60, until: { m.load == .crate(crate) && m.phaseKind == .haul }), "up on the arms and hauling")
            let north = station.walkable.map(\.y).min()! - 4
            m.pos = SIMD2(Double(station.walkable.filter { $0.y == north + 4 }.map(\.x).min()!), Double(north))
            m.path = []
            m.wedged = true
            var gaveUp = false
            let was = sim.onEvent
            sim.onEvent = { if case .log(let t) = $0, t.contains(" gives up ") { gaveUp = true }; was($0) }
            _ = step(sim, seconds: 30, until: { gaveUp })
            expect(gaveUp, "gave up, wedged")
            if let landing = m.landing {
                let cell = Cell(x: Int((landing.pos.x - station.offset.x).rounded()), y: Int((landing.pos.z - station.offset.y).rounded()))
                expect(station.walkable.contains(cell), "the crate lies on the floor at \(cell.x),\(cell.y)")
            } else { expect(false, "the crate was put down") }
            if case .carry(_, let from, _)? = sim.cargo.values.first?.command.kind {
                expect(station.walkable.contains(from.cell), "and the carry starts again from the floor: \(from.cell.x),\(from.cell.y)")
            } else { expect(false, "the carry is still queued") }
        }

        test("a crate a walk cannot get any closer to is reached with the last shuffle, not waited on for good") {
            let (sim, station, m) = fixture()
            for (k, repo) in ["a", "b", "c", "d"].enumerated() { put(station, sim, repo, [300 + k], .stored, quiet: true) }
            put(station, sim, "web", [444], .stored, quiet: true)
            sim.play()
            put(station, sim, "web", [444], .qa)
            sim.play()
            let crate = CrateRef(station: "work", repo: "web", number: 444)
            guard case .carry(_, let from, _)? = sim.cargo.values.first(where: { $0.crate.number == 444 })?.command.kind else { return expect(false, "a carry") }
            let at = SIMD2(from.pos.x - station.offset.x, from.pos.z - station.offset.y)
            let crateCell = Cell(x: Int(at.x.rounded()), y: Int(at.y.rounded()))
            let own = [Cell(x: crateCell.x + 1, y: crateCell.y + 1), Cell(x: crateCell.x - 1, y: crateCell.y + 1),
                       Cell(x: crateCell.x + 1, y: crateCell.y - 1), Cell(x: crateCell.x - 1, y: crateCell.y - 1)].first { station.walkable.contains($0) }
            guard let own else { return expect(false, "a floor cell diagonal to the crate") }
            m.pos = SIMD2(Double(own.x), Double(own.y))
            func block() {
                for c in station.walkable where c != own && abs(c.x - crateCell.x) <= 3 && abs(c.y - crateCell.y) <= 3 {
                    station.obstacles.insert(Cell(x: c.x * Station.fine, y: c.y * Station.fine))
                }
            }
            block()
            sim.assignOrders()
            var gaveUp = false
            let was = sim.onEvent
            sim.onEvent = { if case .log(let t) = $0, t.contains(" gives up ") { gaveUp = true }; was($0) }
            expect(step(sim, seconds: 30, until: { m.load == .crate(crate) }, beat: block), "lifted: \(m.words), phase \(m.phaseKind) at \(m.cell.x),\(m.cell.y)")
            expect(!gaveUp, "never gave up")
        }

        test("a crate left just off the floor, its office gone from under it, is still fetched") {
            let (sim, station, m) = fixture()
            put(station, sim, "web", [440], .stored, quiet: true)
            sim.play()
            let crate = CrateRef(station: "work", repo: "web", number: 440)
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            let north = station.walkable.map(\.y).min()!
            let x = station.walkable.filter { $0.y == north }.map(\.x).min()!
            let spot = Spot(area: .office, station: "work", owner: "gone", label: "gone", cell: Cell(x: x, y: north - 1),
                            pos: SIMD3(station.offset.x + Double(x), 0.12, station.offset.y + Double(north - 1)))
            expect(!station.walkable.contains(spot.cell), "the crate lies off the floor")
            sim.shown["work"]?.crates[CrateID(repo: "web", number: 440)] = .parked(spot)
            sim.play()
            sim.assignOrders()
            var gaveUp = false
            let was = sim.onEvent
            sim.onEvent = { if case .log(let t) = $0, t.contains(" gives up ") { gaveUp = true }; was($0) }
            expect(step(sim, seconds: 60, until: { m.load == .crate(crate) }), "lifted: \(m.words), phase \(m.phaseKind) at \(m.cell.x),\(m.cell.y)")
            expect(!gaveUp, "never gave up")
        }
        test("a minion sent to a console sits on the seat its anchor says, facing the console, at the seat's height, then goes back") {
            let (sim, station, m) = fixture()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            guard let ref = station.anchors(in: "kind:mission").first(where: { station.place($0)?.use != .stand }),
                  let seat = station.place(ref) else { return expect(false, "mission control has a seat") }
            expect(sim.use(m, ref, station: station, seconds: 20) && m.using == ref && m.place == .room("kind:mission"), "off to the console")
            expect(step(sim, seconds: 60, until: { m.inPlace }), "in place: \(m.words) at \(m.pos)")
            let off = seat.at - m.pos
            expect((off.x * off.x + off.y * off.y).squareRoot() < 0.03, "on the seat: \(m.pos) against \(seat.at)")
            expect(abs(atan2(sin(m.facing - seat.facing), cos(m.facing - seat.facing))) < 0.01 && m.seated && m.sittingOn == Seat.height,
                   "facing the console, seated at the seat's height: facing \(m.facing), seated \(m.seated)")
            expect(step(sim, seconds: 40, until: { m.using == nil }) && m.place == .lounge && m.sittingOn == nil && !m.inPlace, "the turn ends back on the couch: \(m.place.words)")
        }
        test("a minion at the holo table stands an arm's length from its rim, facing it; one body to an anchor") {
            let (sim, station, m) = fixture()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            guard let ref = station.anchors(in: "kind:mission").first(where: { station.place($0)?.use == .stand }),
                  let stand = station.place(ref) else { return expect(false, "the holo table has a place to stand") }
            expect(sim.use(m, ref, station: station, seconds: 20), "off to the table")
            expect(step(sim, seconds: 60, until: { m.inPlace }), "in place: \(m.words)")
            let reach = stand.at - m.pos
            let dist = (reach.x * reach.x + reach.y * reach.y).squareRoot()
            expect(abs(dist - Hands.arm) < 0.03 && !m.seated, "an arm's length from the rim, standing: \(dist)")
            let toward = atan2(reach.x, reach.y)
            expect(abs(atan2(sin(m.facing - toward), cos(m.facing - toward))) < 0.05, "facing the table")
            let other = sim.bodies.values.first { $0.id != m.id && $0.station == m.station }
            if let other { expect(!sim.freeAnchors(other, station: station, in: "kind:mission").contains(ref), "nobody else is offered that place") }
        }
        test("a job that cuts in on the way to a fixture takes the body clean: not using it, not in place, not seated, place given back") {
            let (sim, station, m) = fixture()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            guard let ref = station.anchors(in: "kind:mission").first(where: { station.place($0)?.use != .stand }) else { return expect(false, "a seat") }
            expect(sim.use(m, ref, station: station, seconds: 200), "off to the console")
            _ = step(sim, seconds: 1)
            sim.start(m, .deliverOffice(order: 9003, name: "an office"))
            expect(m.using == nil && !m.inPlace && !m.seated && m.sittingOn == nil && m.place == .lounge, "clean: place \(m.place.words), seated \(m.seated)")
        }
        test("a job that cuts in on the way to a visit takes the body clean: no spot, no fixture, no seat, place given back") {
            let (sim, station, m) = fixture()
            sim.send(m, to: .lounge)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            guard let gym = station.rooms["kind:gym"] else { return expect(false, "a gym on the station") }
            expect(sim.takeTurnInGym(m, station: station, gym: gym) && m.fetchSpot != nil && m.place == .gym, "off to the gym, a fixture spot in mind")
            _ = step(sim, seconds: 1)
            sim.start(m, .deliverOffice(order: 9001, name: "an office"))
            expect(!m.exercising && m.fetchSpot == nil && !m.onBench && m.place == .lounge, "the errand is in hand and the turn's leftovers are gone: \(m.words), place \(m.place.words), spot \(String(describing: m.fetchSpot))")
            sim.finish(m)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty })
            m.showering = false
            expect(sim.visitBath(m, station: station) && m.fixture == 0, "then off to the bowl")
            _ = step(sim, seconds: 1)
            sim.start(m, .deliverOffice(order: 9002, name: "an office"))
            expect(!m.bathing && m.fixture == nil && !m.seated && m.fetchSpot == nil && m.place != .bath, "and again clean: fixture \(String(describing: m.fixture)), place \(m.place.words)")
        }

        test("more resting than there are seats: nobody shares a couch or a bed") {
            let (sim, station, first) = fixture()
            let crowd = [first] + (1..<12).map { body("r\($0)", sim: sim, station: station) }
            for (k, m) in crowd.enumerated() { sim.send(m, to: k % 2 == 0 ? .lounge : .quarters) }
            _ = step(sim, seconds: 60)
            let couches = crowd.compactMap(\.couch), beds = crowd.compactMap(\.bed)
            expect(couches.count > 1 && beds.count > 1, "several seated and several in bed: \(couches.count) couches, \(beds.count) beds")
            expect(Set(couches).count == couches.count, "one to a couch: \(couches.sorted())")
            expect(Set(beds).count == beds.count, "one to a bed: \(beds.sorted())")
        }

        test("a sleeper given something to do stands up where it lies before it walks anywhere") {
            let (sim, station, m) = fixture()
            sim.send(m, to: .quarters)
            _ = step(sim, seconds: 30, until: { m.path.isEmpty && m.place == .quarters })
            m.activity = .sleeping
            m.napping = true
            _ = step(sim, seconds: 6, until: { m.lying })
            expect(m.lying, "asleep in the quarters, flat on its back")
            let bedSpot = m.pos

            sim.send(m, to: .lounge)
            expect(m.risingUntil > 0, "roused: it is getting to its feet, not walking yet")
            expect(!m.lying, "and it stands up at once, rather than waiting until it walks")
            var moved = 0.0
            _ = step(sim, seconds: 1.0, beat: {
                moved = max(moved, ((m.pos.x - bedSpot.x) * (m.pos.x - bedSpot.x)
                                    + (m.pos.y - bedSpot.y) * (m.pos.y - bedSpot.y)).squareRoot())
            })
            expect(moved < 0.05, String(format: "it stays where it lay while it rises: moved %.2f", moved))
            _ = step(sim, seconds: 30, until: { m.place == .lounge && m.path.isEmpty })
            expect(m.place == .lounge, "and then walks there")
        }

        test("night falls: a sleeping body goes to bed and sleeps there; in the morning it goes to the lounge") {
            let (sim, _, m) = fixture()
            m.activity = .sleeping
            let hooks = SimHooks()
            sim.hooks = hooks
            var kinds: [Command.Kind] = [], said: [String] = []
            hooks.onCommand = { c, _ in kinds.append(c.kind) }
            sim.onEvent = { if case .log(let t) = $0 { said.append(t) } }
            sim.setNight(true)
            expect(said == ["night falls"], "said: \(said)")
            expect(step(sim, seconds: 60, until: { m.path.isEmpty && m.phaseKind == .settle }), "settled")
            expect(m.place == .quarters && m.bed != nil, "in bed in the quarters: \(m.place.words)")
            expect(kinds.contains { if case .sleep = $0 { return true }; return false }, "asleep: \(m.words)")
            sim.setNight(false)
            expect(said == ["night falls", "morning"], "said: \(said)")
            expect(step(sim, seconds: 60, until: { m.path.isEmpty && m.place == .lounge }), "up and to the lounge: \(m.place.words)")
            expect(kinds.contains { if case .goTo(.lounge) = $0 { return true }; return false } && m.couch != nil, "on a couch: \(m.words)")
        }

        test("step(600) in one call fires every due timer and the beat") {
            let (sim, _, _) = fixture()
            var fired: [Double] = [], beats = 0
            for at in [1.0, 120, 599, 700] { sim.after(at) { fired.append(at) } }
            sim.onBeat = { _ in beats += 1 }
            let start = sim.clock
            sim.step(dt: 600)
            expect(abs(sim.clock - start - 600) < 1e-6, "the clock moved by 600: \(sim.clock - start)")
            expect(abs(sim.now.timeIntervalSince(sim.epoch) - sim.clock) < 1e-6, "and now with it")
            expect(fired == [1, 120, 599], "every due timer fired once, in order, the later one waits: \(fired)")
            expect(beats == 1, "one beat: \(beats)")
        }

        say(failures == 0 ? "simulation: all passed" : "simulation: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static let staged = RepoFacts(hasStaging: true, hasCleared: true)

    private static func put(_ station: Station, _ sim: Simulation<Body>, _ repo: String, _ numbers: [Int], _ stage: Stage, quiet: Bool = false) {
        let news = numbers.map { Event.work(WorkNews(crate: CrateID(repo: repo, number: $0), stage: stage, quiet: quiet)) }
        _ = Rules.apply([.policy(repo: repo, staged)] + news, at: sim.now, to: &station.facts, yard: station.yard)
    }

    private static func shown(_ sim: Simulation<Body>, _ number: Int, repo: String = "web") -> Shown.At? {
        sim.shown["work"]?.crates[CrateID(repo: repo, number: number)]
    }

    private static func fixture() -> (Simulation<Body>, Station, Body) {
        let world = World(demo: true)
        let station = world.fleet.station("work")
        let sim = Simulation<Body>(world: world)
        sim.idleRoll = { 0.99 }
        let m = Body(id: "a", station: "work", home: Home(key: "kind:lounge", name: "a", repo: "r", issue: nil), cwd: "",
                     toolCount: 0, isSubagent: false, start: station.coreCenter)
        m.state = .settled
        m.activity = .waiting
        sim.bodies[m.id] = m
        return (sim, station, m)
    }

    private static func body(_ id: String, sim: Simulation<Body>, station: Station) -> Body {
        let m = Body(id: id, station: "work", home: Home(key: "kind:lounge", name: id, repo: "r", issue: nil), cwd: "",
                     toolCount: 0, isSubagent: false, start: station.coreCenter)
        m.state = .settled
        m.activity = .waiting
        sim.bodies[m.id] = m
        return m
    }

    private static func step(_ sim: Simulation<Body>, seconds: Double, until done: () -> Bool = { false }, beat: @escaping () -> Void = {}) -> Bool {
        sim.onBeat = { _ in beat() }
        defer { sim.onBeat = { _ in } }
        var left = seconds
        while left > 0 {
            sim.step(dt: Tempo.substep)
            left -= Tempo.substep
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
