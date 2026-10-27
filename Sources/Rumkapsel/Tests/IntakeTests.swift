import Foundation

@MainActor
enum IntakeTests {
    private static var failures = 0
    private static var made: [(sim: SimulatorModel, pressed: [String])] = []

    static func run() -> Never {
        test("own PR opens and merges: in storage the moment the merge is heard, said once") {
            let (rig, sim) = org([("Target: ios#298", 0), ("Open PR", 32), ("Merge PR", 1)])
            saw(sim, [.log("PR #298 open"), .arrived(298, in: .waiting)])
            expect(count(sim, .arrived(298, in: .waiting)) == 1, "said once")
            expect(place(rig, "ios", 298) == .waiting, "#298 in storage: \(describe(place(rig, "ios", 298)))")
        }

        test("a branch with no issue, opened, merged and prompted again: one office, its crate in storage") {
            let (rig, sim) = org([("Target: ios#298", 0), ("New branch, no issue", 48), ("Open PR", 32), ("Merge PR", 4.8), ("Prompt", 30)])
            expect(count(sim, .officeOpened("task:ios/claude/"), after: "Merge PR") == 0, "no office opened for the branch after the merge")
            let rooms = station(rig).rooms.values.filter { $0.branch?.hasPrefix("claude/new-work-") == true }
            expect(rooms.count == 1 && rooms[0].key.hasPrefix("task:ios#"), "offices for the branch: \(rooms.map(\.key).sorted())")
            let n = rooms.first.flatMap { Work.number(inOfficeKey: $0.key) } ?? 0
            expect(place(rig, "ios", n) == .waiting, "#\(n) in storage: \(describe(place(rig, "ios", n)))")
        }

        test("a hotfix goes up in its own rocket with its crate; the release rocket keeps standing with its cargo") {
            let (rig, sim) = org([("Target: ios#298", 0), ("Release: Production opens", 16), ("Release: Hotfix opens", 48), ("Release: Hotfix merges", 10)])
            saw(sim, [.log("hotfix #298"), .log("ios: hotfix #298 merged, 1 crate aboard"), deploy("ios")])
            let f = station(rig).facts
            expect(f.rockets["ios|hotfix#298"]?.launched == true && place(rig, "ios", 298) == .aboard("ios|hotfix#298"), "#298 aboard its launched hotfix rocket")
            let release = f.rockets.values.first { $0.repo == "ios" && $0.kind == .release }
            expect(release != nil && release?.launched == false, "the release rocket still stands: \(f.rockets.keys.sorted())")
            expect(place(rig, "ios", 280) == .testing, "the release's cargo stays on the deck: \(describe(place(rig, "ios", 280)))")
        }

        test("a teammate's branch, then its PR: one office by shuttle for him, and his work heard as it happens") {
            let (rig, sim) = org([("Target: api#5158", 0), ("Teammate: New branch", 48), ("Teammate: Open PR", 30)])
            saw(sim, [.officeOpened("task:api#", .shuttle(for: "crew:leo")), .crewActivity("leo", "branch_create"), .crewActivity("leo", "pr_open")])
            expect(count(sim, .officeOpened("task:", shuttle: true)) == 1, "one office by shuttle: \(count(sim, .officeOpened("task:", shuttle: true)))")
            let ordered = station(rig).facts.offices.values.filter { $0.via == .shuttle(for: "crew:leo") }.map(\.key)
            expect(ordered.count == 1, "the office is ordered for leo: \(ordered)")
        }

        test("a staging release opens and merges: every waiting crate goes across to the deck") {
            let (rig, sim) = org([("Target: web#455", 0), ("Release: Staging opens", 80), ("Release: Staging merges", 10)])
            saw(sim, [.staging("web", "open"), .staging("web", "merged")])
            expect([440, 441].allSatisfy { place(rig, "web", $0) == .testing }, "#440 and #441 on the deck: \(describe(place(rig, "web", 440))), \(describe(place(rig, "web", 441)))")
            expect(crates(rig, [.waiting], "web") == 0, "nothing of web left in storage")
        }

        test("the board moves storage to QA before the world sees it: the crates still go to the deck") {
            let (rig, _) = org([("Target: web#455", 0), ("Board: Catch up (yard first)", 10)])
            expect([440, 441].allSatisfy { place(rig, "web", $0) == .testing }, "#440 and #441 on the deck: \(describe(place(rig, "web", 440))), \(describe(place(rig, "web", 441)))")
        }

        test("staging merges and the board leaves cards behind: what git finds on staging goes to the deck anyway, and stays") {
            let (rig, sim) = org([("Target: web#455", 0), ("Release: Staging opens", 80), ("Release: Staging merges (board lags)", 10)])
            saw(sim, [.staging("web", "open"), .staging("web", "merged")])
            expect([440, 441].allSatisfy { place(rig, "web", $0) == .testing }, "#440 and #441 on the deck: \(describe(place(rig, "web", 440))), \(describe(place(rig, "web", 441)))")
            rig.simulateGitHub()
            rig.advance(30)
            expect([440, 441].allSatisfy { place(rig, "web", $0) == .testing }, "the board still saying storage does not pull them back: \(describe(place(rig, "web", 440)))")
        }

        test("rebuilding the yard puts every crate where its work's stage says and sweeps the ones no work holds") {
            let (rig, _) = org([("Target: web#455", 0)])
            rig.advance(20)
            expect(place(rig, "web", 440) == .waiting, "#440 starts in storage")
            rig.world.learn(.work(WorkNews(crate: CrateID(repo: "web", number: 440), stage: .qa, quiet: true)), repo: "web")
            rig.world.learn(.work(WorkNews(crate: CrateID(repo: "web", number: 999), stage: .stored, quiet: true)), repo: "web")
            rig.advance(5)
            expect(place(rig, "web", 440) == .testing && place(rig, "web", 999) == .waiting, "the yard has gone wrong: \(describe(place(rig, "web", 440))), \(describe(place(rig, "web", 999)))")
            rig.world.rebuildYard()
            rig.advance(10)
            expect(place(rig, "web", 440) == .waiting, "#440 back in storage, where its work is: \(describe(place(rig, "web", 440)))")
            expect(place(rig, "web", 999) == nil, "and the crate no work holds is gone: \(describe(place(rig, "web", 999)))")
            rig.world.rebuildYard(dug: [(repo: "web", found: [440: [PullSource.Dug(number: 1440, state: "MERGED", shipped: true)],
                                                              441: [PullSource.Dug(number: 1441, state: "MERGED", shipped: false)]])])
            rig.advance(10)
            expect(place(rig, "web", 440) == nil, "the issue whose pull request is in production has shipped: \(describe(place(rig, "web", 440)))")
            expect(place(rig, "web", 441) == .waiting, "the one merged but not in production stays in storage: \(describe(place(rig, "web", 441)))")
            expect(rig.world.works.find(repo: "web", pull: 1441)?.number == 441, "and its pull request is linked to its work again")
        }

        test("a saved board is history: a stale Shipped on it launches nothing, and the live board confirming storage says nothing") {
            let (rig, _) = org([("Target: web#455", 0)])
            let github = rig.world.github
            guard let live = github.board.items else { return expect(false, "a board") }
            let shipped = ConfigStore.shared.current.statuses.shipped
            github.inject(savedProject: live.map { it in
                guard it.repo == "web", it.number == 440 else { return it }
                return ProjectItem(repo: it.repo, number: it.number, title: it.title, status: shipped, assignees: it.assignees,
                                   prURLs: it.prURLs, url: it.url, updatedAt: it.updatedAt, state: it.state)
            })
            rig.simulateGitHub()
            rig.advance(20)
            expect(place(rig, "web", 440) == .waiting, "#440 still in storage: \(describe(place(rig, "web", 440)))")
            expect(!station(rig).facts.rockets.values.contains { $0.launched }, "no rocket launched")
            github.inject(project: live, quiet: true)
            rig.simulateGitHub()
            rig.advance(20)
            expect(place(rig, "web", 440) == .waiting, "the live board agrees: still in storage")
        }

        test("a saved list of open pull requests is history: a stale one does not pull a stored crate back into an office") {
            let (rig, _) = org([("Target: web#455", 0)])
            let github = rig.world.github
            guard let root = rig.world.repoRoots.first(where: { $0.value.repo == "web" })?.key else { return expect(false, "web's checkout") }
            let offices = station(rig).rooms.count
            github.inject(savedOpenPRs: (github.pulls.teamOpenPRs(repoRoot: root) ?? []) + [OpenPR(number: 440, title: "stored work", author: "kim", isBot: false,
                                         branch: "kim/stored", url: "https://example.invalid/web/440", createdAt: rig.now)], for: root)
            rig.simulateGitHub()
            rig.advance(20)
            expect(place(rig, "web", 440) == .waiting, "#440 still in storage: \(describe(place(rig, "web", 440)))")
            expect(station(rig).rooms.count == offices, "no office for it: \(station(rig).rooms.count) rooms against \(offices)")
        }

        test("a staging release that closes unmerged: the crates stay in storage") {
            let (rig, sim) = org([("Target: web#455", 0), ("Release: Staging opens", 80), ("Release: Staging closes", 30)])
            saw(sim, [.staging("web", "open"), .staging("web", "closed, not merged")])
            expect([440, 441].allSatisfy { place(rig, "web", $0) == .waiting }, "#440 and #441 still in storage")
            expect(crates(rig, [.testing, .cleared], "web") == 2, "only the deck's own two on the deck")
        }

        test("a repository whose merges deploy: the merge is a launched rocket with the crate aboard") {
            let (rig, sim) = org([("Target: ios#298", 0), ("Repo: Ships on merge", 4.8), ("Open PR", 32), ("Merge PR", 10)])
            saw(sim, [.log("ios: #298 merged, 1 crate aboard")])
            guard case .aboard(let id)? = place(rig, "ios", 298), let r = station(rig).facts.rockets[id] else { return expect(false, "#298 aboard: \(describe(place(rig, "ios", 298)))") }
            expect(r.kind == .merge && r.launched, "aboard a launched merge rocket: \(r)")
            expect(count(sim, .standing("ios"), after: "Repo: Ships on merge") == 0, "no release rocket stood for it")
        }

        test("a repository without staging: merged work waits in storage, the release loads from there and goes") {
            let (rig, sim) = org([("Target: ios#298", 0), ("Repo: No staging", 4.8), ("Open PR", 32), ("Merge PR", 128),
                                  ("Release: Production opens", 48), ("Release: Mark tested", 128), ("Release: Production merges", 10)])
            saw(sim, [.arrived(298, in: .waiting), .go("ios"), .releaseMerged("ios")])
            expect(crates(rig, [.waiting], "ios") == 0, "nothing of ios left in storage")
            expect(launchedWith(rig, "ios", 298), "#298 aboard a launched rocket: \(describe(place(rig, "ios", 298)))")
        }

        test("a repository that ships on tags: no rocket for its stored work until the tag, which sends it up") {
            let (rig, sim) = org([("Target: ios#298", 0), ("Repo: Ships on tags", 4.8), ("Open PR", 32), ("Merge PR", 128)])
            saw(sim, [.arrived(298, in: .waiting)])
            expect(station(rig).facts.rockets.values.allSatisfy { $0.repo != "ios" }, "no ios rocket before the tag")
            then(rig, sim, [("Release: Tag", 10)])
            expect(count(sim, .standing("ios"), after: "Repo: Ships on tags") + count(sim, .go("ios"), after: "Repo: Ships on tags") == 0, "nothing stood or loaded for ios")
            expect(crates(rig, [.waiting], "ios") == 0 && launchedWith(rig, "ios", 298), "#298 went up: \(describe(place(rig, "ios", 298)))")
        }

        test("a repository that ships on tags, said shipped with no tag seen: no rocket, the crate just goes") {
            let (rig, sim) = org([("Target: ios#298", 0), ("Repo: Ships on tags", 4.8), ("Open PR", 32), ("Stage: stored", 128), ("Stage: shipped", 10)])
            expect(count(sim, .standing("ios"), after: "Repo: Ships on tags") + count(sim, .go("ios"), after: "Repo: Ships on tags") == 0, "nothing stood or loaded for ios")
            expect(station(rig).facts.rockets.values.allSatisfy { $0.repo != "ios" }, "no ios rocket at all")
            expect(place(rig, "ios", 298) == nil, "#298 is gone: \(describe(place(rig, "ios", 298)))")
        }

        test("the stage panel alone, without staging: stored, cleared, shipped, and the crate goes up from storage") {
            let (rig, sim) = org([("Target: ios#298", 0), ("Repo: No staging", 4.8), ("Open PR", 32), ("Stage: stored", 128), ("Stage: cleared", 96), ("Stage: shipped", 10)])
            saw(sim, [.arrived(298, in: .waiting)])
            expect(crates(rig, [.waiting], "ios") == 1 && place(rig, "ios", 280) == .waiting, "#280 alone left in storage")
            expect(launchedWith(rig, "ios", 298), "#298 went up: \(describe(place(rig, "ios", 298)))")
        }

        test("the stage panel with a staging area: storage, the deck, the tested rows, and up") {
            let (rig, sim) = org([("Target: ios#298", 0), ("Open PR", 32), ("Stage: stored", 128), ("Stage: QA", 128), ("Stage: cleared", 96)])
            saw(sim, [.arrived(298, in: .waiting), .arrived(298, in: .testing), .arrived(298, in: .cleared)])
            then(rig, sim, [("Stage: shipped", 10)])
            expect(crates(rig, [.testing, .cleared], "ios") == 1 && place(rig, "ios", 280) == .testing, "#280 alone left on the deck")
            expect(launchedWith(rig, "ios", 298), "#298 went up: \(describe(place(rig, "ios", 298)))")
        }

        test("a production release: on the pad untested, go once tested, merged it lifts with the deck aboard") {
            let (rig, sim) = org([("Target: web#455", 0), ("Release: Production opens", 48), ("Release: Mark tested", 96), ("Release: Production merges", 10)])
            saw(sim, [.releaseOpened("web", untested: true), .go("web"), .releaseMerged("web")])
            expect(crates(rig, [.testing, .cleared], "web") == 0, "the deck is empty")
            expect([430, 431].allSatisfy { launchedWith(rig, "web", $0) }, "#430 and #431 went up")
        }

        test("ready to ship moved back to QA on the board: the crate goes back to the untested rows") {
            let (rig, _) = org([("Target: web#455", 0), ("Board: Move web#431 to \(ConfigStore.shared.current.statuses.deck)", 10)])
            expect(place(rig, "web", 431) == .testing, "#431 on the untested rows: \(describe(place(rig, "web", 431)))")
        }

        test("my PR closed unmerged: its office goes red and stays mine, nothing is stored") {
            let (rig, sim) = org([("Target: web#455", 0), ("Open PR", 32), ("Close PR", 10)])
            saw(sim, [.log("PR #455 open"), .log("#455 booking flow: pull request closed, not merged")])
            expect(station(rig).facts.offices["task:web#455"]?.closedAt != nil, "the office is red")
            rig.advance(Rules.closedFor)
            expect(station(rig).rooms["task:web#455"] != nil, "and stays: it is mine")
            expect(count(sim, .arrived(455, in: .waiting)) == 0 && place(rig, "web", 455) == nil, "never stored: \(describe(place(rig, "web", 455)))")
        }

        test("a teammate's PR closed unmerged: red, the office held ten minutes, then cleared") {
            let (rig, sim) = org([("Target: api#5140", 0), ("Teammate: Close PR", 200)])
            saw(sim, [.log("pull request closed, not merged")])
            expect(station(rig).rooms["task:api#5140"] != nil, "the office stands for now")
            then(rig, sim, [("Scan: again", 200), ("Scan: again", 200), ("Scan: again", 120), ("GitHub: Poll", 10)])
            saw(sim, [.officeGone("work|task:api#5140", reason: "pull request closed")])
            expect(station(rig).rooms["task:api#5140"] == nil && station(rig).facts.offices["task:api#5140"] == nil, "the office is gone")
            expect(count(sim, .arrived(5140, in: .waiting)) == 0, "never stored")
        }

        test("a teammate's PR merges: its crate is in storage and the office ends at once") {
            let (rig, sim) = org([("Target: api#5140", 0), ("Teammate: Merge PR", 10)])
            saw(sim, [.arrived(5140, in: .waiting), .officeGone("work|task:api#5140", reason: "pull request closed")])
            expect(place(rig, "api", 5140) == .waiting, "#5140 in storage: \(describe(place(rig, "api", 5140)))")
            expect(station(rig).rooms["task:api#5140"] == nil && station(rig).facts.offices["task:api#5140"] == nil, "the office is gone from the facts")
        }

        test("a bot's PR: an object in decon, merged, cleared into storage, and no office for it") {
            let (rig, sim) = org([("Target: ios#298", 0), ("Bot: Open PR", 32), ("Bot: Merge PR", 10)])
            saw(sim, [.log("in decon"), .log(Words.current.clearedDecon)])
            expect(count(sim, .officeOpened("task:ios#", shuttle: true)) == 0, "no office by shuttle")
            let object = station(rig).facts.crates.values.first { $0.id.repo == "ios" && $0.alien }
            expect(object?.place == .waiting && crates(rig, [.decon], "ios") == 0, "the object is in storage: \(describe(object?.place))")
        }

        test("a bot's PR closed unmerged: ejected from decon, never cleared, gone") {
            let (rig, sim) = org([("Target: web#455", 0), ("Bot: Open PR", 32), ("Bot: Close PR", 10)])
            saw(sim, [.log("in decon"), .log("ejected from decon, never cleared")])
            expect(count(sim, .log(Words.current.clearedDecon)) == 0, "never cleared")
            expect(!station(rig).facts.crates.values.contains { $0.id.repo == "web" && $0.alien }, "the object left the facts")
        }

        test("a neighbour arrives and leaves: her office fades in, and is held while she is away") {
            let (rig, sim) = org([("Peer: Leave", 64), ("Peer: Arrive", 96), ("Peer: Leave", 10)])
            saw(sim, [.officeOpened("task:web#460", .fade), .peerLeft("kim"), .peerArrived("kim"), .peerLeft("kim")])
            expect(station(rig).rooms["task:web#460"] != nil && station(rig).facts.offices["task:web#460"] != nil, "kim's office is held")
        }

        test("a neighbour's office kicked: gone, said once") {
            let (rig, sim) = org([("Target: web#460", 0), ("Peer: Kick office", 10)])
            saw(sim, [.officeGone("work|task:web#460", reason: "kicked"), .log("kicked #460 artist tags off the station")])
            expect(station(rig).rooms["task:web#460"] == nil && station(rig).facts.offices["task:web#460"] == nil, "the office is gone")
        }

        test("a session ends: its office stays") {
            let (rig, sim) = org([("Target: api#5158", 0)])
            expect(rig.scanned("api", 5158), "the session is in the scan")
            then(rig, sim, [("Session ends", 160)])
            expect(!rig.scanned("api", 5158), "the session is gone from the scan")
            expect(station(rig).rooms["task:api#5158"] != nil && station(rig).facts.offices["task:api#5158"] != nil, "the office stays")
        }

        test("a workspace's project office becomes its task office when a branch is checked out, whichever session is scanned first") {
            ConfigStore.shared.update { $0.useProject = false }
            defer { ConfigStore.shared.update { $0.useProject = nil } }
            let rig = Rig(), github = rig.world.github
            let base = NSTemporaryDirectory() + "rumkapsel-one-\(UUID().uuidString)"
            let root = base + "/notes", cwd = base + "/notes-ws"
            for d in [root, cwd] { try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true) }
            defer { try? FileManager.default.removeItem(atPath: base) }
            github.inject(login: "me")
            github.inject(owner: "me/notes", for: root)
            github.inject(openPRs: [], for: root)
            github.inject(releases: [], for: root)
            func session(_ id: String, branch: String?, subagent: Bool) -> SessionInfo {
                SessionInfo(id: id, cwd: cwd, repo: "notes", repoRoot: root, owner: "me", lastModified: rig.now, activity: .coding("src"),
                            area: nil, title: nil, branch: branch, toolCount: 0, isSubagent: subagent, cwdExists: true, promptCount: 1,
                            queuedCount: 0, eventMarkers: [:])
            }
            rig.simulate(scan: ScanResult(sessions: [session("main", branch: nil, subagent: false)]))
            rig.advance(16)
            let before = station(rig).rooms.keys.filter { !$0.hasPrefix("kind:") }
            expect(before.count == 1 && before.allSatisfy { $0.hasPrefix("proj:") }, "a project office first: \(before.sorted())")
            let opened = rig.officesOpened
            for _ in 0..<4 {
                let homes = Dictionary(uniqueKeysWithValues: station(rig).rooms.keys.filter { !$0.hasPrefix("kind:") }.prefix(1)
                    .map { ("main", World.MinionHome(station: "work", key: $0, idle: false)) })
                rig.simulate(scan: ScanResult(sessions: [session("sub", branch: "claude/feature", subagent: true),
                                                         session("main", branch: "claude/feature", subagent: false)]), homes: homes)
                rig.advance(6)
            }
            let after = station(rig).rooms.keys.filter { !$0.hasPrefix("kind:") }
            expect(after.count == 1 && after.allSatisfy { $0.hasPrefix("task:notes") }, "one task office for the workspace: \(after.sorted())")
            expect(rig.officesOpened - opened <= 1, "it opened once, not once a scan: \(rig.officesOpened - opened)")
        }

