// Which workspaces are still somebody's.
//
// A workspace is archived in two different ways depending on what made it. Conductor deletes the
// worktree, so the directory going missing is the whole signal. Claude Code leaves the directory where
// it is and drops its lease in the desktop app's registry — so a station that only watched the disk kept
// an office for every workspace ever opened, and the desk filled with rooms nobody had.
//
// Read on every scan, off a file that changes rarely, so it is only parsed when it has moved.

import Foundation

enum Workspaces {
    private static let registry = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/git-worktrees.json")

    private static var cachedAt: Date?
    private static var open: Set<String> = []
    /// Asked from the scan's queue and from the frame's.
    private static let lock = NSLock()

    /// The workspaces the desktop app is holding. It drops the entry when a session is deleted and only
    /// the lease when one is archived, so a path it does not name is neither: it is a directory left
    /// behind. Ten worktrees on this checkout, four of them named.
    private static func held() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        // Asked of the disk each time: a URL keeps the first answer it got, and the registry would never change again.
        let at = (try? FileManager.default.attributesOfItem(atPath: registry.path))?[.modificationDate] as? Date
        if let at, at == cachedAt { return open }
        guard FileManager.default.fileExists(atPath: registry.path) else { cachedAt = at; open = []; return [] }
        // Caught half-written: the last whole answer stands until the next change.
        guard let data = try? Data(contentsOf: registry),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let all = root["worktrees"] as? [String: Any] else { return open }
        cachedAt = at
        var out: Set<String> = []
        for (_, v) in all {
            guard let w = v as? [String: Any], let path = w["path"] as? String else { continue }
            if let l = w["leasedBy"], !(l is NSNull) { out.insert(path) }
        }
        open = out
        return out
    }

    /// Whether a workspace is still somebody's.
    ///
    /// A worktree the desktop app made is under `.claude/worktrees`, and there the registry is the only
    /// word that counts: archived drops the lease, deleted drops the entry, and neither touches the
    /// directory. A subagent's worktree is not a workspace at all and never earns an office.
    ///
    /// Everything else — the checkout itself, a Conductor workspace, a worktree made by hand — is not in
    /// the registry and never will be, so for those the directory is still the whole signal.
    static func isOpen(_ path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        guard path.contains("/.claude/worktrees/") else { return true }
        if (path as NSString).lastPathComponent.hasPrefix("agent-") { return false }
        return held().contains(path)
    }
}
