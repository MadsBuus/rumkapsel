import Foundation

enum CrateStory {
    enum Line: Equatable {
        case step(at: String, what: String, why: String)
        case wait(String)
    }

    struct Told: Equatable {
        var lines: [Line] = []
        var footer: String?
    }

    static let unknown = "before the log began"

    static func tell(_ history: [EventLog.Step], now: Date, current: CrateFact?) -> Told {
        let steps = history.filter(\.moved)
        var told = Told()
        let start = steps.first.map(\.from) ?? current
        var here = start
        var since: Date?
        if let here { told.lines.append(.step(at: "", what: place(here), why: unknown)) }
        for s in steps {
            if let since, let here, s.at.timeIntervalSince(since) >= 60 { told.lines.append(.wait("\(place(here)) \(span(s.at.timeIntervalSince(since)))")) }
            told.lines.append(.step(at: clock(s.at, now: now), what: what(s), why: why(s)))
            here = s.to
            since = s.at
        }
        if let here, let since { told.lines.append(.wait("\(place(here)) for \(span(now.timeIntervalSince(since))) so far")) }
        told.footer = lead(steps, from: start, now: now, still: here != nil)
        return told
    }

    private static func lead(_ steps: [EventLog.Step], from start: CrateFact?, now: Date, still: Bool) -> String? {
        func yard(_ c: CrateFact?) -> Bool {
            switch c?.place {
            case .waiting, .testing, .cleared, .aboard: return true
            default: return false
            }
        }
        func aboard(_ c: CrateFact?) -> Bool { if case .aboard = c?.place { return true }; return false }
        let before = yard(start)
        let merged = before ? nil : steps.first { yard($0.to) && !yard($0.from) }
        let launched = steps.first { aboard($0.to) }
        switch (merged, launched) {
        case (let m?, let l?): return m.at == l.at ? "to production on merge" : "merged to production in \(span(l.at.timeIntervalSince(m.at)))"
        case (nil, _?): return before ? "to production, merged \(unknown)" : nil
        case (let m?, nil): return still ? "on its way to production for \(span(now.timeIntervalSince(m.at))) so far" : nil
        case (nil, nil): return before && still ? "on its way to production since \(unknown)" : nil
        }
    }

    static func place(_ c: CrateFact) -> String {
        let w = Words.current
        switch c.place {
        case .office: return "in its \(w.office)"
        case .waiting: return "in \(w.inStorage)"
        case .testing: return "on \(w.theDeck)"
        case .cleared: return "on \(w.testedRow)"
        case .decon: return "in \(w.inDecon)"
        case .aboard: return w.aboard
        }
    }

    static func what(_ s: EventLog.Step) -> String {
        let w = Words.current
        guard let to = s.to else {
            switch s.from?.place {
            case .aboard: return w.liftedOff
            case .decon: return w.ejected
            default: return s.from?.closedAt != nil ? "closed unmerged, gone" : "gone"
            }
        }
        if s.from?.place == to.place, let stage = to.stage {
            switch stage {
            case .inbound, .working: return "at work"
            case .ready: return "pull request open"
            case .stored: return "merged"
            case .qa: return "in testing"
            case .cleared: return "tested"
            case .shipped: return "shipped"
            }
        }
        switch to.place {
        case .office:
            switch to.stage {
            case .ready?: return "pull request open, in its \(w.office)"
            case let stage? where stage >= .stored: return "merged, in its \(w.office)"
            default: return "at work in its \(w.office)"
            }
        case .waiting:
            switch s.from?.place {
            case .testing?, .cleared?: return "back to \(w.inStorage)"
            case .decon?: return w.clearedDecon
            default: return "merged, to \(w.inStorage)"
            }
        case .testing: return s.from?.place == .cleared ? "back to \(w.theDeck)" : "to \(w.theDeck) for testing"
        case .cleared: return "tested, to \(w.testedRow)"
        case .decon: return "arrived in \(w.inDecon)"
        case .aboard(let rocket): return "\(w.aboard) \(rocketWords(rocket))"
        }
    }

    static func why(_ s: EventLog.Step) -> String {
        if let b = s.baseline { return b == "start" || b == "migrated" ? "while the station was closed" : "" }
        guard let e = s.event else { return "" }
        switch e {
        case .work(let news):
            switch news.by {
            case .board?: return news.stage == .cleared ? "the tester" : "the board"
            case .git?:
                if news.stage == .qa { return s.staging.map { "staging release #\($0)" } ?? "the staging release" }
                return news.stage == .shipped ? "the release" : "git"
            case .pulls?: return news.stage == .cleared ? "the production release" : "its pull request"
            case .session?: return "a session"
            case .deploy?: return "the deploy"
            case .neighbour?: return "a neighbour"
            case nil: return ""
            }
        case .staging(_, .merged(let n)): return "staging release #\(n)"
        case .staging: return "the staging release"
        case .launched(_, let hotfix, _, let label):
            if let hotfix { return "hotfix #\(hotfix)" }
            return label.firstMatch(of: #/ · #(\d+)/#).map { "production release #\($0.1)" } ?? "the production release"
        case .release: return "the production release"
        case .hotfixes: return "a hotfix"
        case .decon: return "a pull request from outside"
        case .deconClosed: return "closed unscreened"
        case .renumbered: return "a new number"
        case .office(.gone): return "its \(Words.current.office) closed"
        case .office: return "its \(Words.current.office)"
        case .policy: return "the repository's way to production"
        case .sweep: return "a count of the yard"
        case .restack: return "a restack"
        case .tick: return ""
        }
    }

    private static func rocketWords(_ id: RocketID) -> String {
        let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return "a rocket" }
        let kind = parts[1].split(separator: "#").first.map(String.init) ?? ""
        return "\(parts[0])'s " + (kind == "release" || kind == "hotfix" ? "\(kind) rocket" : "rocket")
    }

    static func span(_ seconds: TimeInterval) -> String {
        let m = Int(max(0, seconds) / 60)
        if m < 1 { return "under a minute" }
        if m < 60 { return "\(m) min" }
        let h = m / 60, d = h / 24
        if d == 0 { return m % 60 == 0 ? "\(h) h" : "\(h) h \(m % 60) min" }
        return h % 24 == 0 ? "\(d) d" : "\(d) d \(h % 24) h"
    }

    static func clock(_ at: Date, now: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(at, inSameDayAs: now) { return hhmm.string(from: at) }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: at), to: cal.startOfDay(for: now)).day ?? 0
        return (days < 7 && days > 0 ? weekday : dated).string(from: at)
    }

    private static func format(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.dateFormat = f
        return d
    }
    private static let hhmm = format("HH:mm"), weekday = format("EEE HH:mm"), dated = format("d MMM HH:mm")
}
