import Foundation

enum Setup {
    struct Repo: Equatable {
        var name: String
        var pipeline: Pipeline?
        var shown = true
        var shared = false
        var missing: [String] = []
        var remote: Bool { pipeline?.remote ?? true }
    }

    struct Check: Equatable {
        var repos: [Repo] = []
        var ghInstalled = true
        var signedIn: Bool?
        var scanned = true
    }

    struct Problem: Equatable, Hashable {
        var station: String
        var settings: String
    }

    static let shownOnCard = 4

    static func way(_ p: Pipeline) -> String {
        guard p.remote else { return "local work only" }
        switch p.ship {
        case .release: return "ships from \(p.production)" + (p.hasStaging ? " through \(p.staging)" : "")
        case .tag: return "ships on tags" + (p.hasStaging ? ", tested on \(p.staging)" : "")
        case .merge: return "ships on every merge" + (p.hasStaging ? ", tested on \(p.staging)" : "")
        case .never: return p.hasStaging ? "tested on \(p.staging), never shipped" : "doesn't ship"
        }
    }

    static func line(_ r: Repo) -> String {
        guard r.shown else { return "not on the station" }
        return (r.pipeline.map(way) ?? "reading its way to production") + (r.shared ? " · shared with neighbours" : " · not shared")
    }

    static func card(_ repos: [Repo]) -> [String] {
        guard let first = repos.first else { return [] }
        if repos.count == 1 { return ["New repository: \(first.name)", sentence(line(first))] }
        let more = repos.count - shownOnCard
        return ["New repositories"] + repos.prefix(shownOnCard).map { "\($0.name) — \(line($0))" } + (more > 0 ? ["and \(more) more, in Settings"] : [])
    }

    static func problems(_ c: Check) -> [Problem] {
        guard c.scanned else { return [] }
        var out: [Problem] = []
        let shown = c.repos.filter(\.shown)
        let unreachable = "The station can't reach GitHub yet: see Settings."
        if c.repos.isEmpty {
            out.append(Problem(station: "No repositories on the station yet. Start a Claude session in one, or watch one in Settings.",
                               settings: "No repositories yet. Start a Claude session in a git checkout, or use Watch a repository… under Repositories."))
        } else if shown.isEmpty {
            out.append(Problem(station: "Every repository is kept off the station: see Settings.",
                               settings: "Every repository is hidden. Turn on Show on the station for one under Repositories."))
        }
        if !c.ghInstalled {
            out.append(Problem(station: unreachable, settings: "The GitHub CLI isn't installed. Install it (brew install gh), then run gh auth login in a terminal."))
        } else if c.signedIn == false, shown.contains(where: \.remote) {
            out.append(Problem(station: unreachable, settings: "The GitHub CLI isn't signed in. Run gh auth login in a terminal."))
        }
        let local = shown.filter { !$0.remote }.map(\.name)
        if !local.isEmpty, local.count == shown.count {
            let names = local.count == 1 ? local[0] : local.dropLast().joined(separator: ", ") + " and " + local.last!
            let words = local.count == 1 ? "\(names) isn't on GitHub, so it never ships." : "\(names) aren't on GitHub, so they never ship."
            out.append(Problem(station: words, settings: words + " Pull requests, crates and rockets need a GitHub remote."))
        }
        for r in shown {
            for b in r.missing {
                out.append(Problem(station: "\(r.name): \(b) isn't on GitHub: see Settings.", settings: "\(r.name): \(b), set by hand, isn't on GitHub."))
            }
        }
        return out
    }

    static func phrase(_ s: Ships) -> String {
        switch s {
        case .release: return "ships from a release branch"
        case .tag: return "ships on tags"
        case .merge: return "ships on every merge"
        case .never: return "doesn't ship"
        }
    }

    static func disagreements(_ repo: String, own o: AppConfig.RepoOverride?, detected d: Pipeline?, onGitHub: Set<String>?) -> [String] {
        guard let o, o.setsPipeline, let d, d.remote else { return [] }
        var out: [String] = []
        func say(_ mine: String, _ theirs: String) { out.append("\(repo): your settings say it \(mine), but the repository \(theirs).") }
        func missing(_ b: String) -> Bool { onGitHub.map { !$0.contains(b) } ?? false }
        if let t = o.trunk, !t.isEmpty {
            if missing(t) { say("merges into \(t)", "has no branch \(t) on GitHub") } else if t != d.trunk { say("merges into \(t)", "merges into \(d.trunk)") }
        }
        if let s = o.ships, s != d.ship { say(phrase(s), phrase(d.ship)) }
        if (o.ships ?? d.ship) == .release, let p = o.production, !p.isEmpty {
            if missing(p) { say("releases into \(p)", "has no branch \(p) on GitHub") }
            else if d.ship == .release, p != d.production { say("releases into \(p)", "releases into \(d.production)") }
        }
        if let s = o.staging {
            if s.isEmpty {
                if d.hasStaging { say("has no testing phase", "tests on \(d.staging)") }
            } else if missing(s) {
                say("tests on \(s)", "has no branch \(s) on GitHub")
            } else if s != d.staging {
                say("tests on \(s)", d.hasStaging ? "tests on \(d.staging)" : "has no testing branch")
            }
        }
        return out.filter { !(o.kept ?? []).contains($0) }
    }

    static func mismatchCard(_ lines: [String]) -> [String] {
        guard !lines.isEmpty else { return [] }
        let more = lines.count - shownOnCard
        return ["Your settings and the repository disagree"] + lines.prefix(shownOnCard) + (more > 0 ? ["and \(more) more, in Settings"] : [])
    }

    static func sentence(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}

extension World {
    func setup(repo: String) -> Setup.Repo {
        let cfg = ConfigStore.shared.current
        var r = Setup.Repo(name: repo, shown: cfg.shown(repo: repo), shared: cfg.repos[repo]?.share ?? false)
        guard let root = repoRoots.first(where: { $0.value.repo == repo })?.key else { return r }
        if github.pipelineRead(repoRoot: root) { r.pipeline = github.pipeline(repoRoot: root) }
        if let o = cfg.repos[repo], let on = github.githubBranches(repoRoot: root), !on.isEmpty {
            let set: [(String, String?)] = [("the trunk", o.trunk), ("the testing branch", o.staging), ("the release branch", o.ships == .release ? o.production : nil)]
            r.missing = set.compactMap { role, b in b.flatMap { !$0.isEmpty && !on.contains($0) ? "\(role) \($0)" : nil } }
        }
        return r
    }

    var mismatches: [(repo: String, lines: [String])] {
        let cfg = ConfigStore.shared.current
        return repoRoots.sorted(by: { $0.value.repo < $1.value.repo }).compactMap { root, info in
            guard cfg.shown(repo: info.repo), github.pipelineRead(repoRoot: root) else { return nil }
            let lines = Setup.disagreements(info.repo, own: cfg.repos[info.repo], detected: github.detectedPipeline(repoRoot: root),
                                            onGitHub: github.githubBranches(repoRoot: root))
            return lines.isEmpty ? nil : (info.repo, lines)
        }
    }

    var setupCheck: Setup.Check {
        let hidden = ConfigStore.shared.current.repos.filter { !$0.value.shown }.keys
        let names = Set(repoRoots.values.map(\.repo)).union(hidden).sorted()
        return Setup.Check(repos: names.map(setup(repo:)), ghInstalled: simulated || Discovery.ghInstalled, signedIn: github.signedIn, scanned: hasScanned)
    }
}
