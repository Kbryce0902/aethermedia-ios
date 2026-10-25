import SwiftUI

struct NativeSourceSettingsView: View {
    @AppStorage("native.yts.endpoint") private var yts = "https://yts.mx"
    @AppStorage("native.eztv.endpoint") private var eztv = "https://eztvx.to"
    var body: some View {
        Form {
            Section("Seren Native") {
                TextField("Movie index HTTPS base URL", text: $yts)
                TextField("Episode index HTTPS base URL", text: $eztv)
                Text("Direct movie/episode index searches inspired by Seren’s provider workflow. Exact IMDb and episode matching; availability is checked through Real-Debrid when selected.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Red Light") {
                NavigationLink("Source Services & AIOStreams", destination: RedLightSettingsView())
            }
            Section {
                Text("Use base URLs only. Each index must implement its expected API. These services receive search metadata, never your Real-Debrid token. If an index is blocked or offline, use an available compatible endpoint or disable the provider.").font(.footnote).foregroundStyle(.secondary)
                Button("Reset Seren Endpoints") { yts = "https://yts.mx"; eztv = "https://eztvx.to" }
            }
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .navigationTitle("Native Sources")
    }
}
