// A scripted regression suite: `.build/debug/Rumkapsel --scenarios`.
//
// Each scenario is a name, a list of simulator buttons with a pause after each, and what the run
// must have recorded when it is over: presses, events, commands and who ran them, as the values
// they were. Nothing here reads the log's prose. Every scenario gets its own station and its own
// made-up org, runs headless with station time stepped in 1/30 s ticks as fast as the machine goes,
// and passes only if every expectation was met, in order, nothing forbidden was recorded, the floor
// check agrees, and the invariant checker found nothing.
//
//     --scenarios              every scenario
//     --scenarios pallet       only the ones whose name contains "pallet"
//     --scenarios-verbose      print each scenario's whole log
//
// Exits non-zero if anything failed. Every wait is in station seconds: "press, wait 40, judge".

import AppKit

/// One thing the run must, or must not, have recorded. `matches` is the judge; `words` only names
/// the expectation in a failure line.
struct Expect {
    let words: String
    let matches: (SimRecord) -> Bool

    static func press(_ name: String) -> Expect {
        Expect(words: "press \(name)") { if case .press(let n) = $0 { return n == name }; return false }
    }
    static func event(_ words: String, _ test: @escaping (WorldEvent) -> Bool) -> Expect {
        Expect(words: words) { if case .event(let e) = $0 { return test(e) }; return false }
    }
    /// A command by anyone, or by one actor: an office's name, "shuttle", "rocket".
    static func command(_ words: String, by who: String? = nil, _ test: @escaping (Command.Kind) -> Bool) -> Expect {
        Expect(words: who.map { "\(words) by \($0)" } ?? words) {
            if case .command(let c, let by) = $0, who == nil || who == by { return test(c.kind) }
            return false
        }
    }

    // MARK: events

