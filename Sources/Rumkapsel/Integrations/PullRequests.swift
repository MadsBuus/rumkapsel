import Foundation

struct PullRequests {
    let github: GitHubResolver

    func pull(ownOffice room: Room) -> PullRequest? {
        room.branch.flatMap { b in room.repoRoot.flatMap { github.pull(branch: b, repoRoot: $0) } }
    }

    func state(crewOffice room: Room, known: WorkBook.Record?, repoRoot root: String?,
               feed: [(repo: String, e: FeedEvent)]) -> String? {
        let branch = known?.work().branch ?? known?.branches.sorted().first ?? ""
        if feed.contains(where: { $0.repo == room.repo && $0.e.kind == "pr_close" && $0.e.branch == branch }) { return "CLOSED" }
        if feed.contains(where: { $0.repo == room.repo && $0.e.kind == "pr_merge" && $0.e.branch == branch }) { return "MERGED" }
        guard let root else { return "MERGED" }
        if let number = known?.pulls.keys.min() {
            github.refresh(pull: number, repoRoot: root)
            return github.pullAnswered(number: number, repoRoot: root) ? github.pull(number: number, repoRoot: root)?.state : nil
        }
        github.refresh(branch: branch, repoRoot: root)
        return github.pullAnswered(branch: branch, repoRoot: root) ? (github.pull(branch: branch, repoRoot: root)?.state ?? "NONE") : nil
    }

    static func stage(for state: String) -> Stage {
        switch state {
        case "OPEN": return .ready
        case "MERGED": return .stored
        default: return .working
        }
    }
}
