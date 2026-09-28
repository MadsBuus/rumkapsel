// Model-only tests of the station log: `.build/debug/Rumkapsel --spacelog-tests`.
//
// Facts shaped like what GitHub tells the station — a feed, release pull requests, board items — are
// read back as the log. No station and no network. Exits non-zero if anything failed.

import Foundation

enum SpaceLogTests {
    private static var failures = 0
    private static var current = ""

    static func run() -> Never {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }
        func feed(_ kind: String, _ n: Int, _ m: Double, actor: String = "mia", bot: Bool = false, title: String? = nil) -> FeedEvent {
            FeedEvent(at: at(m), actor: actor, isBot: bot, kind: kind, branch: nil, prNumber: n, title: title ?? "work \(n)", url: nil, detail: "")
        }
        func release(_ n: Int, _ m: Double?, production: Bool, state: String = "MERGED") -> ReleasePR {
            ReleasePR(number: n, title: production ? "Production Release" : "Staging Release", base: production ? "production" : "staging",
                      head: production ? "staging" : "develop", state: state, url: "", labels: [], mergedAt: m.map(at),
                      production: production, staging: !production)
        }
        func item(_ n: Int, _ status: String, _ m: Double, assignee: String? = nil) -> ProjectItem {
            ProjectItem(repo: "api", number: n, title: "issue \(n)", status: status, assignees: assignee.map { [$0] } ?? [],
                        prURLs: [], url: "", updatedAt: at(m))
        }
        func facts(feed: [FeedEvent] = [], releases: [ReleasePR] = [], board: [ProjectItem] = []) -> SpaceLog.Facts {
            SpaceLog.Facts(repos: [SpaceLog.Repo(name: "api", feed: feed, releases: releases)], board: board,
                           statuses: AppConfig.ProjectStatuses(), me: "me", name: { $0 == "mia" ? "Mia" : $0 })
        }

        test("a release pull request is a launch or a deploy, never a merge") {
            let f = facts(feed: [feed("pr_merge", 10, 5), feed("pr_merge", 11, 6)],
                          releases: [release(10, 5, production: false), release(11, 6, production: true)])
            let log = SpaceLog.read(f, since: at(0))
            expect(log.map(\.kind) == [.staging, .launch], "staging then launch, got \(log.map(\.kind))")
        }

        test("an open or old release is not in the log") {
            let f = facts(releases: [release(1, nil, production: true, state: "OPEN"), release(2, -10, production: true)])
            expect(SpaceLog.read(f, since: at(0)).isEmpty, "nothing since")
        }

        test("the feed: merges, pull requests and issues by name; your own as you; bots left out") {
            let f = facts(feed: [feed("pr_merge", 1, 1), feed("pr_open", 2, 2, actor: "me"), feed("issue_open", 3, 3),
                                 feed("pr_merge", 4, 4, actor: "dependabot[bot]", bot: true), feed("push", 5, 5)])
            let log = SpaceLog.read(f, since: at(0))
            expect(log.map(\.what) == ["Mia merged", "you opened a pull request", "Mia filed an issue"], "got \(log.map(\.what))")
            expect(log.first?.items == ["#1 work 1"], "the item carries number and title")
        }

        test("a feed event without a title takes one from what the station knows, else stands as its number") {
            var f = facts(feed: [FeedEvent(at: at(1), actor: "mia", isBot: false, kind: "pr_merge", branch: nil, prNumber: 7, title: nil, url: nil, detail: ""),
                                 FeedEvent(at: at(2), actor: "mia", isBot: false, kind: "pr_merge", branch: nil, prNumber: 8, title: nil, url: nil, detail: "")])
            f.title = { _, n in n == 7 ? "known" : nil }
            expect(SpaceLog.read(f, since: at(0)).map(\.items) == [["#7 known"], ["#8"]], "titled, then bare")
        }

        test("the board says where each issue got to since, by its column") {
            let s = AppConfig.ProjectStatuses()
            let f = facts(board: [item(1, s.deck, 1), item(2, s.cleared, 2), item(3, s.shipped, 3), item(4, s.development, 4, assignee: "mia"),
                                  item(5, s.storage, 5), item(6, s.deck, -5)])
            let log = SpaceLog.read(f, since: at(0))
            expect(log.map(\.kind) == [.deck, .cleared, .launch, .started], "got \(log.map(\.kind))")
            expect(log.last?.what == "Mia started", "the assignee started it")
        }

        test("a board item of a repository the station does not show is left out") {
            var other = item(1, AppConfig.ProjectStatuses().deck, 1)
            other = ProjectItem(repo: "elsewhere", number: 1, title: "x", status: other.status, assignees: [], prURLs: [], url: "", updatedAt: at(1))
            expect(SpaceLog.read(facts(board: [other]), since: at(0)).isEmpty, "not ours")
        }

