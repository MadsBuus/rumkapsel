// Model-only tests of how a piece of work is named: `.build/debug/Rumkapsel --work-tests`.
//
// No station. A branch, an issue and a pull request in every combination a source can bring them,
// and the office key, the crate number and the name must come out the one way, whoever asked.

import Foundation

enum WorkTests {
    private static var failures = 0

    static func run() -> Never {
        test("a branch named for its issue is that issue: office, crate and name agree") {
            let w = Work(repo: "web", branch: "gh-128/artist-search-fixes")
            expect(w.issue == 128 && w.number == 128, "issue read off the branch")
            expect(w.officeKey == "task:web#128", "office keyed by issue, got \(w.officeKey)")
            expect(w.name == "#128 artist search fixes", "named by issue and words, got \(w.name)")
            expect(w.label == "#128", "labelled by number")
        }

        test("a branch with no issue is the branch, until a pull request opens on it") {
            let w = Work(repo: "web", branch: "feature/search-fixes")
            expect(w.number == nil && w.officeKey == "task:web/feature/search-fixes", "keyed by branch, got \(w.officeKey)")
            expect(w.name == "search fixes", "named by the branch's last part, got \(w.name)")
            let opened = Work(repo: "web", branch: "feature/search-fixes", pull: 460)
            expect(opened.number == 460 && opened.officeKey == "task:web#460", "the pull request names it once there is one")
            expect(opened.name == w.name, "the name does not change with the number")
            expect(opened.label == "#460", "labelled by the pull request")
        }

        test("an issue outranks a pull request as the number, whichever came first") {
            let a = Work(repo: "web", branch: "feature/x", issue: 128, pull: 460)
            let b = Work(repo: "web", issue: 128, pull: 460)
            expect(a.number == 128 && b.number == 128, "the issue is the crate")
            expect(a.officeKey == b.officeKey && a.officeKey == "task:web#128", "and the office")
            expect(Work(repo: "web", branch: "gh-128/x", pull: 460).number == 128, "a branch's issue too")
        }

        test("the trunk is not work") {
            for b in ["main", "master", "develop", "HEAD", ""] {
                let w = Work(repo: "web", branch: b)
                expect(!w.isTask && w.officeKey == "proj:web" && w.name == "web", "\(b) is the project, got \(w.officeKey)")
            }
            expect(Work(repo: "web", branch: nil).officeKey == "proj:web", "no branch is the project")
            expect(Work(repo: "web", branch: "main", pull: 3).isTask, "but a pull request is work whatever the branch")
        }

        test("a board issue with no branch gets the same office a checkout of gh-N would") {
            let board = Work(repo: "api", issue: 5158)
            let checkout = Work(repo: "api", branch: "gh-5158/offerings-gate")
            expect(board.officeKey == checkout.officeKey, "one office, got \(board.officeKey) and \(checkout.officeKey)")
            expect(Work.guessedBranch(issue: 5158) == "gh-5158", "and a branch name to stand in until one is known")
        }

        test("the number can be read back off an office key, and only a task's") {
            expect(Work.number(inOfficeKey: "task:web#128") == 128, "by number")
            expect(Work.number(inOfficeKey: "task:web/feature/x") == nil, "a branch key has none")
            expect(Work.number(inOfficeKey: "proj:web") == nil && Work.number(inOfficeKey: "kind:lounge") == nil, "nor the rest")
        }

        test("long names are cut at a word") {
            let w = Work(repo: "web", branch: "gh-7/a-very-long-branch-name-that-goes-on-and-on")
            expect(w.name.count <= 4 + 22 && !w.name.hasSuffix(" "), "within the limit, got \(w.name)")
            expect(w.name.hasPrefix("#7 a very long"), "whole words kept, got \(w.name)")
        }

        say(failures == 0 ? "work: all passed" : "work: \(failures) failed")
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
