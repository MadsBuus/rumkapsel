import AppKit
import SceneKit
import simd

struct Expect {
    let words: String
    let matches: (SimRecord) -> Bool

    static func press(_ name: String) -> Expect {
        Expect(words: "press \(name)") { if case .press(let n) = $0 { return n == name }; return false }
    }
    static func event(_ words: String, _ test: @escaping (WorldEvent) -> Bool) -> Expect {
        Expect(words: words) { if case .event(let e) = $0 { return test(e) }; return false }
    }
    static func command(_ words: String, by who: String? = nil, _ test: @escaping (Command.Kind) -> Bool) -> Expect {
        Expect(words: who.map { "\(words) by \($0)" } ?? words) {
            if case .command(let c, let by) = $0, who == nil || who == by { return test(c.kind) }
            return false
        }
    }

    // MARK: events

    static func log(_ text: String) -> Expect {
        event("log \"\(text)\"") { if case .log(let t) = $0 { return t.contains(text) }; return false }
    }
    static func staging(_ repo: String, _ what: String) -> Expect {
        event("staging release \(what) \(repo)") { if case .log(let t) = $0 { return t.hasPrefix("\(repo): staging release #") && t.hasSuffix(" " + what) }; return false }
    }
    static func releaseOpened(_ repo: String, untested: Bool) -> Expect {
        event("release on the pad \(repo)\(untested ? " untested" : "")") {
            if case .log(let t) = $0 { return t.hasPrefix("\(repo): release to ") && t.hasSuffix(untested ? " (untested)" : Words.current.onThePad) }; return false
        }
    }
    static func releaseMerged(_ repo: String) -> Expect {
        event("release merged \(repo)") { if case .log(let t) = $0 { return t.hasPrefix("\(repo): release merged, ") }; return false }
    }
    static func arrived(_ number: Int, in zone: Zone) -> Expect {
        event("arrived #\(number) in \(zone)") { if case .log(let t) = $0 { return t.contains("#\(number)") && t.hasSuffix(" to \(zone.words)") }; return false }
    }
    static func officeOpened(_ keyPrefix: String, _ via: OfficeFact.Via? = nil, shuttle: Bool = false) -> Expect {
        let how = via.map { " \($0)" } ?? (shuttle ? " by shuttle" : "")
        return event("office opened \(keyPrefix)…\(how)") {
            guard case .office(_, .opened(let key, _, let how), _) = $0, key.hasPrefix(keyPrefix) else { return false }
            if shuttle, case .shuttle = how { return true }
            return !shuttle && (via == nil || via == how)
        }
    }
    static func officeGone(_ key: String, reason: String) -> Expect {
        event("office gone \(key) (\(reason))") {
            if case .office(let st, .gone(let k), let why) = $0 { return st + "|" + k == key && why == reason }; return false
        }
    }
    static func crewActivity(_ login: String, _ kind: String) -> Expect {
        event("crewActivity \(login) \(kind)") { if case .crewActivity(let a) = $0 { return a.login == login && a.kind == kind }; return false }
    }
    static func peerArrived(_ name: String) -> Expect {
        event("peerArrived \(name)") { if case .peerArrived(let n) = $0 { return n == name }; return false }
    }
    static func peerLeft(_ name: String) -> Expect {
        event("peerLeft \(name)") { if case .peerLeft(let n) = $0 { return n == name }; return false }
    }

    // MARK: commands

    static func carry(_ number: Int? = nil, to zone: Zone) -> Expect {
        command("carry \(number.map { "#\($0)" } ?? "any crate") to \(zone)") {
            if case .carry(let crate, _, let to) = $0 { return to == zone && (number == nil || crate.number == number) }; return false
        }
    }
    static func deliverOffice(by who: String) -> Expect {
        command("deliverOffice", by: who) { if case .deliverOffice = $0 { return true }; return false }
    }
    static let flight = command("flight", by: "shuttle") { if case .flight = $0 { return true }; return false }
    static func standing(_ repo: String) -> Expect { log("\(repo) \(Words.current.standingBy)") }
    static func go(_ repo: String) -> Expect { log("\(repo) \(Words.current.steaming)") }
    static func liftingOff(_ repo: String) -> Expect { log("\(repo) \(Words.current.liftingOff)") }
}

struct Scenario {
    let name: String
    let steps: [(press: String, wait: Double)]
    let tail: Double
    let expects: [Expect]
    let forbids: [Expect]
    let hold: Double
    let floor: (@MainActor (SimulatorController) -> String?)?

