import Foundation

enum PipelineTests {
    private static var failures = 0

    static func run() -> Never {
        typealias M = PipelineDetection.Merge
        func features(_ base: String, _ n: Int) -> [M] { (0..<n).map { M(base: base, head: "gh-\($0)/work") } }
        func times(_ m: M, _ n: Int) -> [M] { Array(repeating: m, count: n) }
        func flow(_ p: Pipeline) -> String { "\(p.trunk) → \(p.staging.isEmpty ? "-" : p.staging) → \(p.production.isEmpty ? "-" : p.production)" }

        test("staging then production, as api, web and backend release") {
            let p = PipelineDetection.detect(branches: ["develop", "staging", "production"],
                                             merges: features("develop", 12) + times(M(base: "staging", head: "develop"), 3) + times(M(base: "production", head: "staging"), 3),
                                             file: nil)
            expect(flow(p) == "develop → staging → production", "got \(flow(p))")
            expect(p.source == "history", "from history, got \(p.source)")
        }

        test("staging into main, as ios releases") {
            let p = PipelineDetection.detect(branches: ["develop", "staging", "main"],
                                             merges: features("develop", 8) + times(M(base: "staging", head: "develop"), 2) + times(M(base: "main", head: "staging"), 2),
                                             file: nil)
            expect(flow(p) == "develop → staging → main", "got \(flow(p))")
        }

        test("a release branch into master with no staging, as android releases") {
            let merges = features("develop", 10) + [M(base: "release/v9.7.1", head: "develop"), M(base: "master", head: "release/v9.7.1"),
                                                   M(base: "master", head: "release/v9.7.0")] + times(M(base: "develop", head: "master"), 2)
            let p = PipelineDetection.detect(branches: ["develop", "master", "release/v9.7.1"], merges: merges, file: nil)
            expect(flow(p) == "develop → - → master", "got \(flow(p))")
            expect(p.isReleaseHead("release/v9.7.1") && !p.isReleaseHead("gh-12/work"), "a release branch is a release head, a feature branch is not")
        }

        test("a staging branch nobody releases through is not used") {
            let p = PipelineDetection.detect(branches: ["develop", "staging", "production"],
                                             merges: features("develop", 6) + times(M(base: "production", head: "develop"), 3), file: nil)
            expect(flow(p) == "develop → - → production", "got \(flow(p))")
        }

        test("a branch the history names but that is gone is not used") {
            let p = PipelineDetection.detect(branches: ["develop", "production"],
                                             merges: features("develop", 6) + times(M(base: "staging", head: "develop"), 2) + times(M(base: "production", head: "staging"), 2),
                                             file: nil)
            expect(flow(p) == "develop → - → production", "got \(flow(p))")
        }

        test("as many merges back as releases forward: the flow runs away from the trunk, as api's history had it") {
            let merges = features("develop", 49) + times(M(base: "staging", head: "develop"), 30) + times(M(base: "production", head: "staging"), 3)
                + times(M(base: "staging", head: "production"), 3) + times(M(base: "develop", head: "staging"), 3) + features("production", 4)
            let p = PipelineDetection.detect(branches: ["develop", "staging", "production"], merges: merges, file: nil)
            expect(flow(p) == "develop → staging → production", "got \(flow(p)): \(p.why)")
            expect(p.isReleaseHead("staging"), "staging into production is a release")
        }

        test("merges back against the flow, as api, web and backend keep staging in step, do not hide production") {
            let merges = features("develop", 50) + times(M(base: "staging", head: "develop"), 28) + times(M(base: "production", head: "staging"), 5)
                + times(M(base: "staging", head: "production"), 3) + times(M(base: "develop", head: "staging"), 3) + times(M(base: "production", head: "gh-9/hotfix-work"), 8)
            let p = PipelineDetection.detect(branches: ["develop", "staging", "production"], merges: merges, file: nil)
            expect(flow(p) == "develop → staging → production", "got \(flow(p))")
            expect(p.source == "history", "from history, got \(p.source): \(p.why)")
        }

        test("more merges back than releases forward after a run of hotfixes: still away from the trunk, as api's history had it on 2026-10-20") {
            let merges = features("develop", 60) + times(M(base: "staging", head: "develop"), 25) + times(M(base: "staging", head: "production"), 4)
                + times(M(base: "production", head: "staging"), 3) + times(M(base: "develop", head: "staging"), 4) + times(M(base: "production", head: "gh-9/hotfix-prod"), 4)
            let p = PipelineDetection.detect(branches: ["develop", "staging", "production"], merges: merges, file: nil)
            expect(flow(p) == "develop → staging → production", "got \(flow(p)): \(p.why)")
            expect(!p.why.contains("from develop, production"), "a back-merge is no release: \(p.why)")
        }

        test("no releases and a workflow deploying on push: every merge ships, as release-note-bot does") {
            let p = PipelineDetection.detect(branches: ["main"], merges: features("main", 20), file: nil, deploysOnPush: true)
            expect(p.shipsOnMerge && p.trunk == "main" && p.source == "workflow", "ships on merge from main, got \(p.ship) from \(p.trunk), \(p.source)")
            let q = PipelineDetection.detect(branches: ["main"], merges: features("main", 20), file: nil)
            expect(!q.shipsOnMerge, "without a deploying workflow it does not")
            let r = PipelineDetection.detect(branches: ["develop", "staging", "production"],
                                             merges: features("develop", 6) + times(M(base: "production", head: "staging"), 2) + times(M(base: "staging", head: "develop"), 2),
                                             file: nil, deploysOnPush: true)
            expect(!r.shipsOnMerge, "a repository with releases ships by release, whatever its workflows do")
            let f = PipelineDetection.detect(branches: ["main"], merges: [], file: ReleaseFile(ship: .merge))
            expect(f.shipsOnMerge && f.source == "file", "the repository's file can say so")
        }

        test("no release branch but tags on the trunk: the tag is the release, as rumkapsel's own is") {
            let p = PipelineDetection.detect(branches: ["main"], merges: features("main", 20), file: nil, tagged: true)
            expect(p.shipsOnTag && p.trunk == "main" && p.source == "tags", "ships on tags from main, got \(p.ship) from \(p.trunk), \(p.source)")
            expect(!p.shipsOnMerge && p.production.isEmpty, "a tag is not a production branch, and not a deploy on merge")
            let q = PipelineDetection.detect(branches: ["main"], merges: features("main", 20), file: nil)
            expect(!q.shipsOnTag, "untagged, it waits for a release that never comes")
            let r = PipelineDetection.detect(branches: ["develop", "staging", "production"],
                                             merges: features("develop", 6) + times(M(base: "production", head: "staging"), 2) + times(M(base: "staging", head: "develop"), 2),
                                             file: nil, tagged: true)
            expect(!r.shipsOnTag && r.production == "production", "a repository with releases ships by release, tags or no tags")
            let d = PipelineDetection.detect(branches: ["main"], merges: features("main", 20), file: nil, deploysOnPush: true, tagged: true)
            expect(d.shipsOnMerge, "a deploying workflow is the truer answer: it ships without anyone tagging")
            let f = PipelineDetection.detect(branches: ["main"], merges: [], file: ReleaseFile(ship: .tag))
            expect(f.shipsOnTag && f.source == "file", "the repository's file can say so")
        }

        test("no history: the branch names decide") {
            let p = PipelineDetection.detect(branches: ["develop", "staging", "production"], merges: [], file: nil)
            expect(flow(p) == "develop → staging → production", "got \(flow(p))")
            expect(p.source == "branches", "from branch names, got \(p.source)")
        }

        test("the repository's file overrides history, for everyone") {
            let file = ReleaseFile(trunk: nil, staging: "", production: "master", releaseBranches: ["cut/*"], boardColumns: false)
            let p = PipelineDetection.detect(branches: ["develop", "staging", "production", "master"],
                                             merges: features("develop", 12) + times(M(base: "staging", head: "develop"), 3) + times(M(base: "production", head: "staging"), 3),
                                             file: file)
            expect(flow(p) == "develop → - → master", "got \(flow(p))")
            expect(p.releaseBranches == ["cut/*"] && p.isReleaseHead("cut/2026-09") && !p.isReleaseHead("release/v1"), "its release branches replace the defaults")
            expect(p.boardColumns == false && p.source == "file", "its board choice and its name as the source")
        }

        test("set by hand in Settings goes over what was detected, answer by answer, and only while it is set") {
            let read = PipelineDetection.detect(branches: ["main"], merges: features("main", 5), file: nil, deploysOnPush: true)
            let set = read.overridden(by: AppConfig.RepoOverride(trunk: "main", ships: .release, production: "live", staging: ""))
            expect(flow(set) == "main → - → live" && set.source == "override", "got \(flow(set)) from \(set.source)")
            expect(!set.shipsOnMerge, "a production branch set by hand means releases, not every merge")
            let tags = read.overridden(by: AppConfig.RepoOverride(ships: .tag))
            expect(tags.shipsOnTag && tags.production.isEmpty && tags.trunk == "main", "only how it ships changed: \(tags.ship), \(flow(tags))")
            let tested = read.overridden(by: AppConfig.RepoOverride(staging: "qa"))
            expect(tested.staging == "qa" && tested.shipsOnMerge, "a testing phase alone keeps how it ships: \(tested.ship)")
            expect(read.overridden(by: nil) == read && read.overridden(by: AppConfig.RepoOverride(share: true)) == read, "nothing set leaves the detection as it was")
        }

        test("GitHub's default branch is the trunk, over a stale develop") {
            let p = PipelineDetection.detect(branches: ["develop", "main"], merges: [], file: nil, defaultBranch: "main")
            expect(p.trunk == "main", "the default branch, got \(p.trunk)")
            let q = PipelineDetection.detect(branches: ["develop", "main"], merges: [], file: nil)
            expect(q.trunk == "develop", "without a default branch the names decide, got \(q.trunk)")
            let r = PipelineDetection.detect(branches: ["develop", "main"], merges: features("develop", 12), file: nil, defaultBranch: "main")
            expect(r.trunk == "develop", "where the pull requests merge beats the default branch, got \(r.trunk)")
        }

        test("a default branch that is a release branch is no trunk: api-node-nest's origin/HEAD is production, image-lambda's default staging") {
            let api = PipelineDetection.detect(branches: ["develop", "staging", "production"],
                                               merges: features("develop", 30) + times(M(base: "staging", head: "develop"), 20) + times(M(base: "production", head: "staging"), 2),
                                               file: nil, defaultBranch: "production")
            expect(flow(api) == "develop → staging → production" && api.ship == .release, "api: \(flow(api)), \(api.ship)")
            let unread = PipelineDetection.detect(branches: ["develop", "staging", "production"], merges: [], file: nil, defaultBranch: "production", history: false)
            expect(flow(unread) == "develop → staging → production", "api with no history: \(flow(unread))")
            let lambda = PipelineDetection.detect(branches: ["staging", "production", "early-return"],
                                                  merges: features("staging", 20) + times(M(base: "production", head: "staging"), 17), file: nil, defaultBranch: "staging")
            expect(flow(lambda) == "staging → - → production" && lambda.ship == .release, "image-lambda: \(flow(lambda)), \(lambda.ship)")
        }

        test("without history the default branch does not outrank develop") {
            let p = PipelineDetection.detect(branches: ["develop", "main"], merges: [], file: nil, defaultBranch: "main", history: false)
            expect(p.trunk == "develop", "develop while history is unread, got \(p.trunk)")
        }

        test("a stale master beside main: tags win over a guessed production branch; history still decides") {
            let tagged = PipelineDetection.detect(branches: ["main", "master"], merges: features("main", 5), file: nil, defaultBranch: "main", tagged: true)
            expect(tagged.shipsOnTag && tagged.production.isEmpty, "ships on tags, not from master: \(tagged.ship), \(flow(tagged))")
            let plain = PipelineDetection.detect(branches: ["main", "master"], merges: features("main", 5), file: nil, defaultBranch: "main")
            expect(plain.ship == .release && plain.production == "master", "untagged, master is still the guess: \(plain.ship), \(flow(plain))")
            let released = PipelineDetection.detect(branches: ["main", "master"], merges: features("main", 5) + times(M(base: "master", head: "main"), 3),
                                                    file: nil, defaultBranch: "main", tagged: true)
            expect(released.ship == .release && released.production == "master", "releases into master win over tags: \(released.ship)")
            let named = PipelineDetection.detect(branches: ["main", "production"], merges: [], file: nil, defaultBranch: "main", tagged: true)
            expect(named.ship == .release, "a branch called production is no guess: \(named.ship)")
        }

        test("a failed read keeps what was known, and stores nothing new; the cache follows the remote") {
            let known = PipelineDetection.detect(branches: ["develop", "staging", "production"], merges: features("develop", 5), file: nil)
            let partial = PipelineDetection.detect(branches: ["main"], merges: [], file: nil, history: false)
            expect(PipelineDetection.settle(cached: known, read: partial, failed: true) == known, "a failed read keeps the cached way")
            expect(PipelineDetection.settle(cached: nil, read: partial, failed: true) == nil, "nothing cached and a failed read: nothing stored")
            expect(PipelineDetection.settle(cached: known, read: partial, failed: false) == partial, "a whole read replaces it")
            var local = known; local.remote = false
            expect(PipelineDetection.settle(cached: local, read: partial, failed: true) == nil, "a cache from before the remote changed is not kept")
        }

        test("a plain repository: main only, nothing tagged, no deploy: it doesn't ship") {
            let p = PipelineDetection.detect(branches: ["main", "claude/x"], merges: features("main", 8), file: nil, defaultBranch: "main")
            expect(p.trunk == "main" && p.ship == .never && !p.ships && p.production.isEmpty && !p.hasStaging, "got \(flow(p)), \(p.ship)")
            expect(Setup.way(p) == "doesn't ship", "says so: \(Setup.way(p))")
        }

        test("tags only, no GitHub releases, no production branch: it ships on tags, as rumkapsel does with release.sh") {
            let now = Date()
            let tags = [(name: "v0.66", at: now.addingTimeInterval(-3600)), (name: "v0.65", at: now.addingTimeInterval(-86400))]
            expect(PipelineDetection.tagged(tags, now: now), "recent version tags count")
            expect(!PipelineDetection.tagged([(name: "v1.0", at: now.addingTimeInterval(-400 * 86400))], now: now), "a tag from years ago does not")
            expect(!PipelineDetection.tagged([(name: "nightly", at: now)], now: now), "a tag that is no version does not")
            let merges = (0..<20).map { M(base: "main", head: "claude/work-\($0)") }
            let p = PipelineDetection.detect(branches: ["main", "claude/work-1", "claude/work-2"], merges: merges, file: nil, defaultBranch: "main",
                                             tagged: PipelineDetection.tagged(tags, now: now))
            expect(p.shipsOnTag && p.trunk == "main" && p.production.isEmpty && !p.hasStaging, "ships on tags from main, got \(p.ship) from \(flow(p))")
            expect(Setup.way(p) == "ships on tags", "says so: \(Setup.way(p))")
        }

        test("how it ships, one rule each: a production branch, a deploy on push, tags, nothing") {
            let release = PipelineDetection.detect(branches: ["main", "production"], merges: [], file: nil, defaultBranch: "main", deploysOnPush: true, tagged: true)
            expect(release.ship == .release && release.production == "production", "a production branch means release pull requests: \(release.ship)")
            let merge = PipelineDetection.detect(branches: ["main"], merges: [], file: nil, defaultBranch: "main", deploysOnPush: true)
            expect(merge.ship == .merge, "a deploy on push to the trunk ships every merge: \(merge.ship)")
            let tag = PipelineDetection.detect(branches: ["main"], merges: [], file: nil, defaultBranch: "main", tagged: true)
            expect(tag.ship == .tag, "tags ship: \(tag.ship)")
            let never = PipelineDetection.detect(branches: ["main"], merges: [], file: nil, defaultBranch: "main")
            expect(never.ship == .never, "nothing ships: \(never.ship)")
        }

        test("no GitHub remote: local work only") {
            let p = PipelineDetection.detect(branches: ["main", "feature"], merges: [], file: nil, deploysOnPush: true, tagged: true, remote: false)
            expect(!p.remote && p.ship == .never && p.trunk == "main" && p.source == "local", "got \(p.ship) from \(p.trunk), \(p.source)")
            expect(Setup.way(p) == "local work only", "says so: \(Setup.way(p))")
        }

        test("today's Tattoodo flow: develop, staging and production, as before") {
            let p = PipelineDetection.detect(branches: ["develop", "staging", "production", "gh-1/work"],
                                             merges: features("develop", 30) + times(M(base: "staging", head: "develop"), 4) + times(M(base: "production", head: "staging"), 4),
                                             file: nil, defaultBranch: "develop")
            expect(flow(p) == "develop → staging → production" && p.ship == .release, "got \(flow(p)), \(p.ship)")
            expect(Setup.way(p) == "ships from production through staging", "says so: \(Setup.way(p))")
        }

        say(failures == 0 ? "pipelines: all passed" : "pipelines: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func test(_ name: String, _ body: () -> Void) {
        let before = failures
        body()
        say((failures == before ? "PASS  " : "FAIL  ") + name)
    }
    private static func expect(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; say("      not so: \(what)") }
    }
    private static func say(_ text: String) { FileHandle.standardError.write((text + "\n").data(using: .utf8)!) }
}
