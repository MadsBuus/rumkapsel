import Foundation

enum Discovery {
    static func root(ofCheckout path: String) -> String? {
        let fm = FileManager.default
        guard let dir = GitWatch.gitDir(of: path), fm.fileExists(atPath: dir + "/HEAD"),
              let common = GitWatch.commonDir(of: path), common.hasSuffix("/.git"), fm.fileExists(atPath: common + "/HEAD") else { return nil }
        let root = String(common.dropLast(5))
        return fm.fileExists(atPath: root) ? root : nil
    }

    static func root(of path: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        var dir = URL(fileURLWithPath: path).standardizedFileURL
        while dir.path.count > 1, dir.path != home {
            if let root = root(ofCheckout: dir.path) { return root }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    static func conductor(home: URL) -> [(repo: String, root: String)] {
        let workspaces = home.appendingPathComponent("conductor/workspaces")
        let fm = FileManager.default
        guard let repos = try? fm.contentsOfDirectory(atPath: workspaces.path) else { return [] }
        var found: [(repo: String, root: String)] = []
        for repo in repos.sorted() {
            let dir = workspaces.appendingPathComponent(repo)
            let checkouts = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted().map { dir.appendingPathComponent($0).path }
            let linked = checkouts.lazy.filter { GitWatch.gitDir(of: $0)?.contains("/.git/worktrees/") == true }.compactMap(root(ofCheckout:)).first
            let besidePath = home.appendingPathComponent("dev/\(repo)").path
            let beside = root(ofCheckout: besidePath)
            let clone = checkouts.lazy.compactMap(root(ofCheckout:)).first
            if let r = linked ?? beside ?? clone { found.append((repo, r)) }
        }
        return found
    }

    static func worktrees(of root: String) -> [String] {
        guard let text = run("/usr/bin/git", ["-C", root, "worktree", "list", "--porcelain"]) else { return [] }
        return text.split(separator: "\n").filter { $0.hasPrefix("worktree ") }.map { String($0.dropFirst(9)) }
            .filter { GitWatch.real($0) != GitWatch.real(root) }
    }

    static func githubRemote(_ root: String) -> Bool {
        let names = run("/usr/bin/git", ["-C", root, "remote"])?.split(separator: "\n").map(String.init) ?? []
        return names.contains { name in
            guard let url = run("/usr/bin/git", ["-C", root, "remote", "get-url", name])?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            if url.contains("github.com") { return true }
            guard let host = sshHost(url) else { return false }
            return run("/usr/bin/ssh", ["-G", host])?.split(separator: "\n").contains { $0 == "hostname github.com" || $0 == "hostname ssh.github.com" } ?? false
        }
    }

    static func sshHost(_ url: String) -> String? {
        if url.hasPrefix("ssh://") { return URL(string: url)?.host }
        guard !url.contains("://"), let colon = url.firstIndex(of: ":") else { return nil }
        let left = url[..<colon]
        return String(left.split(separator: "@").last ?? left)
    }

    static func run(_ tool: String, _ args: [String], within seconds: Double = 3) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        let ended = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in ended.signal() }
        guard (try? p.run()) != nil else { return nil }
        if ended.wait(timeout: .now() + seconds) == .timedOut { p.terminate(); return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return p.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil
    }

    static let searchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (ProcessInfo.processInfo.environment["PATH"] ?? "")

    static let ghInstalled: Bool = {
        searchPath.split(separator: ":").contains { FileManager.default.isExecutableFile(atPath: "\($0)/gh") }
    }()
}
