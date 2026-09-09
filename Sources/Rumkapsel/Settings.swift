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
            repositories.tabItem { Label("Repositories", systemImage: "shippingbox") }
            people.tabItem { Label("People", systemImage: "person.2") }
            general.tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 560, height: 420)
        .padding()
    }

    private var stations: some View {
        Form {
            Picker("Split sessions into stations", selection: $model.config.stationRule) {
                Text("One station for everything").tag("none")
                Text("Conductor workspaces are work, the rest private").tag("conductor")
                Text("Repositories owned by these organisations are work").tag("owner")
            }
            .pickerStyle(.radioGroup)
            if model.config.stationRule == "owner" {
                TextField("Work organisations (comma separated)", text: Binding(
                    get: { model.config.workOwners.joined(separator: ", ") },
                    set: { model.config.workOwners = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
            }
            Toggle("Show the crew station (teammates' pull requests)", isOn: $model.config.showCrew)
            Text("Per-repository overrides live under Repositories.").font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: model.config) { _ in model.commit() }
        .padding()
    }

    private var repositories: some View {
        VStack(alignment: .leading) {
            Text("Where each repository's sessions go, and whether teammates' work in it shows on the crew station.")
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
                TableColumn("Crew") { (row: Named) in
                    let repo = row.id
                    Toggle("", isOn: Binding(
                        get: { model.config.repos[repo]?.crew ?? true },
                        set: { model.config.repos[repo, default: .init()].crew = $0; model.commit() }))
                    .labelsHidden()
                }
                .width(50)
            }
        }
        .padding()
    }

    private var people: some View {
        VStack(alignment: .leading) {
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
        .padding()
    }

    private var general: some View {
        Form {
            Toggle("Music", isOn: $model.musicOn).onChange(of: model.musicOn) { onMusic($0) }
            Toggle("Float on top of other windows", isOn: $model.floatOn).onChange(of: model.floatOn) { onFloat($0) }
            Toggle("Open at login", isOn: $model.launchAtLogin).onChange(of: model.launchAtLogin) { onLaunchAtLogin($0) }
            Stepper("Ask GitHub every \(model.config.githubMinutes) min", value: $model.config.githubMinutes, in: 1...30)
            Stepper("Minions sleep after \(model.config.sleepMinutes) quiet min", value: $model.config.sleepMinutes, in: 1...60)
            Button("Check for Updates…") { onCheckUpdates() }
            Text("Config file: \(AppConfig.url.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .onChange(of: model.config) { _ in model.commit() }
        .padding()
    }
}
