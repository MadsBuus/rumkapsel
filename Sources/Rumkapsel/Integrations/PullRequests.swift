import Foundation

/// What GitHub's pull requests say about a piece of work, as a word for the record. It reads and reports;
/// the floor never asks it what to do. Open is ready, merged is stored, closed unmerged is back to working.
struct PullRequests {
    let github: GitHubResolver

    /// Your own office: the pull request on its branch, as GitHub last answered by branch.
    func pull(ownOffice room: Room) -> PullRequest? {
        room.branch.flatMap { b in room.repoRoot.flatMap { github.pull(branch: b, repoRoot: $0) } }
    }

    /// A teammate's office whose pull request has left the open list: closed, or merged. The feed may say
    /// which; else it is asked by number, since a board office's branch is only a guess, else by branch.
    /// Nil until GitHub answers: a crate that was never merged work must not be carried to storage. With no
    /// checkout of the repository here there is nothing to ask and nothing to carry: merged.
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
        return github.pullAnswered(branch: branch, repoRoot: root) ? (github.pull(branch: branch, repoRoot: root)?.state ?? "CLOSED") : nil
    }

    /// The word for the record: open is ready, merged is stored, closed unmerged is back to working.
    static func stage(for state: String) -> Stage {
        switch state {
        case "OPEN": return .ready
        case "MERGED": return .stored
        default: return .working
        }
    }
}
