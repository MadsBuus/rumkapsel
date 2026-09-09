import Foundation

/// What a session is doing right now, as far as its transcript tells us.
enum Activity: Equatable {
    case researching, exploring, coding(String), testing, running, shipping, skill(String), planning, delegating
    case writing, thinking, reading, waiting, sleeping, qa

    var label: String {
        switch self {
        case .researching: return "web research"
        case .exploring: return "reading code"
        case .coding(let a): return "coding " + a
        case .testing: return "testing"
        case .running: return "running"
        case .shipping: return "shipping"
        case .skill(let s): return "skill " + s
        case .planning: return "planning"
        case .delegating: return "delegating"
        case .writing: return "writing"
        case .thinking: return "thinking"
        case .reading: return "reading"
        case .waiting: return "waiting for you"
        case .sleeping: return "sleeping"
        case .qa: return "QA testing"
        }
    }
}

enum StationEvent: String { case prOpened, merged, committed, pushed, skill, tool, prompt }

struct SessionInfo {
    let id: String
    let cwd: String
    let repo: String
    let repoRoot: String?
    let owner: String?          // GitHub owner of the origin remote, lowercased
    let lastModified: Date
    let activity: Activity
    let area: String?
    let title: String?
    let branch: String?
    let toolCount: Int
    let isSubagent: Bool
    let cwdExists: Bool
    let promptCount: Int       // your messages seen in the tail
    let queuedCount: Int       // messages still waiting in the queue
    /// Marker of the newest record for each event kind, so the scene can detect fresh ones.
    let eventMarkers: [StationEvent: String]
}

struct ScanResult {
    /// Every session touched within the rooms window; the scene decides which are live.
    var sessions: [SessionInfo] = []
}

/// Reads the tails of Claude Code transcripts and turns them into session facts.
final class TranscriptScanner {
    private struct Parsed {
        var cwd: String?
        var branch: String?
        var title: String?
        var toolCount = 0
        var promptCount = 0
        var queued = 0
        var activity: Activity = .waiting
        var currentSkill: String?
        var area: String?
        var markers: [StationEvent: String] = [:]
    }

    private let projectsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
    private var cache: [String: (mtime: Date, parsed: Parsed)] = [:]
    private var repoCache: [String: (name: String, root: String?)] = [:]
    private var ownerCache: [String: String?] = [:]

    func scan(roomsWithin: TimeInterval) -> ScanResult {
        var result = ScanResult()
        let now = Date()
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) else { return result }

        for project in projects {
            guard let files = fm.enumerator(at: project, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { continue }
            for case let url as URL in files {
                guard url.pathExtension == "jsonl",
                      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true,
                      let mtime = values.contentModificationDate else { continue }
                let age = now.timeIntervalSince(mtime)
                guard age < roomsWithin else { continue }

                let path = url.path
                let parsed: Parsed
                if let hit = cache[path], hit.mtime == mtime {
                    parsed = hit.parsed
                } else {
                    parsed = parseTail(url: url)
                    cache[path] = (mtime, parsed)
                }
                guard let cwd = parsed.cwd else { continue }
                let repo = repoInfo(for: cwd)
                let isSub = url.deletingLastPathComponent() != project
                result.sessions.append(SessionInfo(
                    id: path, cwd: cwd, repo: repo.name, repoRoot: repo.root, owner: repo.root.flatMap(remoteOwner(for:)), lastModified: mtime, activity: parsed.activity, area: parsed.area,
                    title: parsed.title, branch: parsed.branch, toolCount: parsed.toolCount, isSubagent: isSub,
                    cwdExists: fm.fileExists(atPath: cwd), promptCount: parsed.promptCount, queuedCount: max(0, parsed.queued), eventMarkers: parsed.markers))
            }
        }
        return result
    }

