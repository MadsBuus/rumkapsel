import Foundation

/// A repository's way of working, as STAGES.md asks it: for each stage, which sources may say it, in
/// the order they are first in line, and which stages the repository does without. Detected from the
/// repository unless set by hand; the settings only hold what someone changed.
struct Workflow: Codable, Equatable {
    /// When is work stored?
    var stored: [Source] = [.board, .pulls, .git]
    /// Does it go through QA? Nil: no, stored goes straight to the rocket.
    var qa: [Source]? = [.board, .deploy, .pulls]
    /// When is it cleared to ship? Nil: always, the rocket never waits.
    var cleared: [Source]? = [.board, .deploy, .pulls]
    /// When has it shipped?
    var shipped: [Source] = [.board, .deploy, .pulls, .git]
    /// Whose pull requests are outside work.
    var outside: Outside = .bots

    enum Outside: String, Codable { case bots, strangers, nobody }

    /// Who may say a stage, first in line first; nil for a stage the repository does without. The first
    /// three stages are the same everywhere: a session and a pull request say them, nothing else could.
    func inLine(_ stage: Stage) -> [Source]? {
        switch stage {
        case .inbound: return [.session, .pulls, .board, .neighbour]
        case .working: return [.session, .neighbour]
        case .ready: return [.pulls]
        case .stored: return stored
        case .qa: return qa
        case .cleared: return cleared
        case .shipped: return shipped
        }
    }
    func has(_ stage: Stage) -> Bool { inLine(stage) != nil }

    /// What the repository itself says: its pipeline as detected, and whether a board follows it.
    static func detected(pipeline p: Pipeline, board: Bool) -> Workflow {
        var w = Workflow()
        w.qa = p.hasStaging ? (board ? [.board, .deploy, .pulls] : [.deploy, .pulls]) : nil
        // Without a board nothing clears a crate on its own; the release's label clears the lot, which is
        // the pull request's word. A repository that ships every merge has nothing to clear.
        // A repository that ships every merge or by tagging has nothing that clears a crate: nothing waits.
        w.cleared = p.shipsOnMerge || p.shipsOnTag ? nil : board ? [.board, .deploy, .pulls] : [.deploy, .pulls]
        w.stored = board ? [.board, .pulls, .git] : [.pulls, .git]
        w.shipped = p.shipsOnMerge ? [.git] : p.shipsOnTag ? [.git, .board] : board ? [.board, .deploy, .pulls] : [.deploy, .pulls]
        return w
    }

    /// The answers in a few words each, for the settings window.
    var summary: [(question: String, answer: String)] {
        func list(_ s: [Source]?) -> String { s.map { $0.map(\.title).joined(separator: ", ") } ?? "" }
        return [
            ("Stored when", list(stored)),
            ("QA", qa.map(list) ?? "none: stored goes straight to the rocket"),
            ("Cleared when", cleared.map(list) ?? "always: the rocket never waits"),
            ("Shipped when", list(shipped)),
            ("Outside work", outside == .bots ? "bots" : outside == .strangers ? "bots and anyone not on the team" : "nobody"),
        ]
    }
}

extension Source: Codable {
    var title: String {
        switch self {
        case .session: return "a session"; case .git: return "git"; case .pulls: return "pull requests"
        case .board: return "the board"; case .deploy: return "deployments"; case .neighbour: return "a neighbour"
        }
    }
}