    /// A line for the station log. The one expectation that is about words, because the line is the thing.
    static func log(_ text: String) -> Expect {
        event("log \"\(text)\"") { if case .log(let t) = $0 { return t.contains(text) }; return false }
    }
    static func stagingOpened(_ repo: String) -> Expect {
        event("stagingOpened \(repo)") { if case .stagingOpened(_, let r, _) = $0 { return r == repo }; return false }
    }
    static func stagingMerged(_ repo: String) -> Expect {
        event("stagingMerged \(repo)") { if case .stagingMerged(_, let r, _) = $0 { return r == repo }; return false }
    }
    static func stagingClosed(_ repo: String) -> Expect {
        event("stagingClosed \(repo)") { if case .stagingClosed(_, let r, _) = $0 { return r == repo }; return false }
    }
    static func releaseOpened(_ repo: String, untested: Bool) -> Expect {
        event("releaseOpened \(repo)\(untested ? " untested" : "")") {
            if case .releaseOpened(_, let r, _, _, let u, _) = $0 { return r == repo && u == untested }; return false
        }
    }
    static func releaseMerged(_ repo: String, production: Bool) -> Expect {
        event("releaseMerged \(repo)\(production ? " production" : "")") {
            if case .releaseMerged(_, let r, _, _, _, let p) = $0 { return r == repo && p == production }; return false
        }
    }
    static func crateCleared(_ repo: String) -> Expect {
        event("crateCleared \(repo)") { if case .crateCleared(_, let r, _) = $0 { return r == repo }; return false }
    }
    static func boardMoved(_ repo: String, to stage: WorldEvent.Stage) -> Expect {
        event("boardMoved \(repo) -> \(stage)") { if case .boardMoved(let it, _, let to) = $0 { return it.repo == repo && to == stage }; return false }
    }
    static func deconCleared(_ repo: String) -> Expect {
        event("deconCleared \(repo)") { if case .deconCleared(_, let r, _) = $0 { return r == repo }; return false }
    }
    static func officeMerged(_ key: String) -> Expect {
        event("officeMerged \(key)") { if case .officeMerged(_, let k, _, _) = $0 { return k == key }; return false }
    }
    /// An office with this key, or one whose key starts like it when the number is not known ahead.
    static func officeOpened(_ keyPrefix: String, _ arrival: WorldEvent.Arrival, board: String? = nil, peer: String? = nil) -> Expect {
        event("officeOpened \(keyPrefix)… \(arrival)\(board.map { " board(\($0))" } ?? "")\(peer.map { " peer(\($0))" } ?? "")") {
            guard case .officeOpened(_, let key, let source, let how) = $0, key.hasPrefix(keyPrefix), how == arrival else { return false }
            switch source {
            case .board(let who): return board == nil || board == who
            case .peer(let who): return peer == nil || peer == who
            default: return board == nil && peer == nil
            }
        }
    }
    static func officeArchived(_ key: String, reason: String) -> Expect {
        event("officeArchived \(key) (\(reason))") {
            if case .officeArchived(_, let k, _, _, _, _, let why) = $0 { return k == key && why == reason }; return false
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

    /// A crate carried to a yard: any crate, or one by number.
    static func carry(_ number: Int? = nil, to yard: Yard) -> Expect {
        command("carry \(number.map { "#\($0)" } ?? "any crate") to \(yard)") {
            if case .carry(let crate, _, let to) = $0 { return to == yard && (number == nil || crate.number == number) }; return false
        }
    }
    static func deliverOffice(by who: String) -> Expect {
        command("deliverOffice", by: who) { if case .deliverOffice = $0 { return true }; return false }
    }
    static let flight = command("flight", by: "shuttle") { if case .flight = $0 { return true }; return false }
    static func rocket(_ stage: Command.RocketStage, _ repo: String) -> Expect {
        command("rocket \(stage) \(repo)", by: "rocket") {
            if case .rocket(let s, _, let r) = $0 { return s.rank == stage.rank && r == repo }; return false
        }
    }
    static func dispatch(_ repo: String) -> Expect {
        command("dispatch \(repo)") { if case .dispatch(_, let r, _) = $0 { return r == repo }; return false }
    }
    static func loadPallet(_ repo: String) -> Expect {
        command("loadPallet \(repo)") { if case .loadPallet(_, let r) = $0 { return r == repo }; return false }
    }
    static func waitPallet(_ repo: String) -> Expect {
        command("waitPallet \(repo)") { if case .waitPallet(_, let r) = $0 { return r == repo }; return false }
    }
    static func pushPallet(_ repo: String) -> Expect {
        command("pushPallet \(repo)") { if case .pushPallet(_, let r) = $0 { return r == repo }; return false }
    }
    static func unloadPallet(_ repo: String, back: Bool) -> Expect {
        command("unloadPallet \(repo)\(back ? " back" : "")") {
            if case .unloadPallet(_, let r, let b) = $0 { return r == repo && b == back }; return false
        }
    }
    static func stow(by who: String) -> Expect {
        command("stow", by: who) { if case .stow = $0 { return true }; return false }
    }
    static let sleep = command("sleep") { if case .sleep = $0 { return true }; return false }
    static let bath = command("bath") { if case .bath = $0 { return true }; return false }
    static let workout = command("exercise") { if case .exercise = $0 { return true }; return false }
    static let chore = command("chore") { if case .chore = $0 { return true }; return false }
    static func goTo(_ place: Place) -> Expect {
        command("goTo \(place.words)") { if case .goTo(let p) = $0 { return p == place }; return false }
    }
}

struct Scenario {
    let name: String
    /// A button and the station seconds to wait after pressing it.
    let steps: [(press: String, wait: Double)]
    /// Station seconds to keep the station running after the last press.
    let tail: Double
    /// What must have been recorded, in this order.
    let expects: [Expect]
    /// What must not have been recorded at all.
    let forbids: [Expect]
    /// A press the panel refuses is normally a broken script; a few scenarios mean to try one.
    var allowSkips = false
    /// A minion giving up mid-command is a stall the body reconciler caught: a bug in a scripted run,
    /// unless the scenario means to provoke one.
    var allowGiveUp = false
    /// What must stand on the floor when it is over, for the things the run does not record as it
    /// goes. Returns the reason it failed, or nil.
    let floor: (@MainActor (SimulatorController) -> String?)?

    init(_ name: String, _ steps: [(String, Double)], tail: Double, expects: [Expect], forbids: [Expect] = [],
         allowSkips: Bool = false, allowGiveUp: Bool = false, floor: (@MainActor (SimulatorController) -> String?)? = nil) {
        self.name = name
        self.steps = steps.map { (press: $0.0, wait: $0.1) }
        self.tail = tail
        self.expects = expects
        self.forbids = forbids
        self.allowSkips = allowSkips
        self.allowGiveUp = allowGiveUp
        self.floor = floor
    }

    /// How many crates of a repository stand in a yard row right now, by the name the scene gives them.
    @MainActor static func crates(_ sim: SimulatorController, _ area: String, _ repo: String) -> Int {
        sim.station.markerRoot.childNodes.filter { ($0.name ?? "").hasPrefix("\(area):work|\(repo)|") }.count
    }

    /// Every command the run issued, with who ran it, oldest first.
    @MainActor static func commands(_ sim: SimulatorController) -> [(command: Command, by: String)] {
        sim.model.records.compactMap { if case .command(let c, let who) = $0 { return (c, who) }; return nil }
    }

    /// How many times the run recorded something.
    @MainActor static func count(_ sim: SimulatorController, _ e: Expect) -> Int {
        sim.model.records.filter(e.matches).count
    }
}

enum Scenarios {
    /// Every scenario, in the order they run. The first press of each is the target, so a scenario
    /// never depends on what the picker happened to be left on.
    @MainActor static let all: [Scenario] = [
        Scenario("own PR opens, merges, crate reaches storage", [
            ("Target: ios#298", 4.8),
            ("Open PR", 32),
            ("Merge PR", 4.8),
        ], tail: 192, expects: [
            .log("PR #298 open"),
            .officeMerged("task:ios#298"),
            .carry(298, to: .storage),
        ], floor: { sim in
            Scenario.crates(sim, "storage", "ios") > 0 ? nil : "no ios crate stands in storage"
        }),

        Scenario("teammate branch then PR: one shuttle, one crate", [
            ("Target: api#5158", 4.8),
            ("Teammate: New branch", 48),
            ("Teammate: Open PR", 4.8),
        ], tail: 192, expects: [
            .officeOpened("task:api#", .shuttle, board: "leo"),
            .crewActivity("leo", "branch_create"),
            .flight,
            .deliverOffice(by: "leo"),
            .crewActivity("leo", "pr_open"),
        ], floor: { sim in
            let flights = Scenario.count(sim, .flight)
            return flights == 1 ? nil : "\(flights) shuttles flew, not one"
        }),

        Scenario("a late carrier: the crate waits on the bay floor and is still fetched", [
            ("Target: api#5158", 4.8),
            ("Teammate: New branch", 40),
            ("Peer: New office", 40),        // the floor plan changes while the crate is coming down
            ("New branch in repo", 4.8),      // and again, with a second delivery under way
        ], tail: 480, expects: [
            .deliverOffice(by: "leo"),
        ], floor: { sim in
            let fetching = sim.station.minions.values.filter { if case .deliverOffice = $0.current?.kind { return true }; return false }
            if !fetching.isEmpty { return "\(fetching.map(\.home.name).joined(separator: ", ")) still fetching from the bay" }
            let left = sim.station.world.truth.deliveries.values.map(\.key)
            return left.isEmpty ? nil : "crates left on the bay floor: \(left.sorted().joined(separator: ", "))"
        }),

        Scenario("staging release opens, merges: the pallet crosses", [
            ("Target: web#455", 4.8),
            ("Release: Staging opens", 80),
            ("Release: Staging merges", 4.8),
        ], tail: 160, expects: [
            .stagingOpened("web"),
            .dispatch("web"),
            .loadPallet("web"),
            .waitPallet("web"),
            .stagingMerged("web"),
            .pushPallet("web"),
            .unloadPallet("web", back: false),
        ], floor: { sim in
            Scenario.crates(sim, "deck", "web") > 0 ? nil : "nothing of web stands on the deck"
        }),

        Scenario("staging release closes: the pallet unloads back", [
            ("Target: web#455", 4.8),
            ("Release: Staging opens", 80),
            ("Release: Staging closes", 4.8),
        ], tail: 160, expects: [
            .stagingOpened("web"),
            .loadPallet("web"),
            .stagingClosed("web"),
            .unloadPallet("web", back: true),
        ], floor: { sim in
            // One web crate stood on the deck from the start; nothing new may have joined it.
            let deck = Scenario.crates(sim, "deck", "web")
            if deck > 1 { return "\(deck) web crates on the deck after a release that never merged" }
            let storage = Scenario.crates(sim, "storage", "web")
            return storage >= 2 ? nil : "only \(storage) web crates back in storage"
        }),

        Scenario("a repository whose merges deploy: the merged crate goes straight up in a rocket of its own", [
            ("Target: ios#298", 4.8),
            ("Repo: Ships on merge", 4.8),
            ("Open PR", 32),
            ("Merge PR", 4.8),
        ], tail: 720, expects: [
            .officeMerged("task:ios#298"),
            .carry(298, to: .storage),
            .rocket(.launch, "ios"),
            .carry(298, to: .pad),
        ], floor: { sim in
            let row = sim.station.world.fleet.stations["work"]?.ledger["ios", 298]
            return row?.placed == nil ? nil : "#298 is still placed in \(String(describing: row?.placed)) after the launch"
        }),

        Scenario("a repository without staging: merged work waits in storage and the rocket loads from there", [
            ("Target: ios#298", 4.8),
            ("Repo: No staging", 4.8),
            ("Open PR", 32),
            ("Merge PR", 128),                   // the package is carried to storage
            ("Release: Production opens", 48),  // release/v… into master
            ("Release: Mark tested", 128),       // cleared: the rocket loads, from storage
            ("Release: Production merges", 4.8),
        ], tail: 224, expects: [
            .rocket(.standBy, "ios"),           // work is waiting on the board already: the rocket stands before any release
            .officeMerged("task:ios#298"),
            .carry(298, to: .storage),
            .carry(to: .pad),
            .releaseMerged("ios", production: true),
            .rocket(.launch, "ios"),
        ], floor: { sim in
            let stored = Scenario.crates(sim, "storage", "ios")
            return stored == 0 ? nil : "\(stored) ios crates left in storage after lift-off"
        }),

        // The station half alone: no merge on GitHub, no board item moved. A repository without a
        // staging area, so the crate goes from storage straight aboard; the deck's shared cell has a
        // geometry bug of its own (two repositories' columns half a tile apart) that a QA carry walks into.
        Scenario("the stage panel alone: said stored, cleared and shipped, the crate goes from storage up", [
            ("Target: ios#298", 4.8),
            ("Repo: No staging", 4.8),
            ("Open PR", 32),
            ("Stage: stored", 128),      // the record's word hauls the crate
            ("Stage: cleared", 96),      // the rocket loads it, from storage
            ("Stage: shipped", 4.8),     // and goes, with that crate and no other
        ], tail: 224, expects: [
            .officeMerged("task:ios#298"),
            .carry(298, to: .storage),
            .rocket(.launch, "ios"),
            .carry(298, to: .pad),
        ], floor: { sim in
            // ios#280 was on the board in QA, never said shipped: it stays behind.
            let stored = Scenario.crates(sim, "storage", "ios")
            return stored == 1 ? nil : "\(stored) ios crates left in storage; #280 alone should be"
        }),

        Scenario("production release: mark tested, merge, the rocket lifts", [
            ("Target: web#455", 4.8),
            ("Release: Production opens", 48),
            ("Release: Mark tested", 96),
            ("Release: Production merges", 4.8),
        ], tail: 192, expects: [
            .rocket(.standBy, "web"),           // a crate on the deck: the rocket stands before the release is opened
            .releaseOpened("web", untested: true),
            .rocket(.load(1), "web"),
            .crateCleared("web"),
            .carry(to: .pad),
            .rocket(.steam, "web"),
            .releaseMerged("web", production: true),
            .rocket(.launch, "web"),
        ], floor: { sim in
            // One crate of web was on the deck; it goes aboard once. A board still saying "ready to ship"
            // after the crate is in the hold must not put it back on the deck to be carried again.
            let loads = Scenario.count(sim, .carry(to: .pad))
            if loads != 1 { return "\(loads) carries into the rocket for one crate" }
            let deck = Scenario.crates(sim, "deck", "web")
            return deck == 0 ? nil : "\(deck) web crates on the deck after lift-off"
        }),

        Scenario("PR closed unmerged: red, nothing carried", [
            ("Target: web#455", 4.8),
            ("Open PR", 32),
            ("Close PR", 4.8),
        ], tail: 144, expects: [
            .log("PR #455 open"),
            .log("#455 booking flow: pull request closed, not merged"),
        ], forbids: [
            .carry(455, to: .storage),
        ]),

        Scenario("a bot's pull request: an object in decon, merged, cleared into storage", [
            ("Target: ios#298", 4.8),
            ("Bot: Open PR", 32),
            ("Bot: Merge PR", 4.8),
        ], tail: 192, expects: [
            .event("deconArrived") { if case .deconArrived = $0 { return true }; return false },
            .log("in decon"),
            .deconCleared("ios"),
            .carry(to: .storage),
        ], forbids: [
            .officeOpened("task:ios#", .shuttle),   // nothing from decon gets an office or a shuttle
        ], floor: { sim in
            let st = sim.station.world.fleet.stations["work"]!
            if Scenario.crates(sim, "decon", "ios") > 0 { return "an object is still in decon" }
            guard let row = st.ledger.crates(of: "ios").first(where: \.alien) else { return "the cleared object left the ledger" }
            if row.placed != .storage || row.heading != nil { return "the object is \(String(describing: row.placed)), not in storage" }
            return Scenario.crates(sim, "storage", "ios") > 0 ? nil : "no ios crate stands in storage"
        }),

        Scenario("a bot's pull request closed unmerged: ejected from decon, nothing carried", [
            ("Target: web#455", 4.8),
            ("Bot: Open PR", 32),
            ("Bot: Close PR", 4.8),
        ], tail: 64, expects: [
            .log("in decon"),
            .log("ejected from decon, never cleared"),
        ], forbids: [
            .carry(to: .storage),
            .deconCleared("web"),
        ], floor: { sim in
            let st = sim.station.world.fleet.stations["work"]!
            if Scenario.crates(sim, "decon", "web") > 0 { return "an object is still in decon" }
            return st.ledger.crates(of: "web").contains(where: \.alien) ? "the ejected object is still in the ledger" : nil
        }),

        Scenario("peer arrives and leaves: fade in, office held", [
            ("Peer: Leave", 64),
            ("Peer: Arrive", 96),
            ("Peer: Leave", 4.8),
        ], tail: 96, expects: [
            .officeOpened("task:web#460", .fade, peer: "kim"),
            .peerLeft("kim"),
            .peerArrived("kim"),
            .peerLeft("kim"),
        ], floor: { sim in
            // Offices are held for those who left before they clear.
            sim.station.world.fleet.stations["work"]?.rooms["task:web#460"] != nil
                ? nil : "kim's office cleared the moment she left"
        }),

        Scenario("peer office kicked", [
            ("Target: web#460", 4.8),
            ("Peer: Kick office", 4.8),
        ], tail: 128, expects: [
            .officeArchived("work|task:web#460", reason: "kicked"),
            .log("kicked #460 artist tags off the station"),
        ]),

        Scenario("session ends: the office stays", [
            ("Target: api#5158", 4.8),
            ("Session ends", 4.8),
        ], tail: 160, expects: [
            .press("Session ends"),
        ], floor: { sim in
            // Nothing disappears without a cue: an office outlives the session that opened it.
            sim.station.world.fleet.stations["work"]?.rooms["task:api#5158"] != nil
                ? nil : "the office went with the session"
        }),

        Scenario("night falls, then morning", [
            ("Night", 96),
            ("Day", 4.8),
        ], tail: 128, expects: [
            .press("Night"),
            .sleep,
            .log("night falls"),
            .press("Day"),
            .goTo(.lounge),
            .log("morning"),
        ]),

        Scenario("a wedged carrier gives up: the crate goes back in the queue and another is sent for it", [
            ("Target: ios#298", 4.8),
            ("Open PR", 32),
            ("Merge PR", 9.6),        // the package is ordered to storage and a carrier takes it
            ("Wedge carrier", 4.8),   // and stops dead on the way
        ], tail: 448, expects: [       // ten station seconds standing, then the give-up, then the retry
            .officeMerged("task:ios#298"),
            .carry(298, to: .storage),
            .press("Wedge carrier"),
            .log("gives up carrying #298"),
            .carry(298, to: .storage),
        ], allowGiveUp: true, floor: { sim in
            // The retry went to somebody else: a frozen body is not sent for the crate it dropped while
            // there is anyone else. Whether the crate lands is the walk's business, not this rule's.
            var carriers: [String] = []
            for r in sim.model.records {
                if case .command(let c, let by) = r, case .carry(let crate, _, _) = c.kind, crate.number == 298, !carriers.contains(by) { carriers.append(by) }
            }
            return carriers.count >= 2 ? nil : "only \(carriers) carried #298"
        }),
    ]
}

/// Runs the suite in one tight loop: station time stepped a thirtieth of a second at a time, the
/// presses timed on it, and each scenario judged when its time is up.
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
        while sim != nil { frame() }
        finish()
    }