        test("a burst folds into one line; a gap starts a new one") {
            let s = AppConfig.ProjectStatuses()
            let f = facts(board: [item(1, s.deck, 1), item(2, s.deck, 5), item(3, s.deck, 15), item(4, s.deck, 90)])
            let folded = SpaceLog.fold(SpaceLog.read(f, since: at(0)))
            expect(folded.count == 2, "two bursts, got \(folded.count)")
            expect(folded.first?.items.count == 3, "three in the first")
        }

        test("a launch carries the issues the board shipped with it; one shipped long after stands alone") {
            let s = AppConfig.ProjectStatuses()
            let f = facts(releases: [release(9, 60, production: true)],
                          board: [item(1, s.shipped, 58), item(2, s.shipped, 61), item(3, s.shipped, 200)])
            let rolled = SpaceLog.rollUp(SpaceLog.read(f, since: at(0)))
            let launch = rolled.first { $0.isRelease }
            expect(launch?.items == ["#1 issue 1", "#2 issue 2"], "carried: \(launch?.items ?? [])")
            expect(launch?.note == "Production Release", "its own title kept as the note")
            expect(launch?.sentence.rest == "api lifted off, 2 crates aboard", "said: \(launch?.sentence.rest ?? "")")
            expect(rolled.filter(\.isShipped).map(\.items) == [["#3 issue 3"]], "the late one alone")
        }

        test("a staging deploy carries the issues that reached QA with it") {
            let s = AppConfig.ProjectStatuses()
            let f = facts(releases: [release(8, 10, production: false)], board: [item(1, s.deck, 12), item(2, s.deck, 14)])
            let rolled = SpaceLog.rollUp(SpaceLog.read(f, since: at(0)))
            expect(rolled.count == 1 && rolled[0].sentence.rest == "2 crates went to the deck", "one line: \(rolled.map(\.sentence.rest))")
        }

        test("issues filed and started gather into one line per person and day") {
            let s = AppConfig.ProjectStatuses()
            let f = facts(feed: [feed("issue_open", 1, 1), feed("issue_open", 2, 90), feed("issue_open", 3, 95, actor: "leo")],
                          board: [item(4, s.development, 100, assignee: "mia")])
            let gathered = SpaceLog.gather(SpaceLog.fold(SpaceLog.read(f, since: at(0))))
            let mia = gathered.first { $0.who == "Mia" }
            expect(gathered.count == 2, "Mia and leo: \(gathered.map(\.what))")
            expect(mia?.sentence.rest == "logged 2 new jobs and opened an office", "Mia: \(mia?.sentence.rest ?? "")")
            expect(mia?.shape == .office, "an office among them: the hex")
            expect(mia?.items.count == 3, "all three of hers")
        }

        test("the station's words: packed, put in storage, passed inspection") {
            let s = AppConfig.ProjectStatuses()
            let f = facts(feed: [feed("pr_open", 1, 1), feed("pr_merge", 2, 30), feed("pr_merge", 3, 31)], board: [item(4, s.cleared, 60)])
            let said = SpaceLog.fold(SpaceLog.read(f, since: at(0))).map { ($0.sentence.who ?? "") + "|" + $0.sentence.rest }
            expect(said == ["Mia|packed a crate", "Mia|put 2 crates in storage", "|A crate passed inspection"], "said: \(said)")
        }

        test("a pull request from a release branch is no one's work, even before the release list knows it") {
            var f = facts(feed: [FeedEvent(at: at(1), actor: "mia", isBot: false, kind: "pr_open", branch: "develop", prNumber: 9, title: nil, url: nil, detail: ""),
                                 FeedEvent(at: at(2), actor: "mia", isBot: false, kind: "pr_merge", branch: "develop", prNumber: 9, title: nil, url: nil, detail: "")])
            f.isReleaseBranch = { _, b in b == "develop" }
            expect(SpaceLog.read(f, since: at(0)).isEmpty, "nothing: \(SpaceLog.read(f, since: at(0)).map(\.key))")
        }

        test("a release pull request already kept as work is taken back out once it is known for one") {
            var story = SpaceLog.Story()
            let plain = facts(feed: [feed("pr_merge", 9, 1), feed("pr_merge", 10, 2)])
            _ = story.add(SpaceLog.read(plain, since: at(0)), feeds: plain.repos, now: at(3))
            expect(story.add([], feeds: [], now: at(4), releases: ["api": [9]]), "a change")
            expect(story.entries.map(\.key) == ["merged:api:10"], "only the real merge: \(story.entries.map(\.key))")
        }

