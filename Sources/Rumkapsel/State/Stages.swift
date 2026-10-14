import Foundation

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

enum Source: String, CaseIterable {
    case session, git, pulls, board, deploy, neighbour
}

struct Signal {
    var stage: Stage
    var by: Source
    var at: Date
}

struct Transition {
    let from: Stage?
    let to: Stage
    let by: Source
    let at: Date
    var wasQuiet = false
    var back: Bool { from.map { to < $0 } ?? false }
}

extension WorkBook.Record {
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
