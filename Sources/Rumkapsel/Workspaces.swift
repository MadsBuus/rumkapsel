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
    private static var released: Set<String> = []

    /// Workspaces the registry knows and nobody holds: archived, whatever is still on the disk. A path
    /// the registry has never heard of is not in here — Conductor's are not registered, and a worktree
    /// made by hand is nobody's business but the person who made it.
    static func archived() -> Set<String> {
        let at = (try? registry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let at, at == cachedAt { return released }
        cachedAt = at
        guard let data = try? Data(contentsOf: registry),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let all = root["worktrees"] as? [String: Any] else { released = []; return [] }
        var out: Set<String> = []
        for (_, v) in all {
            guard let w = v as? [String: Any], let path = w["path"] as? String else { continue }
            if w["leasedBy"] is NSNull || w["leasedBy"] == nil { out.insert(path) }
        }
        released = out
        return out
    }

    /// Whether a workspace is still open: on the disk, and not handed back.
    static func isOpen(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path) && !archived().contains(path)
    }
}