        test("one session working in two repositories' checkouts: each keeps its own office, none renamed across") {
            ConfigStore.shared.update { $0.useProject = false }
            defer { ConfigStore.shared.update { $0.useProject = nil } }
            let rig = Rig(), github = rig.world.github
            let base = NSTemporaryDirectory() + "rumkapsel-two-\(UUID().uuidString)"
            let web = base + "/web", api = base + "/web/.context/api"
            for d in [web, api] { try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true) }
            defer { try? FileManager.default.removeItem(atPath: base) }
            github.inject(login: "me")
            for (root, repo) in [(web, "web"), (api, "api")] {
                github.inject(owner: "me/" + repo, for: root)
                github.inject(openPRs: [], for: root)
                github.inject(releases: [], for: root)
            }
            func session(in cwd: String, _ repo: String) -> SessionInfo {
                SessionInfo(id: "main", cwd: cwd, repo: repo, repoRoot: cwd, owner: "me", lastModified: rig.now, activity: .coding("src"),
                            area: nil, title: nil, branch: "gh-77/sign-in", toolCount: 0, isSubagent: false, cwdExists: true, promptCount: 1,
                            queuedCount: 0, eventMarkers: [:])
            }
            var lastCwd = api
            rig.simulate(scan: ScanResult(sessions: [session(in: api, "api")]))
            rig.advance(16)
            for (cwd, repo) in [(web, "web"), (api, "api"), (web, "web")] {
                let held = station(rig).rooms.values.first { !$0.key.hasPrefix("kind:") && $0.worktree == lastCwd }?.key
                let homes = held.map { ["main": World.MinionHome(station: "work", key: $0, idle: false)] } ?? [:]
                rig.simulate(scan: ScanResult(sessions: [session(in: cwd, repo)]), homes: homes)
                lastCwd = cwd
                rig.advance(6)
            }
            let rooms = station(rig).rooms.values.filter { !$0.key.hasPrefix("kind:") }
            expect(rooms.contains { $0.key.hasPrefix("task:api") && $0.repo == "api" }, "api's office stays api's: \(rooms.map(\.key).sorted())")
            expect(rooms.contains { $0.key.hasPrefix("task:web") && $0.repo == "web" }, "web's work has its own office: \(rooms.map(\.key).sorted())")
            expect(rooms.allSatisfy { $0.key.hasPrefix("task:\($0.repo ?? "")") }, "no office named for another repository: \(rooms.map { "\($0.key)@\($0.repo ?? "")" })")
        }

        test("a workspace switched from a pull request's branch to a new one holds the new office, opened once") {
            ConfigStore.shared.update { $0.useProject = false }
            defer { ConfigStore.shared.update { $0.useProject = nil } }
            let rig = Rig(), github = rig.world.github
            let base = NSTemporaryDirectory() + "rumkapsel-switch-\(UUID().uuidString)"
            let root = base + "/notes", cwd = base + "/notes-ws"
            for d in [root, cwd] { try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true) }
            defer { try? FileManager.default.removeItem(atPath: base) }
            github.inject(login: "me")
            github.inject(owner: "me/notes", for: root)
            github.inject(releases: [], for: root)
            github.inject(pull: PullRequest(number: 12, title: "first", state: "OPEN", reviewDecision: "", isDraft: false, url: "https://example.invalid/notes/12"),
                          for: "claude/first", repoRoot: root)
            github.inject(openPRs: [OpenPR(number: 12, title: "first", author: "me", isBot: false, branch: "claude/first",
                                           url: "https://example.invalid/notes/12", createdAt: rig.now)], for: root)
            func session(_ id: String, branch: String, subagent: Bool) -> SessionInfo {
                SessionInfo(id: id, cwd: cwd, repo: "notes", repoRoot: root, owner: "me", lastModified: rig.now, activity: .coding("src"),
                            area: nil, title: nil, branch: branch, toolCount: 0, isSubagent: subagent, cwdExists: true, promptCount: 1,
                            queuedCount: 0, eventMarkers: [:])
            }
            rig.simulateGitHub()
            rig.simulate(scan: ScanResult(sessions: [session("main", branch: "claude/first", subagent: false)]))
            rig.advance(16)
            expect(station(rig).rooms["task:notes#12"] != nil, "the pull request's office: \(station(rig).rooms.keys.sorted())")
            let opened = rig.officesOpened
            for _ in 0..<4 {
                rig.simulate(scan: ScanResult(sessions: [session("main", branch: "claude/second", subagent: false)]))
                rig.advance(6)
            }
            let after = station(rig).rooms.keys.filter { !$0.hasPrefix("kind:") }
            expect(after.contains { $0.contains("claude/second") }, "the workspace holds the new branch's office: \(after.sorted())")
            expect(rig.officesOpened - opened == 1, "opened once, not once a scan: \(rig.officesOpened - opened)")
        }

        test("a plain repository: main only, pull requests, no board, release tags: an office, the crate in storage on merge, up on a tag") {
            ConfigStore.shared.update { $0.useProject = false }
            defer { ConfigStore.shared.update { $0.useProject = nil } }
            let rig = Rig(), github = rig.world.github
            let base = NSTemporaryDirectory() + "rumkapsel-plain-\(UUID().uuidString)"
            let root = base + "/notes", cwd = base + "/notes-tidy"
            for d in [root, cwd] { try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true) }
            defer { try? FileManager.default.removeItem(atPath: base) }
            let branch = "claude/tidy"
            let pipeline = PipelineDetection.detect(branches: ["main", branch], merges: [.init(base: "main", head: "claude/older")], file: nil,
                                                    defaultBranch: "main", tagged: true)
            expect(pipeline.shipsOnTag && pipeline.trunk == "main", "detected as shipping on tags from main: \(pipeline.ship), \(pipeline.trunk)")
            github.inject(login: "me")
            github.inject(owner: "me/notes", for: root)
            github.inject(pipeline: pipeline, for: root)
            github.inject(cargo: GitHubResolver.Cargo(storage: 0, deck: 0, storageNumbers: [], deckNumbers: []), for: root)
            github.inject(openPRs: [], for: root)
            github.inject(releases: [], for: root)
            func scan() {
                let s = SessionInfo(id: "plain-1", cwd: cwd, repo: "notes", repoRoot: root, owner: "me", lastModified: rig.now, activity: .coding("src"),
                                    area: nil, title: nil, branch: branch, toolCount: 0, isSubagent: false, cwdExists: true, promptCount: 1,
                                    queuedCount: 0, eventMarkers: [:])
                rig.simulate(scan: ScanResult(sessions: [s]))
            }
            func pull(_ state: String) {
                github.inject(pull: PullRequest(number: 12, title: "tidy the notes", state: state, reviewDecision: "", isDraft: false, url: "https://example.invalid/notes/12"),
                              for: branch, repoRoot: root)
                github.inject(openPRs: state == "OPEN" ? [OpenPR(number: 12, title: "tidy the notes", author: "me", isBot: false, branch: branch,
                                                                  url: "https://example.invalid/notes/12", createdAt: rig.now)] : [], for: root)
                rig.simulateGitHub()
                scan()
            }
            scan()
            rig.advance(16)
            expect(station(rig).rooms.keys.contains { $0.hasPrefix("task:notes") }, "an office for the session: \(station(rig).rooms.keys.sorted())")
            pull("OPEN")
            rig.advance(32)
            expect(station(rig).facts.offices["task:notes#12"]?.crate == CrateID(repo: "notes", number: 12), "its crate packed in the office: \(station(rig).facts.offices.keys.sorted())")
            pull("MERGED")
            rig.advance(32)
            expect(place(rig, "notes", 12) == .waiting, "#12 in storage on the merge: \(describe(place(rig, "notes", 12)))")
            expect(!station(rig).facts.rockets.values.contains { $0.repo == "notes" }, "no rocket stands by: it ships on a tag")
            let tag = ReleasePR(number: 0, title: "v1.0", base: "main", head: "v1.0", state: "MERGED", url: "https://example.invalid/notes/releases/tag/v1.0",
                                labels: [], mergedAt: rig.now, production: true, staging: false, tag: true)
            github.inject(releases: [tag], for: root, merged: [tag])
            rig.simulateGitHub()
            rig.advance(10)
            expect(launchedWith(rig, "notes", 12), "#12 went up in a rocket on the tag: \(describe(place(rig, "notes", 12)))")
        }

        test("a restart finds its office's pull request merged: in production, it is shipped quietly with no crate and no launch; otherwise it goes to storage") {
            ConfigStore.shared.update { $0.useProject = false }
            defer { ConfigStore.shared.update { $0.useProject = nil } }
            for shipped in [true, false] {
                let rig = Rig(), github = rig.world.github
                let base = NSTemporaryDirectory() + "rumkapsel-shipped-\(UUID().uuidString)"
                let root = base + "/api", cwd = base + "/api-patch"
                for d in [root, cwd] { try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true) }
                defer { try? FileManager.default.removeItem(atPath: base) }
                let branch = "me/patch"
                github.inject(login: "me")
                github.inject(owner: "me/api", for: root)
                github.inject(pipeline: PipelineDetection.detect(branches: ["develop", "staging", "production"],
                                                                 merges: (0..<20).map { .init(base: "develop", head: "gh-\($0)/work") }
                                                                     + Array(repeating: .init(base: "staging", head: "develop"), count: 3)
                                                                     + Array(repeating: .init(base: "production", head: "staging"), count: 3),
                                                                 file: nil, defaultBranch: "develop"), for: root)
                github.inject(cargo: GitHubResolver.Cargo(storage: 0, deck: 0, storageNumbers: [], deckNumbers: []), for: root)
                github.inject(openPRs: [], for: root)
                github.inject(releases: [], for: root)
                let s = SessionInfo(id: "shipped-1", cwd: cwd, repo: "api", repoRoot: root, owner: "me", lastModified: rig.now, activity: .coding("src"),
                                    area: nil, title: nil, branch: branch, toolCount: 0, isSubagent: false, cwdExists: true, promptCount: 1,
                                    queuedCount: 0, eventMarkers: [:])
                rig.simulate(scan: ScanResult(sessions: [s]))
                rig.advance(16)
                let before = rig.world.works.find(repo: "api", branch: branch)?.stage
                expect(before.map { $0 < .ready } == true, "the office's work is in development before the pull request is heard: \(before.map { "\($0)" } ?? "unheard")")
                var merged = PullRequest(number: 12, title: "patch the images", state: "MERGED", reviewDecision: "", isDraft: false, url: "https://example.invalid/api/12")
                merged.shipped = shipped
                github.inject(pull: merged, for: branch, repoRoot: root)
                rig.simulateGitHub()
                rig.simulate(scan: ScanResult(sessions: [s]))
                rig.advance(32)
                let r = rig.world.works.find(repo: "api", pull: 12)
                if shipped {
                    expect(r?.stage == .shipped, "#12 is shipped: \(r?.stage.map { "\($0)" } ?? "unheard")")
                    expect(place(rig, "api", 12) == nil, "no crate for #12: \(describe(place(rig, "api", 12)))")
                    expect(!station(rig).facts.rockets.values.contains { $0.repo == "api" }, "nothing launches: \(station(rig).facts.rockets.keys.sorted())")
                } else {
                    expect(place(rig, "api", 12) == .waiting, "#12 in storage: \(describe(place(rig, "api", 12)))")
                }
            }
        }

        test("today's flow, detected: develop, staging and production; staging takes the stored crates, the release takes the deck up") {
            let (rig, sim) = org([])
            let detected = PipelineDetection.detect(branches: ["develop", "staging", "production"],
                                                    merges: (0..<20).map { .init(base: "develop", head: "gh-\($0)/work") }
                                                        + Array(repeating: .init(base: "staging", head: "develop"), count: 3)
                                                        + Array(repeating: .init(base: "production", head: "staging"), count: 3),
                                                    file: nil, defaultBranch: "develop")
            for (root, info) in rig.world.repoRoots where info.repo == "web" { rig.world.github.inject(pipeline: detected, for: root) }
            then(rig, sim, [("Target: web#455", 0), ("Release: Staging opens", 80), ("Release: Staging merges", 10)])
            expect([440, 441].allSatisfy { place(rig, "web", $0) == .testing }, "#440 and #441 on the deck: \(describe(place(rig, "web", 440))), \(describe(place(rig, "web", 441)))")
            then(rig, sim, [("Release: Production opens", 48), ("Release: Mark tested", 96), ("Release: Production merges", 10)])
            expect([430, 431, 440, 441].allSatisfy { launchedWith(rig, "web", $0) }, "the deck went up: \([430, 431, 440, 441].map { describe(place(rig, "web", $0)) })")
        }

        say(failures == 0 ? "intake: all passed" : "intake: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func then(_ rig: Rig, _ sim: SimulatorModel, _ steps: [(String, Double)]) {
        if let i = made.firstIndex(where: { $0.sim === sim }) { made[i].pressed += steps.map(\.0) } else { made.append((sim, steps.map(\.0))) }
        for (press, wait) in steps {
            sim.press(press)
            rig.drain()
            rig.advance(wait)
        }
    }

    private static func station(_ rig: Rig) -> Station { rig.world.fleet.station("work") }

    private static func crates(_ rig: Rig, _ zones: Set<Zone>, _ repo: String) -> Int {
        station(rig).facts.crates.values.filter { $0.id.repo == repo && $0.zone.map(zones.contains) == true }.count
    }

    private static func launchedWith(_ rig: Rig, _ repo: String, _ number: Int) -> Bool {
        guard case .aboard(let id)? = place(rig, repo, number) else { return false }
        return station(rig).facts.rockets[id]?.launched == true
    }

    private static func describe(_ p: CrateFact.Place?) -> String { p.map { "\($0)" } ?? "nowhere" }

    private static func deploy(_ repo: String) -> Expect {
        Expect.event("deploy started \(repo)") { if case .deployStarted(_, let r, true, _, _, _) = $0 { return r == repo }; return false }
    }

    private static func count(_ sim: SimulatorModel, _ e: Expect, after press: String? = nil) -> Int {
        let records = sim.records
        let from = press.flatMap { p in records.firstIndex { if case .press(let n) = $0 { return n == p }; return false } } ?? 0
        return records[from...].filter(e.matches).count
    }

    private static func org(_ steps: [(String, Double)]) -> (Rig, SimulatorModel) {
        let rig = Rig()
        let sim = SimulatorModel(station: rig)
        sim.quiet = true
        sim.quiesce()
        sim.seed()
        rig.advance(16)
        then(rig, sim, steps)
        return (rig, sim)
    }

    private static func place(_ rig: Rig, _ repo: String, _ number: Int) -> CrateFact.Place? {
        station(rig).facts.crates[CrateID(repo: repo, number: number)]?.place
    }

    private static func clean(_ sim: SimulatorModel, _ pressed: [String]) {
        for r in sim.records {
            if case .skipped(let why) = r { expect(false, "a press was refused: \(why)") }
            if case .event(.log(let t)) = r, t.contains(" gives up ") { expect(false, "a minion gave up: \(t)") }
        }
        let presses = sim.records.compactMap { r -> String? in if case .press(let n) = r { return n }; return nil }
        expect(presses == pressed, "every step pressed, in order: \(presses)")
    }

    private static func saw(_ sim: SimulatorModel, _ expects: [Expect]) {
        let records = sim.records
        var at = 0
        for want in expects {
            guard let i = records[at...].firstIndex(where: want.matches) else { return expect(false, "never saw \(want.words)") }
            at = i + 1
        }
    }

    private static func test(_ name: String, _ body: () -> Void) {
        let before = failures
        made = []
        body()
        for (sim, pressed) in made { clean(sim, pressed) }
        say((failures == before ? "PASS  " : "FAIL  ") + name)
    }
    private static func expect(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; say("      not so: \(what)") }
    }
    private static func say(_ text: String) { FileHandle.standardError.write((text + "\n").data(using: .utf8)!) }
}