    init(_ name: String, _ steps: [(String, Double)], tail: Double, expects: [Expect], forbids: [Expect] = [],
         floor: (@MainActor (SimulatorController) -> String?)? = nil) {
        self.name = name
        self.steps = steps.map { (press: $0.0, wait: $0.1) }
        self.tail = tail
        self.hold = forbids.isEmpty ? 20 : 60
        self.expects = expects
        self.forbids = forbids
        self.floor = floor
    }

    @MainActor static func crates(_ sim: SimulatorController, _ zones: Set<Zone>, _ repo: String) -> Int {
        sim.station.world.fleet.stations["work"]?.facts.crates.values.filter { $0.id.repo == repo && $0.zone.map(zones.contains) == true }.count ?? 0
    }

    @MainActor static func drawn(_ sim: SimulatorController) -> String? {
        for st in sim.station.world.fleet.stations.values {
            for (id, at) in sim.station.simulation.shown[st.name]?.crates ?? [:] {
                guard case .row(let slot) = at else { continue }
                guard let node = sim.station.crateNode(CrateRef(station: st.name, repo: id.repo, number: id.number)) else { return "\(id) is not drawn" }
                let off = simd_distance(SIMD2(Double(node.position.x), Double(node.position.z)), SIMD2(slot.pos.x, slot.pos.z))
                if off > 0.05 { return "\(id) is drawn \(off) from its place on the rows" }
            }
        }
        return nil
    }

    @MainActor static func count(_ sim: SimulatorController, _ e: Expect, after press: String? = nil) -> Int {
        let records = sim.model.records
        let from = press.flatMap { p in records.firstIndex { if case .press(let n) = $0 { return n == p }; return false } } ?? 0
        return records[from...].filter(e.matches).count
    }
}

enum Scenarios {
    @MainActor static let all: [Scenario] = [
        Scenario("the pipeline: my PR merges to storage, staging takes it to the deck, it is ticked, released and goes up", [
            ("Target: web#455", 0),
            ("Open PR", 32),
            ("Merge PR", 4.8),
            ("Board: Move web#455 to \(ConfigStore.shared.current.statuses.storage)", 48),
            ("Release: Staging opens", 16),
            ("Release: Staging merges", 64),
            ("Release: Production opens", 32),
            ("Release: Mark tested", 64),
            ("Release: Production merges", 4.8),
        ], tail: 240, expects: [
            .log("PR #455 open"),
            .arrived(455, in: .waiting),
            .carry(455, to: .waiting),
            .staging("web", "merged"),
            .carry(455, to: .testing),
            .releaseOpened("web", untested: true),
            .go("web"),
            .carry(455, to: .cleared),
            .releaseMerged("web"),
            .liftingOff("web"),
        ], floor: { sim in
            let left = Scenario.crates(sim, [.waiting, .testing, .cleared], "web")
            if left > 0 { return "\(left) web crates left on the floor after lift-off" }
            if let r = sim.station.simulation.shown["work"]?.rockets.values.first(where: { $0.repo == "web" && $0.climbing != nil }) { return "the web rocket is still on its way up: \(r.slot)" }
            return Scenario.drawn(sim)
        }),

        Scenario("offices: a teammate's office by shuttle, his merge hauled out before it folds, his closed PR cleared, a neighbour in the gym", [
            ("Target: api#5158", 0),
            ("Prompt", 8),
            ("Teammate: New branch", 48),
            ("Teammate: Open PR", 32),
            ("Teammate: Merge PR", 48),
            ("Target: api#5140", 0),
            ("Teammate: Close PR", 32),
            ("Scan: again", 600),
            ("GitHub: Poll", 16),
            ("Peer: To the gym", 64),
            ("Peer: Back to work", 4.8),
        ], tail: 64, expects: [
            .flight,
            .officeOpened("task:api#", .shuttle(for: "crew:leo")),
            .deliverOffice(by: "leo"),
            .crewActivity("leo", "pr_open"),
            .carry(to: .waiting),
            .log("pull request closed, not merged"),
            .officeGone("work|task:api#5140", reason: "pull request closed"),
            .command("a turn in the gym", by: "kim") { if case .use(let ref, _, _, _) = $0 { return ref.room == "kind:gym" }; return false },
            .command("back at work", by: "kim") { if case .work = $0 { return true }; return false },
        ], forbids: [
            .carry(5140, to: .waiting),
        ], floor: { sim in
            let flights = Scenario.count(sim, .flight)
            if flights != 1 { return "\(flights) shuttles flew, not one" }
            guard let st = sim.station.world.fleet.stations["work"] else { return "no station" }
            let teammate = st.rooms.keys.filter { $0.hasPrefix("task:api#") && $0 != "task:api#5158" }
            if !teammate.isEmpty { return "the teammate's offices still stand: \(teammate.sorted())" }
            if !st.lingering.isEmpty { return "a folded office is still walkable: \(st.lingering.keys.sorted())" }
            return Scenario.drawn(sim)
        }),

        Scenario("outside work and a hotfix: a bot's object cleared from decon into storage, a hotfix up in its own rocket beside the release", [
            ("Target: ios#298", 0),
            ("Bot: Open PR", 32),
            ("Bot: Merge PR", 32),
            ("Release: Production opens", 16),
            ("Release: Hotfix opens", 48),
            ("Release: Hotfix merges", 4.8),
        ], tail: 240, expects: [
            .log("in decon"),
            .log(Words.current.clearedDecon),
            .carry(to: .waiting),
            .log("hotfix #298"),
            .log("ios: hotfix #298 merged, 1 crate aboard"),
            .carry(298, to: .waiting),
            .liftingOff("ios"),
        ], forbids: [
            .officeOpened("task:ios#", shuttle: true),
        ], floor: { sim in
            guard let st = sim.station.world.fleet.stations["work"] else { return "no station" }
            if Scenario.crates(sim, [.decon], "ios") > 0 { return "an object is still in decon" }
            guard let object = st.facts.crates.values.first(where: { $0.id.repo == "ios" && $0.alien }), object.zone == .waiting else { return "the bot's object is not in storage" }
            let rockets = sim.station.simulation.shown["work"]?.rockets ?? [:]
            if rockets.values.contains(where: { if case .hotfix = $0.kind { return true }; return false }) { return "the hotfix rocket is still on the pad: \(rockets.keys.sorted())" }
            guard let release = rockets.first(where: { $0.value.repo == "ios" && $0.value.kind == .release })?.key else { return "the release rocket went: \(rockets.keys.sorted())" }
            if st.facts.rockets[release]?.launched == true { return "the release rocket launched with the hotfix" }
            return Scenario.drawn(sim)
        }),
    ]
}

