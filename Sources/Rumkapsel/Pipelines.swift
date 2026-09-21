// A repository's way to production, decided from the repository itself so nobody has to set it up.
//
// What the repository did says most: the branch most work merges into is the trunk, the branch releases
// end in is production, and a branch released onward into production is staging. Where the history says
// nothing, the branch names decide. A file `.github/rumkapsel.json` on the repository's default branch
// overrides both, and since it lives in the repository, everyone who watches it gets the same answer.

import Foundation

/// The optional file a repository can carry at `.github/rumkapsel.json`. Every field is optional:
/// what it leaves out is still detected. `"staging": ""` says there is none.
struct ReleaseFile: Codable, Equatable {
    var trunk: String?
    var staging: String?
    var production: String?
    /// Head branches a release may come from besides the trunk and staging, as patterns: "release/*".
    var releaseBranches: [String]?
    /// Whether the board's storage and QA columns fill the yard; left out, the board itself decides.
    var boardColumns: Bool?
    /// "merge" when every merge into the trunk deploys, "release" when releases do.
    var ship: String?
}

extension Pipeline {
    /// The branches set by hand for this repository in Settings.
    func overridden(by b: AppConfig.Branches?) -> Pipeline {
        guard let b else { return self }
        var p = self
        p.trunk = b.trunk; p.staging = b.staging; p.production = b.production
        p.source = "override"; p.why = "set in Settings"
        if !b.production.isEmpty, p.ship == "merge" || p.ship == "tag" { p.ship = "release" }
        return p
    }

    /// The way to production in a few words, for Settings.
    var flow: String {
        shipsOnMerge ? "\(trunk), ships on merge"
            : shipsOnTag ? "\(trunk), ships on tags"
            : production.isEmpty ? "\(trunk), no releases"
            : [trunk, staging, production].filter { !$0.isEmpty }.joined(separator: " → ")
    }

    static func override(forRoot root: String) -> AppConfig.Branches? {
        ConfigStore.shared.current.repos[URL(fileURLWithPath: root).lastPathComponent]?.branches
    }
}

enum PipelineDetection {
    struct Merge: Equatable { let base: String; let head: String }

    static let defaultReleaseBranches = ["release*", "hotfix*"]

    /// A trailing star matches any rest: "release*" matches release/v9.7.1.
    static func matches(_ branch: String, _ pattern: String) -> Bool {
        pattern.hasSuffix("*") ? branch.hasPrefix(String(pattern.dropLast())) : branch == pattern
    }

    static func detect(branches: Set<String>, merges: [Merge], file: ReleaseFile?,
                       names: (trunk: String, staging: String, production: String), deploysOnPush: Bool = false,
                       tagged: Bool = false) -> Pipeline {
        // A branch counts only if the repository still has it; with no branch list at all, any name will do.
        let exists: (String) -> Bool = { b in !b.isEmpty && (branches.isEmpty || branches.contains(b)) }
        let releaseLike: (String) -> Bool = { h in defaultReleaseBranches.contains { matches(h, $0) } }
        let longLived = Set([names.trunk, names.staging, names.production, "develop", "main", "master", "staging", "production"].filter { !$0.isEmpty })

        // By names: the settings' names first, then the usual ones.
        var trunk = [names.trunk, "develop", "main", "master"].first(where: exists) ?? names.trunk
        var staging = exists(names.staging) && names.staging != trunk ? names.staging : ""
        var production = [names.production, "master", "main"].first { exists($0) && $0 != trunk && $0 != staging } ?? ""
        var releaseBranches = defaultReleaseBranches
        var source = "branches", why = "branch names only: no release history read"

        // The trunk: the long-lived branch most feature work merges into.
        var featureInto: [String: Int] = [:]
        for m in merges where longLived.contains(m.base) && !longLived.contains(m.head) && !releaseLike(m.head) { featureInto[m.base, default: 0] += 1 }
        if let t = featureInto.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).first?.key, exists(t) { trunk = t }

        // Releases: merges into a long-lived branch other than the trunk, from a long-lived or release branch.
        // A merge back into the trunk after a release is not one.
        let candidates = merges.filter { longLived.contains($0.base) && $0.base != trunk && $0.base != $0.head && (longLived.contains($0.head) || releaseLike($0.head)) }
        // Between two branches the flow runs the way most merges go. The rarer way back, production merged
        // into staging after a hotfix say, keeps them in step and is not a release.
        var edges: [String: Int] = [:]
        for c in candidates { edges["\(c.head)>\(c.base)", default: 0] += 1 }
        let releases = candidates.filter { c in edges["\(c.head)>\(c.base)", default: 0] > edges["\(c.base)>\(c.head)", default: 0] }
        if !releases.isEmpty {
            var perBase: [String: Int] = [:]
            for r in releases { perBase[r.base, default: 0] += 1 }
            let byCount: (String, String) -> Bool = { a, b in perBase[a, default: 0] != perBase[b, default: 0] ? perBase[a, default: 0] > perBase[b, default: 0] : a < b }
            let onward = Set(releases.map(\.head))
            // Production: where releases end, a branch never itself released onward.
            if let p = Set(releases.map(\.base)).filter({ !onward.contains($0) && exists($0) }).sorted(by: byCount).first {
                production = p
                // Staging: a branch released onward into production.
                staging = Set(releases.map(\.base)).filter { b in b != p && exists(b) && releases.contains { $0.base == p && $0.head == b } }.sorted(by: byCount).first ?? ""
                let intoProduction = releases.filter { $0.base == p }
                var labels: [String] = []
                for h in Set(intoProduction.map(\.head)).sorted() {
                    if h != trunk && h != staging && !releaseLike(h) && !releaseBranches.contains(h) { releaseBranches.append(h) }
                    let label = releaseLike(h) ? (h.hasPrefix("hotfix") ? "hotfix branches" : "release branches") : h
                    if !labels.contains(label) { labels.append(label) }
                }
                source = "history"
                why = "\(intoProduction.count) release\(intoProduction.count == 1 ? "" : "s") into \(p) from \(labels.joined(separator: ", "))"
                    + (staging.isEmpty ? "" : "; \(releases.filter { $0.base == staging }.count) into \(staging)")
            }
        }

        if source == "branches" {
            why = merges.isEmpty ? "branch names only: no history read" : "branch names: no release among the last \(merges.count) merges"
        }
        // No releases, and a workflow that deploys on every push to the trunk: every merge ships.
        var ship = "release"
        if production.isEmpty, deploysOnPush {
            ship = "merge"; source = "workflow"; why = "deploys on every push to \(trunk)"
        }
        // No release branch and no deploying workflow, but the repository tags what it ships: the tag is
        // the release. Work merged since the newest tag is waiting; a new tag sends it. This is how a
        // library, a command line tool or anything installed from a release ships.
        if production.isEmpty, ship == "release", tagged {
            ship = "tag"; source = "tags"; why = "no release branch: what is tagged on \(trunk) has shipped"
        }

        // The repository's own word, where it gives one.
        if let f = file {
            if let t = f.trunk, !t.isEmpty { trunk = t }
            if let s = f.staging { staging = s }
            if let p = f.production { production = p }
            if let r = f.releaseBranches { releaseBranches = r }
            if let s = f.ship { ship = s }
            source = "file"; why = ".github/rumkapsel.json"
        }
        return Pipeline(trunk: trunk, staging: staging, production: production, releaseBranches: releaseBranches,
                        boardColumns: file?.boardColumns, source: source, why: why, ship: ship)
    }
}
