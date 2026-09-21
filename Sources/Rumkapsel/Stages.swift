import Foundation

/// What a piece of work goes through, in order. STAGES.md says what each looks like on the station.
enum Stage: Int, Comparable, CaseIterable, CustomStringConvertible {
    case inbound, working, ready, stored, qa, cleared, shipped
    static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    var description: String {
        switch self {
        case .inbound: return "inbound"; case .working: return "working"; case .ready: return "ready"; case .stored: return "stored"
        case .qa: return "QA"; case .cleared: return "cleared"; case .shipped: return "shipped"
        }
    }
}

/// Who said so: the integrations, as STAGES.md lists them.
enum Source: String, CaseIterable {
    case session, git, pulls, board, deploy, neighbour

}

/// One source's word about one piece of work.
struct Signal {
    var stage: Stage
    var by: Source
    var at: Date
}

/// A stage change the station should show.
struct Transition {
    let from: Stage?
    let to: Stage
    let by: Source
    let at: Date
    /// The stage left was the record's first word.
    var wasQuiet = false
    var back: Bool { from.map { to < $0 } ?? false }
}

extension WorkBook.Record {
    /// Hears a source's word by the two rules of STAGES.md, under the repository's workflow. Forward,
    /// the furthest word wins whoever said it first. Back, only the source first in line for the stage
    /// the work is at may take it, and only by changing its own word: a source that has not caught up
    /// says nothing. A stage the repository does without is not heard at all.
    func hear(_ s: Signal, workflow: Workflow = Workflow()) -> Transition? {
        guard workflow.has(s.stage) else { return nil }
        let before = words[s.by]
        words[s.by] = s.stage
        guard let current = stage else {
            stage = s.stage; stagedAt = s.at; stagedBy = s.by; quiet = true
            return Transition(from: nil, to: s.stage, by: s.by, at: s.at)
        }
        if s.stage > current {
            let wasQuiet = quiet
            stage = s.stage; stagedAt = s.at; stagedBy = s.by; quiet = false
            return Transition(from: current, to: s.stage, by: s.by, at: s.at, wasQuiet: wasQuiet)
        }
        if s.stage < current, workflow.inLine(current)?.first == s.by, let before, before >= current {
            stage = s.stage; stagedAt = s.at; stagedBy = s.by; quiet = false
            return Transition(from: current, to: s.stage, by: s.by, at: s.at)
        }
        return nil
    }
}
