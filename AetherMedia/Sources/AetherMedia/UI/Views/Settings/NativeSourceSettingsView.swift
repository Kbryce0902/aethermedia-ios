import SwiftUI

struct NativeSourceSettingsView: View {
    @AppStorage("native.yts.endpoint") private var yts = "https://yts.mx"
    @AppStorage("native.eztv.endpoint") private var eztv = "https://eztvx.to"
    @AppStorage("native.redlight.endpoint") private var redlight = "https://apibay.org"
    var body: some View {
        Form {
            Section("Seren Native") {
                TextField("Movie index HTTPS base URL", text: $yts)
                TextField("Episode index HTTPS base URL", text: $eztv)
                Text("Direct movie/episode index searches inspired by Seren’s provider workflow. Exact IMDb and episode matching; availability is checked through Real-Debrid when selected.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Red Light Native") {
                TextField("APIBay-compatible HTTPS base URL", text: $redlight)
                Text("Standalone index search with title/year/episode validation and Real-Debrid resolution. No PC or Kodi service is required.").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text("Use base URLs only. Each index must implement its expected API. These services receive search metadata, never your Real-Debrid token. If an index is blocked or offline, use an available compatible endpoint or disable the provider.").font(.footnote).foregroundStyle(.secondary)
                Button("Reset Default Endpoints") { yts = "https://yts.mx"; eztv = "https://eztvx.to"; redlight = "https://apibay.org" }
            }
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .navigationTitle("Native Sources")
    }
}
