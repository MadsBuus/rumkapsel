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

        test("one record, whoever saw it first: a folder, then a branch, then a pull request, then an issue") {
            let book = WorkBook()
            let first = book.note(repo: "web", folder: "/w/search")
            expect(first.work().officeKey == "proj:web", "a folder alone names nothing yet")
            let named = book.note(repo: "web", branch: "feature/search", folder: "/w/search")
            expect(named === first && named.work().officeKey == "task:web/feature/search", "the branch joins the folder's record")
            let opened = book.note(repo: "web", branch: "feature/search", pull: 460, pullState: "OPEN")
            expect(opened === first && opened.work().officeKey == "task:web#460", "the pull request names it once open")
            let linked = book.note(repo: "web", issue: 128, pull: 460)
            expect(linked === first && linked.number == 128 && linked.work().officeKey == "task:web#460", "the issue is the crate; the office keeps the pull request's name")
            expect(book.find(repo: "web", issue: 128) === first && book.find(folder: "/w/search") === first, "found by any name")
            expect(book.count == 1, "one record, got \(book.count)")
        }

        test("a board issue and a checkout of its branch are one record, whichever came first") {
            let book = WorkBook()
            let board = book.note(repo: "api", issue: 5158, pull: 77)
            let checkout = book.note(repo: "api", branch: "gh-5158/offerings-gate", folder: "/w/api")
            expect(board === checkout && book.count == 1, "one record")
            expect(checkout.work().officeKey == "task:api#5158" && checkout.number == 5158, "named by the issue")
            expect(book.find(officeKey: "task:api#5158", repo: "api") === board, "found by the office key")
        }

        test("a pull request that closes stops naming the office; the branch does again") {
            let book = WorkBook()
            let r = book.note(repo: "web", branch: "feature/x", pull: 9, pullState: "OPEN")
            expect(r.work().officeKey == "task:web#9", "open: by number")
            book.note(repo: "web", pull: 9, pullState: "MERGED")
            expect(r.work().officeKey == "task:web/feature/x" && r.number == 9, "merged: the office by branch, the crate still #9")
        }

        test("two records that turn out to be one fold together, the older keeping its id") {
            let book = WorkBook()
            let a = book.note(repo: "web", branch: "feature/x")
            let b = book.note(repo: "web", pull: 9)
            expect(a !== b && book.count == 2, "two, until a name joins them")
            let c = book.note(repo: "web", branch: "feature/x", pull: 9)
            expect(c === a && book.count == 1 && book.find(repo: "web", pull: 9) === a, "one, under the older id")
            expect(a.pulls[9] == "OPEN" && a.branches == ["feature/x"], "with both names")
        }

        let t0 = Date(timeIntervalSince1970: 1_000)
        func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

        test("forward, the furthest word wins whoever said it first; a lower word changes nothing") {
            let r = WorkBook.Record(id: 1, repo: "web")
            expect(r.hear(Signal(stage: .ready, by: .pulls, at: at(0)))?.to == .ready, "a first word places it")
            expect(r.hear(Signal(stage: .qa, by: .board, at: at(1)))?.to == .qa && r.stagedBy == .board, "the board says QA first: QA")
            expect(r.hear(Signal(stage: .stored, by: .git, at: at(2))) == nil && r.stage == .qa, "git catching up with stored changes nothing")
            expect(r.hear(Signal(stage: .qa, by: .git, at: at(3))) == nil && r.stagedBy == .board, "git agreeing changes nothing either")
            expect(r.hear(Signal(stage: .shipped, by: .git, at: at(4)))?.to == .shipped, "git saying shipped first moves it on")
        }

        test("back, only the first in line takes work back, and only by changing its own word") {
            let r = WorkBook.Record(id: 1, repo: "web")
            _ = r.hear(Signal(stage: .stored, by: .pulls, at: at(0)))
            _ = r.hear(Signal(stage: .qa, by: .board, at: at(1)))
            expect(r.hear(Signal(stage: .stored, by: .pulls, at: at(2))) == nil && r.stage == .qa, "pull requests are not first in line for QA: no")
            let r2 = WorkBook.Record(id: 2, repo: "web")
            _ = r2.hear(Signal(stage: .qa, by: .pulls, at: at(0)))
            expect(r2.hear(Signal(stage: .stored, by: .board, at: at(1))) == nil && r2.stage == .qa, "the board is first in line but never said QA: not a change of word, no")
            let back = r.hear(Signal(stage: .stored, by: .board, at: at(3)))
            expect(back?.to == .stored && back?.back == true && r.stage == .stored, "the board that said QA now says stored: back it goes")
        }

        test("records that fold keep the furthest stage and every source's newest word") {
            let book = WorkBook()
            let a = book.note(repo: "web", branch: "feature/x")
            book.report(a, .working, by: .session, at: at(0))
            let b = book.note(repo: "web", pull: 9)
            book.report(b, .ready, by: .pulls, at: at(1))
            let c = book.note(repo: "web", branch: "feature/x", pull: 9)
            expect(c === a && c.stage == .ready && c.stagedBy == .pulls, "one record at ready, got \(String(describing: c.stage))")
            expect(c.words[.session] == .working && c.words[.pulls] == .ready, "both words kept")
        }

        test("a crate number from the counts is work of its own until a name claims it") {
            let book = WorkBook()
            let counted = book.note(repo: "web", crate: 460)
            book.report(counted, .stored, by: .git, at: at(0))
            let named = book.note(repo: "web", branch: "feature/x", pull: 460, pullState: "MERGED")
            expect(named === counted && named.stage == .stored && named.number == 460, "the pull request claims the counted crate")
            expect(book.count == 1, "one record, got \(book.count)")
        }

        test("a workflow without QA or cleared hears neither; one detected from a pipeline says which") {
            var w = Workflow(); w.qa = nil; w.cleared = nil
            let r = WorkBook.Record(id: 1, repo: "web")
            _ = r.hear(Signal(stage: .stored, by: .pulls, at: at(0)), workflow: w)
            expect(r.hear(Signal(stage: .qa, by: .board, at: at(1)), workflow: w) == nil && r.stage == .stored, "QA is not a stage here")
            expect(r.hear(Signal(stage: .cleared, by: .board, at: at(2)), workflow: w) == nil, "nor cleared")
            expect(r.hear(Signal(stage: .shipped, by: .git, at: at(3)), workflow: w)?.to == .shipped, "shipped is")
            let tags = Workflow.detected(pipeline: Pipeline(trunk: "main", staging: "", production: "", ship: "tag"), board: false)
            expect(tags.qa == nil && tags.shipped == [.git, .board], "ships on tags: no QA, git says shipped")
            let ours = Workflow.detected(pipeline: Pipeline(trunk: "develop", staging: "staging", production: "production"), board: true)
            expect(ours.qa?.first == .board && ours.cleared?.first == .board, "with a board and staging, the board is first in line")
            let merges = Workflow.detected(pipeline: Pipeline(trunk: "main", staging: "", production: "", ship: "merge"), board: false)
            expect(merges.qa == nil && merges.cleared == nil && merges.shipped == [.git], "every merge ships: nothing to clear")
        }

        test("the workflow's order decides who may take work back") {
            var w = Workflow(); w.qa = [.pulls, .board]
            let r = WorkBook.Record(id: 1, repo: "web")
            _ = r.hear(Signal(stage: .qa, by: .board, at: at(0)), workflow: w)
            expect(r.hear(Signal(stage: .stored, by: .board, at: at(1)), workflow: w) == nil, "the board is not first in line for QA in this repository")
            _ = r.hear(Signal(stage: .qa, by: .pulls, at: at(2)), workflow: w)
            expect(r.hear(Signal(stage: .stored, by: .pulls, at: at(3)), workflow: w)?.back == true, "pull requests are")
        }

        test("the first word of a piece of work is history; the next change is news") {
            let r = WorkBook.Record(id: 1, repo: "web")
            _ = r.hear(Signal(stage: .stored, by: .pulls, at: at(0)))
            expect(r.quiet, "found merged: quiet")
            _ = r.hear(Signal(stage: .stored, by: .git, at: at(1)))
            expect(r.quiet, "the same stage said again is still not news")
            _ = r.hear(Signal(stage: .qa, by: .board, at: at(2)))
            expect(!r.quiet, "a change is news")
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
