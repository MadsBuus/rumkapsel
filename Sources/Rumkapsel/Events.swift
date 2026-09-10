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

    /// An office appeared on a station's floor. Offices GitHub or the board put there come with a
    /// `.pullRequestOpened` or `.issueStarted` alongside, which carries what the log needs to say.
    case officeOpened(station: String, key: String, source: Source, arrival: Arrival)
    /// A session's office took a new key: the same floor under a new name.
    case officeRenamed(station: String, from: String, to: String, name: String, session: String, promoted: Bool)
    /// An office left the floor. The model has already dropped it, so everything the scene needs to
    /// take its tiles down comes with the event.
    case officeArchived(station: String, key: String, roomKey: String, name: String, hall: Cell?, announce: Bool, reason: String)
    /// Merged: the office's package belongs in storage. The scene hauls it, then calls `landedInStorage`.
    case officeMerged(station: String, key: String, repo: String, number: Int)
    /// Crates the board says reached staging: one carry command each, storage across to the deck.
    case carryToDeck(station: String, repo: String, commands: [Command])
    /// One crate passed QA: it crosses the aisle to the tested row.
    case crateCleared(station: String, repo: String, number: Int)
    /// A release pull request appeared: a rocket belongs on the pad.
    case releaseOpened(station: String, repo: String, number: Int, base: String, untested: Bool, isProduction: Bool)
    /// A release pull request merged. A production one ships; a staging one moves the yard.
    case releaseMerged(station: String, repo: String, number: Int, base: String, title: String, isProduction: Bool)
    /// A staging release opened: a pallet is ordered for that repository's crates in storage.
    case stagingOpened(station: String, repo: String, number: Int)
    /// A staging release merged: the loaded pallet is pushed across to the deck.
    case stagingMerged(station: String, repo: String, number: Int)
    /// A staging release closed unmerged: the pallet unloads back into storage.
    case stagingClosed(station: String, repo: String, number: Int)
    /// What a repository's rocket should be doing now, as a command for it to run.
    case rocketCommand(station: String, repo: String, label: String, untested: Bool, tall: Bool, cargo: Int, command: Command)
    /// A message landed in a session's office: cones on the floor, and its worker goes to them.
    case prompt(station: String, key: String, minionId: String, count: Int)
    /// Who is on the crew right now, and how many bot pull requests are open.
    case crewRoster(members: [String: CrewMember], bots: Int)
    /// Something a teammate just did, fresh enough to move their minion.
    case crewActivity(CrewActivity)
    /// The crew was switched off: their minions go.
    case crewHidden
    /// The floor plan changed: the static scene wants rebuilding.
    case layoutChanged
    /// Only what stands on the floor changed: crates, boxes and cones.
    case markersChanged
    /// The saved layout came back from disk: this is the first scan of the run.
    case worldLoaded
    /// A line for the station log.
    case log(String)
    /// Worth a chime, with a seed for its pitch.
    case chime(Int)

    /// Where on the station a board column lands.
    enum Stage { case development, storage, deck, cleared, shipped, other }
    /// Why an office exists, and who to credit: a session id, a peer name or a GitHub login.
    enum Source { case session(String), peer(String), github(String), board(String) }
    /// How a new office should show up.
    enum Arrival { case shuttle, fade, appear }
}

/// A teammate with a place on the station.
struct CrewMember { let homeKey: String; let repo: String }

/// One entry from a repository's activity feed, with everything the scene needs to react to it.
struct CrewActivity {
    let login: String
    let kind: String
    let repo: String
    let roomKey: String
    let hasRoom: Bool
    let label: String        // "#123", or the branch when there is no pull request
    let detail: String
    let branch: String?
    let title: String?
    let ready: Bool          // the repository has answered before: this is news, not history
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
