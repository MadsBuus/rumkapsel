// A scripted regression suite: `.build/debug/Rumkapsel --scenarios`.
//
// Each scenario is a name, a list of simulator buttons with a pause after each, and what the run
// must have recorded when it is over: presses, events, commands and who ran them, as the values
// they were. Nothing here reads the log's prose. Every scenario gets its own station and its own
// made-up org, runs headless at sixteen times speed off the same frame heartbeat `--snapshot` uses,
// and passes only if every expectation was met, in order, nothing forbidden was recorded, the floor
// check agrees, and the invariant checker found nothing.
//
//     --scenarios              every scenario
//     --scenarios pallet       only the ones whose name contains "pallet"
//     --scenarios-verbose      print each scenario's whole log
//
// Exits non-zero if anything failed. Waits are in real seconds; one is about sixteen simulated.

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
    static let chore = command("chore") { if case .chore = $0 { return true }; return false }
    static func goTo(_ place: Place) -> Expect {
        command("goTo \(place.words)") { if case .goTo(let p) = $0 { return p == place }; return false }
    }
}

struct Scenario {
    let name: String
    /// A button and the real seconds to wait after pressing it.
    let steps: [(press: String, wait: Double)]
    /// Real seconds to keep the station running after the last press.
    let tail: Double
    /// What must have been recorded, in this order.
    let expects: [Expect]
    /// What must not have been recorded at all.
    let forbids: [Expect]
    /// A press the panel refuses is normally a broken script; a few scenarios mean to try one.
    var allowSkips = false
    /// What must stand on the floor when it is over, for the things the run does not record as it
    /// goes. Returns the reason it failed, or nil.
    let floor: (@MainActor (SimulatorController) -> String?)?

