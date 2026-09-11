// A scripted regression suite: `.build/debug/Rumkapsel --scenarios`.
//
// Each scenario is a name, a list of simulator buttons with a pause after each, and what the log
// must say when it is over. Every scenario gets its own station and its own made-up org, runs
// headless at sixteen times speed off the same frame heartbeat `--snapshot` uses, and passes only
// if every expectation matched, in order, and the invariant checker found nothing.
//
//     --scenarios              every scenario
//     --scenarios pallet       only the ones whose name contains "pallet"
//     --scenarios-verbose      print each scenario's whole log
//
// Exits non-zero if anything failed. Waits are in real seconds; one is about sixteen simulated.

import AppKit

struct Scenario {
    let name: String
    /// A button and the real seconds to wait after pressing it.
    let steps: [(press: String, wait: Double)]
    /// Real seconds to keep the station running after the last press.
    let tail: Double
    /// Regexes that must all appear in the log, in this order.
    let expects: [String]
    /// Patterns that must not appear anywhere in the log.
    let forbids: [String]
    /// A press the panel refuses is normally a broken script; a few scenarios mean to try one.
    var allowSkips = false
    /// What must stand on the floor when it is over, for the things the log does not say out loud.
    /// Returns the reason it failed, or nil.
    let floor: (@MainActor (SimulatorController) -> String?)?

