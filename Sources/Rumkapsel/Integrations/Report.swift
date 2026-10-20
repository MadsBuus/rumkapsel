import Foundation

enum Report {
    case deploy(repoRoot: String, production: Bool, change: Deployments.Change, usual: TimeInterval)
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
            }
        }
        return events
    }
}
