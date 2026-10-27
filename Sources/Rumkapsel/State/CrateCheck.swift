import Foundation

struct CrateCheck: Equatable {
    struct Answer: Equatable { let source: Source; let says: String; let stage: Stage? }

    let id: CrateID
    let at: Date
    var answers: [Answer] = []
    var linked: [Int] = []
    var believed: Stage?
    var believedBy: Source?
    var heard: [Source: Stage] = [:]
    var known: [Int] = []
    var place: Zone?
    var placeByStage: Zone?
    var drawn: Zone?
    var failed: String?

    var mismatches: [String] {
        var out: [String] = []
        let station = believed.map { "\($0)" } ?? "nothing"
        for a in answers {
            guard let s = a.stage else { continue }
            if let last = heard[a.source], last != s {
                out.append("\(a.source.rawValue) says \(s) now; the station last heard \(last) from it")
            }
            if let b = believed, s > b {
                out.append("\(a.source.rawValue) says \(s), ahead of the station's \(station)")
            }
        }
        if answers.contains(where: { $0.source == .git && $0.stage == .shipped }), believed != .shipped {
            out.append("its merge commit is in production, but the station has it at \(station)")
        }
        let unknown = linked.filter { !known.contains($0) }
        if !unknown.isEmpty {
            out.append("GitHub links pull request " + unknown.map { "#\($0)" }.joined(separator: ", ") + "; the station doesn't know it")
        }
        if place != placeByStage {
            out.append("the \(Words.current.crate) stands \(CrateCheck.words(place)); its stage puts it \(CrateCheck.words(placeByStage))")
        }
        if drawn != place {
            out.append("drawn \(CrateCheck.words(drawn)); the facts say \(CrateCheck.words(place))")
        }
        return out
    }

    static func words(_ zone: Zone?) -> String { zone.map(\.words) ?? "nowhere" }

    static func stage(board status: String, _ s: AppConfig.ProjectStatuses) -> Stage? {
        switch status {
        case s.development: return .working
        case s.storage: return .stored
        case s.deck: return .qa
        case s.cleared: return .cleared
        case s.shipped: return .shipped
        default: return nil
        }
    }
}
