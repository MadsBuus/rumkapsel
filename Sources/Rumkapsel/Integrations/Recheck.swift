import Foundation

extension World {
    func recheckRoot(_ id: CrateID) -> String? { repoRoots.first { $0.value.repo == id.repo }?.key }

    func askAbout(_ id: CrateID, root: String) -> (answers: [CrateCheck.Answer], linked: [Int], failed: String?) {
        let statuses = ConfigStore.shared.current.statuses
        func json(_ args: [String]) -> [String: Any]? {
            github.run(args, cwd: root).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
        func board(_ o: [String: Any]) -> String? {
            ((o["projectItems"] as? [[String: Any]]) ?? []).compactMap { ($0["status"] as? [String: Any])?["name"] as? String }.first
        }
        var answers: [CrateCheck.Answer] = []
        var pulls: [[String: Any]] = []
        var status: String?
        if let pr = json(["gh", "pr", "view", "\(id.number)", "--json", "number,state,mergeCommit,projectItems,closingIssuesReferences"]) {
            pulls = [pr]
            status = board(pr)
            for n in ((pr["closingIssuesReferences"] as? [[String: Any]]) ?? []).compactMap({ $0["number"] as? Int }) where status == nil {
                status = json(["gh", "issue", "view", "\(n)", "--json", "projectItems"]).flatMap(board)
            }
        } else if let issue = json(["gh", "issue", "view", "\(id.number)", "--json", "state,projectItems,closedByPullRequestsReferences"]) {
            status = board(issue)
            for n in ((issue["closedByPullRequestsReferences"] as? [[String: Any]]) ?? []).compactMap({ $0["number"] as? Int }) {
                if let pr = json(["gh", "pr", "view", "\(n)", "--json", "number,state,mergeCommit"]) { pulls.append(pr) }
            }
        } else {
            return ([], [], "GitHub did not answer about #\(id.number)")
        }
        answers.append(CrateCheck.Answer(source: .board, says: status.map { "status \($0)" } ?? "not on the project",
                                         stage: status.flatMap { CrateCheck.stage(board: $0, statuses) }))
        let p = github.pipeline(repoRoot: root)
        for pr in pulls {
            let n = pr["number"] as? Int ?? 0, state = pr["state"] as? String ?? "?"
            answers.append(CrateCheck.Answer(source: .pulls, says: "pull request #\(n) \(state.lowercased())", stage: state == "CLOSED" ? nil : PullRequests.stage(for: state)))
            guard state == "MERGED", let oid = (pr["mergeCommit"] as? [String: Any])?["oid"] as? String else { continue }
            func on(_ branch: String) -> Bool { !branch.isEmpty && github.run(["git", "merge-base", "--is-ancestor", oid, "origin/" + branch], cwd: root) != nil }
            let shipped = PullSource.shipped(pr, repoRoot: root, github: github)
            let staged = p.hasStaging && on(p.staging)
            answers.append(CrateCheck.Answer(source: .git, says: shipped ? "#\(n)'s merge commit is in production" : staged ? "#\(n)'s merge commit is on \(p.staging), not in production" : "#\(n)'s merge commit is on neither \(p.staging) nor \(p.production)",
                                             stage: shipped ? .shipped : staged ? .qa : .stored))
        }
        return (answers, pulls.compactMap { $0["number"] as? Int }.filter { $0 != id.number }, nil)
    }

    func crateCheck(_ id: CrateID, station: Station, asked: (answers: [CrateCheck.Answer], linked: [Int], failed: String?), drawn: Zone?) -> CrateCheck {
        var c = CrateCheck(id: id, at: now, answers: asked.answers, linked: asked.linked, failed: asked.failed)
        let r = works.find(repo: id.repo, crate: id.number)
        c.believed = r?.stage
        c.believedBy = r?.stagedBy
        c.heard = r?.words ?? [:]
        c.known = r.map { Array($0.pulls.keys).sorted() } ?? []
        c.place = station.facts.crates[id]?.zone
        if let stage = r?.stage {
            c.placeByStage = Rules.place(stage, station.facts.repo(id.repo), office: nil, old: nil)?.zone
        }
        c.drawn = drawn
        return c
    }
}