        test("the story keeps a fact once read: a feed that scrolls on takes nothing out") {
            var story = SpaceLog.Story()
            let first = facts(feed: [feed("pr_merge", 1, 1), feed("pr_merge", 2, 2)])
            _ = story.add(SpaceLog.read(first, since: at(0)), feeds: first.repos, now: at(3))
            let later = facts(feed: [feed("pr_merge", 3, 10)])
            _ = story.add(SpaceLog.read(later, since: at(0)), feeds: later.repos, now: at(11))
            expect(story.entries.map(\.key) == ["merged:api:1", "merged:api:2", "merged:api:3"], "all three: \(story.entries.map(\.key))")
        }

        test("reading the same facts again changes nothing") {
            var story = SpaceLog.Story()
            let f = facts(feed: [feed("pr_merge", 1, 1)], releases: [release(9, 2, production: true)])
            _ = story.add(SpaceLog.read(f, since: at(0)), feeds: f.repos, now: at(3))
            expect(!story.add(SpaceLog.read(f, since: at(0)), feeds: f.repos, now: at(3)), "no change the second time")
            expect(story.entries.count == 2, "two facts")
        }

        test("a board item moving on adds its new column; the old one stands") {
            let s = AppConfig.ProjectStatuses()
            var story = SpaceLog.Story()
            let qa = facts(board: [item(1, s.deck, 1)])
            _ = story.add(SpaceLog.read(qa, since: at(0)), feeds: qa.repos, now: at(2))
            let passed = facts(board: [item(1, s.cleared, 30)])
            _ = story.add(SpaceLog.read(passed, since: at(0)), feeds: passed.repos, now: at(31))
            expect(story.entries.map(\.kind) == [.deck, .cleared], "both hops: \(story.entries.map(\.kind))")
        }

        test("a bare number takes its title when one is learned; a fact is otherwise left as it was") {
            var story = SpaceLog.Story()
            let bare = facts(feed: [FeedEvent(at: at(1), actor: "mia", isBot: false, kind: "pr_merge", branch: nil, prNumber: 7, title: nil, url: nil, detail: "")])
            _ = story.add(SpaceLog.read(bare, since: at(0)), feeds: bare.repos, now: at(2))
            var titled = bare
            titled.title = { _, _ in "known" }
            expect(story.add(SpaceLog.read(titled, since: at(0)), feeds: titled.repos, now: at(3)), "a title is news")
            expect(story.entries.first?.items == ["#7 known"], "titled: \(story.entries.first?.items ?? [])")
        }

        test("a full feed that starts after what was last seen leaves a gap; a quiet one does not") {
            var story = SpaceLog.Story()
            let early = facts(feed: [feed("push", 1, 1)])
            _ = story.add([], feeds: early.repos, now: at(2))
            let full = facts(feed: (0..<100).map { feed("push", $0, 600 + Double($0)) })
            _ = story.add([], feeds: full.repos, now: at(800))
            expect(story.gaps == [SpaceLog.Gap(repo: "api", from: at(1), to: at(600))], "one gap: \(story.gaps)")
            var quiet = SpaceLog.Story()
            _ = quiet.add([], feeds: early.repos, now: at(2))
            let few = facts(feed: [feed("push", 2, 600)])
            _ = quiet.add([], feeds: few.repos, now: at(800))
            expect(quiet.gaps.isEmpty, "a quiet repository has no gap")
        }

        test("a line leads to its number: an issue, a release, or none for a bare title") {
            expect(SpaceLog.Target(kind: .deck, repo: "api", item: "#5331 Ban does nothing").number == 5331, "an issue")
            expect(SpaceLog.Target(kind: .staging, repo: "api", item: "release #5352").number == 5352, "a release")
            expect(SpaceLog.Target(kind: .launch, repo: "api", item: "Production Release").number == nil, "a title")
        }

        test("the story forgets what is older than it keeps") {
            var story = SpaceLog.Story()
            let f = facts(feed: [feed("pr_merge", 1, 1)])
            _ = story.add(SpaceLog.read(f, since: at(0)), feeds: f.repos, now: at(2))
            _ = story.add([], feeds: [], now: at(2).addingTimeInterval(SpaceLog.keep + 60))
            expect(story.entries.isEmpty, "gone")
        }

        FileHandle.standardError.write((failures == 0 ? "all station log tests passed\n" : "\(failures) failed\n").data(using: .utf8)!)
        exit(failures == 0 ? 0 : 1)
    }

    private static func test(_ name: String, _ body: () -> Void) {
        current = name
        let before = failures
        body()
        say((failures == before ? "PASS  " : "FAIL  ") + name)
    }
    private static func expect(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; say("      not so: \(what)") }
    }
    private static func say(_ text: String) { FileHandle.standardError.write((text + "\n").data(using: .utf8)!) }
}
