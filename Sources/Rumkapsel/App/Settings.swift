import AppKit
import Combine
import SwiftUI

struct Named: Identifiable, Hashable { let id: String }
struct RepoDetail {
    var path: String?
    var remote: String?
    var detected: Pipeline?
    var workflow: Workflow?
    var worktrees = 0
    var branches: Set<String>?
}

final class SettingsModel: ObservableObject {
    @Published var config: AppConfig = ConfigStore.shared.current
    @Published var knownRepos: [String] = []
    @Published var details: [String: RepoDetail] = [:]
    @Published var people: [String: SeenPerson] = [:]
    @Published var launchAtLogin = false
    @Published var problems: [String] = []
    @Published var tab = 0
    @Published var selected: String?
    let board = BoardCatalog()
    private var forwarding: AnyCancellable?
    init() { forwarding = board.objectWillChange.sink { [weak self] in self?.objectWillChange.send() } }

    func commit() {
        pending?.cancel()
        let latest = ConfigStore.shared.current
        for (name, r) in latest.repos where r.answered == true { config.repos[name, default: .init()].answered = true }
        if config.viewerLogin == nil { config.viewerLogin = latest.viewerLogin }
        ConfigStore.shared.update(byUser: true) { $0 = config }
    }

    private var pending: DispatchWorkItem?
    func commitSoon() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commit() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var onLaunchAtLogin: (Bool) -> Void
    private var selected: String? {
        get { model.selected }
        nonmutating set { model.selected = newValue }
    }

    var body: some View {
        TabView(selection: $model.tab) {
            general.tabItem { Label("General", systemImage: "gear") }.tag(0)
            repositories.tabItem { Label("Repositories", systemImage: "shippingbox") }.tag(1)
            github.tabItem { Label("GitHub", systemImage: "arrow.triangle.pull") }.tag(2)
            teammates.tabItem { Label("Teammates", systemImage: "person.2") }.tag(3)
        }
        .frame(width: 680, height: 560)
    }

    // MARK: General

