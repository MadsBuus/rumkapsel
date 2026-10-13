import Foundation

enum WorldEvent {
    case boardMoved(item: ProjectItem, from: String?, to: Stage)
    case pullRequestOpened(repo: String, number: Int, author: String, roomKey: String)
    case pullRequestClosed(repo: String, author: String, roomKey: String)
    case issueStarted(repo: String, number: Int, author: String, roomKey: String)
    case peerArrived(String), peerLeft(String)

    case officeOpened(station: String, key: String, source: Source, arrival: Arrival)
    case officeRenamed(station: String, from: String, to: String, name: String, session: String, promoted: Bool)
    case officeArchived(station: String, key: String, roomKey: String, name: String, hall: Cell?, announce: Bool, reason: String)
    case officeMerged(station: String, key: String, repo: String, number: Int)
    case carryToDeck(station: String, repo: String, commands: [Command])
    case crateCleared(station: String, repo: String, number: Int)
    case releaseOpened(station: String, repo: String, number: Int, base: String, untested: Bool, isProduction: Bool)
    case releaseMerged(station: String, repo: String, number: Int, base: String, title: String, isProduction: Bool)
    case stagingOpened(station: String, repo: String, number: Int)
    case stagingMerged(station: String, repo: String, number: Int)
    case stagingClosed(station: String, repo: String, number: Int)
    case rocketCommand(station: String, repo: String, label: String, untested: Bool, tall: Bool, cargo: Int, command: Command, hotfix: Int? = nil)
    case prompt(station: String, key: String, minionId: String, count: Int)
    case crewRoster(members: [String: CrewMember])
    case deconArrived(station: String, repo: String, numbers: [Int])
    case deconCleared(station: String, repo: String, number: Int)
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
    enum Source { case session(String), peer(String), github(String), board(String) }
    enum Arrival { case shuttle, fade, appear }
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
