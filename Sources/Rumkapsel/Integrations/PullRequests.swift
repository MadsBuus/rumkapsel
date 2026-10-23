import Foundation

struct PullRequests {
    let github: GitHubResolver

    func pull(ownOffice room: Room) -> PullRequest? {
        room.branch.flatMap { b in room.repoRoot.flatMap { github.pulls.pull(branch: b, repoRoot: $0) } }
    }

    func state(crewOffice room: Room, known: WorkBook.Record?, repoRoot root: String?,
               feed: [(repo: String, e: FeedEvent)]) -> String? {
        let branch = known?.work().branch ?? known?.branches.sorted().first ?? ""
        if feed.contains(where: { $0.repo == room.repo && $0.e.kind == "pr_close" && $0.e.branch == branch }) { return "CLOSED" }
        if feed.contains(where: { $0.repo == room.repo && $0.e.kind == "pr_merge" && $0.e.branch == branch }) { return "MERGED" }
        guard let root else { return "MERGED" }
        if let number = known?.pulls.keys.min() {
            github.pulls.refresh(pull: number, repoRoot: root)
            return github.pulls.pullAnswered(number: number, repoRoot: root) ? github.pulls.pull(number: number, repoRoot: root)?.state : nil
        }
        github.pulls.refresh(branch: branch, repoRoot: root)
        return github.pulls.pullAnswered(branch: branch, repoRoot: root) ? (github.pulls.pull(branch: branch, repoRoot: root)?.state ?? "NONE") : nil
    }

    static func stage(for state: String) -> Stage {
        switch state {
        case "OPEN": return .ready
        case "MERGED": return .stored
        default: return .working
        }
    }
}

