import Foundation

enum GitHubTests {
    private static var failures = 0
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func run() -> Never {
        test("an unchanged answer is a 304: the cached body, not news, and the poll interval heard") {
            Stub.reply = { request in
                let etag = request.value(forHTTPHeaderField: "If-None-Match")
                return etag == "\"a\"" ? (304, ["X-Poll-Interval": "60"], Data()) : (200, ["ETag": "\"a\"", "X-Poll-Interval": "60"], Data("[1]".utf8))
            }
            let http = stubbed()
            let first = http.get("repos/o/r/events")
            expect(first?.changed == true && first?.data == Data("[1]".utf8), "the first answer is news")
            let second = http.get("repos/o/r/events")
            expect(second?.changed == false && second?.data == Data("[1]".utf8), "the second is a 304 with the held body")
            expect(second?.pollInterval == 60, "X-Poll-Interval read, got \(String(describing: second?.pollInterval))")
            expect(Stub.asked.last?.value(forHTTPHeaderField: "If-None-Match") == "\"a\"", "the ETag sent back")
        }

        test("a rate limit closes the gate until GitHub's reset, and nothing is asked meanwhile") {
            let reset = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
            Stub.reply = { _ in (403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "\(reset)"], Data()) }
            let http = stubbed()
            expect(http.get("repos/o/r/pulls") == nil, "the 403 is no answer")
            let asked = Stub.asked.count
            expect(http.get("repos/o/r/pulls") == nil && Stub.asked.count == asked, "closed: no request goes out")
            expect(!http.open && !http.ghOpen, "the gate says closed, for gh too")
        }

        test("a 401 drops the token, and the next one is asked for no sooner than five minutes") {
            var tokens = 0
            Stub.reply = { _ in (401, [:], Data()) }
            let c = URLSessionConfiguration.ephemeral
            c.protocolClasses = [Stub.self]
            let http = GitHubHTTP(token: { tokens += 1; return "t" }, session: URLSession(configuration: c))
            _ = http.get("user"); _ = http.get("user"); _ = http.get("user")
            expect(tokens == 1 && !http.hasToken, "one token asked, then held off, got \(tokens)")
        }

