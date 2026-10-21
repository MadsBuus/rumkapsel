import Foundation

enum GitHubDiag {
    static func run(seconds: TimeInterval, only: String? = nil) -> Never {
        GitHubResolver.diag = true
        let cfg = ConfigStore.shared.current
        let github = GitHubResolver()
        github.pace = .focused
        github.intervalMinutes = cfg.githubMinutes
        let home = FileManager.default.homeDirectoryForCurrentUser
        var roots: [String] = []
        if let only {
            roots = [(only as NSString).expandingTildeInPath]
        } else if let repos = try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("conductor/workspaces").path) {
            for repo in repos.sorted() {
                let root = home.appendingPathComponent("dev/\(repo)").path
                if FileManager.default.fileExists(atPath: root + "/.git") { roots.append(root) }
            }
        }
        say("github diag: \(roots.count) repositories, board \(cfg.project.map { "\($0.owner)/\($0.number)" } ?? "none"), interval \(cfg.githubMinutes) min, paced as focused, \(Int(seconds))s")
        let token = GitHubHTTP.ghToken()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = GitHubMeter.limits(token: token)
        GitHubMeter.start()
        let end = Date().addingTimeInterval(seconds)
        var lastMoves = 0
        while Date() < end {
            if let p = cfg.project { github.board.refresh(owner: p.owner, number: p.number) }
            github.watch(Dictionary(uniqueKeysWithValues: roots.map { ($0, true) }), board: cfg.project.map { ($0.owner, $0.number) })
            for root in roots {
                github.releases.refresh(repoRoot: root)
                let p = github.pipeline(repoRoot: root)
                say("\(root): \(p.trunk) · ships on \(p.ship) · \(p.source): \(p.why)"
                    + (github.cargo(repoRoot: root).map { " · storage \($0.storageNumbers) deck \($0.deckNumbers)" } ?? ""))
                github.pulls.refreshOpenPRs(repoRoot: root)
                for d in github.deployments.deploys(repoRoot: root) {
                    say("  deploys on \(d.branch): usual \(Int(d.usual))s · newest \(d.newest.map { "\($0.workflow) \($0.status) \($0.conclusion) \($0.release)" } ?? "none")")
                }
            }
            for case let .deploy(root, production, change, _) in github.deployments.reports() { say("deploy: \(root) \(production ? "production" : "staging") \(change)") }
            for case let .cardMoved(item, from) in github.board.reports() {
                say("board moved: \(item.repo)#\(item.number) \(from ?? "-") -> \(item.status) at \(item.updatedAt.map { "\($0)" } ?? "?"), seen \(Date())")
                lastMoves += 1
            }
            Thread.sleep(forTimeInterval: 5)
        }
        Thread.sleep(forTimeInterval: 3)
        say("github diag: done, \(lastMoves) board move(s) seen")
        GitHubMeter.report(seconds: seconds).forEach(say)
        if let before, let after = GitHubMeter.limits(token: token) { say(GitHubMeter.spent(from: before, to: after)) }
        exit(0)
    }

    static func watch(seconds: TimeInterval) -> Never {
        GitHubResolver.diag = true
        let world = World(demo: false)
        world.waitsForGitHub = true
        let github = world.github
        let scanner = TranscriptScanner()
        var heard = false
        github.onUpdate = { heard = true }
        let token = GitHubHTTP.ghToken()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = GitHubMeter.limits(token: token)
        let phases = ["in front", "as the sessions say", "idle"]
        let start = Date(), part = seconds / Double(phases.count)
        say("watch diag: the real World and resolver, \(Int(seconds))s: \(phases.joined(separator: ", then "))")
        var phase = -1
        var scanned = Date.distantPast
        func show(_ events: [WorldEvent]) {
            for e in events {
                let text = String(describing: e)
                if ["markersChanged", "layoutChanged", "crewRoster", "chime"].contains(where: text.hasPrefix) { continue }
                say("event: " + String(text.prefix(200)))
            }
        }
        while Date() < start.addingTimeInterval(seconds) {
            let now = Date()
            let i = min(phases.count - 1, Int(now.timeIntervalSince(start) / part))
            if i != phase {
                if phase >= 0 { GitHubMeter.report(seconds: part).forEach(say) }
                phase = i
                GitHubMeter.start()
                say("phase: \(phases[i])")
            }
            if now.timeIntervalSince(scanned) >= 5 {
                scanned = now
                let result = scanner.scan(roomsWithin: StationController.scanWindow)
                show(world.applyScan(result, now: now, minionHomes: [:]))
                let was = github.pace
                github.front = i == 0
                github.worked = result.sessions.map(\.lastModified).max() ?? .distantPast
                if i == 2 { github.pace = .idle }
                if github.pace != was { say("pace: \(github.pace)") }
            }
            if heard {
                heard = false
                show(world.applyGitHub(now: Date()))
                show(world.reconcileYards())
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        GitHubMeter.report(seconds: part).forEach(say)
        if let before, let after = GitHubMeter.limits(token: token) { say(GitHubMeter.spent(from: before, to: after)) }
        exit(0)
    }

    private static func say(_ text: String) { FileHandle.standardError.write((text + "\n").data(using: .utf8)!) }
}
