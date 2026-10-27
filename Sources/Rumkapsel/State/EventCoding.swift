import Foundation

private enum Field: String, CodingKey {
    case e, repo, facts, crate, office, stage, closed, quiet, link, pull, key, via, by = "for", from, to, merged, closedAt, open, n, deploy
    case production, label, hotfix, crates, keep, source, housekeeping, untested
}

extension CrateID {
    init(text: String) throws {
        guard let i = text.lastIndex(of: "#"), let n = Int(text[text.index(after: i)...]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not a crate: \(text)"))
        }
        self.init(repo: String(text[..<i]), number: n)
    }
}

extension Stage {
    var name: String { "\(self)".lowercased() }
    init(name: String) throws {
        guard let s = Stage.allCases.first(where: { $0.name == name }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not a stage: \(name)"))
        }
        self = s
    }
}

extension Event: Codable {
    static let kinds: Set<String> = ["policy", "work", "officeOpened", "officeRenamed", "officeStatus", "officeGone", "decon", "deconClosed", "renumbered",
                                     "stagingOpened", "stagingMerged", "stagingClosed", "stagingDeploy", "release", "hotfixes", "launched", "sweep", "restack", "tick"]

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Field.self)
        func put(_ e: String, repo: String? = nil, quiet: Bool = false) throws {
            try c.encode(e, forKey: .e)
            try c.encodeIfPresent(repo, forKey: .repo)
            if quiet { try c.encode(true, forKey: .quiet) }
        }
        switch self {
        case .policy(let repo, let r):
            try put("policy", repo: repo)
            try c.encode(r, forKey: .facts)
        case .work(let w):
            try put("work", quiet: w.quiet)
            try c.encode(w.crate.description, forKey: .crate)
            try c.encodeIfPresent(w.office, forKey: .office)
            try c.encode(w.stage.name, forKey: .stage)
            if w.closed { try c.encode(true, forKey: .closed) }
            if !w.link.isEmpty { try c.encode(w.link, forKey: .link) }
            try c.encodeIfPresent(w.by?.rawValue, forKey: .source)
            try c.encodeIfPresent(w.pull, forKey: .pull)
            if w.housekeeping { try c.encode(true, forKey: .housekeeping) }
            if w.untested { try c.encode(true, forKey: .untested) }
        case .office(.opened(let key, let repo, let via)):
            try put("officeOpened", repo: repo)
            try c.encode(key, forKey: .key)
            switch via {
            case .appear: try c.encode("appear", forKey: .via)
            case .fade: try c.encode("fade", forKey: .via)
            case .shuttle(let who):
                try c.encode("shuttle", forKey: .via)
                try c.encodeIfPresent(who, forKey: .by)
            }
        case .office(.renamed(let from, let to)):
            try put("officeRenamed")
            try c.encode(from, forKey: .from)
            try c.encode(to, forKey: .to)
        case .office(.status(let key, let crate, let merged, let closedAt)):
            try put("officeStatus")
            try c.encode(key, forKey: .key)
            try c.encodeIfPresent(crate?.description, forKey: .crate)
            if merged { try c.encode(true, forKey: .merged) }
            try c.encodeIfPresent(closedAt, forKey: .closedAt)
        case .office(.gone(let key)):
            try put("officeGone")
            try c.encode(key, forKey: .key)
        case .decon(let repo, let open, let quiet):
            try put("decon", repo: repo, quiet: quiet)
            try c.encode(open, forKey: .open)
        case .deconClosed(let id):
            try put("deconClosed")
            try c.encode(id.description, forKey: .crate)
        case .renumbered(let from, let to):
            try put("renumbered")
            try c.encode(from.description, forKey: .from)
            try c.encode(to.description, forKey: .to)
        case .staging(let repo, .opened(let n)):
            try put("stagingOpened", repo: repo)
            try c.encode(n, forKey: .n)
        case .staging(let repo, .merged(let n)):
            try put("stagingMerged", repo: repo)
            try c.encode(n, forKey: .n)
        case .staging(let repo, .closed(let n)):
            try put("stagingClosed", repo: repo)
            try c.encode(n, forKey: .n)
        case .staging(let repo, .deploy(let d)):
            try put("stagingDeploy", repo: repo)
            try c.encode(d, forKey: .deploy)
        case .release(let repo, let production, let label, let quiet):
            try put("release", repo: repo, quiet: quiet)
            try c.encodeIfPresent(production, forKey: .production)
            if !label.isEmpty { try c.encode(label, forKey: .label) }
        case .hotfixes(let repo, let open, let quiet):
            try put("hotfixes", repo: repo, quiet: quiet)
            try c.encode(Dictionary(uniqueKeysWithValues: open.map { ("\($0.key)", $0.value) }), forKey: .open)
        case .launched(let repo, let hotfix, let crates, let label):
            try put("launched", repo: repo)
            try c.encodeIfPresent(hotfix, forKey: .hotfix)
            try c.encodeIfPresent(crates, forKey: .crates)
            if !label.isEmpty { try c.encode(label, forKey: .label) }
        case .sweep(let repo, let keep):
            try put("sweep", repo: repo)
            try c.encode(keep, forKey: .keep)
        case .restack:
            try put("restack")
        case .tick:
            try put("tick")
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Field.self)
        func text(_ k: Field) throws -> String { try c.decode(String.self, forKey: k) }
        func flag(_ k: Field) throws -> Bool { try c.decodeIfPresent(Bool.self, forKey: k) ?? false }
        func crate(_ k: Field) throws -> CrateID { try CrateID(text: text(k)) }
        let e = try text(.e)
        switch e {
        case "policy":
            self = .policy(repo: try text(.repo), try c.decode(RepoFacts.self, forKey: .facts))
        case "work":
            self = .work(WorkNews(crate: try crate(.crate), office: try c.decodeIfPresent(String.self, forKey: .office), stage: try Stage(name: text(.stage)),
                                  closed: try flag(.closed), quiet: try flag(.quiet), link: try c.decodeIfPresent(String.self, forKey: .link) ?? "",
                                  by: try c.decodeIfPresent(String.self, forKey: .source).flatMap(Source.init(rawValue:)),
                                  pull: try c.decodeIfPresent(Int.self, forKey: .pull), housekeeping: try flag(.housekeeping), untested: try flag(.untested)))
        case "officeOpened":
            let via: OfficeFact.Via
            switch try text(.via) {
            case "fade": via = .fade
            case "shuttle": via = .shuttle(for: try c.decodeIfPresent(String.self, forKey: .by))
            default: via = .appear
            }
            self = .office(.opened(try text(.key), repo: try c.decodeIfPresent(String.self, forKey: .repo), via: via))
        case "officeRenamed":
            self = .office(.renamed(from: try text(.from), to: try text(.to)))
        case "officeStatus":
            self = .office(.status(try text(.key), crate: try c.decodeIfPresent(String.self, forKey: .crate).map(CrateID.init(text:)), merged: try flag(.merged),
                                   closedAt: try c.decodeIfPresent(Date.self, forKey: .closedAt)))
        case "officeGone":
            self = .office(.gone(try text(.key)))
        case "decon":
            self = .decon(repo: try text(.repo), open: try c.decode([Int].self, forKey: .open), quiet: try flag(.quiet))
        case "deconClosed":
            self = .deconClosed(try crate(.crate))
        case "renumbered":
            self = .renumbered(from: try crate(.from), to: try crate(.to))
        case "stagingOpened":
            self = .staging(repo: try text(.repo), .opened(try c.decode(Int.self, forKey: .n)))
        case "stagingMerged":
            self = .staging(repo: try text(.repo), .merged(try c.decode(Int.self, forKey: .n)))
        case "stagingClosed":
            self = .staging(repo: try text(.repo), .closed(try c.decode(Int.self, forKey: .n)))
        case "stagingDeploy":
            self = .staging(repo: try text(.repo), .deploy(try c.decode(StagingFact.Deploy.self, forKey: .deploy)))
        case "release":
            self = .release(repo: try text(.repo), production: try c.decodeIfPresent(Bool.self, forKey: .production),
                            label: try c.decodeIfPresent(String.self, forKey: .label) ?? "", quiet: try flag(.quiet))
        case "hotfixes":
            let open = try c.decode([String: String].self, forKey: .open)
            self = .hotfixes(repo: try text(.repo), open: Dictionary(uniqueKeysWithValues: open.compactMap { k, v in Int(k).map { ($0, v) } }), quiet: try flag(.quiet))
        case "launched":
            self = .launched(repo: try text(.repo), hotfix: try c.decodeIfPresent(Int.self, forKey: .hotfix), crates: try c.decodeIfPresent([Int].self, forKey: .crates),
                             label: try c.decodeIfPresent(String.self, forKey: .label) ?? "")
        case "sweep":
            self = .sweep(repo: try text(.repo), keep: try c.decode([Int].self, forKey: .keep))
        case "restack":
            self = .restack
        case "tick":
            self = .tick
        default:
            throw DecodingError.dataCorruptedError(forKey: .e, in: c, debugDescription: "not an event: \(e)")
        }
    }

    var words: String {
        func list(_ numbers: [Int]) -> String { numbers.sorted().map { "#\($0)" }.joined(separator: ", ") }
        switch self {
        case .policy(let repo, _): return "policy \(repo)"
        case .work(let w): return "work \(w.crate) \(w.stage.name)" + (w.closed ? " closed" : "") + (w.office.map { " in \($0)" } ?? "") + (w.by.map { " by \($0)" } ?? "")
        case .office(.opened(let key, _, _)): return "office \(key) opened"
        case .office(.renamed(let from, let to)): return "office \(from) renamed \(to)"
        case .office(.status(let key, _, let merged, _)): return "office \(key) status" + (merged ? " merged" : "")
        case .office(.gone(let key)): return "office \(key) gone"
        case .decon(let repo, let open, _): return "decon \(repo) \(list(open))"
        case .deconClosed(let id): return "decon \(id) closed"
        case .renumbered(let from, let to): return "renumbered \(from) to \(to)"
        case .staging(let repo, .opened(let n)): return "staging \(repo) #\(n) opened"
        case .staging(let repo, .merged(let n)): return "staging \(repo) #\(n) merged"
        case .staging(let repo, .closed(let n)): return "staging \(repo) #\(n) closed"
        case .staging(let repo, .deploy(let d)): return "staging \(repo) deploy \(d)"
        case .release(let repo, let production, _, _): return "release \(repo) production \(production.map { "\($0)" } ?? "none")"
        case .hotfixes(let repo, let open, _): return "hotfixes \(repo) \(list(Array(open.keys)))"
        case .launched(let repo, let hotfix, let crates, _):
            return "launched \(repo)" + (hotfix.map { " hotfix #\($0)" } ?? "") + (crates.map { " " + list($0) } ?? "")
        case .sweep(let repo, _): return "sweep \(repo)"
        case .restack: return "restack"
        case .tick: return "tick"
        }
    }
}

extension YardGeometry: Codable {
    private enum CodingKeys: String, CodingKey { case grids, pads }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let named = try c.decode([String: [[Cell]]].self, forKey: .grids)
        grids = Dictionary(uniqueKeysWithValues: named.compactMap { k, v in Zone(rawValue: k).map { ($0, v) } })
        offset = .zero
        pads = try c.decode(Int.self, forKey: .pads)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Dictionary(uniqueKeysWithValues: grids.map { ($0.key.rawValue, $0.value) }), forKey: .grids)
        try c.encode(pads, forKey: .pads)
    }

    func same(_ other: YardGeometry) -> Bool { grids == other.grids && pads == other.pads }
}
