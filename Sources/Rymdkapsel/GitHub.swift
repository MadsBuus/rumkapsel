import Foundation

struct PullRequest: Equatable {
    let number: Int
    let title: String
    let state: String          // OPEN, MERGED, CLOSED
    let reviewDecision: String // APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED or empty
    let isDraft: Bool
    let url: String

    var summary: String {
        var s = "PR #\(number) " + (isDraft ? "draft" : state.lowercased())
        switch reviewDecision {
        case "APPROVED": s += " · approved"
        case "CHANGES_REQUESTED": s += " · changes requested"
        case "REVIEW_REQUIRED": s += " · awaiting review"
        default: break
        }
        return s
    }
}

/// Resolves pull requests for task branches with the gh CLI, off the main thread.
final class GitHubResolver {
    private let queue = DispatchQueue(label: "rymdkapsel.github", qos: .utility)
    private var pulls: [String: (PullRequest?, Date)] = [:]
    private var commits: [String: (Int, Date)] = [:]
    private var owners: [String: String] = [:]
    private var inFlight = Set<String>()
    private let lock = NSLock()
    var onUpdate: (() -> Void)?

    func pull(branch: String, repoRoot: String) -> PullRequest? {
        lock.lock(); defer { lock.unlock() }
        return pulls[repoRoot + "@" + branch]?.0
    }

    /// Commits on the worktree's branch that are not on the default branch, or nil if unknown yet.
    func commitsAhead(worktree: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return commits[worktree]?.0
    }

    func refreshCommits(worktree: String) {
        lock.lock()
        if let (_, at) = commits[worktree], Date().timeIntervalSince(at) < 60 { lock.unlock(); return }
        if inFlight.contains("c:" + worktree) { lock.unlock(); return }
        inFlight.insert("c:" + worktree)
        lock.unlock()
        queue.async { [self] in
            var base = "origin/main"
            if let out = run(["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"], cwd: worktree),
               let name = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                base = name
            } else if run(["git", "rev-parse", "--verify", "origin/main"], cwd: worktree) == nil,
                      run(["git", "rev-parse", "--verify", "origin/master"], cwd: worktree) != nil {
                base = "origin/master"
            }
            var n = 0
            if let out = run(["git", "rev-list", "--count", "\(base)..HEAD"], cwd: worktree),
               let text = String(data: out, encoding: .utf8), let v = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                n = v
            }
            lock.lock()
            let changed = commits[worktree]?.0 != n
            commits[worktree] = (n, Date())
            inFlight.remove("c:" + worktree)
            lock.unlock()
            if changed { DispatchQueue.main.async { self.onUpdate?() } }
        }
    }

    func nameWithOwner(repoRoot: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return owners[repoRoot]
    }

    /// Refreshes stale entries; each branch at most once every two minutes.
    func refresh(branch: String, repoRoot: String) {
        let key = repoRoot + "@" + branch
        lock.lock()
        if let (_, at) = pulls[key], Date().timeIntervalSince(at) < 120 { lock.unlock(); return }
        if inFlight.contains(key) { lock.unlock(); return }
        inFlight.insert(key)
        lock.unlock()

        queue.async { [self] in
            if nameWithOwner(repoRoot: repoRoot) == nil,
               let out = run(["gh", "repo", "view", "--json", "nameWithOwner"], cwd: repoRoot),
               let obj = try? JSONSerialization.jsonObject(with: out) as? [String: Any],
               let n = obj["nameWithOwner"] as? String {
                lock.lock(); owners[repoRoot] = n; lock.unlock()
            }
            var pr: PullRequest?
            if let out = run(["gh", "pr", "list", "--head", branch, "--state", "all", "--limit", "1",
                              "--json", "number,title,state,reviewDecision,isDraft,url"], cwd: repoRoot),
               let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]],
               let o = arr.first {
                pr = PullRequest(number: o["number"] as? Int ?? 0, title: o["title"] as? String ?? "",
                                 state: o["state"] as? String ?? "", reviewDecision: o["reviewDecision"] as? String ?? "",
                                 isDraft: o["isDraft"] as? Bool ?? false, url: o["url"] as? String ?? "")
            }
            lock.lock()
            let changed = pulls[key]?.0 != pr
            pulls[key] = (pr, Date())
            inFlight.remove(key)
            lock.unlock()
            if changed { DispatchQueue.main.async { self.onUpdate?() } }
        }
    }

    private func run(_ args: [String], cwd: String) -> Data? {
        guard FileManager.default.fileExists(atPath: cwd) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }
}
