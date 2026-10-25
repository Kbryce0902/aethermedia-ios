import SwiftUI

/// Settings Screen: Real-Debrid Account management, Provider Toggles, Playback preferences, and Cache controls
@MainActor
public struct SettingsView: View {
    @State private var userProfile: RDUser?
    @State private var isLoadingUser = false
    @State private var showingAuthSheet = false
    @State private var showingLogoutConfirmation = false
    @State private var providers: [ProviderStatus] = []
    
    @State private var isConnected = false
    @State private var accountError: String?
    
    private let debridClient: RealDebridClientProtocol
    private let providerManager: ProviderManager
    private let persistence: PersistenceServiceProtocol
    
    public init(
        debridClient: RealDebridClientProtocol = RealDebridClient.shared,
        providerManager: ProviderManager = .shared,
        persistence: PersistenceServiceProtocol = PersistenceService.shared
    ) {
        self.debridClient = debridClient
        self.providerManager = providerManager
        self.persistence = persistence
    }
    
    public var body: some View {
        NavigationStack {
            List {
                
                // MARK: - Real-Debrid Account Section
                Section(header: Text("Real-Debrid Connection")) {
                    if isConnected {
                        connectedAccountRow
                    } else {
                        disconnectedAccountRow
                    }
                }
                
                if let accountError {
                    Text(accountError).font(.footnote).foregroundStyle(.orange)
                }

                // MARK: - Provider Subsystem
                Section(header: Text("Media & Torrent Providers")) {
                    ForEach(providers, id: \.id) { provider in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text("v\(provider.version)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { provider.isEnabled },
                                set: { newValue in
                                    providerManager.setProviderEnabled(id: provider.id, enabled: newValue)
                                    refreshProviders()
                                }
                            ))
                            .disabled(!provider.isAvailable)
                        }
                    }
                }
                
                Section {
                    NavigationLink("Native Source Settings", destination: NativeSourceSettingsView())
                    Text("Seren and Red Light source modes are native implementations. Kodi ZIP add-ons and their full menus are not executed.").font(.footnote).foregroundStyle(.secondary)
                }

                // MARK: - Playback Settings
                Section(header: Text("Playback & Engine")) {
                    Text("Automatic playback uses AVPlayer for compatible streams and the bundled VideoLAN decoder for MKV, DTS and other formats.")
                        .font(.footnote).foregroundStyle(.secondary)
                    
                    NavigationLink(destination: FormatSupportView()) {
                        Text("Supported Video & Audio Formats")
                    }
                }
                
                // MARK: - Cache & History
                Section(header: Text("Storage & Privacy")) {
                    Button("Clear Search History") {
                        Task { await persistence.clearSearchHistory() }
                    }
                    .foregroundColor(.primary)
                }
                
                // MARK: - About & Handoff
                Section(header: Text("About AetherMedia")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Target Architecture")
                        Spacer()
                        Text("AVPlayer + VideoLAN")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Seren / Red Light")
                        Spacer()
                        Text("Native source modes")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .task {
                refreshProviders()
                await loadUserProfile()
            }
            .sheet(isPresented: $showingAuthSheet) {
                DeviceAuthorizationView(debridClient: debridClient) {
                    isConnected = debridClient.isAuthenticated
                    showingAuthSheet = false
                    Task { await loadUserProfile() }
                }
            }
            .confirmationDialog("Disconnect Real-Debrid?", isPresented: $showingLogoutConfirmation) {
                Button("Disconnect", role: .destructive) {
                    debridClient.logout()
                    userProfile = nil
                    isConnected = false
                    accountError = nil
                }
            }
        }
    }
    
    // MARK: - Connected Account Row
    
    private var connectedAccountRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(userProfile?.username ?? "Connected User")
                        .font(.headline)
                    
                    if let user = userProfile {
                        HStack(spacing: 6) {
                            Text(user.type.uppercased())
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(user.isPremium ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                                .foregroundColor(user.isPremium ? .green : .orange)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            
                            if let exp = user.expiration {
                                Text("Expires: \(exp.prefix(10))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            
            HStack(spacing: 10) {
                Button("Re-authorize") {
                    showingAuthSheet = true
                }
                .font(.footnote.bold())
                
                Spacer()
                
                Button("Disconnect") {
                    showingLogoutConfirmation = true
                }
                .font(.footnote.bold())
                .foregroundColor(.red)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - Disconnected Account Row
    
    private var disconnectedAccountRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No Real-Debrid account connected. Connect to unlock high-speed cached streaming.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            GlassButton(
                title: "Connect Real-Debrid Account",
                systemImage: "link.circle.fill",
                variant: .prominentPlay
            ) {
                showingAuthSheet = true
            }
            .padding(.vertical, 4)
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - Helpers
    
    private func refreshProviders() {
        providers = providerManager.allProviders()
    }
    
    private func loadUserProfile() async {
        isConnected = debridClient.isAuthenticated
        accountError = nil
        guard isConnected else { userProfile = nil; return }
        isLoadingUser = true
        defer { isLoadingUser = false }
        do { userProfile = try await debridClient.getUserProfile() }
        catch { if !Task.isCancelled { accountError = error.localizedDescription } }
        isConnected = debridClient.isAuthenticated
    }
}

/// Information view explaining container and codec support
struct FormatSupportView: View {
    var body: some View {
        List {
            Section(header: Text("Hardware-Decoded Formats (AVPlayer)")) {
                Text("• Video Containers: MP4, M4V, MOV, HLS (m3u8)")
                Text("• Prefer H.264 or HEVC; actual support depends on the device and stream profile.")
                Text("• Audio Codecs: AAC, MP3, Dolby Digital (AC3), Dolby Digital Plus (E-AC3)")
            }
            Section(header: Text("VideoLAN Extended Player")) {
                Text("• Bundled decoding for MKV, AVI, WebM, MPEG-TS, DTS and TrueHD. Actual stream support depends on the codec/profile.")
                Text("• Extended playback includes seeking, embedded audio tracks and subtitles. Native AVPlayer streams retain system PiP/AirPlay; extended playback currently uses the in-app video view.")
            }
        }
        .navigationTitle("Format Support")
    }
}
