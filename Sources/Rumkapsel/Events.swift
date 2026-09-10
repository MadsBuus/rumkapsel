import Foundation

/// What changed in the world, as the scene wants to hear it.
///
/// The app has three layers, and this is the seam between the first two and the third:
///
/// 1. **Sources** poll the outside world and cache answers: the session scanner, GitHub (pull requests,
///    feed, releases), the project board, peers on the network. They know nothing about the picture.
/// 2. **Diffs** compare each fresh answer with what was known and turn the difference into events.
///    A source's first answer is never an event: whatever it holds already existed.
/// 3. **The scene** renders the model and consumes events once each, deciding the cue: a shuttle,
///    a haul, a fade, a log line. It never re-derives "what just happened" from raw data.
///
/// Invariants worth keeping: an update re-plans, it never resets; a layout is a pure function of
/// counts, so a carrier can be sent to the slot its crate will get; counts follow the source
/// through the minions' hands wherever a haul can carry the change.
enum WorldEvent {
    /// An issue on the project board changed column.
    case boardMoved(item: ProjectItem, from: String?, to: Stage)
    /// A teammate opened a pull request; the office is already on the floor.
    case pullRequestOpened(repo: String, number: Int, author: String, roomKey: String)
    /// A teammate's pull request closed or merged.
    case pullRequestClosed(repo: String, author: String, roomKey: String)
    /// Someone on the board started an issue and its office is already on the floor.
    case issueStarted(repo: String, number: Int, author: String, roomKey: String)
    /// A peer came into range or left.
    case peerArrived(String), peerLeft(String)

    /// Where on the station a board column lands.
    enum Stage { case development, storage, deck, cleared, shipped, other }
}

extension AppConfig.ProjectStatuses {
    func stage(of status: String) -> WorldEvent.Stage {
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