@MainActor
final class ScenarioRunner {
    private let scenarios: [Scenario]
    private let verbose: Bool
    private var index = -1
    private var sim: SimulatorController?
    private var step = 0
    private var nextPressAt = 0.0
    private var endAt = 0.0
    private var startedAt = 0.0
    private var failed = 0
    private let suiteStart = Date()

    init(filter: String?, verbose: Bool) {
        scenarios = Scenarios.all.filter { s in filter.map { s.name.localizedCaseInsensitiveContains($0) } ?? true }
        self.verbose = verbose
    }

    func run() {
        guard !scenarios.isEmpty else { say("no scenarios matched"); NSApp.terminate(nil); return }
        say("running \(scenarios.count) scenario\(scenarios.count == 1 ? "" : "s"), station time stepped headless")
        begin()
        while sim != nil { autoreleasepool { frame() } }
        finish()
    }

    // MARK: the run

    private var simTime = 0.0
    private var lastPressAt = 0.0

    private func begin() {
        index += 1
        guard index < scenarios.count else { return finish() }
        sim = SimulatorController(frame: NSRect(x: 0, y: 0, width: 1060, height: 700))
        sim?.station.headless = true
        sim?.station.simulation.substep = ScenarioRunner.tick
        sim?.model.quiet = true
        step = 0
        simTime = 0
        startedAt = CACurrentMediaTime()
        nextPressAt = ScenarioRunner.settle
        endAt = .greatestFiniteMagnitude
    }

    static let settle = 16.0
    static let tick = 0.1

    private func frame() {
        guard let sim else { return }
        sim.station.stepSimulated(seconds: ScenarioRunner.tick)
        simTime += ScenarioRunner.tick
        let s = scenarios[index]
        let second = Int(simTime) != Int(simTime - ScenarioRunner.tick)
        if second, step == 0, quiet(sim.station) { nextPressAt = simTime }
        if step < s.steps.count, simTime >= nextPressAt {
            let it = s.steps[step]
            sim.model.press(it.press)
            step += 1
            nextPressAt = simTime + it.wait
            if step == s.steps.count { endAt = simTime + s.tail; lastPressAt = simTime }
        }
        if second { SCNTransaction.flush() }
        if simTime >= endAt {
            judge(verdict(s, sim))
        } else if second, step == s.steps.count, simTime - lastPressAt >= s.hold, verdict(s, sim) == nil {
            judge(nil)
        }
    }

