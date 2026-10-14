import Foundation

final class EventLog {
    struct Line: Codable {
        var at: Date
        var station: String
        var baseline: String?
        var facts: Facts?
        var yard: YardGeometry?
        var events: [Event]?
        var effects: Int?
    }

    struct Step {
        var at: Date
        var from: CrateFact?
        var to: CrateFact?
        var event: Event?
        var baseline: String?
        var staging: Int?

        var moved: Bool { from?.place != to?.place || from?.stage != to?.stage }
        var cause: String { baseline.map { "baseline \($0)" } ?? event?.words ?? "time" }
    }

    struct Replayed {
        var facts: Facts
        var yard: YardGeometry
        var batches = 0
        var mismatch: String?
    }

    struct Read {
        var lines: [Line] = []
        var unreadable = 0
        var unknown: [String: Int] = [:]
    }

    static let days = 30, kept = 24, flushEvery: TimeInterval = 2
    static var home: URL? {
        guard !Scripted.run, !CommandLine.arguments.contains("--github-diag") else { return nil }
        return AppSupport.root.appendingPathComponent("Rumkapsel", isDirectory: true).appendingPathComponent("events", isDirectory: true)
    }

    var dir: URL?
    private var session: [String: [CrateID: [Step]]] = [:]
    private var asked: Set<String> = []
    private var last: [String: (facts: Facts, yard: YardGeometry, day: String)] = [:]
    private var newest = ""
    private let queue = DispatchQueue(label: "rumkapsel.events", qos: .utility)
    private let lock = NSLock()
    private var loaded: [String: [CrateID: [Step]]] = [:]
    private let encoder = EventLog.makeEncoder()
    private var waiting: [URL: [Data]] = [:]
    private var opened: Set<URL> = []
    private var failed = false
    private var timer: DispatchSourceTimer?

    init(dir: URL?) { self.dir = dir }

    func record(_ events: [Event], at: Date, station: Station, yard: YardGeometry, before: Facts, effects: Int) {
        let after = station.facts
        guard after != before || events.contains(where: { $0 != .tick }) else { return }
        let line = Line(at: at, station: station.name, events: events, effects: effects)
        if let dir { file(line, in: dir, station: station, yard: yard, before: before, after: after) }
        for (id, step) in EventLog.steps(line, before, after) {
            session[station.name, default: [:]][id, default: []].append(step)
            if let n = session[station.name]?[id]?.count, n > EventLog.kept { session[station.name]?[id]?.removeFirst(n - EventLog.kept) }
        }
    }

    private func file(_ line: Line, in dir: URL, station: Station, yard: YardGeometry, before: Facts, after: Facts) {
        let at = line.at
        newest = max(EventLog.day(at), newest)
        let day = newest, url = EventLog.file(dir, station.name, day)
        func baseline(_ reason: String, _ facts: Facts) {
            write(Line(at: at, station: station.name, baseline: reason, facts: facts, yard: yard), to: url)
        }
        if let was = last[station.name] {
            if was.day != day { baseline("day", before); prune(dir, at) }
            else if !was.yard.same(yard) { baseline("yard", before) }
            else if was.facts != before { baseline("outside", before) }
        } else {
            if !asked.contains(station.name) { asked.insert(station.name); load(dir, station.name, day) }
            baseline(station.migrated ? "migrated" : "start", before)
            station.migrated = false
            prune(dir, at)
        }
        write(line, to: url)
        if line.events?.contains(.restack) == true { baseline("restack", after) }
        last[station.name] = (after, yard, day)
    }

    func history(_ station: String, _ id: CrateID) -> [Step] {
        lock.lock()
        let early = loaded[station]?[id] ?? []
        lock.unlock()
        return Array((early + (session[station]?[id] ?? [])).suffix(EventLog.kept))
    }

    func forget() { last = [:] }

    func flush() { queue.sync { drain() } }

    private func load(_ dir: URL, _ station: String, _ day: String) {
        let yesterday = EventLog.days(day).flatMap { Calendar.current.date(byAdding: .day, value: -1, to: $0) }.map(EventLog.day)
        let files = [yesterday, day].compactMap { $0 }.map { EventLog.file(dir, station, $0) }
        queue.async { [self] in
            let found = EventLog.history(files.flatMap { EventLog.read($0).lines })
            lock.lock()
            loaded[station] = found
            lock.unlock()
        }
    }

