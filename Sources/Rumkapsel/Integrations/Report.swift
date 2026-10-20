import Foundation

enum Report {
    case deploy(repoRoot: String, production: Bool, change: Deployments.Change, usual: TimeInterval)
    case cardMoved(ProjectItem, from: String?)
    case pullChanged(branch: String, PullRequest)
}

extension World {
    func hear(_ reports: [Report]) -> [WorldEvent] {
        var events: [WorldEvent] = []
        for report in reports {
            switch report {
            case .deploy(let root, let production, let change, let usual):
                guard let info = repoRoots[root] else { continue }
                if production { releases.awaitingDeploy[root] = nil }
                switch change {
                case .started(let run, let elapsed):
                    events.append(.deployStarted(station: info.station, repo: info.repo, production: production, expected: usual,
                                                 release: run.release, elapsed: elapsed))
                    if !production { learn(.staging(repo: info.repo, .deploy(.running(since: now.addingTimeInterval(-elapsed), usual: usual))), repo: info.repo) }
                case .ended(_, let outcome):
                    events.append(.deployEnded(station: info.station, repo: info.repo, production: production, outcome: outcome))
                    if !production { learn(.staging(repo: info.repo, .deploy(outcome == .live ? .live : .failed)), repo: info.repo) }
                }
            case .cardMoved(let item, let from):
                events.append(.boardMoved(item: item, from: from, to: ConfigStore.shared.current.statuses.stage(of: item.status)))
            case .pullChanged(let branch, let pr):
                let rooms = fleet.stations.values.flatMap { $0.rooms.values.filter { $0.branch == branch } }
                for room in rooms { if let repo = room.repo { works.note(repo: repo, branch: branch, issue: pr.closes.first, pull: pr.number, pullState: pr.state) } }
                for room in rooms { if let repo = room.repo { self.report(pullState: pr.state, record: works.find(repo: repo, pull: pr.number), at: now) } }
                events.append(.log("\(Work(repo: "", branch: branch).label): \(pr.summary)"))
                events.append(.chime(pr.number))
            }
        }
        return events
    }
}
