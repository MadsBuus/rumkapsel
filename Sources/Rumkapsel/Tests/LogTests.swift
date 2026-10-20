import Foundation

@MainActor
enum LogTests {
    private static var failures = 0

    static func run() -> Never {
        test("every event goes into a line and comes back the same") {
            let t = Date(timeIntervalSinceReferenceDate: 782_049_612.345_678)
            let web = CrateID(repo: "web", number: 455), ios = CrateID(repo: "ios", number: 298)
            let all: [Event] = [
                .policy(repo: "web", RepoFacts(hasStaging: true, hasCleared: true, shipsOnMerge: true, shipsOnTag: true, ships: false, shipsAtOnce: true)),
                .policy(repo: "ios", RepoFacts()),
                .work(WorkNews(crate: web, office: "task:web#455", stage: .qa, closed: true, quiet: true, link: "https://github.com/o/web/pull/455")),
                .work(WorkNews(crate: ios, stage: .stored)), .work(WorkNews(crate: ios, stage: .cleared, by: .board)),
                .office(.opened("task:web#455", repo: "web", via: .appear)),
                .office(.opened("task:web#460", repo: nil, via: .fade)),
                .office(.opened("task:api#5", repo: "api", via: .shuttle(for: "crew:leo"))),
                .office(.opened("task:api#6", repo: "api", via: .shuttle(for: nil))),
                .office(.renamed(from: "task:web#1", to: "task:web#2")),
                .office(.status("task:web#455", crate: web, merged: true, closedAt: t)),
                .office(.status("task:web#455", crate: nil, merged: false, closedAt: nil)),
                .office(.gone("task:web#455")),
                .decon(repo: "web", open: [3, 1], quiet: true),
                .decon(repo: "web", open: []),
                .deconClosed(web),
                .renumbered(from: web, to: ios),
                .staging(repo: "web", .opened(40)), .staging(repo: "web", .merged(40)), .staging(repo: "web", .closed(40)),
                .staging(repo: "web", .deploy(.unheard)), .staging(repo: "web", .deploy(.running(since: t, usual: 312.5))),
                .staging(repo: "web", .deploy(.live)), .staging(repo: "web", .deploy(.failed)),
                .release(repo: "web", production: nil, label: ""), .release(repo: "web", production: false, label: "staging"),
                .release(repo: "web", production: true, label: "v2.1", quiet: true),
                .hotfixes(repo: "ios", open: [298: "hotfix #298", 7: ""], quiet: true), .hotfixes(repo: "ios", open: [:]),
                .launched(repo: "web"), .launched(repo: "ios", hotfix: 298, label: "v2.1.1"), .launched(repo: "web", crates: [455, 431]),
                .sweep(repo: "web", keep: [455]), .sweep(repo: "web", keep: []),
                .restack, .tick,
            ]
            let line = EventLog.Line(at: t, station: "work", events: all, effects: 3)
            guard let data = try? EventLog.makeEncoder().encode(line), let back = try? JSONDecoder().decode(EventLog.Line.self, from: data) else {
                return expect(false, "the line encodes and decodes")
            }
            expect(back.at == t && back.station == "work" && back.effects == 3, "time, station and effects: \(back.at.timeIntervalSinceReferenceDate)")
            for (a, b) in zip(all, back.events ?? []) where a != b { expect(false, "\(a.words) came back as \(b.words)") }
            expect(back.events?.count == all.count, "\(back.events?.count ?? 0) of \(all.count) events")
            expect(!String(decoding: data, as: UTF8.self).contains("_0"), "no synthesized keys")
            let station = Station(name: "work")
            let base = EventLog.Line(at: t, station: "work", baseline: "start", facts: Facts(), yard: station.yard)
            let yard = (try? EventLog.makeEncoder().encode(base)).flatMap { try? JSONDecoder().decode(EventLog.Line.self, from: $0) }?.yard
            expect(yard?.same(station.yard) == true, "the yard comes back the same")
            let kinds = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["events"] as? [[String: Any]] ?? []
            expect(Set(kinds.compactMap { $0["e"] as? String }) == Event.kinds, "every kind is known and written")
        }

        test("a broken line loses only itself, unknown events are named, replay starts at the first baseline") {
            let dir = scratch(), url = dir.appendingPathComponent("work-2026-10-14.jsonl")
            let e = EventLog.makeEncoder(), t = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let station = Station(name: "work")
            let batch = EventLog.Line(at: t, station: "work", events: [.decon(repo: "web", open: [7])], effects: 1)
            let base = EventLog.Line(at: t, station: "work", baseline: "start", facts: Facts(), yard: station.yard)
            var data = Data()
            for l in [batch, base, batch] { data += (try! e.encode(l)) + [0x0A] }
            let broken = try! e.encode(EventLog.Line(at: t, station: "work", events: [.work(WorkNews(crate: CrateID(repo: "wéb", number: 1), stage: .ready))]))
            data += broken.prefix(broken.firstIndex(of: 0xC3)! + 1) + [0x0A]
            data += Data(#"{"at":0,"events":[{"e":"teleport"}],"station":"work"}"#.utf8) + [0x0A]
            data += (try! e.encode(batch)) + [0x0A]
            try? data.write(to: url)
            let read = EventLog.read(url)
            expect(read.lines.count == 4 && read.unreadable == 1 && read.unknown == ["teleport": 1], "lines \(read.lines.count), unreadable \(read.unreadable), unknown \(read.unknown)")
            expect(Replay.notes(read) == ["1 unreadable line", "unknown event teleport in 1 line"], "\(Replay.notes(read))")
            let out = EventLog.replay(read.lines)
            expect(out?.batches == 2 && out?.facts.crates[CrateID(repo: "web", number: 7)]?.zone == .decon, "two batches after the baseline: \(out?.batches ?? -1)")
        }

        test("a crash's partial line does not swallow the next session's baseline") {
            let (rig, dir) = org([("Target: ios#298", 0), ("Open PR", 32), ("Merge PR", 10)])
            rig.world.log.flush()
            guard let url = logs(dir).first, let h = try? FileHandle(forWritingTo: url) else { return expect(false, "a log to cut") }
            h.seekToEndOfFile()
            h.write(Data(#"{"at":81365,"events":[{"e":"wo"#.utf8))
            try? h.close()
            let world = World(demo: true)
            world.log.dir = dir
            let station = world.fleet.station("work", fixed: [])
            station.facts = rig.world.fleet.station("work").facts.persisted
            _ = world.apply([.restack], at: rig.now.addingTimeInterval(5), to: station)
            world.log.flush()
            let read = EventLog.read(url)
            expect(read.unreadable == 1 && read.lines.filter { $0.baseline == "start" }.count == 2, "one lost line, two start baselines: \(read.unreadable), \(read.lines.compactMap(\.baseline))")
            let r = Replay.check(url, read.lines, station: "work")
            expect(r.ok, r.words)
            var cut = read.lines
            if let i = cut.lastIndex(where: { $0.baseline == "start" }) { cut[i].facts?.crates = [:] }
            expect(!Replay.check(url, cut, station: "work").ok, "the session break is checked")
        }

        test("two writers on one file never mix their lines") {
            let dir = scratch(), worlds = [World(demo: true), World(demo: true)]
            let t = Date()
            for w in worlds {
                w.log.dir = dir
                let st = w.fleet.station("work", fixed: [])
                for i in 0..<400 { _ = w.apply([.decon(repo: "web\(i % 7)", open: Array(0..<(i % 30)))], at: t, to: st) }
            }
            DispatchQueue.concurrentPerform(iterations: 2) { worlds[$0].log.flush() }
            let read = EventLog.read(logs(dir)[0])
            expect(read.unreadable == 0 && read.lines.count == 2 * 401, "lines \(read.lines.count), unreadable \(read.unreadable)")
        }

        test("scripted runs keep no log, and the day in a file name never goes back") {
            expect(EventLog.home == nil, "no log dir in a scripted run")
            let dir = scratch(), world = World(demo: true), st = world.fleet.station("work", fixed: [])
            world.log.dir = dir
            let t = Date()
            _ = world.apply([.restack], at: t, to: st)
            _ = world.apply([.restack], at: t.addingTimeInterval(-2 * 86400), to: st)
            world.log.flush()
            expect(logs(dir).map(\.lastPathComponent) == ["work-\(EventLog.day(t)).jsonl"], "\(logs(dir).map(\.lastPathComponent))")
        }

        let runs: [[(String, Double)]] = [
            [("Target: web#455", 0), ("Release: Staging opens", 80), ("Release: Staging merges", 10), ("Release: Production opens", 48),
             ("Release: Mark tested", 96), ("Release: Production merges", 10)],
            [("Target: ios#298", 0), ("Release: Production opens", 16), ("Release: Hotfix opens", 48), ("Release: Hotfix merges", 700)],
            [("Target: ios#298", 0), ("Bot: Open PR", 32), ("Bot: Merge PR", 10), ("Repo: Ships on merge", 4.8), ("Open PR", 32), ("Merge PR", 10)],
            [("Target: api#5140", 0), ("Teammate: Close PR", 200), ("Scan: again", 200), ("Scan: again", 200), ("Scan: again", 120), ("GitHub: Poll", 10)],
            [("Target: web#455", 0), ("Peer: Kick office", 10), ("Board: Move web#431 to \(ConfigStore.shared.current.statuses.deck)", 10)],
        ]
        for steps in runs {
            test("a recorded run replays to exactly its final facts: \(steps[0].0) … \(steps.last!.0)") {
                let (rig, dir) = org(steps)
                rig.world.log.flush()
                let files = logs(dir)
                expect(!files.isEmpty, "a log was written")
                for url in files {
                    expect(EventLog.read(url).lines.first?.baseline != nil, "\(url.lastPathComponent) begins with a baseline")
                }
                for url in files.dropLast() {
                    let lines = EventLog.read(url).lines, r = Replay.check(url, lines, station: "work")
                    expect(r.ok, "\(url.lastPathComponent): \(r.words)")
                }
                guard let url = files.last, let out = EventLog.replay(EventLog.read(url).lines) else { return expect(false, "the newest file replays") }
                expect(out.mismatch == nil, out.mismatch ?? "")
                let live = rig.world.fleet.station("work").facts
                let d = EventLog.difference(live, out.facts)
                expect(d == nil, "replayed facts match the live ones: \(d ?? "")")
                expect(out.batches > 0, "batches were replayed")
                save(live, beside: dir)
                let other = replayElsewhere(url)
                expect(other.hasPrefix("OK") && other.contains("the saved facts"), "another process replays it to the saved facts: \(other)")
            }
        }

        test("a crate's history: office, storage, the deck, the tested rows, aboard") {
            let (rig, dir) = org([("Target: ios#298", 0), ("Open PR", 32), ("Stage: stored", 128), ("Stage: QA", 128), ("Stage: cleared", 96), ("Stage: shipped", 10)])
            rig.world.log.flush()
            let id = CrateID(repo: "ios", number: 298)
            let kept = rig.world.log.history("work", id)
            let places = kept.filter(\.moved).compactMap(\.to).map(kind).reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }
            expect(places == ["office", "waiting", "testing", "cleared", "aboard"], "the places it went: \(places)")
            let lines = logs(dir).flatMap { Replay.history(EventLog.read($0).lines, of: id) }
            say("      " + lines.joined(separator: "\n      "))
            let order = ["office", "waiting", "testing", "cleared", "aboard"]
            let firsts = order.map { w in lines.firstIndex { $0.contains("  \(w)") } }
            expect(firsts.allSatisfy { $0 != nil } && firsts.map { $0! } == firsts.map { $0! }.sorted(), "one line per change, in order: \(firsts)")
            expect(lines.contains { $0.contains("← work ios#298 stored") } && lines.contains { $0.contains("← launched ios") }, "each line names its event")
            let story = StationController.crateStory(kept) ?? ""
            say("      hover: \(story)")
            expect(story.hasPrefix("on the deck ") && story.contains(" · on the cleared rows ") && story.contains(" · aboard since "), "the hover tells it: \(story)")
        }

        test("a crate's story: what happened, what moved it, and the lead time, across midnight") {
            let id = CrateID(repo: "web", number: 455)
            func at(_ day: Int, _ h: Int, _ m: Int) -> Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))! }
            func crate(_ place: CrateFact.Place, _ stage: Stage) -> CrateFact { CrateFact(id: id, place: place, stage: stage, seq: 1) }
            func work(_ stage: Stage, _ by: Source, pull: Int? = nil) -> Event { .work(WorkNews(crate: id, stage: stage, by: by, pull: pull)) }
            let office = crate(.office("task:web#455"), .ready), stored = crate(.waiting, .stored), deck = crate(.testing, .qa)
            let cleared = crate(.cleared, .cleared), aboard = crate(.aboard("web|release#6"), .shipped)
            let launch = Event.launched(repo: "web", crates: [455], label: "rocket:https://github.com/o/web/pull/14090|web · develop → main · #14090 Release")
            let steps = [
                EventLog.Step(at: at(12, 14, 24), from: nil, to: office, event: work(.ready, .pulls)),
                EventLog.Step(at: at(12, 16, 5), from: office, to: stored, event: work(.stored, .pulls, pull: 14062)),
                EventLog.Step(at: at(13, 11, 30), from: stored, to: deck, event: work(.qa, .git), staging: 14080),
                EventLog.Step(at: at(13, 15, 30), from: deck, to: stored, event: work(.stored, .board), staging: 14080),
                EventLog.Step(at: at(13, 23, 50), from: stored, to: deck, event: .staging(repo: "web", .merged(14081))),
                EventLog.Step(at: at(14, 0, 20), from: deck, to: cleared, event: work(.cleared, .board)),
                EventLog.Step(at: at(14, 10, 40), from: cleared, to: aboard, event: launch),
                EventLog.Step(at: at(14, 10, 52), from: aboard, to: nil),
            ]
            let told = CrateStory.tell(steps, now: at(14, 11, 30), current: nil)
            for line in told.lines { say("      \(line)") }
            say("      \(told.footer ?? "")")
            let want: [CrateStory.Line] = [
                .step(at: "Mon 14:24", what: "pull request open, in its office", why: "#455 opened"),
                .step(at: "Mon 16:05", what: "merged, to storage", why: "#14062 merged"),
                .step(at: "Tue 11:30", what: "to the deck for testing", why: "staging release #14080 merged"),
                .step(at: "Tue 15:30", what: "back to storage", why: "its card moved to ready for staging"),
                .step(at: "Tue 23:50", what: "to the deck for testing", why: "staging release #14081 merged"),
                .step(at: "00:20", what: "tested, to the cleared rows", why: "its card moved to ready to ship"),
                .step(at: "10:40", what: "aboard web's release rocket", why: "production release #14090 merged"),
                .step(at: "10:52", what: "lifted off", why: ""),
            ]
            expect(told.lines == want, "the rows: \(told.lines.count) of \(want.count)")
            for (a, b) in zip(told.lines, want) where a != b { expect(false, "\(a) should be \(b)") }
            expect(told.footer == "merged to production in 1 d 18 h", "the footer: \(told.footer ?? "none")")

            let waiting = CrateStory.tell(Array(steps.prefix(3)), now: at(13, 13, 40), current: deck)
            expect(waiting.footer == "on its way to production for 21 h 35 min so far", "the footer so far: \(waiting.footer ?? "none")")
            expect(waiting.lines.first == .step(at: "Mon 14:24", what: "pull request open, in its office", why: "#455 opened"), "yesterday and before carry the day")

            let late = CrateStory.tell(Array(steps[2...3]), now: at(13, 16, 0), current: stored)
            expect(late.lines.first == .step(at: "", what: "in storage", why: "before the log began"), "a story older than the log: \(String(describing: late.lines.first))")
            expect(late.footer == "on its way to production since before the log began", late.footer ?? "none")
            let policy = EventLog.Step(at: at(13, 16, 0), from: deck, to: stored, event: .policy(repo: "web", RepoFacts(hasStaging: false)))
            expect(CrateStory.why(policy) == "web's way to production changed: no testing", "a policy says what changed: \(CrateStory.why(policy))")
            let quiet = CrateStory.tell([], now: at(13, 16, 0), current: stored)
            expect(quiet.lines == [.step(at: "", what: "in storage", why: "before the log began")], "a crate the log never saw move: \(quiet.lines)")
        }

