import Foundation

enum SetupTests {
    private static var failures = 0

    static func run() -> Never {
        let tattoodo = Pipeline(trunk: "develop", staging: "staging", production: "production", source: "history")
        let tags = Pipeline(trunk: "main", staging: "", production: "", source: "tags", ship: .tag)

        test("the new-repository card, one repository, in station words") {
            let card = Setup.card([Setup.Repo(name: "tattoodo-web", pipeline: tattoodo)])
            expect(card == ["New repository: tattoodo-web", "Ships from production through staging · not shared"], "got \(card)")
            let local = Setup.card([Setup.Repo(name: "notes", pipeline: Pipeline(trunk: "main", staging: "", production: "", ship: .never, remote: false))])
            expect(local == ["New repository: notes", "Local work only · not shared"], "got \(local)")
        }

        test("the new-repository card, several at once: one card listing them") {
            let card = Setup.card([Setup.Repo(name: "web", pipeline: tattoodo, shared: true), Setup.Repo(name: "rumkapsel", pipeline: tags),
                                   Setup.Repo(name: "bot", pipeline: Pipeline(trunk: "main", staging: "", production: "", ship: .merge))])
            expect(card == ["New repositories", "web — ships from production through staging · shared with neighbours",
                            "rumkapsel — ships on tags · not shared", "bot — ships on every merge · not shared"], "got \(card)")
            expect(Setup.card([]).isEmpty, "no new repositories, no card")
        }

        test("the setup check says why the yard is empty, from what is so, in station words on the station and the command in Settings") {
            func station(_ c: Setup.Check) -> [String] { Setup.problems(c).map(\.station) }
            func settings(_ c: Setup.Check) -> [String] { Setup.problems(c).map(\.settings) }
            expect(Setup.problems(Setup.Check(scanned: false)).isEmpty, "nothing before the first scan")
            expect(station(Setup.Check()) == ["No repositories on the station yet. Start a Claude session in one, or watch one in Settings."], "no repositories: \(station(Setup.Check()))")
            let hidden = Setup.Check(repos: [Setup.Repo(name: "web", shown: false)], signedIn: true)
            expect(station(hidden) == ["Every repository is kept off the station: see Settings."], "every one hidden: \(station(hidden))")
            let web = Setup.Repo(name: "web", pipeline: tattoodo)
            expect(Setup.problems(Setup.Check(repos: [web], signedIn: true)).isEmpty, "all set says nothing")
            expect(Setup.problems(Setup.Check(repos: [web], signedIn: nil)).isEmpty, "not asked yet says nothing")
            let out = Setup.Check(repos: [web], signedIn: false)
            expect(station(out) == ["The station can't reach GitHub yet: see Settings."] && settings(out) == ["The GitHub CLI isn't signed in. Run gh auth login in a terminal."],
                   "signed out: \(Setup.problems(out))")
            let none = Setup.Check(repos: [web], ghInstalled: false)
            expect(station(none) == ["The station can't reach GitHub yet: see Settings."] && settings(none).first?.contains("brew install gh") == true, "no gh: \(Setup.problems(none))")
            for p in Setup.problems(none) + Setup.problems(out) { expect(!p.station.contains("gh "), "no commands on the station: \(p.station)") }
            let local = Setup.Repo(name: "notes", pipeline: Pipeline(trunk: "main", staging: "", production: "", ship: .never, remote: false))
            expect(station(Setup.Check(repos: [local], signedIn: false)) == ["notes isn't on GitHub, so it never ships."], "only local: \(station(Setup.Check(repos: [local])))")
            expect(Setup.problems(Setup.Check(repos: [local, web], signedIn: true)).isEmpty, "a local one beside one on GitHub says nothing")
            var missing = web; missing.missing = ["the testing branch qa"]
            expect(station(Setup.Check(repos: [missing], signedIn: true)) == ["web: the testing branch qa isn't on GitHub: see Settings."], "a branch set by hand that is gone")
        }

        test("the card lists at most four, then how many more") {
            let six = (1...6).map { Setup.Repo(name: "r\($0)", pipeline: tags) }
            let card = Setup.card(six)
            expect(card.count == 6 && card.last == "and 2 more, in Settings" && card[4].hasPrefix("r4 —"), "got \(card)")
        }

        test("an old config: the retired fields are read once and dropped, nothing else is lost") {
            let old = """
            {"githubMinutes": 5, "sleepMinutes": 5, "showCrew": true, "shareOnLAN": true, "shareName": "Mads", "crewNames": {},
             "trunkBranch": "develop", "stagingBranch": "staging", "productionBranch": "production", "workOwners": ["Tattoodo"],
             "repos": {
               "web": {"station": "auto", "crew": true, "share": true, "color": {"r": 1, "g": 0.5, "b": 0}},
               "book4": {"station": "private", "crew": false, "share": false},
               "madplan": {"station": "hidden", "crew": true, "share": false},
               "api": {"station": "auto", "crew": true, "share": false, "branches": {"trunk": "develop", "staging": "", "production": "live"},
                       "workflow": {"stored": ["pulls", "git"], "qa": null, "cleared": null, "shipped": ["pulls"], "outside": "strangers"}},
               "lib": {"station": "auto", "crew": true, "share": false, "branches": {"trunk": "main", "staging": "qa", "production": ""}}
             }}
            """
            guard let c = try? JSONDecoder().decode(AppConfig.self, from: Data(old.utf8)) else { return expect(false, "the old config decodes") }
            expect(c.shareOnLAN && c.shareName == "Mads", "the global settings kept")
            expect(c.shown(repo: "web") && !c.shown(repo: "book4") && !c.shown(repo: "madplan") && c.shown(repo: "unknown"), "auto shown; private and hidden not")
            expect(c.repos["web"]?.share == true && c.repos["web"]?.color == RGB(r: 1, g: 0.5, b: 0), "share and colour kept")
            let api = c.repos["api"]
            expect(api?.trunk == "develop" && api?.staging == "" && api?.production == "live" && api?.ships == .release, "branches set by hand become the answers: \(String(describing: api))")
            expect(api?.workflow?.stored == [.pulls, .git] && api?.workflow?.qa == nil, "the workflow kept, its outside answer dropped")
            let lib = c.repos["lib"]
            expect(lib?.staging == "qa" && lib?.production == nil && lib?.ships == .never, "an empty production by hand meant no releases: \(String(describing: lib))")
            expect(c.repos.values.allSatisfy { $0.answered == nil }, "an old repository was never asked")
            let saved = String(data: (try? JSONEncoder().encode(c)) ?? Data(), encoding: .utf8) ?? ""
            expect(!saved.contains("\"branches\""), "the old branches are not written back")
            let again = try? JSONDecoder().decode(AppConfig.self, from: Data(saved.utf8))
            expect(again == c, "what is written reads back the same")
        }

        test("a config this build writes still reads in the builds before it") {
            let dir = NSTemporaryDirectory() + "rk-config-\(UUID().uuidString)"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(atPath: dir) }
            let url = URL(fileURLWithPath: dir + "/config.json")
            var c = AppConfig()
            c.shareOnLAN = true
            c.repos["web"] = AppConfig.RepoOverride(share: true, color: RGB(r: 1, g: 0.5, b: 0), ships: .tag)
            c.repos["book4"] = AppConfig.RepoOverride(shown: false)
            c.repos["api"] = AppConfig.RepoOverride(workflow: Workflow(stored: [.pulls], qa: nil, cleared: [.pulls], shipped: [.pulls]), answered: true)
            ConfigFile.write(c, to: url)
            guard let data = try? Data(contentsOf: url) else { return expect(false, "written") }
            do {
                let old = try JSONDecoder().decode(OldConfig.self, from: data)
                expect(old.repos["web"]?.share == true && old.repos["web"]?.color == RGB(r: 1, g: 0.5, b: 0), "the old build keeps share and colour")
                expect(old.repos["book4"]?.station == "hidden" && old.repos["web"]?.station == "auto", "the old build keeps hidden")
                expect(old.repos["api"]?.workflow?.outside == "bots" && old.repos["api"]?.workflow?.stored == [.pulls], "the old build reads the workflow")
                expect(old.trunkBranch == "develop" && old.productionBranch == "production" && old.shareOnLAN, "the old globals are there")
                var edited = old
                edited.repos["web"]?.station = "hidden"
                let back = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(edited))
                expect(!back.shown(repo: "web") && back.repos["web"]?.color == RGB(r: 1, g: 0.5, b: 0), "and what the old build writes reads here")
            } catch {
                expect(false, "the old build decodes it: \(error)")
            }
            let first = try? String(contentsOf: url, encoding: .utf8)
            var more = c; more.repos["web"]?.share = false
            ConfigFile.write(more, to: url)
            expect((try? String(contentsOf: url.appendingPathExtension("bak"), encoding: .utf8)) == first, "the file before the first rewrite is kept as config.json.bak")
        }

        test("an unreadable config is kept, not overwritten; one bad repository spoils nothing else; unknown keys stay") {
            let dir = NSTemporaryDirectory() + "rk-config-\(UUID().uuidString)"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(atPath: dir) }
            let url = URL(fileURLWithPath: dir + "/config.json")
            try? Data("{ not json".utf8).write(to: url)
            let (_, held) = ConfigFile.read(from: url)
            let aside = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.filter { $0.contains("unreadable") } ?? []
            expect(held && (try? String(contentsOf: url, encoding: .utf8)) == "{ not json" && aside.count == 1, "held, the file untouched, a copy aside: \(aside)")
            let mixed = """
            {"githubMinutes": 5, "sleepMinutes": 5, "showCrew": true, "shareOnLAN": false, "shareName": "M", "crewNames": {}, "futureKey": 7,
             "repos": {"bad": "nonsense", "odd": {"color": "red", "share": true, "later": 1}, "web": {"station": "auto", "share": true}}}
            """
            try? Data(mixed.utf8).write(to: url)
            let (c, held2) = ConfigFile.read(from: url)
            expect(!held2 && c.repos["web"]?.share == true && c.repos["odd"]?.share == true && c.repos["odd"]?.color == nil, "the rest read: \(c.repos.keys.sorted())")
            ConfigFile.write(c, to: url)
            let saved = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any]
            expect(saved?["futureKey"] as? Int == 7 && ((saved?["repos"] as? [String: Any])?["odd"] as? [String: Any])?["later"] as? Int == 1, "unknown keys come back")
        }

        test("answering the card changes nothing the station draws from") {
            var c = AppConfig()
            c.repos["web"] = AppConfig.RepoOverride(share: true)
            var answered = c
            answered.repos["web"]?.answered = true
            answered.repos["new"] = AppConfig.RepoOverride(answered: true)
            expect(answered.withoutAnswers == c.withoutAnswers, "only answers differ")
            answered.repos["new"]?.shown = false
            expect(answered.withoutAnswers != c.withoutAnswers, "a real change still counts")
        }

        test("discovery: a worktree joins its repository, a folder inside one finds it, a GitHub remote is seen") {
            let base = GitWatch.real(NSTemporaryDirectory()) + "/rk-setup-\(UUID().uuidString)"
            let repo = base + "/notes", tree = base + "/notes-tidy"
            defer { try? FileManager.default.removeItem(atPath: base) }
            func git(_ args: String...) { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p.arguments = ["-C", repo] + args
                p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; try? p.run(); p.waitUntilExit() }
            try? FileManager.default.createDirectory(atPath: repo + "/src/deep", withIntermediateDirectories: true)
            git("init", "-q", "-b", "main")
            git("-c", "user.email=a@b", "-c", "user.name=a", "commit", "-q", "--allow-empty", "-m", "first")
            git("worktree", "add", "-q", "-b", "claude/tidy", tree)
            expect(Discovery.root(ofCheckout: repo) == repo, "a checkout is its own repository: \(String(describing: Discovery.root(ofCheckout: repo)))")
            expect(Discovery.root(ofCheckout: tree) == repo, "a worktree joins its repository: \(String(describing: Discovery.root(ofCheckout: tree)))")
            expect(Discovery.root(of: repo + "/src/deep") == repo, "a folder inside finds it")
            expect(Discovery.worktrees(of: repo).map(GitWatch.real) == [GitWatch.real(tree)], "the repository lists its worktree: \(Discovery.worktrees(of: repo))")
            expect(!Discovery.githubRemote(repo), "no remote yet")
            git("remote", "add", "origin", "git@github.com:someone/notes.git")
            expect(Discovery.githubRemote(repo) && Discovery.githubRemote(tree), "a GitHub remote, seen from the worktree too")
        }

        test("Conductor: workspaces join their repository; stubs, stale worktrees and phantom folders are no repositories") {
            let home = GitWatch.real(NSTemporaryDirectory()) + "/rk-home-\(UUID().uuidString)"
            defer { try? FileManager.default.removeItem(atPath: home) }
            let fm = FileManager.default
            func git(_ dir: String, _ args: String...) { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p.arguments = ["-C", dir] + args
                p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; try? p.run(); p.waitUntilExit() }
            func repo(_ path: String) {
                try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
                git(path, "init", "-q", "-b", "main"); git(path, "-c", "user.email=a@b", "-c", "user.name=a", "commit", "-q", "--allow-empty", "-m", "first")
            }
            let ws = home + "/conductor/workspaces"
            repo(home + "/src/notes")
            try? fm.createDirectory(atPath: ws + "/notes/aaa-stub/.git/info", withIntermediateDirectories: true)
            try? fm.createDirectory(atPath: ws + "/notes", withIntermediateDirectories: true)
            git(home + "/src/notes", "worktree", "add", "-q", "-b", "tidy", ws + "/notes/tidy")
            repo(home + "/dev/app-ios")
            try? fm.createDirectory(atPath: ws + "/app-ios/copenhagen/.git/info", withIntermediateDirectories: true)
            try? fm.createDirectory(atPath: ws + "/backend-api/bandung-v1/.git/info", withIntermediateDirectories: true)
            try? fm.createDirectory(atPath: ws + "/gone/old", withIntermediateDirectories: true)
            try? Data("gitdir: \(home)/nowhere/.git/worktrees/old\n".utf8).write(to: URL(fileURLWithPath: ws + "/gone/old/.git"))
            let found = Discovery.conductor(home: URL(fileURLWithPath: home)).map { "\($0.repo)=\($0.root)" }
            expect(found == ["app-ios=\(home)/dev/app-ios", "notes=\(home)/src/notes"], "got \(found)")
            expect(Discovery.root(ofCheckout: ws + "/app-ios/copenhagen") == nil, "a .git with only info/ is no repository")
            expect(Discovery.root(ofCheckout: ws + "/gone/old") == nil, "a worktree whose repository is gone is none either")
        }

        say(failures == 0 ? "setup: all passed" : "setup: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private struct OldConfig: Codable {
        struct RepoOverride: Codable {
            var station: String = "auto"
            var crew: Bool = true
            var share: Bool = false
            var color: RGB?
            var branches: Branches?
            var workflow: OldWorkflow?
            var path: String?
        }
        struct Branches: Codable { var trunk: String; var staging: String; var production: String }
        var workOwners: [String] = []
        var repos: [String: RepoOverride] = [:]
        var crewNames: [String: String] = [:]
        var viewerLogin: String?
        var githubMinutes: Int = 5
        var sleepMinutes: Int = 5
        var showCrew: Bool = true
        var showRepoTitles: Bool?
        var themeName: String?
        var placementName: String?
        var trunkBranch: String = "develop"
        var stagingBranch: String = "staging"
        var productionBranch: String = "production"
        var shareOnLAN: Bool = false
        var shareName: String = ""
        var projectOwner: String?
        var projectNumber: Int?
        var projectStatuses: AppConfig.ProjectStatuses?
        var projectField: String?
        var useProject: Bool?
    }
    private struct OldWorkflow: Codable { var stored: [Source]; var qa: [Source]?; var cleared: [Source]?; var shipped: [Source]; var outside: String }

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
