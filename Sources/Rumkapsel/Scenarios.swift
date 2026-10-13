import AppKit
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
    let steps: [(press: String, wait: Double)]
    let tail: Double
    let expects: [Expect]
    let forbids: [Expect]
    var allowSkips = false
    var allowGiveUp = false
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

    @MainActor static func crates(_ sim: SimulatorController, _ area: String, _ repo: String) -> Int {
        sim.station.markerRoot.childNodes.filter { ($0.name ?? "").hasPrefix("\(area):work|\(repo)|") }.count
    }

    @MainActor static func commands(_ sim: SimulatorController) -> [(command: Command, by: String)] {
        sim.model.records.compactMap { if case .command(let c, let who) = $0 { return (c, who) }; return nil }
    }

    @MainActor static func count(_ sim: SimulatorController, _ e: Expect, after press: String? = nil) -> Int {
        let records = sim.model.records
        let from = press.flatMap { p in records.firstIndex { if case .press(let n) = $0 { return n == p }; return false } } ?? 0
        return records[from...].filter(e.matches).count
    }
}

enum Scenarios {
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

        Scenario("a branch with no issue: opened, merged and prompted again, still one office", [
            ("Target: ios#298", 4.8),
            ("New branch, no issue", 48),
            ("Open PR", 32),
            ("Merge PR", 4.8),
            ("Prompt", 4.8),
        ], tail: 192, expects: [
            .carry(to: .storage),
        ], floor: { sim in
            let reopened = Scenario.count(sim, .officeOpened("task:ios/claude/", .appear), after: "Merge PR")
                + Scenario.count(sim, .officeOpened("task:ios/claude/", .shuttle), after: "Merge PR")
            if reopened > 0 { return "an office opened for the branch after the merge" }
            let rooms = sim.station.world.fleet.stations["work"]?.rooms.values.filter { $0.branch?.hasPrefix("claude/new-work-") == true } ?? []
            return rooms.count == 1 && rooms[0].key.hasPrefix("task:ios#") ? nil : "offices for the branch: \(rooms.map(\.key).sorted())"
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
            ("Peer: New office", 40),
            ("New branch in repo", 4.8),
        ], tail: 480, expects: [
            .deliverOffice(by: "leo"),
        ], floor: { sim in
            let fetching = sim.station.minions.values.filter { if case .deliverOffice = $0.current?.kind { return true }; return false }
            if !fetching.isEmpty { return "\(fetching.map(\.home.name).joined(separator: ", ")) still fetching from the bay" }
            let left = sim.station.world.truth.deliveries.values.map(\.key)
            return left.isEmpty ? nil : "crates left on the bay floor: \(left.sorted().joined(separator: ", "))"
        }),

        Scenario("staging release opens, merges: the crates are carried to the staged rows", [
            ("Target: web#455", 4.8),
            ("Release: Staging opens", 80),
            ("Release: Staging merges", 4.8),
        ], tail: 160, expects: [
            .stagingOpened("web"),
            .stagingMerged("web"),
            .carry(to: .deck),
        ], floor: { sim in
            Scenario.crates(sim, "deck", "web") > 0 ? nil : "nothing of web stands on the deck"
        }),

        Scenario("the board moves storage to QA and the yard sees it first: the crates are still carried", [
            ("Target: web#455", 4.8),
            ("Board: Catch up (yard first)", 4.8),
        ], tail: 160, expects: [
            .carry(to: .deck),
        ], floor: { sim in
            Scenario.crates(sim, "deck", "web") > 0 ? nil : "nothing of web stands on the deck"
        }),

        Scenario("staging release closes: the crates stay in storage", [
            ("Target: web#455", 4.8),
            ("Release: Staging opens", 80),
            ("Release: Staging closes", 4.8),
        ], tail: 160, expects: [
            .stagingOpened("web"),
            .stagingClosed("web"),
        ], floor: { sim in
            let deck = Scenario.crates(sim, "deck", "web")
            if deck > 2 { return "\(deck) web crates on the deck after a release that never merged" }
            let storage = Scenario.crates(sim, "storage", "web")
            return storage >= 2 ? nil : "only \(storage) web crates in storage"
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
        ], floor: { sim in
            let row = sim.station.world.fleet.stations["work"]?.ledger["ios", 298]
            return row?.placed == nil ? nil : "#298 is still placed in \(String(describing: row?.placed)) after the launch"
        }),

