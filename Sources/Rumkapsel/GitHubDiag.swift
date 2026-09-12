// The GitHub poller on its own: `.build/debug/Rumkapsel --github-diag [seconds]`.
//
// No window, no station. The same refresh calls the station makes every five seconds, against the
// real settings and checkouts, with every ask and every answer that changed on stderr. For seeing
// what the poller does with a real board and real repositories, and how fast a change reaches it.

import Foundation

enum GitHubDiag {
    static func run(seconds: TimeInterval) -> Never {
        GitHubResolver.diag = true
        let cfg = ConfigStore.shared.current
        let github = GitHubResolver()
        github.intervalMinutes = cfg.githubMinutes
        // The same checkouts the station finds on its first run: every Conductor repository under ~/dev.
        let home = FileManager.default.homeDirectoryForCurrentUser
        var roots: [String] = []
        if let repos = try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("conductor/workspaces").path) {
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
                github.refreshFeed(repoRoot: root)
                github.refreshOpenPRs(repoRoot: root)
            }
            let moves = github.takeProjectMoves()
            if !moves.isEmpty { for m in moves { say("board moved: \(m.item.repo)#\(m.item.number) \(m.from ?? "-") -> \(m.item.status)") }; lastMoves += moves.count }
            Thread.sleep(forTimeInterval: 5)
        }
        say("github diag: done, \(lastMoves) board move(s) seen")
        exit(0)
    }

    private static func say(_ text: String) { FileHandle.standardError.write((text + "\n").data(using: .utf8)!) }
}
