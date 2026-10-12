import Foundation

enum SpaceLog {
    static let reach: TimeInterval = 3 * 24 * 3600

    enum Kind: String, Codable, CaseIterable, Hashable {
        case launch, staging, deck, cleared, merged, opened, started
    }

    struct Entry: Codable, Equatable {
        var key: String
        var at: Date
        var kind: Kind
        var repo: String?
        var what: String
        var items: [String]
        var who: String? = nil

        var note: String? = nil

        var isShipped: Bool { kind == .launch && what == "shipped" }
        var isRelease: Bool { kind == .staging || (kind == .launch && !isShipped) }
        var releaseID: String? {
            guard isRelease else { return nil }
            let p = key.split(separator: ":", maxSplits: 3)
            return p.count >= 3 ? "\(p[1]):\(p[2])" : nil
        }

        enum Shape { case rocket, crate, checked, office, order }
        var shape: Shape {
            switch kind {
            case .launch: return isShipped ? .crate : .rocket
            case .cleared: return .checked
            case .started: return what.startedCount > 0 || (!key.hasPrefix("gathered|") && !what.hasSuffix("filed an issue")) ? .office : .order
            default: return .crate
            }
        }

        var sentence: (who: String?, rest: String) {
            let v = Words.current
            let n = items.count
            func crates(_ c: Int) -> String { c == 1 ? "a \(v.crate)" : "\(c) \(v.crates)" }
            func capital(_ t: String) -> String { t.prefix(1).uppercased() + t.dropFirst() }
            switch kind {
            case .launch where isShipped: return (nil, capital("\(crates(n)) shipped"))
            case .launch: return (nil, (repo ?? "The \(v.theRocket)") + " \(v.liftedOff)" + (note == nil ? "" : ", \(crates(n)) \(v.aboard)"))
            case .staging:
                let load = note == nil ? "a load" : crates(n)
                return who.map { ($0, "sent \(load) to \(v.theDeck)") } ?? (nil, capital("\(load) went to \(v.theDeck)"))
            case .deck: return (nil, capital("\(crates(n)) reached \(v.theDeck)"))
            case .cleared: return (nil, capital("\(crates(n)) \(v.passedInspection)"))
            case .merged: return (who, (who == nil ? "Put " : "put ") + "\(crates(n)) in \(v.inStorage)")
            case .opened: return (who, (who == nil ? "Packed " : "packed ") + crates(n))
            case .started:
                let filed = key.hasPrefix("gathered|") ? what.filedCount : what.hasSuffix("filed an issue") ? n : 0
                let started = key.hasPrefix("gathered|") ? what.startedCount : filed == 0 ? n : 0
                let parts = [filed > 0 ? "logged \(filed == 1 ? "a new \(v.job)" : "\(filed) new \(v.jobs)")" : nil,
                             started > 0 ? "opened \(started == 1 ? "an \(v.office)" : "\(started) \(v.offices)")" : nil].compactMap { $0 }
                let rest = parts.joined(separator: " and ")
                return who == nil ? (nil, capital(rest)) : (who, rest)
            }
        }
    }

    struct Target: Hashable {
        var kind: Kind
        var repo: String
        var number: Int?

        init(kind: Kind, repo: String, item: String) {
            self.kind = kind
            self.repo = repo
            number = item.firstMatch(of: #/#(\d+)/#).flatMap { Int($0.1) }
        }
    }

    struct Repo {
        var name: String
        var feed: [FeedEvent]
        var releases: [ReleasePR]
    }

    struct Facts {
        var repos: [Repo]
        var board: [ProjectItem]
        var statuses: AppConfig.ProjectStatuses
        var me: String?
        var name: (String) -> String = { $0 }
        var title: (_ repo: String, _ number: Int) -> String? = { _, _ in nil }
        var isReleaseBranch: (_ repo: String, _ branch: String) -> Bool = { _, _ in false }
    }

    static func releaseNumbers(_ f: Facts) -> [String: Set<Int>] {
        var out: [String: Set<Int>] = [:]
        for r in f.repos {
            out[r.name] = Set(r.releases.map(\.number).filter { $0 > 0 })
            for e in r.feed { if let n = e.prNumber, let b = e.branch, f.isReleaseBranch(r.name, b) { out[r.name, default: []].insert(n) } }
        }
        return out
    }