        test("a restart begins with a baseline and remembers today's history") {
            let (rig, dir) = org([("Target: ios#298", 0), ("Open PR", 32), ("Merge PR", 10)])
            rig.world.log.flush()
            let id = CrateID(repo: "ios", number: 298)
            let world = World(demo: true)
            world.log.dir = dir
            let station = world.fleet.station("work", fixed: [])
            station.facts = rig.world.fleet.station("work").facts.persisted
            _ = world.apply([.tick, .restack], at: rig.now.addingTimeInterval(5), to: station)
            world.log.flush()
            let lines = logs(dir).flatMap { EventLog.read($0).lines }
            expect(lines.filter { $0.baseline == "start" }.count == 2, "two start baselines: \(lines.compactMap(\.baseline))")
            expect(lines.last?.baseline == "restack", "a baseline after the restack")
            expect(world.log.history("work", id).contains { $0.to?.place == .waiting }, "the merge into storage is remembered")
            for url in logs(dir) { let r = Replay.check(url, EventLog.read(url).lines, station: "work"); expect(r.ok, r.words) }
        }

        test("files older than thirty days are pruned, the rest kept") {
            let dir = scratch(), now = Date()
            func ago(_ d: Int) -> String { EventLog.day(Calendar.current.date(byAdding: .day, value: -d, to: now)!) }
            let names = ["work-\(ago(40)).jsonl", "work-\(ago(31)).jsonl", "work-\(ago(29)).jsonl", "home-\(ago(45)).jsonl", "home-\(ago(1)).jsonl", "notes.txt"]
            for n in names { FileManager.default.createFile(atPath: dir.appendingPathComponent(n).path, contents: Data()) }
            let world = World(demo: true)
            world.log.dir = dir
            _ = world.apply([.restack], at: now, to: world.fleet.station("work", fixed: []))
            world.log.flush()
            let left = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            let want: Set = ["work-\(ago(29)).jsonl", "home-\(ago(1)).jsonl", "notes.txt", "work-\(EventLog.day(now)).jsonl"]
            expect(left == want, "left: \(left.sorted())")
        }

