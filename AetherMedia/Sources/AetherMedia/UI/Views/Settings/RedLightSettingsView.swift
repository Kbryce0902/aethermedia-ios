import SwiftUI

struct RedLightSettingsView: View {
    @State private var configuration: RedLightConfiguration
    @State private var error: String?
    @State private var saved = false
    private let store: RedLightSettingsStore
    init(store: RedLightSettingsStore = .shared) {
        self.store = store
        _configuration = State(initialValue: store.load())
    }
    var body: some View {
        Form {
            Section {
                Text("Search the native torrent services available in Red Light. Results resolve through your existing Real-Debrid connection. Enable the services you use and choose a working instance for each.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Source services") {
                ForEach(RedLightBackend.allCases) { backend in
                    DisclosureGroup {
                        Toggle("Enabled", isOn: Binding(get: { configuration.enabled.contains(backend) }, set: {
                            if $0 { configuration.enabled.insert(backend) } else { configuration.enabled.remove(backend) }
                            saved = false
                        }))
                        TextField("HTTPS instance or manifest URL", text: Binding(
                            get: { configuration.endpoint(for: backend) },
                            set: { configuration.endpoints[backend.id] = $0; saved = false }))
                            .keyboardType(.URL).privacySensitive()
                        if backend.animeOnly { Text("Used for anime titles.").font(.caption).foregroundStyle(.secondary) }
                        if backend == .aiostreams {
                            TextField("Search API username", text: $configuration.aioUsername).privacySensitive()
                            SecureField("Search API password", text: $configuration.aioPassword)
                            Text("Use the same instance and Search API credentials configured in Kodi Red Light. Configure its providers on the instance first. The iPhone's Real-Debrid token is never sent here. Header-dependent and P2P-only results are not supported.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } label: {
                        HStack {
                            Text(backend.name)
                            Spacer()
                            Text(configuration.enabled.contains(backend) ? "On" : "Off").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Episode sources") {
                Toggle("Include season packs", isOn: $configuration.includeSeasonPacks)
                Text("The requested episode must uniquely match a video in the torrent. Existing cloud selections are preserved.")
                    .font(.footnote).foregroundStyle(.secondary)
                Stepper("Search timeout: \(Int(configuration.timeout)) seconds", value: $configuration.timeout, in: 5...60, step: 5)
            }
            Section {
                Button(saved ? "Settings Saved" : "Save Settings") {
                    do { try store.save(configuration); saved = true; error = nil }
                    catch { self.error = error.localizedDescription }
                }
                Button("Restore Defaults") { configuration = RedLightConfiguration(); saved = false }
                if let error { Text(error).foregroundStyle(.orange).font(.footnote) }
            }
            Section("Compatibility") {
                Text("This is the native iPhone source workflow. Kodi skins, Python ZIP add-ons, Coco/Gears external packs, Trakt menus, Easynews and NZB accounts are not executed by this app.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .navigationTitle("Red Light Settings")
    }
}