        test("the rate gate: retry-after, an empty budget, secondary limits doubling, a low budget stretches") {
            let reset = "\(Int(t0.timeIntervalSince1970) + 600)"
            var g = RateGate()
            g.heard(status: 429, headers: ["retry-after": "30"], now: t0, jitter: 0)
            expect(!g.open(t0.addingTimeInterval(29)) && g.open(t0.addingTimeInterval(30)), "retry-after 30 s")
            g = RateGate()
            g.heard(status: 403, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": reset], now: t0, jitter: 2)
            expect(!g.open(t0.addingTimeInterval(601)) && g.open(t0.addingTimeInterval(602)), "empty: shut until the reset, plus jitter")
            g = RateGate()
            g.heard(status: 403, headers: ["x-ratelimit-remaining": "4000"], limited: true, now: t0, jitter: 0)
            expect(!g.open(t0.addingTimeInterval(59)) && g.open(t0.addingTimeInterval(60)), "a secondary limit: a minute")
            g.heard(status: 429, headers: [:], now: t0.addingTimeInterval(60), jitter: 0)
            expect(!g.open(t0.addingTimeInterval(179)) && g.open(t0.addingTimeInterval(180)), "again: two minutes")
            g.heard(status: 304, headers: [:], now: t0.addingTimeInterval(180), jitter: 0)
            g.heard(status: 429, headers: [:], now: t0.addingTimeInterval(200), jitter: 0)
            expect(g.open(t0.addingTimeInterval(260)), "an answer in between starts over at a minute")
            g = RateGate()
            g.heard(status: 403, headers: ["x-ratelimit-remaining": "4000"], now: t0, jitter: 0)
            expect(g.open(t0), "a plain 403 (no access) is the detector's, not the gate's")
            g.heard(status: 200, headers: ["x-ratelimit-remaining": "\(RateGate.reserve - 1)", "x-ratelimit-reset": reset], now: t0)
            expect(g.open(t0) && g.stretch == 4, "below the reserve: open, four times slower")
            g.heard(status: 200, headers: ["x-ratelimit-remaining": "10", "x-ratelimit-reset": reset], now: t0)
            expect(g.stretch == 8, "nearly spent: eight times")
            g.heard(graphql: 50, reset: t0.addingTimeInterval(300))
            expect(g.open(t0) && !g.ghOpen(t0) && g.ghOpen(t0.addingTimeInterval(300)), "GraphQL spent: gh waits, REST goes on")
        }

        test("a failing detector backs off, doubling to five minutes, and starts over when it hears") {
            var d = Detector.pulls
            d.asking(t0)
            d.failed()
            expect(!d.due(t0.addingTimeInterval(9), pace: .focused) && d.due(t0.addingTimeInterval(10), pace: .focused), "ten seconds")
            for _ in 0..<10 { d.failed() }
            expect(d.wait(t0, pace: .focused) == Detector.longest, "capped at five minutes")
            d.ring()
            expect(d.wait(t0, pace: .focused) == Detector.longest, "a ring does not skip the backoff")
            d.heard(pollInterval: nil)
            expect(d.wait(t0, pace: .focused) == 0, "heard: rung and back to normal")
            d.asking(t0)
            expect(d.wait(t0, pace: .focused, stretch: 4) == 20, "a stretched budget slows it")
            var j = Detector.feed
            j.start(t0, pace: .focused, jitter: 2)
            expect(!j.due(t0.addingTimeInterval(1), pace: .focused) && j.due(t0.addingTimeInterval(2), pace: .focused), "its first ask jittered")
        }

        test("a detector's cadence follows the pace, heats, and never beats X-Poll-Interval") {
            var d = Detector.pulls
            d.asking(t0)
            expect(d.due(t0.addingTimeInterval(5), pace: .focused) && !d.due(t0.addingTimeInterval(5), pace: .active), "5 s focused, not active")
            expect(d.due(t0.addingTimeInterval(60), pace: .idle) && !d.due(t0.addingTimeInterval(59), pace: .idle), "a minute idle")
            var r = Detector.runs
            r.asking(t0)
            r.heat(for: 300, t0)
            expect(r.due(t0.addingTimeInterval(5), pace: .idle), "hot: every 5 s whatever the pace")
            r.asking(t0.addingTimeInterval(400))
            expect(!r.due(t0.addingTimeInterval(405), pace: .idle), "cooled: back to its idle two minutes")
            var f = Detector.feed
            f.asking(t0)
            f.heard(pollInterval: 90)
            f.ring()
            expect(!f.due(t0.addingTimeInterval(60), pace: .focused), "rung, but GitHub asked for 90 s")
            expect(f.due(t0.addingTimeInterval(90), pace: .focused), "due once the poll interval is up")
            var b = Detector.board
            b.asking(t0)
            b.ring()
            expect(b.due(t0.addingTimeInterval(0), pace: .idle), "rung with no floor: at once")
            b.asking(t0)
            expect(!b.due(t0.addingTimeInterval(1), pace: .focused), "asking clears the ring")
        }

        test("follow-up reads: one per repository while one is pending, carrying every change since") {
            var f = FollowUps()
            let one = FollowUps.Due(pulls: [.init(number: 1, branch: "a")], team: true)
            let two = FollowUps.Due(pulls: [.init(number: 2, branch: "b")], releasing: true)
            expect(f.note("/r", one), "the first change schedules one")
            expect(!f.note("/r", two), "a second change before it rides along")
            expect(f.note("/s", two), "another repository has its own")
            let due = f.take("/r")
            expect(due == FollowUps.Due(pulls: [.init(number: 1, branch: "a"), .init(number: 2, branch: "b")], team: true, releasing: true),
                   "it carries both, got \(String(describing: due))")
            expect(f.take("/r") == nil, "taken once")
            expect(f.note("/r", one), "after it ran, the next change schedules again")
            expect(FollowUps.after == 15, "fifteen seconds after")
        }

        test("the pace: in front is focused, a session within ten minutes active, else idle") {
            expect(Pace.of(front: true, worked: .distantPast, now: t0) == .focused, "in front")
            expect(Pace.of(front: false, worked: t0.addingTimeInterval(-599), now: t0) == .active, "worked a moment ago")
            expect(Pace.of(front: false, worked: t0.addingTimeInterval(-601), now: t0) == .idle, "quiet ten minutes")
        }

        test("pull requests that moved: who reads what") {
            func pr(_ n: Int, _ updated: String, state: String = "open", merged: Bool = false, base: String = "develop") -> [String: Any] {
                var o: [String: Any] = ["number": n, "updated_at": updated, "state": state, "base": ["ref": base], "head": ["ref": "b\(n)"]]
                if merged { o["merged_at"] = updated }
                return o
            }
            let first = PullSource.moved([pr(1, "a"), pr(2, "a", state: "closed", merged: true)], before: nil, releasesInto: ["staging", "production"], team: true)
            expect(first.due == FollowUps.Due() && first.moved.isEmpty, "the first look is quiet")
            let comment = PullSource.moved([pr(1, "b"), pr(2, "b", state: "closed", merged: true)], before: first.seen, releasesInto: ["staging"], team: true)
            expect(comment.due == FollowUps.Due(pulls: [.init(number: 1, branch: "b1"), .init(number: 2, branch: "b2")]),
                   "a comment or a push: those pull requests only, not the list or the releases, got \(comment.due)")
            let merge = PullSource.moved([pr(1, "c", state: "closed", merged: true), pr(3, "c")], before: comment.seen, releasesInto: ["staging"], team: true)
            expect(merge.due.team && merge.due.releasing, "a merge and a new one: the open list and the releases")
            let release = PullSource.moved([pr(4, "d", base: "staging")], before: [4: .init(updated: "c", open: true, merged: false)], releasesInto: ["staging"], team: false)
            expect(release.due.releasing && !release.due.team, "a release pull request labelled: the releases; no list for a repository off the team")
            let page = (1...20).map { pr($0 + 100, "z") }
            let flood = PullSource.moved(page, before: [1: .init(updated: "a", open: true, merged: false)], releasesInto: [], team: true)
            expect(flood.due.all, "a full page with nothing seen before: everything followed is read again")
            let calm = PullSource.moved(page, before: flood.seen.merging([7: .init(updated: "a", open: true, merged: false)]) { a, _ in a }, releasesInto: [], team: true)
            expect(!calm.due.all, "overlap with the last page: no flood")
        }

        test("feed events are new by id, not by time") {
            func e(_ id: String) -> FeedEvent { FeedEvent(at: t0, actor: "a", isBot: false, kind: "release", branch: nil, prNumber: nil, title: nil, url: nil, detail: "", id: id) }
            expect(PullSource.fresh([e("2"), e("1")], since: [e("1")]).map(\.id) == ["2"], "same second, new id: new")
            expect(PullSource.fresh([e("2")], since: nil).isEmpty, "the first look is quiet")
        }

        test("a whole board read never undoes a fresher item from the delta") {
            let r = GitHubResolver()
            r.frozen = true
            func item(_ status: String, _ at: TimeInterval) -> ProjectItem {
                ProjectItem(repo: "web", number: 1, title: "t", status: status, assignees: [], prURLs: [], url: "", updatedAt: t0.addingTimeInterval(at))
            }
            r.inject(project: [item("QA", 100)], at: t0.addingTimeInterval(100), quiet: true)
            _ = r.board.reports()
            r.board.adopt([item("In Development", 50)], at: t0.addingTimeInterval(200))
            expect(r.board.items?.first?.status == "QA" && r.board.reports().isEmpty, "the older read keeps the newer status, no move")
            r.board.adopt([item("Shipped", 150)], at: t0.addingTimeInterval(300))
            expect(r.board.items?.first?.status == "Shipped", "a newer read wins")
        }

        test("a board item from the REST project API becomes the resolver's item") {
            let json = """
            [{"content_type": "Issue", "updated_at": "2026-10-14T08:32:07Z",
              "content": {"number": 14053, "title": "Book a guest", "state": "open", "html_url": "https://github.com/T/web/issues/14053",
                          "repository": {"name": "web"}, "assignees": [{"login": "skogge"}]},
              "fields": [{"id": 7, "name": "Status", "data_type": "single_select", "value": {"name": {"raw": "QA"}}},
                         {"id": 8, "name": "Linked pull requests", "data_type": "linked_pull_requests",
                          "value": [{"html_url": "https://github.com/T/web/pull/14060", "state": "open"},
                                    {"html_url": "https://github.com/T/web/pull/14001", "state": "closed"}]}]},
             {"content_type": "DraftIssue", "content": {"title": "an idea"}, "fields": []}]
            """
            let arr = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
            let items = arr.compactMap { ProjectItem(rest: $0, status: 7) }
            let want = ProjectItem(repo: "web", number: 14053, title: "Book a guest", status: "QA", assignees: ["skogge"],
                                   prURLs: ["https://github.com/T/web/pull/14060"], url: "https://github.com/T/web/issues/14053",
                                   updatedAt: ISO8601DateFormatter().date(from: "2026-10-14T08:32:07Z"), state: "OPEN")
            expect(items == [want], "one issue, its status and open pull request; drafts left out, got \(items)")
        }

        test("the events feed becomes feed events") {
            let json = """
            [{"type": "PushEvent", "created_at": "2026-10-14T08:00:00Z", "actor": {"login": "skogge"},
              "payload": {"ref": "refs/heads/staging", "size": 3}},
             {"type": "PullRequestEvent", "created_at": "2026-10-14T08:01:00Z", "actor": {"login": "dependabot[bot]"},
              "payload": {"action": "closed", "pull_request": {"number": 9, "merged": true, "title": "Bump", "head": {"ref": "dep/x"}}}},
             {"type": "WatchEvent", "created_at": "2026-10-14T08:02:00Z", "actor": {"login": "x"}, "payload": {}}]
            """
            let events = PullSource.feedEvents(try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]])
            expect(events.map(\.kind) == ["push", "pr_merge"], "a push and a merge, got \(events.map(\.kind))")
            expect(events.first?.branch == "staging" && events.first?.detail == "3", "the push's branch and size")
            expect(events.last?.isBot == true && events.last?.prNumber == 9 && events.last?.branch == "dep/x", "the merge's pull request, by a bot")
        }

        test("which .git paths are a local change, a worktree's, a remote one, tags") {
            let g = "/r/.git"
            expect(GitChange.of([g + "/refs/heads/main"], gitDir: g) == GitChange(local: true), "a commit")
            expect(GitChange.of([g + "/HEAD", g + "/logs/HEAD"], gitDir: g) == GitChange(local: true), "a checkout")
            expect(GitChange.of([g + "/worktrees/manado/HEAD", g + "/worktrees/lima/index"], gitDir: g) == GitChange(worktrees: ["manado"]), "one worktree's checkout")
            expect(GitChange.of([g + "/refs/remotes/origin/develop"], gitDir: g) == GitChange(remote: true), "a fetch or a push")
            expect(GitChange.of([g + "/refs/tags/v1.2"], gitDir: g) == GitChange(tags: true), "a tag")
            expect(GitChange.of([g + "/packed-refs"], gitDir: g) == GitChange(remote: true, tags: true), "packed refs")
            expect(!GitChange.of([g + "/objects/ab/cdef", g + "/refs/heads/main.lock", g + "/index", g + "/FETCH_HEAD"], gitDir: g).any,
                   "objects, locks, the index and FETCH_HEAD are nothing")
        }

        test("the .git watcher hears a commit, a remote ref, a tag and a worktree's checkout; worktrees find their repository") {
            let dir = GitWatch.real(NSTemporaryDirectory()) + "/rk-git-\(UUID().uuidString)"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(atPath: dir); try? FileManager.default.removeItem(atPath: dir + "-wt") }
            git(["init", "-q", "-b", "main"], dir)
            git(["commit", "-q", "--allow-empty", "-m", "one"], dir)
            git(["worktree", "add", "-q", dir + "-wt", "-b", "side"], dir)
            let heard = Heard()
            let watch = GitWatch(root: dir) { heard.add($0) }
            Thread.sleep(forTimeInterval: 0.5)
            git(["commit", "-q", "--allow-empty", "-m", "two"], dir)
            expect(wait { heard.all.contains { $0.local } }, "a commit is heard, got \(heard.all)")
            git(["update-ref", "refs/remotes/origin/main", "HEAD"], dir)
            expect(wait { heard.all.contains { $0.remote } }, "a remote ref is heard, got \(heard.all)")
            git(["tag", "v1"], dir)
            expect(wait { heard.all.contains { $0.tags } }, "a tag is heard, got \(heard.all)")
            let name = (dir + "-wt" as NSString).lastPathComponent
            git(["checkout", "-q", "-b", "other"], dir + "-wt")
            expect(wait { heard.all.contains { $0.worktrees.contains(name) } }, "the worktree's checkout is its own, got \(heard.all)")
            expect(GitWatch.link(ofWorktree: dir + "-wt").map { "\($0.root)|\($0.name ?? "-")" } == "\(dir)|\(name)", "the worktree's repository and name")
            expect(GitWatch.link(ofWorktree: dir).map { "\($0.root)|\($0.name ?? "-")" } == "\(dir)|-", "a checkout is its own")
            let watch2 = GitWatch(root: dir + "-wt") { heard.add($0) }
            expect(GitWatch.commonDir(of: dir + "-wt") == dir + "/.git", "a worktree root watches the common .git, got \(String(describing: GitWatch.commonDir(of: dir + "-wt")))")
            withExtendedLifetime((watch, watch2)) {}
        }

        say(failures == 0 ? "github: all passed" : "github: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private final class Stub: URLProtocol {
        static var reply: (URLRequest) -> (Int, [String: String], Data) = { _ in (500, [:], Data()) }
        static var asked: [URLRequest] = []
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Stub.asked.append(request)
            let (status, headers, body) = Stub.reply(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private static func stubbed() -> GitHubHTTP {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [Stub.self]
        return GitHubHTTP(token: { "test" }, session: URLSession(configuration: c))
    }

    private final class Heard {
        private let lock = NSLock()
        private var list: [GitChange] = []
        func add(_ c: GitChange) { lock.lock(); list.append(c); lock.unlock() }
        var all: [GitChange] { lock.lock(); defer { lock.unlock() }; return list }
    }

    private static func wait(_ ok: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(5)
        while Date() < end { if ok() { return true }; Thread.sleep(forTimeInterval: 0.05) }
        return ok()
    }

    private static func git(_ args: [String], _ cwd: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"] + args
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
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