        for root in made { try? FileManager.default.removeItem(at: root) }
        say(failures == 0 ? "log: all passed" : "log: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func org(_ steps: [(String, Double)]) -> (Rig, URL) {
        let rig = Rig(), dir = scratch()
        rig.world.log.dir = dir
        let sim = SimulatorModel(station: rig)
        sim.quiet = true
        sim.quiesce()
        sim.seed()
        rig.advance(16)
        for (press, wait) in steps {
            sim.press(press)
            rig.drain()
            rig.advance(wait)
        }
        return (rig, dir)
    }

    private static func save(_ facts: Facts, beside dir: URL) {
        struct Saved: Encodable { var facts: Facts }
        struct Saves: Encodable { var stations: [String: Saved] }
        let url = dir.deletingLastPathComponent().appendingPathComponent(Fleet.saveName)
        try? JSONEncoder().encode(Saves(stations: ["work": Saved(facts: facts.persisted)])).write(to: url)
    }

    private static func replayElsewhere(_ url: URL) -> String {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        p.arguments = ["--replay", url.path]
        p.environment = ProcessInfo.processInfo.environment
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "could not run" }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        while p.isRunning { usleep(1000) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func kind(_ c: CrateFact) -> String {
        switch c.place {
        case .office: return "office"
        case .aboard: return "aboard"
        default: return c.zone?.rawValue ?? ""
        }
    }

    private static func logs(_ dir: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".jsonl") }.sorted().map { dir.appendingPathComponent($0) }
    }

    private static var made: [URL] = []

    private static func scratch() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rumkapsel-log-\(UUID().uuidString)", isDirectory: true)
        let dir = root.appendingPathComponent("Rumkapsel/events", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        made.append(root)
        return dir
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