    init(_ name: String, _ steps: [(String, Double)], tail: Double, expects: [String], forbids: [String] = [],
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
            #"log: #298: PR #298 open"#,
            #"officeMerged task:ios#298"#,
            #"command .*: carrying #298 to storage"#,
        ], floor: { sim in
            Scenario.crates(sim, "storage", "ios") > 0 ? nil : "no ios crate stands in storage"
        }),

        Scenario("teammate branch then PR: one shuttle, one crate", [
            ("Target: api#5158", 0.3),
            ("Teammate: New branch", 3.0),
            ("Teammate: Open PR", 0.3),
        ], tail: 12, expects: [
            #"officeOpened work\|task:api#\d+ board\("leo"\) shuttle"#,
            #"crewActivity leo branch_create"#,
            #"command\s+shuttle: shuttle inbound with the office for"#,
            #"command\s+leo: fetching .* from the bay"#,
            #"crewActivity leo pr_open"#,
        ], floor: { sim in
            let flights = sim.model.logLines.filter { $0.contains("shuttle inbound") }.count
            return flights == 1 ? nil : "\(flights) shuttles flew, not one"
        }),

        Scenario("staging release opens, merges: the pallet crosses", [
            ("Target: web#455", 0.3),
            ("Release: Staging opens", 5.0),
            ("Release: Staging merges", 0.3),
        ], tail: 10, expects: [
            #"stagingOpened web#\d+"#,
            #"command .*: off to the storage console with the clipboard"#,
            #"command .*: loading the pallet for web"#,
            #"command .*: waiting for the release to merge"#,
            #"stagingMerged web#\d+"#,
            #"command .*: pushing the pallet to the deck"#,
            #"command .*: unloading the pallet"#,
        ], floor: { sim in
            Scenario.crates(sim, "deck", "web") > 0 ? nil : "nothing of web stands on the deck"
        }),

        Scenario("staging release closes: the pallet unloads back", [
            ("Target: web#455", 0.3),
            ("Release: Staging opens", 5.0),
            ("Release: Staging closes", 0.3),
        ], tail: 10, expects: [
            #"stagingOpened web#\d+"#,
            #"command .*: loading the pallet for web"#,
            #"stagingClosed web#\d+"#,
            #"command .*: unloading the pallet back into storage"#,
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
            #"releaseOpened web#\d+ -> \S+ untested"#,
            #"command\s+rocket: web standing by on the pad"#,
            #"command\s+rocket: loading .* into the rocket"#,
            #"crateCleared web#\d+"#,
            #"command .*: carrying #\d+ to the rocket"#,
            #"command\s+rocket: web loaded and steaming"#,
            #"releaseMerged web#\d+ .* production"#,
            #"command\s+rocket: web lifting off"#,
        ]),

        Scenario("PR closed unmerged: red, nothing carried", [
            ("Target: web#455", 0.3),
            ("Open PR", 2.0),
            ("Close PR", 0.3),
        ], tail: 9, expects: [
            #"log: #455: PR #455 open"#,
            #"log: #455 booking flow: pull request closed, not merged"#,
        ]),

        Scenario("peer arrives and leaves: fade in, office held", [
            ("Peer: Leave", 4.0),
            ("Peer: Arrive", 6.0),
            ("Peer: Leave", 0.3),
        ], tail: 6, expects: [
            #"officeOpened work\|task:web#460 peer\("kim"\) fade"#,
            #"peerLeft kim"#,
            #"peerArrived kim"#,
            #"peerLeft kim"#,
        ], floor: { sim in
            // Offices are held for those who left before they clear.
            sim.station.world.fleet.stations["work"]?.rooms["task:web#460"] != nil
                ? nil : "kim's office cleared the moment she left"
        }),

        Scenario("peer office kicked", [
            ("Target: web#460", 0.3),
            ("Peer: Kick office", 0.3),
        ], tail: 8, expects: [
            #"officeArchived work\|task:web#460 \(kicked\)"#,
            #"kicked #460 artist tags off the station"#,
        ]),

        Scenario("session ends: the office stays", [
            ("Target: api#5158", 0.3),
            ("Session ends", 0.3),
        ], tail: 10, expects: [
            #"press  Session ends"#,
        ], floor: { sim in
            // Nothing disappears without a cue: an office outlives the session that opened it.
            sim.station.world.fleet.stations["work"]?.rooms["task:api#5158"] != nil
                ? nil : "the office went with the session"
        }),

        Scenario("night falls, then morning", [
            ("Night", 6.0),
            ("Day", 0.3),
        ], tail: 8, expects: [
            #"press  Night"#,
            #"command .*: asleep in the dorm"#,
            #"night falls"#,
            #"press  Day"#,
            #"command .*: heading for the couch"#,
            #"morning"#,
        ]),

        Scenario("a bath lasts its whole time", [
            ("Everyone to lounge", 3.0),
            ("Bath", 0.3),
        ], tail: 14, expects: [
            #"command .*: off to the bath"#,
        ]),

        Scenario("pallet operator stays on the errand through the night", [
            ("Target: web#455", 0.5),
            ("Release: Staging opens", 6.0),   // whoever is nearest the console takes the errand
            ("Night", 6.0),                    // bedtime does not take it off the pallet
            ("Release: Staging merges", 0.5),
        ], tail: 30, expects: [
            #"command .*: pushing the pallet to the deck"#,
            #"command .*: unloading the pallet"#,
        ], forbids: [
            #"taking over the pallet"#,
        ]),
        Scenario("a commit lands: the worker stows a cube", [
            ("Target: web#455", 0.5),
            ("Commit", 0.5),
        ], tail: 8, expects: [
            #"command\s+#455 booking flow: stowing a cube for the commit"#,
        ]),
        Scenario("a chore", [
            ("Everyone to lounge", 3.0),
            ("Chore", 0.3),
        ], tail: 12, expects: [
            #"command .*: having a look round the station"#,
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
        let lines = sim.model.logLines
        let seconds = CACurrentMediaTime() - startedAt
        if verbose {
            say("--- \(s.name) ---")
            for l in lines { say("    " + l) }
        }
        var reason: String?
        if let v = lines.first(where: { $0.contains("VIOLATION:") }) {
            reason = v.trimmingCharacters(in: .whitespaces)
        }
        if reason == nil, !s.allowSkips, let skipped = lines.first(where: { $0.contains("  skipped  ") }) {
            reason = "a press was refused · " + skipped.trimmingCharacters(in: .whitespaces)
        }
        if reason == nil {
            for bad in s.forbids {
                guard let rx = try? Regex(bad) else { reason = "bad pattern /\(bad)/"; break }
                if let line = lines.first(where: { $0.firstRange(of: rx) != nil }) { reason = "said /\(bad)/ · " + line.trimmingCharacters(in: .whitespaces); break }
            }
        }
        if reason == nil {
            var at = 0
            for want in s.expects {
                guard let rx = try? Regex(want) else { reason = "bad expectation /\(want)/"; break }
                var hit = false
                while at < lines.count {
                    let line = lines[at]
                    at += 1
                    if line.firstRange(of: rx) != nil { hit = true; break }
                }
                if !hit { reason = "never said /\(want)/"; break }
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
        let violations = lines.filter { $0.contains("VIOLATION:") }
        if violations.count > 1 {
            for v in violations.dropFirst() { say("      " + v.trimmingCharacters(in: .whitespaces)) }
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