    private func write(_ line: Line, to url: URL) {
        queue.async { [self] in
            do {
                var data = try encoder.encode(line)
                data.append(0x0A)
                waiting[url, default: []].append(data)
            } catch {
                StationLog.write("events", "a line for \(line.station) at \(EventLog.clock(line.at)) could not be encoded: \(error)")
            }
            guard timer == nil, !waiting.isEmpty else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + EventLog.flushEvery, repeating: EventLog.flushEvery)
            t.setEventHandler { [weak self] in self?.drain() }
            t.resume()
            timer = t
        }
    }

    private func drain() {
        for url in waiting.keys.sorted(by: { $0.path < $1.path }) {
            let lines = waiting[url] ?? []
            let done = append(lines, to: url)
            waiting[url] = done == lines.count ? nil : Array(lines[done...])
        }
        guard waiting.isEmpty else { return }
        timer?.cancel()
        timer = nil
    }

    private func append(_ lines: [Data], to url: URL) -> Int {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = Darwin.open(url.path, O_RDWR | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { fail(url, errno); return 0 }
        defer { Darwin.close(fd) }
        if !opened.contains(url) {
            var end: UInt8 = 0x0A
            let size = lseek(fd, 0, SEEK_END)
            if size > 0, pread(fd, &end, 1, size - 1) == 1, end != 0x0A, !put(Data([0x0A]), fd) { fail(url, errno); return 0 }
            opened.insert(url)
        }
        for (i, line) in lines.enumerated() where !put(line, fd) {
            fail(url, errno)
            opened.remove(url)
            return i
        }
        return lines.count
    }

    private func put(_ data: Data, _ fd: Int32) -> Bool {
        data.withUnsafeBytes { raw in
            var at = 0
            while at < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + at, raw.count - at)
                if n < 0 { if errno == EINTR { continue }; return false }
                at += n
            }
            return true
        }
    }

    private func fail(_ url: URL, _ code: Int32) {
        guard !failed else { return }
        failed = true
        StationLog.write("events", "could not write \(url.lastPathComponent): \(String(cString: strerror(code))); keeping the lines for the next try")
    }

    private func prune(_ dir: URL, _ at: Date) {
        guard let edge = Calendar.current.date(byAdding: .day, value: -EventLog.days, to: at).map(EventLog.day) else { return }
        queue.async {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasSuffix(".jsonl") {
                let stamp = String(name.dropLast(6).suffix(10))
                if EventLog.days(stamp) != nil, stamp < edge { try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
            }
        }
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let clockFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func day(_ at: Date) -> String { dayFormat.string(from: at) }
    static func days(_ stamp: String) -> Date? { dayFormat.date(from: stamp) }
    static func clock(_ at: Date) -> String { clockFormat.string(from: at) }

    static func file(_ dir: URL, _ station: String, _ day: String) -> URL {
        let safe = station.map { "/:".contains($0) ? "-" : String($0) }.joined()
        return dir.appendingPathComponent("\(safe)-\(day).jsonl")
    }

    static func next(after url: URL) -> URL? {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.count > 11 else { return nil }
        let prefix = String(name.dropLast(10)), stamp = String(name.suffix(10))
        let dir = url.deletingLastPathComponent()
        let later = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { n in
            n.hasSuffix(".jsonl") && n.count == prefix.count + 16 && n.hasPrefix(prefix) && String(n.dropLast(6).suffix(10)) > stamp
        }
        return later.min().map { dir.appendingPathComponent($0) }
    }

    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    static func read(_ url: URL) -> Read {
        var out = Read()
        guard let data = try? Data(contentsOf: url) else { return out }
        let decoder = JSONDecoder()
        for raw in data.split(separator: 0x0A) {
            let text = Data(String(decoding: raw, as: UTF8.self).utf8)
            if let line = try? decoder.decode(Line.self, from: text) { out.lines.append(line); continue }
            let strange = ((try? decoder.decode(Kinds.self, from: text))?.events ?? []).map(\.e).filter { !Event.kinds.contains($0) }
            if strange.isEmpty { out.unreadable += 1 }
            for e in strange { out.unknown[e, default: 0] += 1 }
        }
        return out
    }

    private struct Kinds: Decodable {
        struct Kind: Decodable { var e: String }
        var events: [Kind]?
    }

    static func replay(_ lines: [Line], each: (Line, Facts, Facts) -> Void = { _, _, _ in }) -> Replayed? {
        guard let i = lines.firstIndex(where: { $0.facts != nil && $0.yard != nil }), let start = lines[i].facts, let yard = lines[i].yard else { return nil }
        var out = Replayed(facts: start, yard: yard)
        for line in lines[(i + 1)...] {
            if let base = line.facts {
                if out.mismatch == nil, line.baseline != "migrated", let d = difference(base, out.facts, persisted: line.baseline == "start") {
                    out.mismatch = "\(clock(line.at)) at the \(line.baseline ?? "") baseline: \(d)"
                }
                each(line, out.facts, base)
                out.facts = base
                out.yard = line.yard ?? out.yard
                continue
            }
            let before = out.facts
            _ = Rules.apply(line.events ?? [], at: line.at, to: &out.facts, yard: out.yard)
            out.batches += 1
            each(line, before, out.facts)
        }
        return out
    }

    static func history(_ lines: [Line]) -> [CrateID: [Step]] {
        var out: [CrateID: [Step]] = [:]
        _ = replay(lines) { line, before, after in
            for (id, step) in steps(line, before, after) { out[id, default: []].append(step) }
        }
        return out.mapValues { Array($0.suffix(kept)) }
    }

    static func steps(_ line: Line, _ before: Facts, _ after: Facts) -> [(CrateID, Step)] {
        Set(before.crates.keys).union(after.crates.keys).sorted().compactMap { id in
            let a = before.crates[id], b = after.crates[id]
            guard a?.place != b?.place || a?.column != b?.column || a?.stage != b?.stage else { return nil }
            let event = line.facts != nil ? nil : cause(id, a?.place, line.events ?? [])
            let staging = after.staging[id.repo].flatMap { $0.number > 0 ? $0.number : nil }
            return (id, Step(at: line.at, from: a, to: b, event: event, baseline: line.facts != nil ? line.baseline ?? "" : nil, staging: staging))
        }
    }

    static func cause(_ id: CrateID, _ was: CrateFact.Place?, _ events: [Event]) -> Event? {
        func named(_ e: Event) -> Bool {
            switch e {
            case .work(let w): return w.crate == id
            case .deconClosed(let c): return c == id
            case .renumbered(let from, let to): return from == id || to == id
            case .decon(let repo, let open, _): return repo == id.repo && open.contains(id.number)
            case .launched(let repo, let hotfix, let crates, _): return repo == id.repo && (hotfix == id.number || crates?.contains(id.number) == true)
            case .office(.gone(let key)), .office(.renamed(let key, _)): return was == .office(key)
            default: return false
            }
        }
        func repoWide(_ e: Event) -> Bool {
            switch e {
            case .policy(let repo, _), .staging(let repo, _), .release(let repo, _, _, _), .hotfixes(let repo, _, _), .launched(let repo, _, _, _), .sweep(let repo, _):
                return repo == id.repo
            case .restack: return true
            default: return false
            }
        }
        return events.first(where: named) ?? events.first(where: repoWide)
    }

    static func whereabouts(_ c: CrateFact?) -> String {
        guard let c else { return "gone" }
        let place: String
        switch c.place {
        case .office(let key): place = "office \(key)"
        case .aboard(let rocket): place = "aboard \(rocket)"
        default: place = c.zone?.rawValue ?? "\(c.place)"
        }
        return ([place] + [c.column.map { "column \($0)" }, c.stage?.name].compactMap { $0 }).joined(separator: " · ")
    }

    static func canonical(_ f: Facts) -> Facts {
        (try? JSONDecoder().decode(Facts.self, from: makeEncoder().encode(f))) ?? f
    }

    static func difference(_ want: Facts, _ got: Facts, persisted: Bool = false) -> String? {
        let w = canonical(persisted ? want.persisted : want), g = canonical(persisted ? got.persisted : got)
        guard w != g else { return nil }
        for id in Set(w.crates.keys).union(g.crates.keys).sorted() {
            let a = w.crates[id], b = g.crates[id]
            if (a == nil) != (b == nil) { return "crate \(id): expected \(whereabouts(a)), got \(whereabouts(b))" }
            if let d = fields(a, b) { return "crate \(id) \(d)" }
        }
        for key in Set(w.rockets.keys).union(g.rockets.keys).sorted() { if let d = fields(w.rockets[key], g.rockets[key]) { return "rocket \(key) \(d)" } }
        for key in Set(w.offices.keys).union(g.offices.keys).sorted() { if let d = fields(w.offices[key], g.offices[key]) { return "office \(key) \(d)" } }
        for key in Set(w.staging.keys).union(g.staging.keys).sorted() { if let d = fields(w.staging[key], g.staging[key]) { return "staging \(key) \(d)" } }
        for key in Set(w.repos.keys).union(g.repos.keys).sorted() { if let d = fields(w.repos[key], g.repos[key]) { return "repo \(key) \(d)" } }
        if w.homes != g.homes { return "homes: expected \(w.homes.sorted { $0.key < $1.key }), got \(g.homes.sorted { $0.key < $1.key })" }
        return fields(w, g).map { "facts \($0)" } ?? "facts differ"
    }

    private static func fields<T>(_ want: T?, _ got: T?) -> String? {
        guard let want, let got else { return want == nil && got == nil ? nil : "expected \(want == nil ? "none" : "one"), got \(got == nil ? "none" : "one")" }
        for (a, b) in zip(Mirror(reflecting: want).children, Mirror(reflecting: got).children) where show(a.value) != show(b.value) {
            return "\(a.label ?? "field"): expected \(show(a.value)), got \(show(b.value))"
        }
        return nil
    }

    private static func show(_ v: Any) -> String {
        let m = Mirror(reflecting: v)
        if m.displayStyle == .optional { return m.children.first.map { show($0.value) } ?? "nil" }
        return "\(v)"
    }
}
