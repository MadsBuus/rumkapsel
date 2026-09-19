// Model-only tests of pipeline detection: `.build/debug/Rumkapsel --pipeline-tests`.
//
// Histories shaped like the real repositories', and the cases detection must not get wrong: a staging
// branch nobody releases through, a branch that is gone, no history at all, and a repository's own file.

import Foundation

enum PipelineTests {
    private static var failures = 0

    static func run() -> Never {
        typealias M = PipelineDetection.Merge
        let names = (trunk: "develop", staging: "staging", production: "production")
        func features(_ base: String, _ n: Int) -> [M] { (0..<n).map { M(base: base, head: "gh-\($0)/work") } }
        func times(_ m: M, _ n: Int) -> [M] { Array(repeating: m, count: n) }
        func flow(_ p: Pipeline) -> String { "\(p.trunk) → \(p.staging.isEmpty ? "-" : p.staging) → \(p.production.isEmpty ? "-" : p.production)" }

        test("staging then production, as api, web and backend release") {
            let p = PipelineDetection.detect(branches: ["develop", "staging", "production"],
                                             merges: features("develop", 12) + times(M(base: "staging", head: "develop"), 3) + times(M(base: "production", head: "staging"), 3),
                                             file: nil, names: names)
            expect(flow(p) == "develop → staging → production", "got \(flow(p))")
            expect(p.source == "history", "from history, got \(p.source)")
        }

        test("staging into main, as ios releases") {
            let p = PipelineDetection.detect(branches: ["develop", "staging", "main"],
                                             merges: features("develop", 8) + times(M(base: "staging", head: "develop"), 2) + times(M(base: "main", head: "staging"), 2),
                                             file: nil, names: names)
            expect(flow(p) == "develop → staging → main", "got \(flow(p))")
        }

        test("a release branch into master with no staging, as android releases") {
            let merges = features("develop", 10) + [M(base: "release/v9.7.1", head: "develop"), M(base: "master", head: "release/v9.7.1"),
                                                   M(base: "master", head: "release/v9.7.0")] + times(M(base: "develop", head: "master"), 2)
            let p = PipelineDetection.detect(branches: ["develop", "master", "release/v9.7.1"], merges: merges, file: nil, names: names)
            expect(flow(p) == "develop → - → master", "got \(flow(p))")
            expect(p.isReleaseHead("release/v9.7.1") && !p.isReleaseHead("gh-12/work"), "a release branch is a release head, a feature branch is not")
        }

        test("a staging branch nobody releases through is not used") {
            let p = PipelineDetection.detect(branches: ["develop", "staging", "production"],
                                             merges: features("develop", 6) + times(M(base: "production", head: "develop"), 3), file: nil, names: names)
            expect(flow(p) == "develop → - → production", "got \(flow(p))")
        }

        test("a branch the history names but that is gone is not used") {
            let p = PipelineDetection.detect(branches: ["develop", "production"],
                                             merges: features("develop", 6) + times(M(base: "staging", head: "develop"), 2) + times(M(base: "production", head: "staging"), 2),
                                             file: nil, names: names)
            expect(flow(p) == "develop → - → production", "got \(flow(p))")
        }

        test("merges back against the flow, as api, web and backend keep staging in step, do not hide production") {
            let merges = features("develop", 50) + times(M(base: "staging", head: "develop"), 28) + times(M(base: "production", head: "staging"), 5)
                + times(M(base: "staging", head: "production"), 3) + times(M(base: "develop", head: "staging"), 3) + times(M(base: "production", head: "gh-9/hotfix-work"), 8)
            let p = PipelineDetection.detect(branches: ["develop", "staging", "production"], merges: merges, file: nil, names: names)
            expect(flow(p) == "develop → staging → production", "got \(flow(p))")
            expect(p.source == "history", "from history, got \(p.source): \(p.why)")
        }

        test("no releases and a workflow deploying on push: every merge ships, as release-note-bot does") {
            let p = PipelineDetection.detect(branches: ["main"], merges: features("main", 20), file: nil, names: names, deploysOnPush: true)
            expect(p.shipsOnMerge && p.trunk == "main" && p.source == "workflow", "ships on merge from main, got \(p.ship) from \(p.trunk), \(p.source)")
            let q = PipelineDetection.detect(branches: ["main"], merges: features("main", 20), file: nil, names: names)
            expect(!q.shipsOnMerge, "without a deploying workflow it does not")
            let r = PipelineDetection.detect(branches: ["develop", "staging", "production"],
                                             merges: features("develop", 6) + times(M(base: "production", head: "staging"), 2) + times(M(base: "staging", head: "develop"), 2),
                                             file: nil, names: names, deploysOnPush: true)
            expect(!r.shipsOnMerge, "a repository with releases ships by release, whatever its workflows do")
            let f = PipelineDetection.detect(branches: ["main"], merges: [], file: ReleaseFile(ship: "merge"), names: names)
            expect(f.shipsOnMerge && f.source == "file", "the repository's file can say so")
        }

        test("no release branch but tags on the trunk: the tag is the release, as rumkapsel's own is") {
            let p = PipelineDetection.detect(branches: ["main"], merges: features("main", 20), file: nil, names: names, tagged: true)
            expect(p.shipsOnTag && p.trunk == "main" && p.source == "tags", "ships on tags from main, got \(p.ship) from \(p.trunk), \(p.source)")
            expect(!p.shipsOnMerge && p.production.isEmpty, "a tag is not a production branch, and not a deploy on merge")
            let q = PipelineDetection.detect(branches: ["main"], merges: features("main", 20), file: nil, names: names)
            expect(!q.shipsOnTag, "untagged, it waits for a release that never comes")
            // Tags are what is left when nothing better is known: a repository that releases by branch,
            // or deploys every push, ships that way however many tags it has lying about.
            let r = PipelineDetection.detect(branches: ["develop", "staging", "production"],
                                             merges: features("develop", 6) + times(M(base: "production", head: "staging"), 2) + times(M(base: "staging", head: "develop"), 2),
                                             file: nil, names: names, tagged: true)
            expect(!r.shipsOnTag && r.production == "production", "a repository with releases ships by release, tags or no tags")
            let d = PipelineDetection.detect(branches: ["main"], merges: features("main", 20), file: nil, names: names, deploysOnPush: true, tagged: true)
            expect(d.shipsOnMerge, "a deploying workflow is the truer answer: it ships without anyone tagging")
            let f = PipelineDetection.detect(branches: ["main"], merges: [], file: ReleaseFile(ship: "tag"), names: names)
            expect(f.shipsOnTag && f.source == "file", "the repository's file can say so")
        }

        test("no history: the branch names decide") {
            let p = PipelineDetection.detect(branches: ["develop", "staging", "production"], merges: [], file: nil, names: names)
            expect(flow(p) == "develop → staging → production", "got \(flow(p))")
            expect(p.source == "branches", "from branch names, got \(p.source)")
        }

        test("the repository's file overrides history, for everyone") {
            let file = ReleaseFile(trunk: nil, staging: "", production: "master", releaseBranches: ["cut/*"], boardColumns: false)
            let p = PipelineDetection.detect(branches: ["develop", "staging", "production", "master"],
                                             merges: features("develop", 12) + times(M(base: "staging", head: "develop"), 3) + times(M(base: "production", head: "staging"), 3),
                                             file: file, names: names)
            expect(flow(p) == "develop → - → master", "got \(flow(p))")
            expect(p.releaseBranches == ["cut/*"] && p.isReleaseHead("cut/2026-09") && !p.isReleaseHead("release/v1"), "its release branches replace the defaults")
            expect(p.boardColumns == false && p.source == "file", "its board choice and its name as the source")
        }

        test("branches set by hand in Settings go over what was detected, and only while they are set") {
            let read = PipelineDetection.detect(branches: ["main"], merges: features("main", 5), file: nil, names: names, deploysOnPush: true)
            let set = read.overridden(by: AppConfig.Branches(trunk: "main", staging: "", production: "live"))
            expect(flow(set) == "main → - → live" && set.source == "override", "got \(flow(set)) from \(set.source)")
            expect(!set.shipsOnMerge, "a production branch set by hand means releases, not every merge")
            expect(read.overridden(by: nil) == read, "nothing set leaves the detection as it was")
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
