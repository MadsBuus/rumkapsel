import Foundation

struct GitChange: Equatable {
    var local = false
    var remote = false
    var tags = false
    var worktrees: Set<String> = []

    var any: Bool { local || remote || tags || !worktrees.isEmpty }

    static func of(_ paths: [String], gitDir: String) -> GitChange {
        var c = GitChange()
        for path in paths where path.hasPrefix(gitDir + "/") {
            let rel = String(path.dropFirst(gitDir.count + 1))
            if rel.hasSuffix(".lock") || rel.hasPrefix("objects/") { continue }
            let parts = rel.split(separator: "/")
            if parts.first == "worktrees", parts.count > 2 {
                let own = parts.dropFirst(2).joined(separator: "/")
                if own == "HEAD" || own == "logs/HEAD" { c.worktrees.insert(String(parts[1])) }
            } else if rel == "packed-refs" {
                c.remote = true; c.tags = true
            } else if rel.hasPrefix("refs/remotes/") || rel.hasPrefix("logs/refs/remotes/") {
                c.remote = true
            } else if rel.hasPrefix("refs/tags/") {
                c.tags = true
            } else if rel == "HEAD" || rel == "logs/HEAD" || rel.hasPrefix("refs/heads/") || rel.hasPrefix("logs/refs/heads/") {
                c.local = true
            }
        }
        return c
    }
}

final class GitWatch {
    private let watcher: DirectoryWatcher

    init(root: String, onChange: @escaping (GitChange) -> Void) {
        let dir = GitWatch.commonDir(of: root) ?? GitWatch.real(root + "/.git")
        watcher = DirectoryWatcher(path: dir, excluding: [dir + "/objects", dir + "/lfs"], debounce: 0.3) { paths in
            let c = GitChange.of(paths, gitDir: dir)
            if c.any { onChange(c) }
        }
    }

    static func real(_ path: String) -> String {
        guard let p = realpath(path, nil) else { return path }
        defer { free(p) }
        return String(cString: p)
    }

    static func gitDir(of checkout: String) -> String? {
        let dotGit = checkout + "/.git"
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDir) else { return nil }
        if isDir.boolValue { return dotGit }
        guard let text = try? String(contentsOfFile: dotGit, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir: ") }) else { return nil }
        let target = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
        return target.hasPrefix("/") ? target : (checkout + "/" + target as NSString).standardizingPath
    }

    static func commonDir(of checkout: String) -> String? {
        guard let dir = gitDir(of: checkout) else { return nil }
        guard let common = try? String(contentsOfFile: dir + "/commondir", encoding: .utf8) else { return real(dir) }
        let target = common.trimmingCharacters(in: .whitespacesAndNewlines)
        return real(target.hasPrefix("/") ? target : (dir + "/" + target as NSString).standardizingPath)
    }

    static func link(ofWorktree worktree: String) -> (root: String, name: String?)? {
        guard let dir = gitDir(of: worktree) else { return nil }
        guard let r = dir.range(of: "/.git/worktrees/") else { return (worktree, nil) }
        return (String(dir[..<r.lowerBound]), String(dir[r.upperBound...]).split(separator: "/").first.map(String.init))
    }
}
