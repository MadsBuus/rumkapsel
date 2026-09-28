// The station log: the few things worth hearing about when you come back to the station after hours
// away — launches, deploys, QA, merges, work started. It is read out of what GitHub already told the
// station (each repository's feed, its release pull requests, the board), so it covers the hours the
// app was not running as well as the ones it was. What happened stays happened: every fact read is
// kept in the story on disk and later reads only add to it, so a feed that has scrolled on or a board
// item that has moved again takes nothing out of the log.

import Foundation

enum SpaceLog {
    /// How far back the log reaches.
    static let reach: TimeInterval = 3 * 24 * 3600

    enum Kind: String, Codable, CaseIterable, Hashable {
        case launch, staging, deck, cleared, merged, opened, started
    }

    /// One thing that happened. `what` says it without numbers, so a burst of the same thing folds into
    /// one line; `items` are the numbers and titles it happened to.
    struct Entry: Codable, Equatable {
        /// What makes it the same fact when it is read again: kind, repository, number, and for the board the column.
        var key: String
        var at: Date
        var kind: Kind
        var repo: String?
        var what: String
        var items: [String]
        /// Who did it, where the line is someone's doing: "you", or a teammate's name.
        var who: String? = nil

        /// A release's own line — its title, or "release #5365" — once the issues it carried have become its items.
        var note: String? = nil

        /// An issue the board calls shipped, as against the release that shipped it.
        var isShipped: Bool { kind == .launch && what == "shipped" }
        var isRelease: Bool { kind == .staging || (kind == .launch && !isShipped) }

        /// The station's own shape for what happened: a rocket for a launch, a crate for anything that
        /// moves one, a ticked crate for one that passed, a hex for an office, a cone for a new job.
        enum Shape { case rocket, crate, checked, office, order }
        var shape: Shape {
            switch kind {
            case .launch: return isShipped ? .crate : .rocket
            case .cleared: return .checked
            case .started: return what.startedCount > 0 || (!key.hasPrefix("gathered|") && !what.hasSuffix("filed an issue")) ? .office : .order
            default: return .crate
            }
        }

        /// The line as the station says it: who, and what they did in the station's own words — crates
        /// packed, put in storage, sent to the deck, lifted off. The name comes apart so it can be set in
        /// its own weight; a line with nobody to name starts with its first word capitalised.
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

    /// Where a line of the log leads: its repository and, where the line names one, its number.
    struct Target: Hashable {
        var kind: Kind
        var repo: String
        var number: Int?

        /// Read off a line's item: "#5331 Ban does nothing", "release #5352", or a bare release title.
        init(kind: Kind, repo: String, item: String) {
            self.kind = kind
            self.repo = repo
            number = item.firstMatch(of: #/#(\d+)/#).flatMap { Int($0.1) }
        }
    }

    /// What one repository has told the station.
    struct Repo {
        var name: String
        var feed: [FeedEvent]
        var releases: [ReleasePR]
    }

    /// The facts the log is read out of.
    struct Facts {
        var repos: [Repo]
        var board: [ProjectItem]
        var statuses: AppConfig.ProjectStatuses
        /// Your own login, so your work reads as yours.
        var me: String?
        var name: (String) -> String = { $0 }
        /// A title for a number, where the feed brought none: GitHub's feed carries numbers only.
        var title: (_ repo: String, _ number: Int) -> String? = { _, _ in nil }
        /// Whether a pull request from this branch is a release: the same test the rockets use.
        var isReleaseBranch: (_ repo: String, _ branch: String) -> Bool = { _, _ in false }
    }

    /// Every release pull request the facts know of, by repository: the release list's, and any the feed
    /// shows coming from a release branch.
    static func releaseNumbers(_ f: Facts) -> [String: Set<Int>] {
        var out: [String: Set<Int>] = [:]
        for r in f.repos {
            out[r.name] = Set(r.releases.map(\.number).filter { $0 > 0 })
            for e in r.feed { if let n = e.prNumber, let b = e.branch, f.isReleaseBranch(r.name, b) { out[r.name, default: []].insert(n) } }
        }
        return out
    }

