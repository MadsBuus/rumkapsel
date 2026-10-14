import Foundation

enum Replay {
    static func run(_ path: String, crate: String?) -> Never {
        Words.pinned = Vocabulary()
        let url = URL(fileURLWithPath: path)
        let read = EventLog.read(url)
        for note in notes(read) { say(note) }
        guard let station = read.lines.first(where: { $0.facts != nil })?.station else { say("\(path): no baseline to start from"); exit(1) }
        if let crate {
            guard let id = try? CrateID(text: crate) else { say("\(crate): not a crate, try repo#123"); exit(1) }
            let story = history(read.lines, of: id)
            say(story.isEmpty ? "\(id): no changes in \(url.lastPathComponent)" : story.joined(separator: "\n"))
            exit(0)
        }
        let result = check(url, read.lines, station: station)
        say(result.ok ? "OK: \(result.words)" : "not so: \(result.words)")
        exit(result.ok ? 0 : 1)
    }

    static func notes(_ read: EventLog.Read) -> [String] {
        var out: [String] = []
        if read.unreadable > 0 { out.append("\(read.unreadable) unreadable \(read.unreadable == 1 ? "line" : "lines")") }
        for (kind, n) in read.unknown.sorted(by: { $0.key < $1.key }) { out.append("unknown event \(kind) in \(n) \(n == 1 ? "line" : "lines")") }
        return out
    }

    static func check(_ url: URL, _ lines: [EventLog.Line], station: String) -> (ok: Bool, words: String) {
        guard let out = EventLog.replay(lines) else { return (false, "no baseline to start from") }
        if let m = out.mismatch { return (false, m) }
        let batches = "\(out.batches) \(out.batches == 1 ? "batch" : "batches")"
        if let next = EventLog.next(after: url), let base = EventLog.read(next).lines.first(where: { $0.facts != nil }), let facts = base.facts {
            if let d = EventLog.difference(facts, out.facts, persisted: base.baseline == "start") { return (false, "against \(next.lastPathComponent): \(d)") }
            return (true, "\(batches) replay to the baseline of \(next.lastPathComponent)")
        }
        let save = url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(Fleet.saveName)
        guard let data = try? Data(contentsOf: save), let fleet = try? JSONDecoder().decode(SavedFleet.self, from: data),
              let saved = fleet.stations[station]?.facts else { return (true, "\(batches) replay without a difference; no saved facts to end on") }
        if let d = EventLog.difference(saved, out.facts, persisted: true) { return (false, "against the saved facts: \(d)") }
        return (true, "\(batches) replay to the saved facts")
    }

    static func history(_ lines: [EventLog.Line], of id: CrateID) -> [String] {
        var out: [String] = []
        _ = EventLog.replay(lines) { line, before, after in
            guard let (_, step) = EventLog.steps(line, before, after).first(where: { $0.0 == id }) else { return }
            out.append("\(EventLog.clock(step.at))  \(EventLog.whereabouts(step.to))  ← \(step.cause)")
        }
        return out
    }

    private struct SavedFleet: Decodable {
        struct Saved: Decodable { var facts: Facts? }
        var stations: [String: Saved]
    }

    private static func say(_ text: String) { print(text) }
}
