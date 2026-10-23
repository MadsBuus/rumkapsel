import SwiftUI

struct SentryOrg: Hashable { let slug: String; let name: String; let region: String? }

final class SentryCatalog: ObservableObject {
    @Published var connected = ConfigStore.shared.current.sentryOrg != nil
    @Published var orgs: [SentryOrg]?
    @Published var projects: [String]?
    @Published var status = ""

    func connect(_ token: String, then: @escaping ([SentryOrg]) -> Void) {
        status = "Asking Sentry…"
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let found = organisations(token: token)
            DispatchQueue.main.async { [self] in
                guard let found else { status = "Sentry did not take that token"; return }
                Sentry.keep(token)
                connected = true
                orgs = found
                status = found.isEmpty ? "Connected, but the token sees no organisation" : "Connected"
                then(found)
            }
        }
    }

    func load() {
        guard let token = Sentry.token else { connected = false; return }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let found = organisations(token: token)
            DispatchQueue.main.async { [self] in
                orgs = found ?? []
                status = found == nil ? "Sentry is not answering, or the token was revoked" : "Connected"
            }
        }
    }

    func loadProjects(_ org: SentryOrg, then: @escaping ([String]) -> Void = { _ in }) {
        guard let token = Sentry.token, let url = URL(string: Sentry.base(org.region) + "organizations/\(org.slug)/projects/") else { return }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let answer = Sentry.get(url, token: token)
            let slugs = answer.flatMap { $0.status == 200 ? try? JSONSerialization.jsonObject(with: $0.data) as? [[String: Any]] : nil }?
                .compactMap { $0["slug"] as? String }.sorted()
            DispatchQueue.main.async { [self] in
                projects = slugs ?? []
                then(slugs ?? [])
            }
        }
    }

    func disconnect() {
        Sentry.keep(nil)
        connected = false; orgs = nil; projects = nil; status = ""
    }

    private func organisations(token: String) -> [SentryOrg]? {
        guard let url = URL(string: Sentry.base(nil) + "organizations/"), let answer = Sentry.get(url, token: token), answer.status == 200,
              let arr = try? JSONSerialization.jsonObject(with: answer.data) as? [[String: Any]] else { return nil }
        return arr.compactMap { o in
            guard let slug = o["slug"] as? String else { return nil }
            return SentryOrg(slug: slug, name: o["name"] as? String ?? slug, region: (o["links"] as? [String: Any])?["regionUrl"] as? String)
        }
    }
}

extension SettingsView {
    var monitors: some View {
        let s = model.sentry
        let org = s.orgs?.first { $0.slug == model.config.sentryOrg }
        return Form {
            Section {
                if s.connected {
                    LabeledContent("Sentry", value: s.status.isEmpty ? "Connected" : s.status)
                    Button("Disconnect") {
                        s.disconnect()
                        model.config.sentryOrg = nil; model.config.sentryRegion = nil; model.config.sentryProjects = nil
                        model.commit()
                    }
                } else {
                    SecureField("Personal token", text: sentryToken)
                    Button("Connect") {
                        let token = sentryToken.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        sentryToken.wrappedValue = ""
                        s.connect(token) { found in if found.count == 1 { pick(found[0]) } }
                    }
                    .disabled(sentryToken.wrappedValue.isEmpty)
                    if !s.status.isEmpty { Text(s.status).foregroundStyle(.secondary) }
                }
            } header: {
                Text("Sentry")
            } footer: {
                Text("Make a personal token at sentry.io under Settings → Personal Tokens, with org:read, project:read and event:read. It is kept in this Mac's Keychain, never in a file.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if s.connected, let orgs = s.orgs, !orgs.isEmpty {
                Section {
                    Picker("Organisation", selection: Binding(get: { model.config.sentryOrg ?? "" },
                                                              set: { slug in if let o = orgs.first(where: { $0.slug == slug }) { pick(o) } })) {
                        if model.config.sentryOrg == nil { Text("Choose…").tag("") }
                        ForEach(orgs, id: \.slug) { Text($0.name).tag($0.slug) }
                    }
                }
                if org != nil, let projects = s.projects {
                    Section {
                        ForEach(projects, id: \.self) { p in
                            Picker(p, selection: Binding(get: { model.config.sentryProjects?[p] ?? "" }, set: { repo in
                                var map = model.config.sentryProjects ?? [:]
                                map[p] = repo.isEmpty ? nil : repo
                                model.config.sentryProjects = map.isEmpty ? nil : map
                                model.commit()
                            })) {
                                Text("Not followed").tag("")
                                ForEach(model.knownRepos, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    } header: {
                        Text("Whose errors each project holds")
                    } footer: {
                        Text("A project's new errors light its repository's Errors lamp in mission control.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            guard s.connected else { return }
            if s.orgs == nil { s.load() }
            if let slug = model.config.sentryOrg, s.projects == nil {
                s.loadProjects(SentryOrg(slug: slug, name: slug, region: model.config.sentryRegion))
            }
        }
    }

    private func pick(_ o: SentryOrg) {
        let s = model.sentry
        let changed = model.config.sentryOrg != o.slug
        model.config.sentryOrg = o.slug
        model.config.sentryRegion = o.region
        if changed { model.config.sentryProjects = nil }
        model.commit()
        s.loadProjects(o) { projects in
            guard model.config.sentryProjects == nil else { return }
            var map: [String: String] = [:]
            for p in projects { if let repo = Sentry.guess(project: p, repos: model.knownRepos) { map[p] = repo } }
            model.config.sentryProjects = map.isEmpty ? nil : map
            model.commit()
        }
    }
}