    /// Everything since `since`, oldest first. Release pull requests are launches and deploys, never
    /// merges; the board says what reached QA, passed it and shipped; the feed says who merged, opened
    /// and filed what.
    static func read(_ f: Facts, since: Date) -> [Entry] {
        var out: [Entry] = []
        func who(_ login: String) -> String { login == f.me ? "you" : f.name(login) }
        let releases = releaseNumbers(f)
        for r in f.repos {
            let releaseNumbers = releases[r.name] ?? []
            for pr in r.releases where pr.state == "MERGED" {
                guard let at = pr.mergedAt, at > since else { continue }
                // Who pressed merge on the release: the feed has it, the release pull request does not.
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
        // A board item says where it is and when it last changed, not every column it passed through:
        // enough to say where each one got to while you were away.
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

    /// How close a board move must be to a release to have gone out with it.
    static let carried: TimeInterval = 30 * 60

    /// A release's cargo: the board's shipped issues go into the launch they left with, and the issues
    /// that reached QA into the staging deploy that took them there, as the release's own items. A
    /// board move no release accounts for stays a line of its own.
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

    /// Issues filed and started are gathered into one line per person, repository and day: "Leo filed 3
    /// issues · started 2". Everything else passes as it came.
    static func gather(_ entries: [Entry], calendar: Calendar = .current) -> [Entry] {
        var out: [Entry] = []
        var at: [String: Int] = [:]
        for e in entries.sorted(by: { $0.at < $1.at }) {
            guard e.kind == .started else { out.append(e); continue }
            let key = "\(calendar.startOfDay(for: e.at).timeIntervalSince1970)|\(e.repo ?? "")|\(e.who ?? "")"
            let filed = e.what.hasSuffix("filed an issue")
            // Folded before it gets here, a line may already stand for several of the same.
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

    /// A gathered line's counts, which `sentence` puts into words.
    private static func gatheredWhat(filed: Int, started: Int) -> String { "filed \(filed) · started \(started)" }

    /// Entries of the same kind, repository and wording within this long of each other are one burst.
    static let burst: TimeInterval = 20 * 60

    /// Oldest first in, oldest first out, with each burst folded into its first entry's line.
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

    /// A stretch where a repository's feed had scrolled on before the station read it: GitHub keeps a
    /// busy repository's last few hundred events, so a weekend away can outrun it.
    struct Gap: Codable, Equatable {
        var repo: String
        var from: Date
        var to: Date
    }

    /// Everything the station has read so far, and when you last read it.
    struct Story: Codable, Equatable {
        var entries: [Entry] = []
        var readAt: Date?
        /// Per repository, the newest feed event already taken in: where the next read must reach back to.
        var seen: [String: Date] = [:]
        var gaps: [Gap] = []

        /// Takes in a fresh read. A fact already in the story stands as it was; all a later read may add to
        /// one is the title a bare number lacked, or who did it. The one fact taken back is a release pull
        /// request that was read as work before it was known for a release. True when anything changed.
        mutating func add(_ fresh: [Entry], feeds: [Repo], now: Date, releases: [String: Set<Int>] = [:]) -> Bool {
            var changed = false
            // A release pull request read as ordinary work before it was known for one: it never was.
            let before = entries.count
            entries.removeAll { e in
                guard e.kind == .merged || e.kind == .opened, let repo = e.repo, let known = releases[repo] else { return false }
                return e.items.contains { Target(kind: e.kind, repo: repo, item: $0).number.map(known.contains) == true }
            }
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
                // A full feed that starts after what was last seen skipped something in between.
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

    /// How long the story is kept on disk.
    static let keep: TimeInterval = 30 * 24 * 3600
}

/// The story on disk, `spacelog.json` beside the station's settings. Added to on the scene's thread,
/// read on the main one, so every touch is under the lock.
final class StoryBook {
    static let shared = StoryBook()
    private let lock = NSLock()
    private var story: SpaceLog.Story?
    private var url: URL { AppSupport.root.appendingPathComponent("Rumkapsel", isDirectory: true).appendingPathComponent("spacelog.json") }
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    /// Called with the lock held.
    private func loaded() -> SpaceLog.Story {
        if let story { return story }
        let s = (try? Data(contentsOf: url)).flatMap { try? Self.decoder.decode(SpaceLog.Story.self, from: $0) } ?? SpaceLog.Story()
        story = s
        return s
    }

    var current: SpaceLog.Story { lock.lock(); defer { lock.unlock() }; return loaded() }

    /// Changes the story and writes it down when anything changed; says whether it did.
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
    /// The counts a gathered line carries: "filed 3 · started 2".
    var filedCount: Int { firstMatch(of: #/filed (\d+)/#).flatMap { Int($0.1) } ?? 0 }
    var startedCount: Int { firstMatch(of: #/started (\d+)/#).flatMap { Int($0.1) } ?? 0 }
}
