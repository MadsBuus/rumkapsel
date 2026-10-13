import Foundation

enum Workspaces {
    private static let registry = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/git-worktrees.json")

    private static var cachedAt: Date?
    private static var open: Set<String> = []
    private static let lock = NSLock()

    private static func held() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        let at = (try? FileManager.default.attributesOfItem(atPath: registry.path))?[.modificationDate] as? Date
        if let at, at == cachedAt { return open }
        guard FileManager.default.fileExists(atPath: registry.path) else { cachedAt = at; open = []; return [] }
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

    private static let sessionFiles = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    private static var sessionsReadAt: Date?
    private static var checkouts: [String: Bool] = [:]

    private static func sessionFolders() -> [String: Bool] {
        lock.lock(); defer { lock.unlock() }
        if let t = sessionsReadAt, Date().timeIntervalSince(t) < 10 { return checkouts }
        sessionsReadAt = Date()
        var out: [String: Bool] = [:]
        let files = FileManager.default.enumerator(at: sessionFiles, includingPropertiesForKeys: nil)
        while let f = files?.nextObject() as? URL {
            guard f.lastPathComponent.hasPrefix("local_"), f.pathExtension == "json",
                  let data = try? Data(contentsOf: f),
                  let session = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cwd = session["cwd"] as? String else { continue }
            let folder = (cwd as NSString).standardizingPath
            out[folder] = (out[folder] ?? false) || (session["isArchived"] as? Bool) != true
        }
        checkouts = out
        return out
    }

    static func isOpen(_ path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        guard path.contains("/.claude/worktrees/") else { return sessionFolders()[(path as NSString).standardizingPath] ?? true }
        if (path as NSString).lastPathComponent.hasPrefix("agent-") { return false }
        return held().contains(path)
    }
}
