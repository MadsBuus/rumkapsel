import Foundation

struct RepoFolder {
    struct Git: Equatable {
        var lastCommit: Date?
        var lastOwnCommit: Date?
        var changed = 0
        var untracked = 0
        var stashes = 0
        var unpushed = 0
        var branches = 0
        var worktrees = 0
        var remote: String?
    }

    let repo: String
    let root: String
    var via: World.RepoVia?
    var lastSession: Date?
    var lastActive: Date
    var offices = 0
    var crates = 0
    var github: String?
    var way: String?
    var git: Git?

    static let quietDays = 30

    static func words(_ seconds: TimeInterval) -> String {
        let units: [(TimeInterval, String)] = [(365 * 86400, "year"), (30 * 86400, "month"), (7 * 86400, "week"), (86400, "day"), (3600, "hour"), (60, "minute")]
        guard let (size, name) = units.first(where: { seconds >= $0.0 * ($0.1 == "day" || $0.1 == "hour" ? 2 : 1) }) else { return "a moment" }
        let n = Int(seconds / size)
        return "\(n) \(name)\(n == 1 ? "" : "s")"
    }

    static func readGit(root: String, run: ([String], String) -> Data?) -> Git {
        func lines(_ args: [String]) -> [String] {
            guard let d = run(args, root), let s = String(data: d, encoding: .utf8) else { return [] }
            return s.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        }
        func date(_ args: [String]) -> Date? { lines(args).first.flatMap(TimeInterval.init).map { Date(timeIntervalSince1970: $0) } }
        var g = Git()
        g.lastCommit = date(["git", "log", "--all", "-1", "--format=%ct"])
        if let me = lines(["git", "config", "user.email"]).first {
            g.lastOwnCommit = date(["git", "log", "--all", "-1", "--format=%ct", "--author=\(me)"])
        }
        let status = lines(["git", "status", "--porcelain"])
        g.untracked = status.filter { $0.hasPrefix("??") }.count
        g.changed = status.count - g.untracked
        g.stashes = lines(["git", "stash", "list"]).count
        g.unpushed = lines(["git", "log", "--branches", "--not", "--remotes", "--format=%h"]).count
        g.branches = lines(["git", "branch", "--format=%(refname:short)"]).count
        g.worktrees = max(0, lines(["git", "worktree", "list", "--porcelain"]).filter { $0.hasPrefix("worktree ") }.count - 1)
        g.remote = lines(["git", "remote", "get-url", "origin"]).first
        return g
    }

    func quietFor(now: Date) -> TimeInterval {
        now.timeIntervalSince([lastActive, git?.lastCommit ?? .distantPast].max()!)
    }

    var holdsWork: Bool { (git?.changed ?? 0) + (git?.untracked ?? 0) + (git?.stashes ?? 0) + (git?.unpushed ?? 0) > 0 }
    var download: Bool { git.map { $0.remote != nil && $0.lastOwnCommit == nil } ?? false }

    func whyHere(window: TimeInterval, now: Date) -> String {
        switch via {
        case .sessions:
            let left = lastSession.map { window - now.timeIntervalSince($0) } ?? 0
            return "A Claude session ran here, so it stays on the station"
                + (left > 0 ? " for another \(RepoFolder.words(left)) unless one runs again." : ".")
        case .conductor: return "Conductor has a workspace for it, so it stays on the station."
        case .settings: return "Settings give it a folder, so it stays on the station."
        case nil: return offices > 0 ? "It has an office on the station." : "It is on the station from an earlier session."
        }
    }

    func unsaved() -> [String] {
        guard let g = git else { return [] }
        var out: [String] = []
        if g.changed > 0 { out.append("\(g.changed) changed file\(g.changed == 1 ? "" : "s") never committed") }
        if g.untracked > 0 { out.append("\(g.untracked) new file\(g.untracked == 1 ? "" : "s") git doesn't track") }
        if g.unpushed > 0 { out.append("\(g.unpushed) commit\(g.unpushed == 1 ? "" : "s") on no remote: only on this Mac") }
        if g.stashes > 0 { out.append("\(g.stashes) stash\(g.stashes == 1 ? "" : "es")") }
        return out
    }

    func advice(now: Date) -> String? {
        guard git != nil else { return nil }
        let quiet = quietFor(now: now)
        guard quiet > Double(RepoFolder.quietDays) * 86400 else { return nil }
        let days = "Quiet for \(RepoFolder.words(quiet))"
        if holdsWork { return "\(days), but it holds work found nowhere else. Look through it before you throw it out." }
        if download { return "\(days), and you never committed here: it looks like someone else's project you downloaded. Safe to move to the Trash." }
        return "\(days), and everything is pushed. Hide it from the station, or move the folder to the Trash."
    }
}
