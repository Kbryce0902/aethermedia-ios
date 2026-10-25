import Foundation

public final class DebridCloudProvider: MediaProviderProtocol, Sendable {
    public let id = "builtin.debrid.cloud"
    public let displayName = "Real-Debrid Cloud"
    public let version = "0.2.0"
    public let capabilities: ProviderCapabilities = .all
    public let isEnabled = true
    public let priority = 105
    public let supportedTypes: [MediaType] = [.cloudTorrent]
    private let debridClient: RealDebridClientProtocol
    public init(debridClient: RealDebridClientProtocol = RealDebridClient.shared) { self.debridClient = debridClient }
    public func fetchCatalog(category: CatalogCategory) async throws -> [MediaItem] {
        guard category == .debridCloud, debridClient.isAuthenticated else { return [] }
        let torrents = try await debridClient.getTorrents(offset: 0, limit: 2500)
        return torrents.map {
            MediaItem(id: "rd_cloud_\($0.id)", title: $0.filename,
                      overview: "Status: \($0.status) • Size: \($0.formattedSize)", type: .cloudTorrent, providerId: id)
        }
    }
    public func search(query: String) async throws -> [MediaItem] {
        try await fetchCatalog(category: .debridCloud).filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
    public func discoverSources(for item: MediaItem, episode: Episode?) async throws -> [SourceStream] {
        guard item.id.hasPrefix("rd_cloud_") else { return [] }
        let torrentId = String(item.id.dropFirst("rd_cloud_".count))
        let info = try await debridClient.getTorrentInfo(id: torrentId)
        return info.files.filter { $0.isVideo && (info.isAwaitingFileSelection || $0.isSelected) }.map { file in
            SourceStream(id: "\(torrentId):\(file.id)", title: String(file.path.split(separator: "/").last ?? Substring(file.path)),
                         providerName: displayName, sizeBytes: file.bytes, isRealDebridCached: info.isReadyToStream && file.isSelected,
                         infoHash: info.hash, fileIndex: file.id, originalFileName: file.path, providerId: id, cloudTorrentId: torrentId)
        }
    }
    public func resolve(source: SourceStream, using debridClient: RealDebridClientProtocol) async throws -> PlayableStream {
        guard let torrentId = source.cloudTorrentId, let fileId = source.fileIndex else {
            throw RealDebridError.debridLinkResolutionFailed("The cloud file is missing its torrent or file ID.")
        }
        var didSelect = false
        for attempt in 0..<60 {
            try Task.checkCancellation()
            let info = try await debridClient.getTorrentInfo(id: torrentId)
            if ["error", "dead", "virus", "magnet_error"].contains(info.status) {
                throw RealDebridError.debridLinkResolutionFailed("The cloud torrent failed (\(info.status)).")
            }
            if info.isAwaitingFileSelection && !didSelect {
                guard info.files.contains(where: { $0.id == fileId && $0.isVideo }) else { throw RealDebridError.torrentNotFound }
                try await debridClient.selectFiles(torrentId: torrentId, fileIds: [fileId])
                didSelect = true
            } else if info.isReadyToStream {
                let link = try info.link(forFileId: fileId)
                let response = try await debridClient.unrestrictLink(link)
                return try RealDebridClient.playable(from: response, source: source)
            }
            if attempt < 59 { try await Task.sleep(nanoseconds: 1_000_000_000) }
        }
        throw RealDebridError.debridLinkResolutionFailed("This torrent is still preparing. Refresh your cloud and retry when downloaded.")
    }
}