    // MARK: the run

    /// Station seconds so far in this scenario; presses and the judgement are timed on it.
    private var simTime = 0.0

    private func begin() {
        index += 1
        guard index < scenarios.count else { return finish() }
        // A station and an org of its own, so nothing carries over from the scenario before.
        sim = SimulatorController(frame: NSRect(x: 0, y: 0, width: 1060, height: 700))
        sim?.station.headless = true
        step = 0
        simTime = 0
        startedAt = CACurrentMediaTime()
        // Sixteen station seconds for the seed to settle before the first press.
        nextPressAt = ScenarioRunner.settle
        endAt = .greatestFiniteMagnitude
    }

    /// Station seconds before a scenario's first press.
    static let settle = 16.0

    private func frame() {
        guard let sim else { return }
        sim.station.stepSimulated(seconds: 1.0 / 30)
        simTime += 1.0 / 30
        let s = scenarios[index]
        if step < s.steps.count, simTime >= nextPressAt {
            let it = s.steps[step]
            sim.model.press(it.press)
            step += 1
            nextPressAt = simTime + it.wait
            if step == s.steps.count { endAt = simTime + s.tail }
        }
        if simTime >= endAt { judge() }
    }

    private func judge() {
        guard let sim else { return }
        let s = scenarios[index]
        let records = sim.model.records
        let seconds = CACurrentMediaTime() - startedAt
        if verbose {
            say("--- \(s.name) ---")
            for l in sim.model.logLines { say("    " + l) }
            if let st = sim.station.world.fleet.stations["work"] {
                for c in st.ledger.allCrates.sorted(by: { ($0.repo, $0.number) < ($1.repo, $1.number) }) {
                    say("    crate  \(c.repo)#\(c.number): placed \(String(describing: c.placed)) wanted \(String(describing: c.wanted)) heading \(String(describing: c.heading)) at \(String(describing: c.at))")
                }
            }
            for r in sim.station.simulation.rockets.values {
                say("    rocket  \(r.key): \(r.stage) phase \(r.phaseKind) · assigned \(r.assigned.count), pending \(r.pending.count), aboard \(sim.station.world.aboard(station: r.station, repo: r.repo))")
            }
            // Every body at the end, for the failures the records do not explain.
            for m in sim.station.minions.values.sorted(by: { $0.home.name < $1.home.name }) {
                let spot = m.fetchSpot.map { " fetchSpot \(Int($0.x.rounded())),\(Int($0.y.rounded()))" } ?? ""
                say("    body  \(m.home.name): \(m.current?.words ?? "nothing") · \(m.phaseKind) at \(m.cell.x),\(m.cell.y) pos \(String(format: "%.2f,%.2f", m.pos.x, m.pos.y)) path \(m.path.count)\(spot)\(m.waitingOn.map { " waiting on \($0)" } ?? "")\(m.hasLoad ? " carrying" : "")")
            }
        }
        var reason: String?
        let violations = records.compactMap { if case .violation(let t) = $0 { return t }; return nil }
        if let v = violations.first { reason = v }
        if reason == nil, !s.allowGiveUp, let gaveUp = records.lazy.compactMap({ r -> String? in
            if case .event(.log(let t)) = r, t.contains(" gives up ") { return t }; return nil }).first {
            reason = "a minion gave up · " + gaveUp
        }
        if reason == nil, !s.allowSkips, let skipped = records.lazy.compactMap({ if case .skipped(let why) = $0 { return why }; return nil }).first {
            reason = "a press was refused · " + skipped
        }
        if reason == nil {
            for bad in s.forbids {
                if let hit = records.first(where: bad.matches) { reason = "saw \(bad.words) · \(hit.words)"; break }
            }
        }
        if reason == nil {
            var at = 0
            for want in s.expects {
                var hit = false
                while at < records.count {
                    let r = records[at]
                    at += 1
                    if want.matches(r) { hit = true; break }
                }
                if !hit { reason = "never saw \(want.words)"; break }
            }
        }
        if reason == nil, let floor = s.floor { reason = floor(sim) }
        if let reason {
            failed += 1
            say(String(format: "FAIL  %-52@  %@  (%.1fs)", s.name as NSString, reason as NSString, seconds))
        } else {
            say(String(format: "PASS  %-52@  (%.1fs)", s.name as NSString, seconds))
        }
        // Every violation of the run, not only the first, so one pass says everything it found.
        for v in violations.dropFirst() { say("      " + v) }
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