    init(_ name: String, _ steps: [(String, Double)], tail: Double, expects: [Expect], forbids: [Expect] = [],
         allowSkips: Bool = false, floor: (@MainActor (SimulatorController) -> String?)? = nil) {
        self.name = name
        self.steps = steps.map { (press: $0.0, wait: $0.1) }
        self.tail = tail
        self.expects = expects
        self.forbids = forbids
        self.allowSkips = allowSkips
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
            ("Target: ios#298", 0.3),
            ("Open PR", 2.0),
            ("Merge PR", 0.3),
        ], tail: 12, expects: [
            .log("PR #298 open"),
            .officeMerged("task:ios#298"),
            .carry(298, to: .storage),
        ], floor: { sim in
            Scenario.crates(sim, "storage", "ios") > 0 ? nil : "no ios crate stands in storage"
        }),

        Scenario("teammate branch then PR: one shuttle, one crate", [
            ("Target: api#5158", 0.3),
            ("Teammate: New branch", 3.0),
            ("Teammate: Open PR", 0.3),
        ], tail: 12, expects: [
            .officeOpened("task:api#", .shuttle, board: "leo"),
            .crewActivity("leo", "branch_create"),
            .flight,
            .deliverOffice(by: "leo"),
            .crewActivity("leo", "pr_open"),
        ], floor: { sim in
            let flights = Scenario.count(sim, .flight)
            return flights == 1 ? nil : "\(flights) shuttles flew, not one"
        }),

        Scenario("staging release opens, merges: the pallet crosses", [
            ("Target: web#455", 0.3),
            ("Release: Staging opens", 5.0),
            ("Release: Staging merges", 0.3),
        ], tail: 10, expects: [
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
            ("Target: web#455", 0.3),
            ("Release: Staging opens", 5.0),
            ("Release: Staging closes", 0.3),
        ], tail: 10, expects: [
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

        Scenario("production release: mark tested, merge, the rocket lifts", [
            ("Target: web#455", 0.3),
            ("Release: Production opens", 3.0),
            ("Release: Mark tested", 6.0),
            ("Release: Production merges", 0.3),
        ], tail: 12, expects: [
            .releaseOpened("web", untested: true),
            .rocket(.standBy, "web"),
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

        Scenario("staging merges before the board: the deck keeps the pallet's crates", [
            ("Target: web#455", 0.3),
            ("Release: Staging opens", 5.0),
            ("Release: Staging merges (board lags)", 10.0),   // the pallet crosses and empties while the board still says storage
            ("Commit", 1.0),                                  // any redraw meanwhile: the source must not take them back
            ("Board: Catch up", 0.3),                         // the board's poll arrives: nothing left to carry
        ], tail: 6, expects: [
            .stagingOpened("web"),
            .stagingMerged("web"),
            .pushPallet("web"),
            .unloadPallet("web", back: false),
            .boardMoved("web", to: .deck),
        ], forbids: [
            .carry(to: .deck),   // the pallet did the carrying; nothing redoes it by hand
        ], floor: { sim in
            // Two web crates rode the pallet over to join the one already there, each drawn by its own number.
            let deck = Scenario.crates(sim, "deck", "web")
            if deck != 3 { return "\(deck) web crates on the deck, not 3" }
            let nameless = sim.station.markerRoot.childNodes.filter { ($0.name ?? "").hasPrefix("deck:work|web|0") }.count
            if nameless > 0 { return "\(nameless) web crates on the deck without a number" }
            let storage = Scenario.crates(sim, "storage", "web")
            if storage > 0 { return "\(storage) web crates back in storage" }
            // The board has caught up: the ledger's two sides agree on every crate of web.
            let open = sim.station.world.fleet.stations["work"]!.ledger.disagreements(repo: "web")
            return open.isEmpty ? nil : "the ledger still disagrees about \(open.map { "#\($0.number)" }.joined(separator: ", "))"
        }),

        Scenario("teammate PR closed unmerged, feed behind: red, nothing carried, no crate", [
            ("Target: api#5158", 0.3),
            ("Teammate: New branch", 3.0),
            ("Teammate: Open PR", 1.0),
            ("Teammate: Close PR (feed lags)", 0.5),   // gone from the open list, no close in the feed
            ("Board: Move api#5161 to Backlog", 0.3),  // and off the board's development column: now the office must decide
        ], tail: 8, expects: [
            .crewActivity("leo", "pr_open"),
            .log("pull request closed, not merged"),
        ], forbids: [
            .carry(to: .storage),
        ], floor: { sim in
            // Never merged work: nothing of it in storage, on the floor or in the ledger.
            let st = sim.station.world.fleet.stations["work"]!
            if let stray = st.ledger.crates(of: "api").first(where: { $0.placed == .storage && $0.number > 5160 }) { return "#\(stray.number) is in the ledger's storage" }
            return nil
        }),

        Scenario("PR closed unmerged: red, nothing carried", [
            ("Target: web#455", 0.3),
            ("Open PR", 2.0),
            ("Close PR", 0.3),
        ], tail: 9, expects: [
            .log("PR #455 open"),
            .log("#455 booking flow: pull request closed, not merged"),
        ], forbids: [
            .carry(455, to: .storage),
        ]),

        Scenario("peer arrives and leaves: fade in, office held", [
            ("Peer: Leave", 4.0),
            ("Peer: Arrive", 6.0),
            ("Peer: Leave", 0.3),
        ], tail: 6, expects: [
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
            ("Target: web#460", 0.3),
            ("Peer: Kick office", 0.3),
        ], tail: 8, expects: [
            .officeArchived("work|task:web#460", reason: "kicked"),
            .log("kicked #460 artist tags off the station"),
        ]),

        Scenario("session ends: the office stays", [
            ("Target: api#5158", 0.3),
            ("Session ends", 0.3),
        ], tail: 10, expects: [
            .press("Session ends"),
        ], floor: { sim in
            // Nothing disappears without a cue: an office outlives the session that opened it.
            sim.station.world.fleet.stations["work"]?.rooms["task:api#5158"] != nil
                ? nil : "the office went with the session"
        }),

        Scenario("night falls, then morning", [
            ("Night", 6.0),
            ("Day", 0.3),
        ], tail: 8, expects: [
            .press("Night"),
            .sleep,
            .log("night falls"),
            .press("Day"),
            .goTo(.lounge),
            .log("morning"),
        ]),

        Scenario("a bath lasts its whole time", [
            ("Everyone to lounge", 3.0),
            ("Bath", 0.3),
        ], tail: 14, expects: [
            .bath,
        ]),

        Scenario("pallet operator stays on the errand through the night", [
            ("Target: web#455", 0.5),
            ("Release: Staging opens", 6.0),   // whoever is nearest the console takes the errand
            ("Night", 6.0),                    // bedtime does not take it off the pallet
            ("Release: Staging merges", 0.5),
        ], tail: 30, expects: [
            .pushPallet("web"),
            .unloadPallet("web", back: false),
        ], floor: { sim in
            // One pair of hands from the clipboard to the last crate off: nobody took the pallet over.
            var operators: [String] = []
            for (c, who) in Scenario.commands(sim) {
                switch c.kind {
                case .dispatch, .loadPallet, .waitPallet, .pushPallet, .unloadPallet: if !operators.contains(who) { operators.append(who) }
                default: break
                }
            }
            return operators.count == 1 ? nil : "the pallet passed through \(operators.count) pairs of hands: \(operators.joined(separator: ", "))"
        }),
        Scenario("a commit lands: the worker stows a cube", [
            ("Target: web#455", 0.5),
            ("Commit", 0.5),
        ], tail: 8, expects: [
            .stow(by: "#455 booking flow"),
        ]),
        Scenario("a stacked deck goes aboard: the carrier hurries", [
            ("Target: web#455", 0.3),
            ("Release: Staging opens", 5.0),
            ("Release: Staging merges (board lags)", 10.0),   // three web crates on the deck, one column
            ("Board: Catch up", 0.5),
            ("Release: Production opens", 3.0),
            ("Release: Mark tested", 6.0),                    // the rocket loads all three: a chain, top down
            ("Release: Production merges", 0.3),
        ], tail: 10, expects: [
            .rocket(.load(3), "web"),
            .carry(to: .pad),
            .log("more waiting"),   // the carrier with carries queued behind it says so
            .rocket(.launch, "web"),
        ], floor: { sim in
            let loads = Scenario.count(sim, .carry(to: .pad))
            if loads != 3 { return "\(loads) carries into the rocket for three crates" }
            let deck = Scenario.crates(sim, "deck", "web")
            return deck == 0 ? nil : "\(deck) web crates on the deck after lift-off"
        }),
        Scenario("a wedged carrier: the station catches up", [
            ("Target: ios#298", 0.3),
            ("Open PR", 2.0),
            ("Merge PR", 0.6),        // the package is ordered to storage and a carrier takes it
            ("Wedge carrier", 0.3),   // and stops dead on the way
        ], tail: 9, expects: [        // the carry's patience is ninety station seconds: under six real
            .officeMerged("task:ios#298"),
            .carry(298, to: .storage),
            .press("Wedge carrier"),
            .log("set down late"),
        ], floor: { sim in
            // Truth before the picture: the crate is in storage and the ledger says so, carrier or no carrier.
            guard Scenario.crates(sim, "storage", "ios") > 0 else { return "no ios crate stands in storage" }
            let row = sim.station.world.fleet.stations["work"]!.ledger["ios", 298]
            return row?.placed == .storage && row?.heading == nil ? nil : "the ledger does not have #298 down in storage"
        }),
        Scenario("a chore", [
            ("Everyone to lounge", 3.0),
            ("Chore", 0.3),
        ], tail: 12, expects: [
            .chore,
        ]),
    ]
}

/// Runs the suite off one heartbeat: a frame asked for thirty times a second, the presses timed
/// against the wall clock, and each scenario judged when its time is up.
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
        step = 0
        simTime = 0
        startedAt = CACurrentMediaTime()
        // A beat for the seed to settle before the first press; waits are the old wall seconds at 16x.
        nextPressAt = 16.0
        endAt = .greatestFiniteMagnitude
    }

    private func frame() {
        guard let sim else { return }
        sim.station.stepSimulated(seconds: 1.0 / 30)
        simTime += 1.0 / 30
        let s = scenarios[index]
        if step < s.steps.count, simTime >= nextPressAt {
            let it = s.steps[step]
            sim.model.press(it.press)
            step += 1
            nextPressAt = simTime + it.wait * 16
            if step == s.steps.count { endAt = simTime + s.tail * 16 }
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
        }
        var reason: String?
        let violations = records.compactMap { if case .violation(let t) = $0 { return t }; return nil }
        if let v = violations.first { reason = v }
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
