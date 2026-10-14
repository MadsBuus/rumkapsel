import Foundation

enum WorldEvent {
    case boardMoved(item: ProjectItem, from: String?, to: Stage)
    case pullRequestOpened(repo: String, number: Int, author: String)
    case pullRequestClosed(repo: String, author: String, roomKey: String)
    case issueStarted(repo: String, number: Int, author: String, roomKey: String)
    case peerArrived(String), peerLeft(String)

    case office(station: String, OfficeNews, reason: String = "")
    case releaseOpened(station: String, repo: String, number: Int, base: String, untested: Bool, isProduction: Bool)
    case releaseMerged(station: String, repo: String, number: Int, base: String, title: String, isProduction: Bool)
    case stagingOpened(station: String, repo: String, number: Int)
    case stagingMerged(station: String, repo: String, number: Int)
    case stagingClosed(station: String, repo: String, number: Int)
    case rocketCommand(station: String, repo: String, label: String, untested: Bool, tall: Bool, cargo: Int, command: Command, hotfix: Int? = nil)
    case prompt(station: String, key: String, minionId: String, count: Int)
    case crewRoster(members: [String: CrewMember])
    case crewActivity(CrewActivity)
    case crewHidden
    case layoutChanged
    case markersChanged
    case worldLoaded
    case deployStarted(station: String, repo: String, production: Bool, expected: TimeInterval, release: String, elapsed: TimeInterval = 0)
    case deployEnded(station: String, repo: String, production: Bool, outcome: DeployOutcome)
    case log(String)
    case chime(Int)

    enum Stage { case development, storage, deck, cleared, shipped, other }
}

struct CrewMember { let homeKey: String; let repo: String }

struct CrewActivity {
    let login: String
    let kind: String
    let repo: String
    let roomKey: String
    let hasRoom: Bool
    let label: String
    let detail: String
    let branch: String?
    let title: String?
    let ready: Bool
}

extension AppConfig.ProjectStatuses {
    func stage(of status: String) -> WorldEvent.Stage {
        guard !status.isEmpty else { return .other }
        switch status {
        case development: return .development
        case storage: return .storage
        case deck: return .deck
        case cleared: return .cleared
        case shipped: return .shipped
        default: return .other
        }
    }
}