        Scenario("a repository without staging: merged work waits in storage and the rocket loads from there", [
            ("Target: ios#298", 4.8),
            ("Repo: No staging", 4.8),
            ("Open PR", 32),
            ("Merge PR", 128),
            ("Release: Production opens", 48),
            ("Release: Mark tested", 128),
            ("Release: Production merges", 4.8),
        ], tail: 224, expects: [
            .rocket(.standBy, "ios"),
            .officeMerged("task:ios#298"),
            .carry(298, to: .storage),
            .releaseMerged("ios", production: true),
            .rocket(.launch, "ios"),
        ], floor: { sim in
            let stored = Scenario.crates(sim, "storage", "ios")
            return stored == 0 ? nil : "\(stored) ios crates left in storage after lift-off"
        }),

        Scenario("a repository that ships on tags: merged work waits in storage with no rocket, and the tag sends it up", [
            ("Target: ios#298", 4.8),
            ("Repo: Ships on tags", 4.8),
            ("Open PR", 32),
            ("Merge PR", 128),
            ("Release: Tag", 4.8),
        ], tail: 224, expects: [
            .officeMerged("task:ios#298"),
            .carry(298, to: .storage),
            .rocket(.launch, "ios"),
        ], floor: { sim in
            let standing = Scenario.count(sim, .rocket(.standBy, "ios"), after: "Repo: Ships on tags")
                + Scenario.count(sim, .rocket(.load(0), "ios"), after: "Repo: Ships on tags")
                - Scenario.count(sim, .rocket(.load(0), "ios"), after: "Release: Tag")
            if standing > 0 { return "a rocket stood or loaded for ios's work \(standing) times before any tag" }
            let stored = Scenario.crates(sim, "storage", "ios")
            return stored == 0 ? nil : "\(stored) ios crates left in storage after the tag"
        }),

        Scenario("a repository that ships on tags, said shipped with no tag seen: nothing goes up, the crate just goes", [
            ("Target: ios#298", 4.8),
            ("Repo: Ships on tags", 4.8),
            ("Open PR", 32),
            ("Stage: stored", 128),
            ("Stage: shipped", 4.8),
        ], tail: 64, expects: [
            .carry(298, to: .storage),
        ], forbids: [
            .rocket(.launch, "ios"),
        ], floor: { sim in
            let standing = Scenario.count(sim, .rocket(.standBy, "ios"), after: "Repo: Ships on tags")
                + Scenario.count(sim, .rocket(.load(0), "ios"), after: "Repo: Ships on tags")
            if standing > 0 { return "a rocket stood or loaded for ios's work \(standing) times" }
            let row = sim.station.world.fleet.stations["work"]?.ledger["ios", 298]
            return row?.stands(in: .storage) == true ? "#298 still stands in storage after it shipped" : nil
        }),

        Scenario("the stage panel alone: said stored, cleared and shipped, the crate goes from storage up", [
            ("Target: ios#298", 4.8),
            ("Repo: No staging", 4.8),
            ("Open PR", 32),
            ("Stage: stored", 128),
            ("Stage: cleared", 96),
            ("Stage: shipped", 4.8),
        ], tail: 224, expects: [
            .officeMerged("task:ios#298"),
            .carry(298, to: .storage),
            .rocket(.launch, "ios"),
        ], floor: { sim in
            let stored = Scenario.crates(sim, "storage", "ios")
            return stored == 1 ? nil : "\(stored) ios crates left in storage; #280 alone should be"
        }),

        Scenario("the stage panel with a staging area: to the deck beside another repository's crate, across it, and up", [
            ("Target: ios#298", 4.8),
            ("Open PR", 32),
            ("Stage: stored", 128),
            ("Stage: QA", 128),
            ("Stage: cleared", 96),
            ("Stage: shipped", 4.8),
        ], tail: 224, expects: [
            .officeMerged("task:ios#298"),
            .carry(298, to: .storage),
            .carry(298, to: .deck),
            .crateCleared("ios"),
            .rocket(.launch, "ios"),
        ], floor: { sim in
            let deck = Scenario.crates(sim, "deck", "ios")
            return deck == 1 ? nil : "\(deck) ios crates left on the deck; #280 alone should be"
        }),

        Scenario("production release: mark tested, merge, the rocket lifts", [
            ("Target: web#455", 4.8),
            ("Release: Production opens", 48),
            ("Release: Mark tested", 96),
            ("Release: Production merges", 4.8),
        ], tail: 192, expects: [
            .rocket(.standBy, "web"),
            .releaseOpened("web", untested: true),
            .crateCleared("web"),
            .rocket(.load(2), "web"),
            .rocket(.steam, "web"),
            .releaseMerged("web", production: true),
            .rocket(.launch, "web"),
        ], floor: { sim in
            let deck = Scenario.crates(sim, "deck", "web")
            return deck == 0 ? nil : "\(deck) web crates on the deck after lift-off"
        }),