    private func quiet(_ station: StationController) -> Bool {
        !station.world.placementsLeft && station.world.fleet.stations.values.allSatisfy { station.simulation.officeLag($0) == nil }
            && station.simulation.flights.isEmpty && station.simulation.cargo.isEmpty && station.minions.values.allSatisfy { $0.path.isEmpty }
    }

    private func verdict(_ s: Scenario, _ sim: SimulatorController) -> String? {
        let records = sim.model.records
        if let gaveUp = records.lazy.compactMap({ r -> String? in
            if case .event(.log(let t)) = r, t.contains(" gives up ") { return t }; return nil }).first {
            return "a minion gave up · " + gaveUp
        }
        if let skipped = records.lazy.compactMap({ if case .skipped(let why) = $0 { return why }; return nil }).first {
            return "a press was refused · " + skipped
        }
        for bad in s.forbids {
            if let hit = records.first(where: bad.matches) { return "saw \(bad.words) · \(hit.words)" }
        }
        var at = 0
        for want in s.expects {
            var hit = false
            while at < records.count {
                let r = records[at]
                at += 1
                if want.matches(r) { hit = true; break }
            }
            if !hit { return "never saw \(want.words)" }
        }
        if let lag = sim.station.simulation.lag() { return "the picture never caught up · " + lag }
        if sim.station.simulation.snapped > 0 { return "the playback watchdog had to snap \(sim.station.simulation.snapped) crate(s) to their facts" }
        return s.floor?(sim)
    }

    private func judge(_ reason: String?) {
        guard let sim else { return }
        let s = scenarios[index]
        let seconds = CACurrentMediaTime() - startedAt
        if verbose {
            say("--- \(s.name) ---")
            for l in sim.model.logLines { say("    " + l) }
            if let st = sim.station.world.fleet.stations["work"] {
                let view = sim.station.simulation.shown[st.name] ?? Shown()
                for c in st.facts.crates.values.sorted(by: { $0.id < $1.id }) {
                    say("    fact  \(c.id): \(c.place) column \(c.column.map(String.init) ?? "-") stage \(c.stage.map(String.init(describing:)) ?? "-")\(c.alien ? " alien" : "") · shown \(sim.station.simulation.describe(view.crates[c.id]))")
                }
                for job in sim.station.simulation.cargo.values.sorted(by: { $0.command.id < $1.command.id }) {
                    say("    move  \(job.command.words) · \(job.rank) · \(job.carrier ?? "nobody")\(job.blockedBy.isEmpty ? "" : " · waits on \(job.blockedBy.sorted())")")
                }
            }
            if let st = sim.station.world.fleet.stations["work"] {
                for f in st.facts.rockets.values.sorted(by: { $0.id < $1.id }) {
                    let r = sim.station.simulation.shown[st.name]?.rockets[f.id]
                    say("    rocket  \(f.id): slot \(f.slot.map(String.init) ?? "-")\(f.docked ? " docked" : "")\(f.go ? " go" : "")\(f.launched ? " launched" : "") · shown \(r.map { "slot \($0.slot) dock \($0.dock) welded \($0.welded)\($0.climbing == nil ? "" : " climbing")" } ?? "no") · vortex \(sim.station.simulation.vortices["work|" + f.id] != nil), pending \(sim.station.simulation.pending(st, f.id))")
                }
            }
            for m in sim.station.minions.values.sorted(by: { $0.home.name < $1.home.name }) {
                let spot = m.fetchSpot.map { " fetchSpot \(Int($0.x.rounded())),\(Int($0.y.rounded()))" } ?? ""
                say("    body  \(m.home.name): \(m.current?.words ?? "nothing") · \(m.phaseKind) at \(m.cell.x),\(m.cell.y) pos \(String(format: "%.2f,%.2f", m.pos.x, m.pos.y)) path \(m.path.count)\(spot)\(m.waitingOn.map { " waiting on \($0)" } ?? "")\(m.hasLoad ? " carrying" : "")")
            }
        }
        if let reason {
            failed += 1
            say(String(format: "FAIL  %-52@  %@  (%.1fs, %.0f station-s)", s.name as NSString, reason as NSString, seconds, simTime))
        } else {
            say(String(format: "PASS  %-52@  (%.1fs, %.0f station-s)", s.name as NSString, seconds, simTime))
        }
        self.sim = nil
        begin()
    }

    private func finish() {
        let seconds = Date().timeIntervalSince(suiteStart)
        say(String(format: "%d of %d passed in %.0fs", scenarios.count - failed, scenarios.count, seconds))
        exit(failed == 0 ? 0 : 1)
    }

    private func say(_ text: String) {
        FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
    }
}