    static func read(_ f: Facts, since: Date) -> [Entry] {
        var out: [Entry] = []
        func who(_ login: String) -> String { login == f.me ? "you" : f.name(login) }
        let releases = releaseNumbers(f)
        for r in f.repos {
            let releaseNumbers = releases[r.name] ?? []
            for pr in r.releases where pr.state == "MERGED" {
                guard let at = pr.mergedAt, at > since else { continue }
                let by = r.feed.first { $0.kind == "pr_merge" && $0.prNumber == pr.number && pr.number > 0 }.map { who($0.actor) }
                if pr.isProduction {
                    out.append(Entry(key: "launch:\(r.name):\(pr.number):\(pr.title)", at: at, kind: .launch, repo: r.name, what: "\(Words.current.launchedTo) production", items: [pr.title], who: by))
                } else if pr.isStaging {
                    out.append(Entry(key: "staging:\(r.name):\(pr.number)", at: at, kind: .staging, repo: r.name, what: "deployed to staging", items: ["release #\(pr.number)"], who: by))
                }
            }
            for e in r.feed where e.at > since && !e.isBot {
                guard let n = e.prNumber, !releaseNumbers.contains(n) else { continue }
                let label = "#\(n)" + ((e.title ?? f.title(r.name, n)).map { " " + $0 } ?? "")
                switch e.kind {
                case "pr_merge": out.append(Entry(key: "merged:\(r.name):\(n)", at: e.at, kind: .merged, repo: r.name, what: "\(who(e.actor)) merged", items: [label], who: who(e.actor)))
                case "pr_open": out.append(Entry(key: "opened:\(r.name):\(n)", at: e.at, kind: .opened, repo: r.name, what: "\(who(e.actor)) opened a pull request", items: [label], who: who(e.actor)))
                case "issue_open": out.append(Entry(key: "filed:\(r.name):\(n)", at: e.at, kind: .started, repo: r.name, what: "\(who(e.actor)) filed an issue", items: [label], who: who(e.actor)))
                default: break
                }
            }
        }
        let repos = Set(f.repos.map(\.name))
        for item in f.board where repos.contains(item.repo) {
            guard let at = item.updatedAt, at > since else { continue }
            let label = "#\(item.number) \(item.title)"
            let key = "board:\(item.repo):\(item.number):\(item.status)"
            switch f.statuses.stage(of: item.status) {
            case .deck: out.append(Entry(key: key, at: at, kind: .deck, repo: item.repo, what: "in QA", items: [label]))
            case .cleared: out.append(Entry(key: key, at: at, kind: .cleared, repo: item.repo, what: "passed QA", items: [label]))
            case .shipped: out.append(Entry(key: key, at: at, kind: .launch, repo: item.repo, what: "shipped", items: [label]))
            case .development:
                let by = item.assignees.first.map(who)
                out.append(Entry(key: key, at: at, kind: .started, repo: item.repo, what: (by.map { $0 + " " } ?? "") + "started", items: [label], who: by))
            default: break
            }
        }
        return out.sorted { $0.at < $1.at }
    }

    static let carried: TimeInterval = 30 * 60

    static func rollUp(_ entries: [Entry]) -> [Entry] {
        var out = entries.sorted { $0.at < $1.at }
        var claimed = Set<String>()
        for i in out.indices where out[i].isRelease {
            let r = out[i]
            let cargo = out.filter { e in
                !claimed.contains(e.key) && e.repo == r.repo && abs(e.at.timeIntervalSince(r.at)) <= carried
                    && (r.kind == .launch ? e.isShipped : e.kind == .deck)
            }
            guard !cargo.isEmpty else { continue }
            cargo.forEach { claimed.insert($0.key) }
            out[i].note = r.items.first
            out[i].items = cargo.flatMap(\.items).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        }
        return out.filter { !claimed.contains($0.key) }
    }

    static func gather(_ entries: [Entry], calendar: Calendar = .current) -> [Entry] {
        var out: [Entry] = []
        var at: [String: Int] = [:]
        for e in entries.sorted(by: { $0.at < $1.at }) {
            guard e.kind == .started else { out.append(e); continue }
            let key = "\(calendar.startOfDay(for: e.at).timeIntervalSince1970)|\(e.repo ?? "")|\(e.who ?? "")"
            let filed = e.what.hasSuffix("filed an issue")
            if let i = at[key] {
                out[i].at = e.at
                for item in e.items where !out[i].items.contains(item) { out[i].items.append(item) }
                let (f, s) = (out[i].what.filedCount + (filed ? e.items.count : 0), out[i].what.startedCount + (filed ? 0 : e.items.count))
                out[i].what = gatheredWhat(filed: f, started: s)
            } else {
                var g = e
                g.key = "gathered|" + key
                g.what = gatheredWhat(filed: filed ? e.items.count : 0, started: filed ? 0 : e.items.count)
                at[key] = out.count
                out.append(g)
            }
        }
        return out
    }