final class Rig: SimStation {
    let model = Simulation<Body>(world: World(demo: true))
    var world: World { model.world }
    var sim: SimHooks? { model.hooks }
    var missions: [Mission] { [] }
    private var timers: [(at: Double, run: () -> Void)] = []
    private var pending: [() -> Void] = []
    private var later: [() -> Void] = []

    var now: Date { model.now }

    init() {
        world.simulated = true
        world.waitsForGitHub = false
        world.fleet.persists = false
        world.github.frozen = true
        model.hooks = SimHooks()
        model.onEvent = { [unowned self] in handle($0) }
        world.github.onUpdate = { [unowned self] in simulateGitHub() }
    }

    func advance(_ seconds: Double) {
        let end = model.clock + seconds
        while model.clock < end - 1e-9 {
            model.clock = min(end, model.clock + 1)
            pending += later
            later = []
            let due = timers.enumerated().filter { $0.element.at <= model.clock }.sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
            timers.removeAll { $0.at <= model.clock }
            due.forEach { $0.run() }
            drain()
            world.settle(tick: true)
            handle(world.reconcileYards())
        }
    }

    func drain() {
        while !pending.isEmpty {
            let work = pending
            pending = []
            for w in work { w(); handle(world.reconcileYards()) }
        }
    }

    func handle(_ events: [WorldEvent]) { events.forEach(handle) }
    private(set) var officesOpened = 0
    func handle(_ event: WorldEvent) {
        if case .office(_, .opened, _) = event { officesOpened += 1 }
        sim?.onEvent?(event)
    }
    func after(_ seconds: Double, _ run: @escaping () -> Void) { timers.append((model.clock + seconds, run)) }

    private var scan = ScanResult()

    func scanned(_ repo: String, _ number: Int) -> Bool {
        scan.sessions.contains { $0.repo == repo && $0.branch?.hasPrefix("gh-\(number)/") == true }
    }

    func simulate(scan: ScanResult) { simulate(scan: scan, homes: [:]) }

    func simulate(scan: ScanResult, homes: [String: World.MinionHome]) {
        pending.append { [unowned self] in
            self.scan = scan
            handle(world.applyScan(scan, now: now, minionHomes: homes))
        }
    }

    func simulateGitHub() { pending.append { [unowned self] in github() } }

    private func github() {
        handle(world.applyGitHub(now: now))
        if world.placementsLeft { later.append { [unowned self] in github() } }
    }

    func simulate(peer: PeerSnapshot) { pending.append { [unowned self] in handle(world.applyPeer(peer, now: now)) } }
    func simulatePeerLeft(_ name: String) { pending.append { [unowned self] in handle(world.dropPeer(name)) } }
    func simulateKick(roomKey key: String) { pending.append { [unowned self] in handle(world.kick(roomKey: key)) } }
    func simulate(_ nudge: SimNudge) {}
}