    private var general: some View {
        Form {
            Section {
                if model.problems.isEmpty {
                    Text("All set: \(model.knownRepos.count) \(model.knownRepos.count == 1 ? "repository" : "repositories") on the station.")
                } else {
                    ForEach(model.problems, id: \.self) { Text($0) }
                }
            } header: {
                Text("Setup check")
            } footer: {
                Text("Needed: git, and GitHub pull requests read through the GitHub CLI, signed in. Optional: a GitHub project board, issues, a staging branch, releases or tags.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Look", selection: Binding(get: { model.config.theme }, set: { model.config.themeName = $0.rawValue })) {
                    ForEach(Theme.allCases) { Text($0.title).tag($0) }
                }
                if let credit = model.config.theme.credit {
                    Text(credit).font(.caption).foregroundStyle(.secondary)
                }
                Picker("New offices open", selection: Binding(get: { model.config.officePlacement }, set: { model.config.placementName = $0.rawValue })) {
                    ForEach(OfficePlacement.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show repository titles across the top", isOn: Binding(get: { model.config.showTitles }, set: { model.config.showRepoTitles = $0 }))
                Toggle("Show teammates' branches and pull requests", isOn: $model.config.showCrew)
                Stepper("A minion sleeps after \(model.config.sleepMinutes) quiet min", value: $model.config.sleepMinutes, in: 1...60)
                Toggle("Open at login", isOn: $model.launchAtLogin).onChange(of: model.launchAtLogin) { _, on in onLaunchAtLogin(on) }
            }
            Section {
                Toggle("Share my station on the local network", isOn: $model.config.shareOnLAN)
                TextField("Shown to others as", text: $model.config.shareName)
                    .disabled(!model.config.shareOnLAN)
            } header: {
                Text("Sharing")
            } footer: {
                Text("Only repositories set to share on their page are sent: the offices you have checked out, their branch names and package counts, and where minions stand. No paths or transcripts. Right-click an office someone else put on your station to kick it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text(AppConfig.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            } header: {
                Text("Config file")
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.config) { old, new in old.shareName != new.shareName ? model.commitSoon() : model.commit() }
    }

    // MARK: Repositories

    private var repositories: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(model.knownRepos, id: \.self, selection: $model.selected) { repo in
                    HStack(spacing: 8) {
                        Circle().fill(swatch(repo)).frame(width: 10, height: 10)
                        Text(repo).foregroundStyle(model.config.shown(repo: repo) ? .primary : .secondary)
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    Button("Watch a repository…") { addRepository() }
                        .help("Put a git checkout on this Mac on the station")
                    Spacer()
                    Button { removeRepository() } label: { Image(systemName: "minus").frame(width: 20, height: 18) }
                        .help("Stop watching a repository you added")
                        .disabled(selected.map { model.config.repos[$0]?.path == nil } ?? true)
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 210)
            Divider()
            if let repo = selected, model.knownRepos.contains(repo) {
                repositoryPage(repo)
            } else if model.knownRepos.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.problems, id: \.self) { Text($0) }
                }
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text("Select a repository").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if selected == nil { selected = model.knownRepos.first } }
    }

    private func edit(_ repo: String, soon: Bool = false, _ change: (inout AppConfig.RepoOverride) -> Void) {
        var o = model.config.repos[repo] ?? AppConfig.RepoOverride()
        change(&o)
        o.answered = true
        model.config.repos[repo] = o
        soon ? model.commitSoon() : model.commit()
    }

    private func branchField(_ title: String, _ repo: String, _ path: WritableKeyPath<AppConfig.RepoOverride, String?>, detected: String,
                             on github: Set<String>?, effective: String) -> some View {
        BranchField(title: title, saved: model.config.repos[repo]?[keyPath: path] ?? "", detected: detected, missing: github.map { !$0.contains(effective) } ?? false) { name in
            edit(repo) { $0[keyPath: path] = name.isEmpty ? nil : name }
        }
        .id(repo + title)
    }

    private static let shipChoices: [(Ships, String)] = [
        (.release, "from a release branch"), (.tag, "on tags"), (.merge, "on every merge"), (.never, "it doesn't ship"),
    ]

    private func repositoryPage(_ repo: String) -> some View {
        let detail = model.details[repo]
        let path = model.config.repos[repo]?.path ?? detail?.path
        let shown = model.config.shown(repo: repo)
        let picked = model.config.repos[repo]?.color
        let own = model.config.repos[repo]
        let detected = detail?.detected
        let way = (detected ?? .unread).overridden(by: own)
        return Form {
            Section {
                LabeledContent("Folder") {
                    if let path {
                        HStack {
                            Text((path as NSString).abbreviatingWithTildeInPath).textSelection(.enabled)
                            Button { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) } label: { Image(systemName: "arrow.right.circle.fill") }
                                .buttonStyle(.borderless).help("Show in Finder")
                        }
                    } else {
                        Text("no checkout on this Mac").foregroundStyle(.secondary)
                    }
                }
                if let n = detail?.worktrees, n > 0 {
                    LabeledContent("Worktrees", value: "\(n) more \(n == 1 ? "checkout" : "checkouts"), part of this repository")
                }
                LabeledContent("GitHub", value: detail?.remote ?? (detected?.remote == false ? "no GitHub remote: local work only" : "not read yet"))
            } header: {
                Text(repo)
            }
            Section {
                Toggle("Show on the station", isOn: Binding(get: { shown }, set: { on in edit(repo) { $0.shown = on } }))
                Toggle("Share with neighbours", isOn: Binding(
                    get: { shown && (own?.share ?? false) },
                    set: { on in edit(repo) { $0.share = on } }))
                    .disabled(!shown)
                LabeledContent("Colour") {
                    HStack(spacing: 8) {
                        if picked != nil {
                            Button("Clear") { edit(repo) { $0.color = nil } }
                                .buttonStyle(.link)
                                .help("Back to the colour its name gives it")
                        }
                        ColorPicker("", selection: Binding(
                            get: { swatch(repo) },
                            set: { c in
                                guard let n = NSColor(c).usingColorSpace(.genericRGB) else { return }
                                edit(repo, soon: true) { $0.color = RGB(r: n.redComponent, g: n.greenComponent, b: n.blueComponent) }
                            }), supportsOpacity: false)
                        .labelsHidden()
                    }
                }
            } footer: {
                Text((model.config.shareOnLAN ? "" : "Sharing is off for this Mac in General. ")
                     + "The colour comes from the name, so it is the same on every station. A colour you pick is yours alone.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("How does it ship?", selection: Binding(get: { way.ship }, set: { v in edit(repo) { $0.ships = v } })) {
                    ForEach(Self.shipChoices, id: \.0) { Text(Setup.sentence($0.1)).tag($0.0) }
                }
                if way.ship == .release {
                    branchField("Release branch", repo, \.production, detected: detected?.production.isEmpty == false ? detected!.production : Pipeline.productionName,
                                on: detail?.branches, effective: way.production)
                }
                Toggle("Testing phase", isOn: Binding(
                    get: { way.hasStaging },
                    set: { on in edit(repo) { $0.staging = on ? (detected?.hasStaging == true ? detected!.staging : Pipeline.stagingName) : "" } }))
                if way.hasStaging {
                    branchField("Testing branch", repo, \.staging, detected: detected?.hasStaging == true ? detected!.staging : Pipeline.stagingName,
                                on: detail?.branches, effective: way.staging)
                }
                branchField("Trunk", repo, \.trunk, detected: detected.map { $0.trunk.isEmpty ? "main" : $0.trunk } ?? "main",
                            on: detail?.branches, effective: way.trunk)
                if own?.setsPipeline == true {
                    Button("Use what the repository says") { edit(repo) { $0.trunk = nil; $0.ships = nil; $0.production = nil; $0.staging = nil } }
                        .buttonStyle(.link)
                }
            } header: {
                Text("Way to production · " + (own?.setsPipeline == true ? "set by hand" : detected == nil ? "not read yet" : "detected"))
            } footer: {
                Text((detected.map { "Detected: \($0.why). " } ?? "")
                     + "Merged pull requests wait in storage, a testing phase takes them to the test deck, and the release, the tag or the merge sends them up in a rocket. To set it for everyone, put .github/rumkapsel.json on the default branch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let workflow = detail?.workflow {
                let byHand = own?.workflow != nil
                Section {
                    if byHand {
                        stagePicker("Stored when", repo, workflow, \.stored)
                        optionalStagePicker("QA", repo, workflow, \.qa, off: "none: stored goes straight to the rocket")
                        optionalStagePicker("Cleared when", repo, workflow, \.cleared, off: "always: the rocket never waits")
                        stagePicker("Shipped when", repo, workflow, \.shipped)
                        Button("Use what is detected") { edit(repo) { $0.workflow = nil } }
                            .buttonStyle(.link)
                    } else {
                        ForEach(workflow.summary, id: \.question) { row in
                            LabeledContent(row.question, value: row.answer)
                        }
                        Button("Set by hand") { edit(repo) { $0.workflow = workflow } }
                            .buttonStyle(.link)
                    }
                } header: {
                    Text("Who says each stage" + (byHand ? " · set by hand" : " · detected"))
                } footer: {
                    Text("Who may say each stage, first in line first. Any of them moves work on; only the first may take it back. Detected from the way to production above and the board.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func stagePicker(_ title: String, _ repo: String, _ workflow: Workflow, _ path: WritableKeyPath<Workflow, [Source]>) -> some View {
        Picker(title, selection: Binding(
            get: { workflow[keyPath: path].first ?? .pulls },
            set: { s in var w = workflow; w[keyPath: path] = Workflow.first(s, in: w[keyPath: path]); edit(repo) { $0.workflow = w } })) {
            ForEach([Source.board, .pulls, .git, .deploy], id: \.self) { Text("\($0.title) first").tag($0) }
        }
    }

    private func optionalStagePicker(_ title: String, _ repo: String, _ workflow: Workflow, _ path: WritableKeyPath<Workflow, [Source]?>, off: String) -> some View {
        Picker(title, selection: Binding(
            get: { workflow[keyPath: path]?.first },
            set: { s in
                var w = workflow
                w[keyPath: path] = s.map { Workflow.first($0, in: w[keyPath: path] ?? Workflow()[keyPath: path] ?? [$0]) }
                edit(repo) { $0.workflow = w }
            })) {
            Text(off).tag(Source?.none)
            ForEach([Source.board, .pulls, .git, .deploy], id: \.self) { Text("\($0.title) first").tag(Source?.some($0)) }
        }
    }

    private func swatch(_ repo: String) -> Color {
        Color(nsColor: NSColor(model.config.repos[repo]?.color ?? Fleet.handedOut(repo: repo) ?? Colors.idle))
    }

    private func addRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Watch"
        panel.message = "Choose a git checkout, or any folder inside one"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let root = Discovery.root(of: url.path) else {
            let alert = NSAlert()
            alert.messageText = "Not a git checkout"
            alert.informativeText = "\((url.path as NSString).abbreviatingWithTildeInPath) is not inside a git repository."
            alert.runModal()
            return
        }
        let repo = URL(fileURLWithPath: root).lastPathComponent
        if !model.knownRepos.contains(repo) { model.knownRepos = (model.knownRepos + [repo]).sorted() }
        model.details[repo, default: RepoDetail()].path = root
        selected = repo
        edit(repo) { $0.path = root; $0.shown = true }
    }

    private func removeRepository() {
        guard let repo = selected, model.config.repos[repo]?.path != nil else { return }
        model.config.repos[repo]?.path = nil
        if model.config.repos[repo].map({ var o = $0; o.answered = nil; return o == AppConfig.RepoOverride() }) == true { model.config.repos[repo] = nil }
        if model.config.repos[repo] == nil {
            model.details[repo] = nil
            model.knownRepos.removeAll { $0 == repo }
            selected = model.knownRepos.first
        }
        model.commit()
    }

    // MARK: GitHub

    private var useBoard: Binding<Bool> {
        Binding(get: { model.config.useProject != false && model.config.projectNumber != nil || model.config.useProject == true },
                set: { model.config.useProject = $0; model.commit(); if $0 { model.board.loadOrganisations() } })
    }

    private var github: some View {
        let on = useBoard.wrappedValue
        let board = model.board
        let project = board.projects?.first { $0.number == model.config.projectNumber }
        let field = project?.fields.first { $0.name == model.config.statusField }
        return Form {
            Section {
                Toggle("Follow issues on a GitHub project", isOn: useBoard)
                if on {
                    Picker("Organisation", selection: Binding(
                        get: { model.config.projectOwner ?? "" },
                        set: { model.config.projectOwner = $0.isEmpty ? nil : $0; model.config.projectNumber = nil; model.commit(); board.loadProjects(owner: $0) })) {
                        if model.config.projectOwner == nil { Text("Choose…").tag("") }
                        ForEach(options(board.organisations, keeping: model.config.projectOwner), id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Project", selection: Binding(
                        get: { model.config.projectNumber ?? 0 },
                        set: { model.config.projectNumber = $0 == 0 ? nil : $0; guessStages(); model.commit() })) {
                        if model.config.projectNumber == nil { Text("Choose…").tag(0) }
                        ForEach(board.projects ?? []) { Text($0.title).tag($0.number) }
                        if let n = model.config.projectNumber, project == nil { Text(board.projects == nil ? "#\(n)" : "#\(n), not found").tag(n) }
                    }
                    .disabled(model.config.projectOwner == nil)
                    Picker("Status field", selection: Binding(
                        get: { model.config.statusField },
                        set: { model.config.projectField = $0 == "Status" ? nil : $0; guessStages(); model.commit() })) {
                        ForEach(options(project?.fields.map(\.name) ?? [], keeping: model.config.statusField), id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(model.config.projectNumber == nil)
                    if let problem = board.problem { Text(problem).font(.caption).foregroundStyle(.secondary) }
                }
            } footer: {
                Text("With a project whose status field follows issues through the pipeline, the station is laid out from the board instead of git history: one read for every repository.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if on {
                Section {
                    stageRow("Office", "being worked on", \.development, field)
                    stageRow("Storage", "merged, waiting for staging", \.storage, field)
                    stageRow("Test deck", "on staging, in QA", \.deck, field)
                    stageRow("Ticked on the deck", "passed QA, ready to ship", \.cleared, field)
                    stageRow("Rocket", "shipped", \.shipped, field)
                } header: {
                    Text("Where each value puts an issue")
                }
                .disabled(model.config.projectNumber == nil)
            }
            Section {
                Stepper("Re-read everything every \(model.config.githubMinutes) min", value: $model.config.githubMinutes, in: 1...30)
            } footer: {
                Text("The backstop only. Board changes arrive within about twenty seconds, each repository's activity feed is checked once a minute, and a pull request you just opened, pushed or merged is asked about right away.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.config.githubMinutes) { model.commitSoon() }
        .onAppear { if on { board.loadOrganisations(); if let o = model.config.projectOwner { board.loadProjects(owner: o) } } }
    }

    private func guessStages() {
        guard let project = model.board.projects?.first(where: { $0.number == model.config.projectNumber }),
              let field = project.fields.first(where: { $0.name == model.config.statusField }) ?? project.fields.first(where: { $0.name == "Status" }) else { return }
        if model.config.projectField == nil, field.name != "Status" { model.config.projectField = field.name }
        let likely: [(WritableKeyPath<AppConfig.ProjectStatuses, String>, [String])] = [
            (\.development, ["in development", "in progress", "doing", "started"]),
            (\.storage, ["ready for staging", "merged", "ready for qa"]),
            (\.deck, ["qa", "on staging", "in qa", "testing", "staging"]),
            (\.cleared, ["ready to ship", "ready for release", "approved", "qa passed"]),
            (\.shipped, ["shipped", "released", "done", "live"]),
        ]
        var s = model.config.statuses
        for (path, names) in likely where !field.options.contains(s[keyPath: path]) {
            s[keyPath: path] = names.lazy.compactMap { n in field.options.first { $0.lowercased() == n } }.first ?? ""
        }
        model.config.projectStatuses = s
    }

    private func stageRow(_ title: String, _ meaning: String, _ path: WritableKeyPath<AppConfig.ProjectStatuses, String>, _ field: BoardField?) -> some View {
        let current = model.config.statuses[keyPath: path]
        return Picker(selection: Binding(
            get: { current },
            set: { var s = model.config.statuses; s[keyPath: path] = $0; model.config.projectStatuses = s; model.commit() })) {
            Text("None").tag("")
            ForEach(options(field?.options ?? [], keeping: current), id: \.self) { Text($0).tag($0) }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(meaning).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func options(_ offered: [String], keeping saved: String?) -> [String] {
        guard let saved, !saved.isEmpty, !offered.contains(saved) else { return offered }
        return offered + [saved]
    }

    // MARK: Teammates

    private var teammates: some View {
        let logins = Set(model.people.keys).union(model.config.crewNames.keys).sorted { $0.lowercased() < $1.lowercased() }
        let me = model.config.viewerLogin
        return VStack(alignment: .leading, spacing: 12) {
            Text("A nickname is shown on the minion and in the log instead of the GitHub login. Anyone seen in your repositories is listed.")
                .font(.caption).foregroundStyle(.secondary)
            Table(logins.map(Named.init)) {
                TableColumn("GitHub login") { (row: Named) in
                    Text(row.id == me ? "\(row.id) (you)" : row.id).foregroundStyle(.secondary)
                }
                TableColumn("Nickname") { (row: Named) in
                    let login = row.id
                    TextField("", text: Binding(
                        get: { model.config.crewNames[login] ?? "" },
                        set: { model.config.crewNames[login] = $0.isEmpty ? nil : $0; model.commitSoon() }),
                        prompt: Text(login))
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(20)
    }
}

struct BranchField: View {
    let title: String
    let saved: String
    let detected: String
    let missing: Bool
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(title, text: $draft, prompt: Text(detected))
                .focused($focused)
                .onSubmit(save)
                .onChange(of: focused) { _, now in if !now { save() } }
            if missing {
                Text("\(draft.isEmpty ? detected : draft) isn't on GitHub").font(.caption).foregroundStyle(.orange)
            }
        }
        .onAppear { draft = saved }
    }

    private func save() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        if name != saved { commit(name) }
    }
}

struct BoardField: Hashable { let name: String; let options: [String] }
struct BoardProject: Identifiable, Hashable { let number: Int; let title: String; let fields: [BoardField]; var id: Int { number } }

final class BoardCatalog: ObservableObject {
    @Published var organisations: [String] = []
    @Published var projects: [BoardProject]?
    @Published var problem: String?
    private var projectsOf: String?

    func loadOrganisations() {
        guard organisations.isEmpty else { return }
        ask("{ viewer { login organizations(first: 50) { nodes { login } } } }") { [weak self] data in
            let viewer = data?["viewer"] as? [String: Any]
            let orgs = ((viewer?["organizations"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).compactMap { $0["login"] as? String }
            self?.organisations = orgs.sorted { $0.lowercased() < $1.lowercased() }
        }
    }

    func loadProjects(owner: String) {
        guard !owner.isEmpty, projectsOf != owner else { return }
        projectsOf = owner
        projects = nil
        let query = """
        { organization(login: \(GitHubResolver.quoted(owner))) { projectsV2(first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) { nodes {
          number title closed fields(first: 50) { nodes { ... on ProjectV2SingleSelectField { name options { name } } } } } } } }
        """
        ask(query) { [weak self] data in
            let nodes = ((data?["organization"] as? [String: Any])?["projectsV2"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
            self?.projects = nodes.filter { $0["closed"] as? Bool != true }.compactMap { p in
                guard let n = p["number"] as? Int else { return nil }
                let fields = ((p["fields"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).compactMap { f -> BoardField? in
                    guard let name = f["name"] as? String, let opts = f["options"] as? [[String: Any]] else { return nil }
                    return BoardField(name: name, options: opts.compactMap { $0["name"] as? String })
                }
                return BoardProject(number: n, title: p["title"] as? String ?? "#\(n)", fields: fields)
            }
        }
    }

    private func ask(_ query: String, then: @escaping ([String: Any]?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["gh", "api", "graphql", "-f", "query=" + query]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            p.environment = env
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            var data: [String: Any]?
            if (try? p.run()) != nil {
                let raw = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                data = (try? JSONSerialization.jsonObject(with: raw) as? [String: Any])?["data"] as? [String: Any]
            }
            DispatchQueue.main.async { [weak self] in
                self?.problem = data == nil ? "GitHub did not answer; is gh signed in?" : nil
                then(data)
            }
        }
    }
}
