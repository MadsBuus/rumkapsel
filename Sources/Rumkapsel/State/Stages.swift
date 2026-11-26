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

    static let unshippable: Set<Source> = [.pulls, .git]

    var shippedOnMerge: Bool { stage == .shipped && stagedBy.map(Self.unshippable.contains) == true }

    func notInProduction(at: Date, workflow: Workflow = Workflow()) -> Transition? {
        guard shippedOnMerge, let by = stagedBy else { return nil }
        for s in Self.unshippable where words[s] == .shipped { words[s] = nil }
        let said = words.filter { $0.value < .shipped && workflow.inLine($0.value)?.contains($0.key) == true }.values
        let back = max(said.max() ?? .stored, .stored)
        stage = back; stagedAt = at; stagedBy = by; quiet = false
        return Transition(from: .shipped, to: back, by: by, at: at)
    }
}
