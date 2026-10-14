import Foundation

struct Workflow: Codable, Equatable {
    var stored: [Source] = [.board, .pulls, .git]
    var qa: [Source]? = [.board, .deploy, .pulls]
    var cleared: [Source]? = [.board, .deploy, .pulls]
    var shipped: [Source] = [.board, .deploy, .pulls, .git]

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

    static func detected(pipeline p: Pipeline, board: Bool) -> Workflow {
        var w = Workflow()
        w.qa = p.hasStaging ? (board ? [.board, .deploy, .pulls] : [.deploy, .pulls]) : nil
        w.cleared = p.shipsOnMerge || p.shipsOnTag ? nil : board ? [.board, .deploy, .pulls] : [.deploy, .pulls]
        w.stored = board ? [.board, .pulls, .git] : [.pulls, .git]
        w.shipped = p.shipsOnMerge ? [.git] : p.shipsOnTag ? [.git, .board] : board ? [.board, .deploy, .pulls] : [.deploy, .pulls]
        return w
    }

    static func first(_ s: Source, in list: [Source]) -> [Source] { [s] + list.filter { $0 != s } }

    var summary: [(question: String, answer: String)] {
        func list(_ s: [Source]?) -> String { s.map { $0.map(\.title).joined(separator: ", ") } ?? "" }
        return [
            ("Stored when", list(stored)),
            ("QA", qa.map(list) ?? "none: stored goes straight to the rocket"),
            ("Cleared when", cleared.map(list) ?? "always: the rocket never waits"),
            ("Shipped when", list(shipped)),
        ]
    }
}

extension Workflow {
    private enum Retired: String, CodingKey { case outside }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(stored, forKey: .stored)
        try c.encode(qa, forKey: .qa)
        try c.encode(cleared, forKey: .cleared)
        try c.encode(shipped, forKey: .shipped)
        var old = encoder.container(keyedBy: Retired.self)
        try old.encode("bots", forKey: .outside)
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