    private static func gatheredWhat(filed: Int, started: Int) -> String { "filed \(filed) · started \(started)" }

    static let burst: TimeInterval = 20 * 60

    static func fold(_ entries: [Entry]) -> [Entry] {
        var out: [Entry] = []
        var lastAt: [Int: Date] = [:]
        for e in entries.sorted(by: { $0.at < $1.at }) {
            if let i = out.lastIndex(where: { $0.kind == e.kind && $0.repo == e.repo && $0.what == e.what }),
               let last = lastAt[i], e.at.timeIntervalSince(last) <= burst {
                for item in e.items where !out[i].items.contains(item) { out[i].items.append(item) }
                lastAt[i] = e.at
            } else {
                out.append(e)
                lastAt[out.count - 1] = e.at
            }
        }
        return out
    }

    struct Gap: Codable, Equatable {
        var repo: String
        var from: Date
        var to: Date
    }

    struct Story: Codable, Equatable {
        var entries: [Entry] = []
        var readAt: Date?
        var seen: [String: Date] = [:]
        var gaps: [Gap] = []

        mutating func add(_ fresh: [Entry], feeds: [Repo], now: Date, releases: [String: Set<Int>] = [:]) -> Bool {
            var changed = false
            let before = entries.count
            entries.removeAll { e in
                guard e.kind == .merged || e.kind == .opened, let repo = e.repo, let known = releases[repo] else { return false }
                return e.items.contains { Target(kind: e.kind, repo: repo, item: $0).number.map(known.contains) == true }
            }
            let releaseKind = Dictionary(fresh.filter(\.isRelease).compactMap { e in e.releaseID.map { ($0, e.kind) } }, uniquingKeysWith: { a, _ in a })
            entries.removeAll { e in e.isRelease && e.releaseID.flatMap { releaseKind[$0] }.map { $0 != e.kind } == true }
            if entries.count != before { changed = true }
            var index = Dictionary(entries.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { a, _ in a })
            for e in fresh {
                if let i = index[e.key] {
                    let old = entries[i].items, new = e.items
                    if old.count == 1, new.count == 1, new[0].count > old[0].count, new[0].hasPrefix(old[0]) {
                        entries[i].items = new; changed = true
                    }
                    if entries[i].who == nil, let who = e.who { entries[i].who = who; changed = true }
                } else {
                    index[e.key] = entries.count
                    entries.append(e); changed = true
                }
            }
            for r in feeds where !r.feed.isEmpty {
                let oldest = r.feed.map(\.at).min()!, newest = r.feed.map(\.at).max()!
                if let last = seen[r.name], r.feed.count >= 100, oldest > last {
                    gaps.append(Gap(repo: r.name, from: last, to: oldest)); changed = true
                }
                if newest > (seen[r.name] ?? .distantPast) { seen[r.name] = newest; changed = true }
            }
            let floor = now.addingTimeInterval(-SpaceLog.keep)
            let kept = entries.count + gaps.count
            entries.removeAll { $0.at < floor }
            gaps.removeAll { $0.to < floor }
            if entries.count + gaps.count != kept { changed = true }
            return changed
        }
    }

    static let keep: TimeInterval = 30 * 24 * 3600
}

final class StoryBook {
    static let shared = StoryBook()
    private let lock = NSLock()
    private var story: SpaceLog.Story?
    private var url: URL { AppSupport.root.appendingPathComponent("Rumkapsel", isDirectory: true).appendingPathComponent("spacelog.json") }
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    private func loaded() -> SpaceLog.Story {
        if let story { return story }
        let s = (try? Data(contentsOf: url)).flatMap { try? Self.decoder.decode(SpaceLog.Story.self, from: $0) } ?? SpaceLog.Story()
        story = s
        return s
    }

    var current: SpaceLog.Story { lock.lock(); defer { lock.unlock() }; return loaded() }

    @discardableResult
    func update(_ change: (inout SpaceLog.Story) -> Bool) -> Bool {
        lock.lock()
        var s = loaded()
        let changed = change(&s)
        story = s
        lock.unlock()
        guard changed, let data = try? Self.encoder.encode(s) else { return changed }
        let url = url
        Fleet.writing.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        return true
    }
}

extension String {
    var filedCount: Int { firstMatch(of: #/filed (\d+)/#).flatMap { Int($0.1) } ?? 0 }
    var startedCount: Int { firstMatch(of: #/started (\d+)/#).flatMap { Int($0.1) } ?? 0 }
}
