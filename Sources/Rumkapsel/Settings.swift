import AppKit
import SwiftUI

struct Named: Identifiable, Hashable { let id: String }

/// The settings window: stations, repositories, people and general options.
final class SettingsModel: ObservableObject {
    @Published var config: AppConfig = ConfigStore.shared.current
    @Published var knownRepos: [String] = []
    @Published var knownLogins: [String] = []
    @Published var launchAtLogin = false
    @Published var musicOn = UserDefaults.standard.bool(forKey: "music")
    @Published var floatOn = UserDefaults.standard.bool(forKey: "float")

    func commit() { ConfigStore.shared.update { $0 = config } }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var onMusic: (Bool) -> Void
    var onFloat: (Bool) -> Void
    var onLaunchAtLogin: (Bool) -> Void
    var onCheckUpdates: () -> Void

    var body: some View {
        TabView {
            stations.tabItem { Label("Stations", systemImage: "building.2") }
            pipeline.tabItem { Label("Releases", systemImage: "airplane.departure") }
            repositories.tabItem { Label("Repositories", systemImage: "shippingbox") }
            people.tabItem { Label("People", systemImage: "person.2") }
            general.tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 600, height: 440)
    }

    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
    }

    private var stations: some View {
        page {
            Text("Split sessions into stations").font(.headline)
            Picker("", selection: $model.config.stationRule) {
                Text("One station for everything").tag("none")
                Text("Conductor workspaces are work, the rest private").tag("conductor")
                Text("Repositories owned by these organisations are work").tag("owner")
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            HStack {
                Text("Work organisations")
                TextField("comma separated", text: Binding(
                    get: { model.config.workOwners.joined(separator: ", ") },
                    set: { model.config.workOwners = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                    .frame(width: 260)
            }
            .disabled(model.config.stationRule != "owner")
            .opacity(model.config.stationRule == "owner" ? 1 : 0.5)
            Divider()
            Toggle("Show teammates' branches and pull requests on the work station", isOn: $model.config.showCrew)
            Text("Hide a repository under Repositories to keep it off the station entirely.").font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: model.config) { _ in model.commit() }
    }

    private var pipeline: some View {
        page {
            Text("How work flows to production").font(.headline)
            Text("Merged pull requests go to storage. A release into the staging branch moves them to the test deck. A release into the production branch loads the rocket. Repositories without the staging branch skip the deck; a repository without the production branch falls back to main or master.")
                .font(.caption).foregroundStyle(.secondary)
            Grid(alignment: .leading, verticalSpacing: 10) {
                GridRow { Text("Trunk branch"); TextField("develop", text: $model.config.trunkBranch).frame(width: 200) }
                GridRow { Text("Staging branch"); TextField("optional", text: $model.config.stagingBranch).frame(width: 200) }
                GridRow { Text("Production branch"); TextField("production", text: $model.config.productionBranch).frame(width: 200) }
            }
        }
        .onChange(of: model.config) { _ in model.commit() }
    }

    private var repositories: some View {
        page {
            Text("Where each repository's sessions go, and whether it is shared on the local network. Nothing is shared unless ticked.")
                .font(.caption).foregroundStyle(.secondary)
            Table(model.knownRepos.map(Named.init)) {
                TableColumn("Repository") { Text($0.id) }
                TableColumn("Station") { (row: Named) in
                    let repo = row.id
                    Picker("", selection: Binding(
                        get: { model.config.repos[repo]?.station ?? "auto" },
                        set: { model.config.repos[repo, default: .init()].station = $0; model.commit() })) {
                        Text("Automatic").tag("auto")
                        Text("Work").tag("work")
                        Text("Private").tag("private")
                        Text("Hidden").tag("hidden")
                    }
                    .labelsHidden()
                }
                .width(130)
                TableColumn("Share") { (row: Named) in
                    let repo = row.id
                    Toggle("", isOn: Binding(
                        get: { model.config.repos[repo]?.share ?? false },
                        set: { model.config.repos[repo, default: .init()].share = $0; model.commit() }))
                    .labelsHidden()
                }
                .width(50)
            }
        }
    }

    private var people: some View {
        page {
            Text("Display names for GitHub logins seen in your repositories.").font(.caption).foregroundStyle(.secondary)
            Table(model.knownLogins.map(Named.init)) {
                TableColumn("GitHub login") { Text($0.id) }
                TableColumn("Shown as") { (row: Named) in
                    let login = row.id
                    TextField("", text: Binding(
                        get: { model.config.crewNames[login] ?? "" },
                        set: { model.config.crewNames[login] = $0.isEmpty ? nil : $0 }),
                        onCommit: { model.commit() })
                }
            }
        }
    }

    private var general: some View {
        page {
            Toggle("Music", isOn: $model.musicOn).onChange(of: model.musicOn) { onMusic($0) }
            Toggle("Float on top of other windows", isOn: $model.floatOn).onChange(of: model.floatOn) { onFloat($0) }
            Toggle("Open at login", isOn: $model.launchAtLogin).onChange(of: model.launchAtLogin) { onLaunchAtLogin($0) }
            Divider()
            Stepper("Ask GitHub every \(model.config.githubMinutes) min", value: $model.config.githubMinutes, in: 1...30)
            Stepper("Minions sleep after \(model.config.sleepMinutes) quiet min", value: $model.config.sleepMinutes, in: 1...60)
            Divider()
            Toggle("Share my station on the local network", isOn: $model.config.shareOnLAN)
            HStack { Text("Shown to others as"); TextField("name", text: $model.config.shareName).frame(width: 180) }
                .disabled(!model.config.shareOnLAN).opacity(model.config.shareOnLAN ? 1 : 0.5)
            Text("Only repositories ticked under Repositories are shared: the offices you have checked out, their branch names and package counts, and where minions stand. No paths or transcripts. Right-click an office someone else put on your station to kick it.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("Check for Updates…") { onCheckUpdates() }
            Spacer()
            Text("Config file: \(AppConfig.url.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .onChange(of: model.config) { _ in model.commit() }
    }
}