final class PullSource: Intake {
    let name = "pulls"
    private weak var github: GitHubResolver?
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "rumkapsel.pulls", qos: .utility, attributes: .concurrent)
    private var teams: [String: Bool] = [:]
    private var open: [String: ([OpenPR], Date)] = [:]
    private var feeds: [String: ([FeedEvent], Date)] = [:]
    private var answeredLive: Set<String> = []
    private var failedAt: [String: Date] = [:]
    private var fromCache: Set<String> = []
    private var savedOnly: Set<String> = []
    private var byBranch: [String: (PullRequest?, Date)] = [:]
    private var byNumber: [String: (PullRequest?, Date)] = [:]
    private var changes: [Report] = []
    private var seen: [String: [Int: Seen]] = [:]
    private var followUps = FollowUps()
    private var heavyAt: [String: Date] = [:]
    private var expected: [String: (until: Date, every: TimeInterval)] = [:]
    private var inFlight = Set<String>()
    private var rerun = Set<String>()

    init(github: GitHubResolver) { self.github = github }

    func watch(_ roots: [String: Bool]) { lock.lock(); teams = roots; lock.unlock() }

    func checks() -> [Watch.Check] {
        guard let github, !github.frozen else { return [] }
        lock.lock(); let roots = teams; lock.unlock()
        var out: [Watch.Check] = []
        for (root, team) in roots where github.nameWithOwner(repoRoot: root) != nil {
            out.append(.init(root + "#watch:pulls", .pulls) { [weak self] in self?.detectPulls(root) })
            if team { out.append(.init(root + "#watch:feed", .feed) { [weak self] in self?.detectFeed(root) }) }
        }
        return out
    }

    func reports() -> [Report] {
        lock.lock(); defer { lock.unlock() }
        let out = changes; changes = []; return out
    }

    var hasAnswers: Bool { lock.lock(); defer { lock.unlock() }; return !open.isEmpty }
    func answered(repoRoot: String) -> Bool { lock.lock(); defer { lock.unlock() }; return answeredLive.contains(repoRoot) }

    func teamOpenPRs(repoRoot: String) -> [OpenPR]? {
        lock.lock(); defer { lock.unlock() }
        return savedOnly.contains("o:" + repoRoot) ? nil : open[repoRoot]?.0
    }

    func feed(repoRoot: String) -> [FeedEvent]? {
        lock.lock(); defer { lock.unlock() }
        return savedOnly.contains("f:" + repoRoot) ? nil : feeds[repoRoot]?.0
    }

    func pull(branch: String, repoRoot: String) -> PullRequest? {
        lock.lock(); defer { lock.unlock() }
        return byBranch[repoRoot + "@" + branch]?.0
    }
    func pullAnswered(branch: String, repoRoot: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return byBranch[repoRoot + "@" + branch] != nil
    }
    func pull(number: Int, repoRoot: String) -> PullRequest? {
        lock.lock(); defer { lock.unlock() }
        return byNumber[repoRoot + "#\(number)"]?.0
    }
    func pullAnswered(number: Int, repoRoot: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return byNumber[repoRoot + "#\(number)"] != nil
    }

    func isBusy(repoRoot: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return inFlight.contains { $0.hasSuffix(repoRoot) || $0.hasPrefix(repoRoot + "@") }
    }

    func expect(branch: String, repoRoot: String) {
        lock.lock(); expected["pull:" + repoRoot + "@" + branch] = (Date().addingTimeInterval(180), 30); lock.unlock()
    }

    func invalidate(repoRoot: String?) {
        lock.lock(); defer { lock.unlock() }
        for k in byBranch.keys where repoRoot.map({ k.hasPrefix($0 + "@") }) ?? true { byBranch[k] = (byBranch[k]!.0, .distantPast) }
    }

    // MARK: saved

    struct Knowledge: Codable { var repo: String; var openPRs: [OpenPR]?; var prsAt: Date?; var feed: [FeedEvent]?; var feedAt: Date? }

    private static var cacheURL: URL { AppSupport.root.appendingPathComponent("rumkapsel.github.json") }

    func save(_ roots: [String: String]) {
        var out: [String: Knowledge] = [:]
        for (root, repo) in roots { if let k = knowledge(repoRoot: root, repo: repo) { out[root] = k } }
        guard !out.isEmpty, let json = try? JSONEncoder().encode(out) else { return }
        Fleet.writing.async { try? json.write(to: PullSource.cacheURL) }
    }

    func load() {
        guard let data = try? Data(contentsOf: PullSource.cacheURL),
              let saved = try? JSONDecoder().decode([String: Knowledge].self, from: data) else { return }
        for (root, k) in saved { adopt(k, repoRoot: root, saved: true) }
        lock.lock(); fromCache.formUnion(saved.keys); lock.unlock()
    }

    func knowledge(repoRoot: String, repo: String) -> Knowledge? {
        lock.lock(); defer { lock.unlock() }
        let prs = open[repoRoot], f = feeds[repoRoot]
        guard prs != nil || f != nil else { return nil }
        let recent = Date().addingTimeInterval(-24 * 3600)
        return Knowledge(repo: repo, openPRs: prs?.0, prsAt: prs?.1, feed: f.map { Array($0.0.filter { $0.at > recent }.prefix(80)) }, feedAt: f?.1)
    }

    func adopt(_ k: Knowledge, repoRoot: String, saved: Bool = false) {
        var changed = false
        lock.lock()
        if let prs = k.openPRs, let at = k.prsAt, at > (open[repoRoot]?.1 ?? .distantPast) {
            changed = open[repoRoot]?.0 != prs
            open[repoRoot] = (prs, at)
            if saved { savedOnly.insert("o:" + repoRoot) } else { savedOnly.remove("o:" + repoRoot) }
        }
        if let f = k.feed, let at = k.feedAt, at > (feeds[repoRoot]?.1 ?? .distantPast) {
            changed = changed || feeds[repoRoot]?.0 != f
            feeds[repoRoot] = (f, at)
            if saved { savedOnly.insert("f:" + repoRoot) } else { savedOnly.remove("f:" + repoRoot) }
        }
        lock.unlock()
        if changed { updated() }
    }

    // MARK: reads

    func refreshOpenPRs(repoRoot: String) {
        guard let github, !github.frozen else { return }
        lock.lock()
        let remembered = fromCache.remove(repoRoot) != nil
        if !remembered, let (_, at) = open[repoRoot],
           Date().timeIntervalSince(at) < github.baseInterval { lock.unlock(); return }
        if inFlight.contains("o:" + repoRoot) || Date().timeIntervalSince(failedAt["o:" + repoRoot] ?? .distantPast) < 60 { lock.unlock(); return }
        inFlight.insert("o:" + repoRoot)
        lock.unlock()
        github.trace("ask openPRs \(repoRoot)")
        queue.async { [self] in
            defer { if landed("o:" + repoRoot) { refetchOpenPRs(repoRoot) } }
            guard let github = self.github else { return }
            let iso = ISO8601DateFormatter()
            var found: [OpenPR] = []
            guard let out = github.run(["gh", "pr", "list", "--state", "open", "--limit", "40", "--json", "number,title,author,headRefName,url,createdAt,updatedAt"], cwd: repoRoot) else {
                github.trace("openPRs \(repoRoot) failed")
                lock.lock(); failedAt["o:" + repoRoot] = Date(); lock.unlock()
                return
            }
            if let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] {
                let stale = Date().addingTimeInterval(-14 * 24 * 3600)
                for o in arr {
                    if let u = (o["updatedAt"] as? String).flatMap(iso.date(from:)), u < stale { continue }
                    let a = o["author"] as? [String: Any]
                    let login = a?["login"] as? String ?? "?"
                    let isBot = (a?["is_bot"] as? Bool ?? false) || GitHubResolver.isBot(login)
                    found.append(OpenPR(number: o["number"] as? Int ?? 0, title: o["title"] as? String ?? "", author: login, isBot: isBot,
                                        branch: o["headRefName"] as? String ?? "", url: o["url"] as? String ?? "",
                                        createdAt: (o["createdAt"] as? String).flatMap(iso.date(from:)) ?? Date()))
                }
            }
            lock.lock()
            let changed = open[repoRoot]?.0 != found || savedOnly.remove("o:" + repoRoot) != nil
            open[repoRoot] = (found, Date())
            let first = answeredLive.insert(repoRoot).inserted
            lock.unlock()
            github.note(open: found, repoRoot: repoRoot)
            if changed || first { updated() }
        }
    }

    func refresh(pull number: Int, repoRoot: String) {
        guard let github, !github.frozen else { return }
        let key = repoRoot + "#\(number)"
        lock.lock()
        if let (_, at) = byNumber[key], Date().timeIntervalSince(at) < github.baseInterval { lock.unlock(); return }
        if inFlight.contains(key) { lock.unlock(); return }
        inFlight.insert(key)
        lock.unlock()
        github.trace("ask pull \(key)")
        queue.async { [self] in
            defer { if landed(key) { refetch(pull: number, branch: "", repoRoot: repoRoot) } }
            guard let github = self.github,
                  let out = github.run(["gh", "pr", "view", "\(number)", "--json", "number,title,state,reviewDecision,isDraft,url,author,createdAt,mergedAt,closingIssuesReferences"], cwd: repoRoot),
                  let o = try? JSONSerialization.jsonObject(with: out) as? [String: Any] else { return }
            var pr = PullRequest(number: o["number"] as? Int ?? number, title: o["title"] as? String ?? "",
                                 state: o["state"] as? String ?? "", reviewDecision: o["reviewDecision"] as? String ?? "",
                                 isDraft: o["isDraft"] as? Bool ?? false, url: o["url"] as? String ?? "")
            pr.closes = PullSource.closes(o)
            pr.mergedAt = (o["mergedAt"] as? String).flatMap(ISO8601DateFormatter().date(from:))
            lock.lock(); byNumber[key] = (pr, Date()); lock.unlock()
            github.note(task: pr, repoRoot: repoRoot)
            github.note(author: o, number: pr.number, repoRoot: repoRoot, issue: pr.closes.first)
            updated()
        }
    }

    func refresh(branch: String, repoRoot: String) {
        guard let github, !github.frozen else { return }
        let key = repoRoot + "@" + branch
        lock.lock()
        if let (_, at) = byBranch[key], Date().timeIntervalSince(at) < gate("pull:" + key, base: github.baseInterval) { lock.unlock(); return }
        if inFlight.contains(key) { lock.unlock(); return }
        inFlight.insert(key)
        lock.unlock()
        github.trace("ask pull \(key)")

        queue.async { [self] in
            guard let github = self.github else { _ = landed(key); return }
            if github.nameWithOwner(repoRoot: repoRoot) == nil { github.learnOwner(repoRoot) }
            var pr: PullRequest?
            func parse(_ o: [String: Any]) -> PullRequest {
                var checks = ""
                if let rollup = o["statusCheckRollup"] as? [[String: Any]], !rollup.isEmpty {
                    let conclusions = rollup.map { ($0["conclusion"] as? String ?? "").uppercased() }
                    let statuses = rollup.map { ($0["status"] as? String ?? $0["state"] as? String ?? "").uppercased() }
                    if conclusions.contains(where: { ["FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "ERROR"].contains($0) }) || statuses.contains("FAILURE") || statuses.contains("ERROR") { checks = "failure" }
                    else if statuses.contains(where: { ["IN_PROGRESS", "QUEUED", "PENDING", "WAITING"].contains($0) }) || conclusions.contains("") { checks = "pending" }
                    else { checks = "success" }
                }
                var pr = PullRequest(number: o["number"] as? Int ?? 0, title: o["title"] as? String ?? "",
                                     state: o["state"] as? String ?? "", reviewDecision: o["reviewDecision"] as? String ?? "",
                                     isDraft: o["isDraft"] as? Bool ?? false, url: o["url"] as? String ?? "")
                pr.checks = checks
                pr.closes = PullSource.closes(o)
                pr.mergedAt = (o["mergedAt"] as? String).flatMap(ISO8601DateFormatter().date(from:))
                github.note(task: pr, repoRoot: repoRoot)
                github.note(author: o, number: pr.number, repoRoot: repoRoot, issue: pr.closes.first)
                return pr
            }
            let fields = "number,title,state,reviewDecision,isDraft,url,author,createdAt,mergedAt,statusCheckRollup,closingIssuesReferences"
            var answered = false
            if let out = github.run(["gh", "pr", "list", "--head", branch, "--state", "open", "--limit", "1", "--json", fields], cwd: repoRoot),
               let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]], let o = arr.first {
                pr = parse(o); answered = true
            } else if let out = github.run(["gh", "pr", "list", "--head", branch, "--state", "all", "--limit", "1", "--json", fields], cwd: repoRoot),
                      let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] {
                pr = arr.first.map(parse); answered = true
            }
            lock.lock()
            if !answered, let old = byBranch[key] {
                byBranch[key] = (old.0, Date().addingTimeInterval(60 - github.baseInterval))
                lock.unlock()
                if landed(key) { refetch(pull: 0, branch: branch, repoRoot: repoRoot) }
                return
            }
            let changed = byBranch[key]?.0 != pr
            if changed, let pr, byBranch[key] != nil { changes.append(.pullChanged(branch: branch, pr)) }
            byBranch[key] = (pr, Date())
            if let pr, pr.state == "OPEN", pr.checks == "pending" || pr.reviewDecision == "APPROVED" {
                expected["pull:" + key] = (Date().addingTimeInterval(180), 30)
            }
            lock.unlock()
            if landed(key) { refetch(pull: 0, branch: branch, repoRoot: repoRoot) }
            if changed { updated() }
        }
    }

    // MARK: watching

    struct Seen: Equatable { let updated: String; let open: Bool; let merged: Bool }

    private func detectPulls(_ repoRoot: String) {
        guard let github, let owner = github.nameWithOwner(repoRoot: repoRoot),
              let answer = github.watch.ask(repoRoot + "#watch:pulls", "repos/\(owner)/pulls?state=all&sort=updated&direction=desc&per_page=20"), answer.changed,
              let arr = try? JSONSerialization.jsonObject(with: answer.data) as? [[String: Any]] else { return }
        let p = github.pipeline(repoRoot: repoRoot)
        lock.lock(); let before = seen[repoRoot]; let team = teams[repoRoot] == true; lock.unlock()
        let (now, due, moved) = PullSource.moved(arr, before: before, releasesInto: [p.staging, p.production], team: team)
        for m in moved { github.trace("watch: #\(m.number) moved (\(m.head) → \(m.base)) at \(m.updated)") }
        if due.all { github.trace("watch: more than a page moved in \(repoRoot), reading all it follows") }
        lock.lock(); seen[repoRoot] = now; lock.unlock()
        if due != FollowUps.Due() { follow(due, repoRoot: repoRoot) }
    }

    static func moved(_ arr: [[String: Any]], before: [Int: Seen]?, releasesInto bases: [String], team: Bool)
        -> (seen: [Int: Seen], due: FollowUps.Due, moved: [(number: Int, head: String, base: String, updated: String)]) {
        var now: [Int: Seen] = [:]
        var due = FollowUps.Due()
        var moved: [(number: Int, head: String, base: String, updated: String)] = []
        for o in arr {
            guard let n = o["number"] as? Int, let updated = o["updated_at"] as? String else { continue }
            let seen = Seen(updated: updated, open: o["state"] as? String == "open", merged: o["merged_at"] is String)
            now[n] = seen
            guard let before, before[n] != seen else { continue }
            let was = before[n]
            let base = (o["base"] as? [String: Any])?["ref"] as? String ?? ""
            let head = (o["head"] as? [String: Any])?["ref"] as? String ?? ""
            moved.append((n, head, base, updated))
            due.pulls.insert(FollowUps.Pull(number: n, branch: head))
            if was?.open != seen.open { due.team = team }
            if (!base.isEmpty && bases.contains(base)) || (seen.merged && was?.merged != true) { due.releasing = true }
        }
        if let before, !before.isEmpty, arr.count >= 20, !now.contains(where: { before[$0.key] == $0.value }) { due.all = true }
        return (now, due, moved)
    }

    func follow(_ due: FollowUps.Due, repoRoot: String, again: Bool = true) {
        guard let github else { return }
        var due = due
        lock.lock()
        if due.all {
            due.team = teams[repoRoot] == true
            due.releasing = true
            for k in byNumber.keys where k.hasPrefix(repoRoot + "#") { if let n = Int(k.dropFirst(repoRoot.count + 1)) { due.pulls.insert(.init(number: n, branch: "")) } }
            for k in byBranch.keys where k.hasPrefix(repoRoot + "@") { due.pulls.insert(.init(number: 0, branch: String(k.dropFirst(repoRoot.count + 1)))) }
        }
        let heavy = (due.team || due.releasing) && (!again || Date().timeIntervalSince(heavyAt[repoRoot] ?? .distantPast) >= FollowUps.after)
        if heavy { heavyAt[repoRoot] = Date() }
        let later = again && followUps.note(repoRoot, due)
        lock.unlock()
        if due.releasing, again {
            github.watch.tune(repoRoot + "#watch:runs") { $0.heat(for: Deployments.findWithin, Date()) }
            github.watch.tune("watch:board") { $0.heat(for: 120, Date()) }
            github.trace("hot \(repoRoot): deploys for \(Int(Deployments.findWithin))s, the board for 120s")
        }
        for p in due.pulls { refetch(pull: p.number, branch: p.branch, repoRoot: repoRoot) }
        if heavy, due.team { refetchOpenPRs(repoRoot) }
        if heavy, due.releasing { github.releases.refetch(repoRoot) }
        guard later else { return }
        queue.asyncAfter(deadline: .now() + FollowUps.after) { [self] in
            lock.lock(); let d = followUps.take(repoRoot); lock.unlock()
            guard let d else { return }
            self.github?.trace("follow-up \(repoRoot): \(d.pulls.count) pull(s)\(d.team ? ", the open list" : "")\(d.releasing ? ", the releases" : "")")
            follow(d, repoRoot: repoRoot, again: false)
        }
    }

    private func detectFeed(_ repoRoot: String) {
        guard let github else { return }
        github.askWho()
        guard let owner = github.nameWithOwner(repoRoot: repoRoot), let answer = github.watch.ask(repoRoot + "#watch:feed", "repos/\(owner)/events?per_page=100") else { return }
        guard answer.changed else {
            lock.lock(); if let old = feeds[repoRoot] { feeds[repoRoot] = (old.0, Date()) }; lock.unlock()
            return
        }
        guard var arr = try? JSONSerialization.jsonObject(with: answer.data) as? [[String: Any]] else { return }
        if arr.count == 100, let more = github.watch.http.get("repos/\(owner)/events?per_page=100&page=2"),
           let next = try? JSONSerialization.jsonObject(with: more.data) as? [[String: Any]] { arr += next }
        let events = PullSource.feedEvents(arr)
        lock.lock()
        let known = feeds[repoRoot]?.0
        let changed = known != events || savedOnly.remove("f:" + repoRoot) != nil
        feeds[repoRoot] = (events, Date())
        lock.unlock()
        github.note(feed: events, repoRoot: repoRoot)
        let p = github.pipeline(repoRoot: repoRoot)
        if PullSource.fresh(events, since: known).contains(where: { e in
            e.kind == "release" || e.kind == "push" && !(e.branch ?? "").isEmpty && [p.staging, p.production].contains(e.branch ?? "")
        }) { follow(FollowUps.Due(releasing: true), repoRoot: repoRoot) }
        if changed { updated() }
    }

    static func fresh(_ events: [FeedEvent], since known: [FeedEvent]?) -> [FeedEvent] {
        let seen = Set((known ?? []).compactMap(\.id))
        guard !seen.isEmpty else { return [] }
        return events.filter { $0.id.map { !seen.contains($0) } ?? false }
    }

    static func feedEvents(_ arr: [[String: Any]]) -> [FeedEvent] {
        let iso = ISO8601DateFormatter()
        var events: [FeedEvent] = []
        for e in arr {
            guard let at = (e["created_at"] as? String).flatMap(iso.date(from:)) else { continue }
            let actor = (e["actor"] as? [String: Any])?["login"] as? String ?? "?"
            let isBot = GitHubResolver.isBot(actor)
            let payload = e["payload"] as? [String: Any] ?? [:]
            let pr = payload["pull_request"] as? [String: Any]
            let prNumber = pr?["number"] as? Int
            let prBranch = (pr?["head"] as? [String: Any])?["ref"] as? String
            func add(_ kind: String, branch: String?, detail: String = "") {
                events.append(FeedEvent(at: at, actor: actor, isBot: isBot, kind: kind, branch: branch, prNumber: prNumber,
                                        title: pr?["title"] as? String, url: pr?["html_url"] as? String, detail: detail, id: e["id"] as? String))
            }
            switch e["type"] as? String ?? "" {
            case "PushEvent":
                let ref = (payload["ref"] as? String ?? "").replacingOccurrences(of: "refs/heads/", with: "")
                let n = (payload["commits"] as? [[String: Any]])?.count ?? (payload["size"] as? Int ?? 1)
                add("push", branch: ref, detail: "\(max(1, n))")
            case "PullRequestEvent":
                let action = payload["action"] as? String ?? ""
                let merged = (pr?["merged"] as? Bool ?? false) || action == "merged"
                if action == "opened" || action == "reopened" { add("pr_open", branch: prBranch) }
                else if action == "closed" || action == "merged" { add(merged ? "pr_merge" : "pr_close", branch: prBranch) }
            case "PullRequestReviewEvent":
                add("review", branch: prBranch, detail: ((payload["review"] as? [String: Any])?["state"] as? String ?? "").lowercased())
            case "PullRequestReviewCommentEvent":
                add("comment", branch: prBranch)
            case "IssueCommentEvent":
                if let issue = payload["issue"] as? [String: Any], issue["pull_request"] != nil { add("comment", branch: nil) }
            case "CreateEvent":
                if payload["ref_type"] as? String == "branch" { add("branch_create", branch: payload["ref"] as? String) }
            case "DeleteEvent":
                if payload["ref_type"] as? String == "branch" { add("branch_delete", branch: payload["ref"] as? String) }
            case "IssuesEvent":
                if payload["action"] as? String == "opened", let issue = payload["issue"] as? [String: Any] {
                    events.append(FeedEvent(at: at, actor: actor, isBot: isBot, kind: "issue_open", branch: nil, prNumber: issue["number"] as? Int,
                                            title: issue["title"] as? String, url: issue["html_url"] as? String, detail: "", id: e["id"] as? String))
                }
            case "ReleaseEvent":
                add("release", branch: nil, detail: ((payload["release"] as? [String: Any])?["tag_name"] as? String) ?? "")
            default: break
            }
        }
        return events
    }

    // MARK: in flight

    private static func closes(_ o: [String: Any]) -> [Int] {
        ((o["closingIssuesReferences"] as? [[String: Any]]) ?? []).compactMap { $0["number"] as? Int }
    }

    private func gate(_ key: String, base: TimeInterval) -> TimeInterval {
        if let e = expected[key] {
            if Date() < e.until { return e.every }
            expected[key] = nil
        }
        return base
    }

    private func staleLocked(_ flight: String) { if inFlight.contains(flight) { rerun.insert(flight) } }

    private func landed(_ flight: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        inFlight.remove(flight)
        return rerun.remove(flight) != nil
    }

    private func refetchOpenPRs(_ repoRoot: String) {
        lock.lock()
        if let prs = open[repoRoot] { open[repoRoot] = (prs.0, .distantPast) }
        staleLocked("o:" + repoRoot)
        lock.unlock()
        refreshOpenPRs(repoRoot: repoRoot)
    }

    private func refetch(pull n: Int, branch: String, repoRoot: String) {
        let numbered = repoRoot + "#\(n)", branched = repoRoot + "@" + branch
        lock.lock()
        let number = n > 0 ? byNumber[numbered] : nil, named = branch.isEmpty ? nil : byBranch[branched]
        if let number { byNumber[numbered] = (number.0, .distantPast); staleLocked(numbered) }
        if let named {
            byBranch[branched] = (named.0, .distantPast)
            staleLocked(branched)
            expected["pull:" + branched] = (Date().addingTimeInterval(180), 30)
        }
        lock.unlock()
        if number != nil { refresh(pull: n, repoRoot: repoRoot) }
        if named != nil { refresh(branch: branch, repoRoot: repoRoot) }
    }

    private func updated() {
        let github = github
        DispatchQueue.main.async { github?.onUpdate?() }
    }

    // MARK: injection

    func reset() {
        lock.lock(); open = [:]; feeds = [:]; byBranch = [:]; changes = []; lock.unlock()
    }

    func inject(open prs: [OpenPR], for repoRoot: String, saved: Bool) {
        lock.lock()
        open[repoRoot] = (prs, Date())
        if saved { savedOnly.insert("o:" + repoRoot) } else { savedOnly.remove("o:" + repoRoot) }
        lock.unlock()
    }

    func inject(pull pr: PullRequest?, for branch: String, repoRoot: String, changed: Bool) {
        lock.lock()
        byBranch[repoRoot + "@" + branch] = (pr, Date())
        if changed, let pr { changes.append(.pullChanged(branch: branch, pr)) }
        lock.unlock()
    }

    func inject(pull pr: PullRequest, number: Int, repoRoot: String) {
        lock.lock(); byNumber[repoRoot + "#\(number)"] = (pr, Date()); lock.unlock()
    }

    func inject(feed events: [FeedEvent], for repoRoot: String) {
        lock.lock(); feeds[repoRoot] = (events, Date()); lock.unlock()
    }
}