        Scenario("ready to ship moved back to QA: nothing carried, the crate stands untested", [
            ("Target: web#455", 4.8),
            ("Board: Move web#431 to \(ConfigStore.shared.current.statuses.deck)", 32),
        ], tail: 16, expects: [
            .press("Board: Move web#431 to \(ConfigStore.shared.current.statuses.deck)"),
        ], floor: { sim in
            let carried = Scenario.commands(sim).contains {
                if case .carry(let crate, let from, _) = $0.command.kind { return crate.number == 431 && from.area == .tested }; return false
            }
            if carried { return "#431 was carried off its stack" }
            guard let station = sim.station.fleet.stations.values.first,
                  let slot = station.layout(of: .deck).first(where: { $0.repo == "web" && $0.number == 431 }) else {
                return "#431 is not on the deck"
            }
            if slot.cleared { return "#431 still stands with the tested" }
            guard let node = sim.station.crateNode(CrateRef(station: station.name, repo: "web", number: 431)) else { return "#431 is not drawn" }
            let off = simd_distance(SIMD2(Double(node.position.x), Double(node.position.z)), SIMD2(slot.pos.x, slot.pos.z))
            return off < 0.05 ? nil : "#431 is drawn \(off) from its place in the untested row"
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

        Scenario("a teammate's pull request closed unmerged: red, then the office clears", [
            ("Target: api#5140", 4.8),
            ("Teammate: Close PR", 200),
            ("Scan: again", 200),
            ("Scan: again", 200),
            ("Scan: again", 120),
            ("GitHub: Poll", 32),
        ], tail: 32, expects: [
            .log("pull request closed, not merged"),
            .officeArchived("work|task:api#5140", reason: "pull request closed"),
        ], forbids: [
            .carry(5140, to: .storage),
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
            .officeOpened("task:ios#", .shuttle),
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

        Scenario("a neighbour's minion takes a turn in the gym, then goes back to its office", [
            ("Peer: Arrive", 32),
            ("Peer: To the gym", 64),
            ("Peer: Back to work", 64),
        ], tail: 32, expects: [
            .press("Peer: To the gym"),
            .command("exercise", by: "kim") { if case .exercise = $0 { return true }; return false },
            .press("Peer: Back to work"),
        ], floor: { sim in
            guard let m = sim.station.minions["peer:kim/kim-1"] else { return "no figure for kim's minion" }
            if m.exercising { return "still in the gym" }
            return m.place == .room(m.home.key) ? nil : "at \(m.place.words), not in kim's office \(m.home.key)"
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
            ("Merge PR", 9.6),
            ("Wedge carrier", 4.8),
        ], tail: 448, expects: [
            .officeMerged("task:ios#298"),
            .carry(298, to: .storage),
            .press("Wedge carrier"),
            .log("gives up carrying #298"),
            .carry(298, to: .storage),
        ], allowGiveUp: true, floor: { sim in
            var carriers: [String] = []
            for r in sim.model.records {
                if case .command(let c, let by) = r, case .carry(let crate, _, _) = c.kind, crate.number == 298, !carriers.contains(by) { carriers.append(by) }
            }
            return carriers.count >= 2 ? nil : "only \(carriers) carried #298"
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
        while sim != nil { frame() }
        finish()
    }

    // MARK: the run

    private var simTime = 0.0

    private func begin() {
        index += 1
        guard index < scenarios.count else { return finish() }
        sim = SimulatorController(frame: NSRect(x: 0, y: 0, width: 1060, height: 700))
        sim?.station.headless = true
        step = 0
        simTime = 0
        startedAt = CACurrentMediaTime()
        nextPressAt = ScenarioRunner.settle
        endAt = .greatestFiniteMagnitude
    }

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
                say("    rocket  \(r.key): \(r.stage) phase \(r.phaseKind) · vortex \(sim.station.simulation.vortices[r.key] != nil), aboard \(sim.station.world.aboard(station: r.station, repo: r.repo))")
            }
            for m in sim.station.minions.values.sorted(by: { $0.home.name < $1.home.name }) {
                let spot = m.fetchSpot.map { " fetchSpot \(Int($0.x.rounded())),\(Int($0.y.rounded()))" } ?? ""
                say("    body  \(m.home.name): \(m.current?.words ?? "nothing") · \(m.phaseKind) at \(m.cell.x),\(m.cell.y) pos \(String(format: "%.2f,%.2f", m.pos.x, m.pos.y)) path \(m.path.count)\(spot)\(m.waitingOn.map { " waiting on \($0)" } ?? "")\(m.hasLoad ? " carrying" : "")")
            }
        }
        var reason: String?
        if !s.allowGiveUp, let gaveUp = records.lazy.compactMap({ r -> String? in
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