    /// The repository a directory belongs to, seeing through git worktrees (Conductor workspaces).
    func repoInfo(for cwd: String) -> (name: String, root: String?) {
        if let r = repoCache[cwd] { return r }
        var root: String?
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var name = URL(fileURLWithPath: cwd).lastPathComponent
        if cwd == home { name = "home" }
        let parts = cwd.split(separator: "/").map(String.init)
        if let i = parts.firstIndex(of: "conductor"), i + 2 < parts.count, parts[i + 1] == "workspaces" { name = parts[i + 2] }
        var dir = URL(fileURLWithPath: cwd)
        var isDir: ObjCBool = false
        while dir.path.count > 1 && dir.path != home {
            let git = dir.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: git.path, isDirectory: &isDir) {
                root = dir.path
                if isDir.boolValue {
                    name = dir.lastPathComponent
                } else if let text = try? String(contentsOf: git, encoding: .utf8),
                          let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) {
                    let target = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
                    if let r = target.range(of: "/.git/worktrees/") {
                        // A worktree: the repository is the main checkout it was created from.
                        let main = String(target[..<r.lowerBound])
                        name = URL(fileURLWithPath: main).lastPathComponent
                        root = main
                    } else {
                        name = dir.lastPathComponent
                    }
                }
                break
            }
            dir = dir.deletingLastPathComponent()
        }
        repoCache[cwd] = (name, root)
        return (name, root)
    }

    /// The GitHub owner in the origin remote of a repository, read from its git config.
    func remoteOwner(for root: String) -> String? {
        if let cached = ownerCache[root] { return cached }
        var owner: String?
        if let text = try? String(contentsOfFile: root + "/.git/config", encoding: .utf8) {
            for line in text.split(separator: "\n") where line.contains("url =") && line.contains("github.com") {
                let url = line.split(separator: "=", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                let tail = url.replacingOccurrences(of: "git@github.com:", with: "").replacingOccurrences(of: "https://github.com/", with: "")
                owner = tail.split(separator: "/").first.map { String($0).lowercased() }
                break
            }
        }
        ownerCache[root] = owner
        return owner
    }

    private static let sourceRoots: Set<String> = ["src", "app", "apps", "lib", "libs", "packages", "modules", "Sources", "Tests", "test", "tests", "spec", "components", "pages", "features"]

    private func areaName(for filePath: String, cwd: String) -> String? {
        guard filePath.hasPrefix(cwd + "/") else { return nil }
        let rel = filePath.dropFirst(cwd.count + 1).split(separator: "/").map(String.init)
        guard rel.count > 1 else { return "root" }
        if TranscriptScanner.sourceRoots.contains(rel[0]), rel.count > 2 { return rel[0] + "/" + rel[1] }
        return rel[0]
    }

    private static let testPattern = try! NSRegularExpression(pattern:
        #"(^|\s|&&|;)((npm|pnpm|yarn|bun)\s+(run\s+)?(test|build|lint|typecheck)|jest|vitest|pytest|xcodebuild|swift\s+(build|test)|cargo\s+(build|test)|go\s+(test|build)|gradlew?|fastlane|mvn|make(\s|$)|tsc(\s|$)|eslint|phpunit|rspec)"#)

    private func classifyBash(_ cmd: String) -> (Activity, StationEvent?) {
        if cmd.contains("gh pr create") { return (.shipping, .prOpened) }
        if cmd.contains("gh pr merge") || cmd.contains("git merge") { return (.shipping, .merged) }
        if cmd.contains("git commit") { return (.shipping, .committed) }
        if cmd.contains("git push") { return (.shipping, .pushed) }
        if cmd.hasPrefix("git ") || cmd.hasPrefix("gh ") { return (.shipping, nil) }
        let range = NSRange(cmd.startIndex..., in: cmd)
        if TranscriptScanner.testPattern.firstMatch(in: cmd, range: range) != nil { return (.testing, nil) }
        return (.running, nil)
    }

    private func parseTail(url: URL) -> Parsed {
        var p = Parsed()
        guard let fh = try? FileHandle(forReadingFrom: url) else { return p }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let want: UInt64 = 128 * 1024
        let start = size > want ? size - want : 0
        try? fh.seek(toOffset: start)
        guard let data = try? fh.readToEnd() else { return p }
        var lines = data.split(separator: UInt8(ascii: "\n"))
        if start > 0, !lines.isEmpty { lines.removeFirst() }

        for line in lines {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            let type = obj["type"] as? String ?? ""
            if let c = obj["cwd"] as? String { p.cwd = c }
            if let b = obj["gitBranch"] as? String, !b.isEmpty { p.branch = b }
            if type == "custom-title", let t = obj["customTitle"] as? String { p.title = t }
            let uuid = obj["uuid"] as? String ?? ""

            switch type {
            case "assistant":
                guard let m = obj["message"] as? [String: Any],
                      let content = m["content"] as? [[String: Any]] else { continue }
                for block in content {
                    switch block["type"] as? String {
                    case "tool_use":
                        p.toolCount += 1
                        p.markers[.tool] = uuid
                        let name = block["name"] as? String ?? ""
                        let input = block["input"] as? [String: Any] ?? [:]
                        if let f = (input["file_path"] ?? input["notebook_path"] ?? input["path"]) as? String,
                           let cwd = p.cwd, let a = areaName(for: f, cwd: cwd) { p.area = a }
                        switch name {
                        case "WebFetch", "WebSearch":
                            p.activity = .researching
                        case "Read", "Grep", "Glob", "ToolSearch", "ListSkills":
                            p.activity = .exploring
                        case "Edit", "Write", "NotebookEdit", "MultiEdit":
                            p.activity = .coding(p.area ?? "root")
                        case "Bash":
                            let (act, ev) = classifyBash(input["command"] as? String ?? "")
                            p.activity = act
                            if let ev { p.markers[ev] = uuid }
                        case "Skill":
                            let name = input["skill"] as? String ?? "?"
                            p.currentSkill = name
                            p.activity = .skill(name)
                            p.markers[.skill] = uuid
                        case "Agent", "Workflow":
                            p.activity = .delegating
                        case "EnterPlanMode", "ExitPlanMode", "AskUserQuestion":
                            p.activity = name == "AskUserQuestion" ? .waiting : .planning
                        default:
                            p.activity = .running
                        }
                    case "thinking": p.activity = .thinking
                    case "text": p.activity = .writing
                    default: break
                    }
                }
            case "user":
                if obj["toolUseResult"] == nil { p.activity = .reading; p.markers[.prompt] = uuid; p.currentSkill = nil; p.promptCount += 1 }
            case "queue-operation":
                switch obj["operation"] as? String {
                case "enqueue": p.queued += 1
                case "dequeue": p.queued -= 1
                default: break
                }
            default: break
            }
        }
        if p.currentSkill == "test-pr", p.activity != .reading { p.activity = .qa }
        return p
    }
}
