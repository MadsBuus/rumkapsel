import Foundation

enum GitHubDiag {
    static func run(seconds: TimeInterval, only: String? = nil) -> Never {
        GitHubResolver.diag = true
        let cfg = ConfigStore.shared.current
        let github = GitHubResolver()
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
        say("github diag: \(roots.count) repositories, board \(cfg.project.map { "\($0.owner)/\($0.number)" } ?? "none"), interval \(cfg.githubMinutes) min, \(Int(seconds))s")
        let end = Date().addingTimeInterval(seconds)
        var lastMoves = 0
        while Date() < end {
            if let p = cfg.project {
                github.refreshProject(owner: p.owner, number: p.number)
                github.refreshProjectDelta(owner: p.owner, number: p.number)
            }
            for root in roots {
                github.refreshReleases(repoRoot: root)
                let p = github.pipeline(repoRoot: root)
                say("\(root): \(p.trunk) · ships on \(p.ship) · \(p.source): \(p.why)"
                    + (github.cargo(repoRoot: root).map { " · storage \($0.storageNumbers) deck \($0.deckNumbers)" } ?? ""))
                github.refreshFeed(repoRoot: root)
                github.refreshOpenPRs(repoRoot: root)
                github.refreshDeploys(repoRoot: root)
                github.watchPulls(repoRoot: root)
                for d in github.deploys(repoRoot: root) {
                    say("  deploys on \(d.branch): usual \(Int(d.usual))s · newest \(d.newest.map { "\($0.workflow) \($0.status) \($0.conclusion) \($0.release)" } ?? "none")")
                }
            }
            for d in github.takeDeploys() { say("deploy: \(d.repoRoot) \(d.production ? "production" : "staging") \(d.change)") }
            let moves = github.takeProjectMoves()
            if !moves.isEmpty { for m in moves { say("board moved: \(m.item.repo)#\(m.item.number) \(m.from ?? "-") -> \(m.item.status)") }; lastMoves += moves.count }
            Thread.sleep(forTimeInterval: 5)
        }
        say("github diag: done, \(lastMoves) board move(s) seen")
        exit(0)
    }

    private static func say(_ text: String) { FileHandle.standardError.write((text + "\n").data(using: .utf8)!) }
}
