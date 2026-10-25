import SwiftUI
import UIKit

/// Bottom sheet presenting discovered torrent streams, Real-Debrid cache state, and resolution progress
@MainActor
public struct SourceSelectionSheet: View {
    public let mediaItem: MediaItem
    public let episode: Episode?
    public let onStreamResolved: (PlayableStream) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var resolutionTask: Task<Void, Never>?
    @StateObject private var model: SourceSelectionModel
    @State private var selectedFilter: SourceFilter = .all
    
    public enum SourceFilter: String, CaseIterable {
        case all = "All"
        case cached = "Cloud Ready"
        case res4K = "4K UHD"
        case res1080p = "1080p"
        case seren = "Seren Native"
        case redlight = "Red Light"
    }
    
    public init(
        mediaItem: MediaItem,
        episode: Episode? = nil,
        providerManager: ProviderManager = .shared,
        onStreamResolved: @escaping (PlayableStream) -> Void
    ) {
        self.mediaItem = mediaItem
        self.episode = episode
        self._model = StateObject(wrappedValue: SourceSelectionModel(item: mediaItem, episode: episode, manager: providerManager))
        self.onStreamResolved = onStreamResolved
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                // Header with title and episode info
                sheetHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                
                // Quality Filter Pills
                filterBar
                    .padding(.bottom, 12)
                
                if !model.providerWarnings.isEmpty {
                    DisclosureGroup("Some providers could not respond") {
                        ForEach(model.providerWarnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }.font(.footnote).padding(.horizontal, 16).padding(.bottom, 8)
                }
                Divider()
                if !model.backendReports.isEmpty {
                    DisclosureGroup("Red Light source results") {
                        ForEach(model.backendReports) { report in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(report.name): \(report.accepted) sources from \(report.received) results")
                                if let message = report.message { Text(message).foregroundStyle(.orange) }
                            }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        NavigationLink("Red Light Settings", destination: RedLightSettingsView())
                    }.font(.footnote).padding(.horizontal, 16).padding(.vertical, 8)
                }
                
                // Sources List or Loading State
                if let failure = model.resolutionFailure {
                    resolutionFailureBanner(failure)
                }
                if let error = model.discoveryError {
                    ErrorStateBanner(message: error) {
                        Task { await model.discoverSources() }
                    }.padding(.top, 12)
                }
                if model.isLoading && model.sources.isEmpty {
                    loadingView
                } else if model.sources.isEmpty && model.discoveryError != nil {
                    Spacer()
                } else if filteredSources.isEmpty {
                    emptySourcesView
                } else {
                    sourcesList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await model.discoverSources() }
            .onDisappear {
                resolutionTask?.cancel()
                model.cancelResolution()
            }
        }
    }
    
    // MARK: - Header
    
    private var sheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mediaItem.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                
                if let ep = episode {
                    Text("\(ep.code) • \(ep.title)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Select a stream to play with Real-Debrid")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }
    
    // MARK: - Filter Bar
    
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SourceFilter.allCases, id: \.self) { filter in
                    Button(action: { selectedFilter = filter }) {
                        Text(filter.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedFilter == filter ? Color.accentColor : Color.clear)
                            .foregroundColor(selectedFilter == filter ? .white : .primary)
                            .clipShape(Capsule())
                            .liquidGlass(style: .floatingPill, cornerRadius: 16)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Filtered List
    
    private var filteredSources: [SourceStream] {
        switch selectedFilter {
        case .all:
            return model.sources
        case .cached:
            return model.sources.filter { $0.isRealDebridCached }
        case .res4K:
            return model.sources.filter { $0.resolution == .res4K }
        case .res1080p:
            return model.sources.filter { $0.resolution == .res1080p }
        case .seren: return model.sources.filter { $0.providerId == "native.seren" }
        case .redlight: return model.sources.filter { $0.providerId == "native.redlight" }
        }
    }
    
    private var sourcesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(filteredSources) { source in
                    sourceRow(source)
                }
            }
            .padding(16)
        }
    }
    
    // MARK: - Single Source Row
    
    private func sourceRow(_ source: SourceStream) -> some View {
        let isResolving = model.resolvingSourceId == source.id
        
        return Button(action: {
            resolutionTask?.cancel()
            resolutionTask = Task {
                if let playable = await model.resolveSource(source) { onStreamResolved(playable) }
            }
        }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 6) {
                        // Resolution Badge
                        Text(source.resolution.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(resolutionColor(source.resolution).opacity(0.2))
                            .foregroundColor(resolutionColor(source.resolution))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        
                        if let audio = source.audioCodec {
                            Text(audio)
                                .font(.system(size: 10))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        
                        Text(source.formattedSize)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if let seeds = source.seeds {
                            Text("• \(seeds) seeds")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text(source.providerName)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                
                Spacer()
                
                if isResolving {
                    ProgressView()
                        .scaleEffect(0.9)
                } else if model.resolutionFailure?.sourceId == source.id {
                    Label("Failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                } else if source.isRealDebridCached {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                        Text("Ready")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
            .padding(12)
            .liquidGlass(style: .card, cornerRadius: 14)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(model.resolvingSourceId != nil)
    }
    
    // MARK: - Loading & Empty States
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Discovering streams via providers...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Availability is verified when preparing a stream.")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
    }
    
    private var emptySourcesView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No streams found")
                .font(.headline)
            Button("Refresh Sources") { Task { await model.discoverSources() } }
                .buttonStyle(.bordered)
            Text("A newly imported magnet may need time to load its file list. You can also check your Real-Debrid cloud.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
        }
    }
    
    private func resolutionColor(_ res: VideoResolution) -> Color {
        switch res {
        case .res4K: return .purple
        case .res1080p: return .blue
        case .res720p: return .orange
        default: return .secondary
        }
    }
    
    private func resolutionFailureBanner(_ failure: SourceResolutionFailure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(failure.message).font(.subheadline)
                Spacer(minLength: 0)
                Button { model.dismissResolutionFailure() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Dismiss playback error")
            }
            Text("Other sources remain available below.").font(.footnote).foregroundStyle(.secondary)
            if let details = failure.diagnosticDetails {
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(details).font(.caption.monospaced()).textSelection(.enabled)
                        ShareLink(item: "AetherMedia \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")\n\(details)") {
                            Label("Share error details", systemImage: "square.and.arrow.up")
                        }.font(.footnote)
                    }.padding(.top, 6)
                }.font(.footnote)
            }
            if let source = model.sources.first(where: { $0.id == failure.sourceId }),
               let hash = SourceStream.extractHash(from: source.infoHash) {
                DisclosureGroup("Source identity") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Compare this hash with the source Kodi plays to check the same release.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(hash).font(.caption.monospaced()).textSelection(.enabled)
                        Button("Copy torrent hash") { UIPasteboard.general.string = hash }
                            .font(.footnote)
                    }.padding(.top, 6)
                }.font(.footnote)
            }
        }
        .padding(14)
        .liquidGlass(style: .card, cornerRadius: 14)
        .padding(.horizontal, 16).padding(.top, 12)
    }
}
