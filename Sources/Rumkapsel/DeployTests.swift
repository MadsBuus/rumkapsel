// Model-only tests of how GitHub Actions runs become flights: `.build/debug/Rumkapsel --deploy-tests`.
//
// No station and no GitHub. Runs as `gh run list` reports them in, started and ended out; workflow files in,
// whether they deploy a branch out.

import Foundation

enum DeployTests {
    private static var failures = 0
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private static func run(_ id: Int, _ workflow: String = "Deploy", status: String = "completed", conclusion: String = "success",
                            began: Double = 0, took: Double = 540, title: String = "Merge pull request #5466 from org/staging") -> DeployRun {
        DeployRun(id: id, workflow: workflow, branch: "production", status: status, conclusion: status == "completed" ? conclusion : "",
                  startedAt: t0.addingTimeInterval(began), updatedAt: t0.addingTimeInterval(began + took), title: title)
    }

    static func run() -> Never {
        test("only deploys count: CI on the same push is left out") {
            let runs = [run(3, "CI"), run(2, "Deploy to Amazon ECS"), run(1, "Ship it")]
            expect(Deployments.deploys(runs, deploying: []).map(\.id) == [2], "named for deploying")
            expect(Deployments.deploys(runs, deploying: ["Ship it"]).map(\.id) == [2], "a workflow named for deploying wins")
            expect(Deployments.deploys([run(3, "CI"), run(1, "Ship it")], deploying: ["Ship it"]).map(\.id) == [1], "else its file deploys")
        }

        test("the usual length is the middle of the successful runs, failures and runs under way aside") {
            let runs = [run(5, status: "in_progress"), run(4, took: 600), run(3, conclusion: "failure", took: 30),
                        run(2, took: 480), run(1, took: 540)]
            expect(Deployments.usual(runs) == 540, "median of 600, 480, 540, got \(Deployments.usual(runs))")
            expect(Deployments.usual([run(1, took: 400), run(2, took: 600)]) == 500, "even count: the two middles")
            expect(Deployments.usual([]) == Deployments.fallback, "no history: the fallback")
        }

        test("the first look is quiet about what is over, and joins what runs where it has got to") {
            expect(Deployments.changes(was: nil, runs: [run(1)], firstLook: true, at: t0.addingTimeInterval(900)).isEmpty, "done before we looked")
            let joined = Deployments.changes(was: nil, runs: [run(2, status: "in_progress")], firstLook: true, at: t0.addingTimeInterval(120))
            expect(joined == [.started(run(2, status: "in_progress"), elapsed: 120)], "two minutes in, got \(joined)")
        }

        test("a run seen starting, then ending, each once") {
            let going = run(2, status: "in_progress")
            let started = Deployments.changes(was: run(1), runs: [going, run(1)], firstLook: false, at: t0.addingTimeInterval(10))
            expect(started == [.started(going, elapsed: 10)], "started, got \(started)")
            let again = Deployments.changes(was: going, runs: [going, run(1)], firstLook: false, at: t0.addingTimeInterval(20))
            expect(again.isEmpty, "still running says nothing, got \(again)")
            let done = run(2)
            expect(Deployments.changes(was: going, runs: [done, run(1)], firstLook: false, at: t0) == [.ended(done, .live)], "live")
            expect(Deployments.changes(was: done, runs: [done, run(1)], firstLook: false, at: t0).isEmpty, "and only once")
        }

        test("failed and cancelled end as such") {
            let going = run(2, status: "in_progress")
            let failed = run(2, conclusion: "failure"), cancelled = run(2, conclusion: "cancelled")
            expect(Deployments.changes(was: going, runs: [failed], firstLook: false, at: t0) == [.ended(failed, .failed)], "failed")
            expect(Deployments.changes(was: going, runs: [cancelled], firstLook: false, at: t0) == [.ended(cancelled, .cancelled)], "cancelled")
        }

        test("a newer deploy takes over from one still running") {
            let old = run(2, status: "in_progress"), oldDone = run(2, conclusion: "cancelled"), new = run(3, status: "in_progress", began: 60)
            let c = Deployments.changes(was: old, runs: [new, oldDone], firstLook: false, at: t0.addingTimeInterval(70))
            expect(c == [.ended(oldDone, .cancelled), .started(new, elapsed: 10)], "the old one ends as the list says, got \(c)")
            let gone = Deployments.changes(was: old, runs: [new], firstLook: false, at: t0.addingTimeInterval(70))
            expect(gone.first == .ended(old, .cancelled), "off the list: cancelled")
        }

        test("a whole deploy between two looks is started and ended") {
            let c = Deployments.changes(was: run(1), runs: [run(2), run(1)], firstLook: false, at: t0.addingTimeInterval(900))
            expect(c.count == 2 && c.last == .ended(run(2), .live), "both, got \(c)")
        }

        test("an answer older than what is known is stale: GitHub serves old snapshots now and then") {
            expect(Deployments.isStale([run(1)], known: run(2)), "older newest")
            expect(!Deployments.isStale([run(3), run(2)], known: run(2)), "newer or the same is fine")
            expect(!Deployments.isStale([run(1)], known: nil), "nothing known yet")
        }

        test("a deploy long over when first heard of is history, not a flight") {
            let old = run(2, began: 0, took: 500)
            let c = Deployments.changes(was: run(1), runs: [old, run(1)], firstLook: false, at: t0.addingTimeInterval(18 * 3600))
            expect(c.isEmpty, "yesterday's deploy flies nothing, got \(c)")
        }

        test("a deploy over before the station was watching is history, even after a stale first look") {
            let stale = run(1, began: -30 * 86400)
            let fresh = run(2, began: 0, took: 400)
            let watching = t0.addingTimeInterval(20 * 60)   // the app started twenty minutes after that deploy began
            let c = Deployments.changes(was: stale, runs: [fresh, stale], firstLook: false, at: t0.addingTimeInterval(23 * 60), watchingSince: watching)
            expect(c.isEmpty, "the replay of an earlier deploy flies nothing, got \(c)")
            let live = run(3, status: "in_progress", began: 25 * 60)
            let d = Deployments.changes(was: fresh, runs: [live, fresh], firstLook: false, at: t0.addingTimeInterval(26 * 60), watchingSince: watching)
            expect(d == [.started(live, elapsed: 60)], "one begun since still flies, got \(d)")
        }

        test("the release is the pull request the merge names") {
            expect(run(1).release == "#5466", "from the merge's title")
            expect(run(1, title: "chore: bump").release == "", "nothing named: nothing")
        }

        test("a workflow deploys a branch when it runs on a push to it and deploys") {
            let ecs = """
            name: Deploy to Amazon ECS
            on:
              push:
                branches: [ staging, production ]
            jobs:
              deploy:
                environment: ${{ github.ref_name }}
            """
            expect(Deployments.deploys(onPushTo: "production", workflow: ecs), "listed inline")
            expect(!Deployments.deploys(onPushTo: "develop", workflow: ecs), "not another branch")
            expect(Deployments.name(ofWorkflow: ecs) == "Deploy to Amazon ECS", "named")
            let listed = "name: 'Ship'\non:\n  push:\n    branches:\n      - main\njobs:\n  go:\n    steps:\n      - run: npx vercel --prod\n"
            expect(Deployments.deploys(onPushTo: "main", workflow: listed), "a list, a deploy tool")
            expect(Deployments.name(ofWorkflow: listed) == "Ship", "quotes taken off")
            let ci = "name: CI\non:\n  push:\n    branches: [main]\njobs:\n  test:\n    steps:\n      - run: npm test  # before deploy\n"
            expect(!Deployments.deploys(onPushTo: "main", workflow: ci), "tests are not a deploy")
            let pr = "name: Preview\non:\n  pull_request:\n    branches: [main]\njobs:\n  d:\n    steps:\n      - run: vercel\n"
            expect(!Deployments.deploys(onPushTo: "main", workflow: pr), "a pull request is not a push")
        }

        say(failures == 0 ? "deploys: all passed" : "deploys: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func test(_ name: String, _ body: () -> Void) {
        let before = failures
        body()
        say((failures == before ? "PASS  " : "FAIL  ") + name)
    }
    private static func expect(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; say("      expected: \(what)") }
    }
    private static func say(_ s: String) { FileHandle.standardOutput.write((s + "\n").data(using: .utf8)!) }
}
