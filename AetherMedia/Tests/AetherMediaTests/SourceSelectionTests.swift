import XCTest
import SwiftUI
import UIKit
@testable import AetherMedia

final class SourceSelectionTests: XCTestCase {
    @MainActor private func model(provider: SelectionFixtureProvider = SelectionFixtureProvider()) -> SourceSelectionModel {
        let manager = ProviderManager(debridClient: MockRealDebridClient(), providers: [provider], preferences: nil)
        return SourceSelectionModel(item: MediaItem(id: "tt1234567", title: "Fixture"), episode: nil, manager: manager)
    }


    @MainActor private func bannerHeight(_ message: String, category: ContentSizeCategory = .large) -> CGFloat {
        let root = ErrorStateBanner(message: message) {}.environment(\.sizeCategory, category).frame(width: 320)
        let host = UIHostingController(rootView: root)
        return host.sizeThatFits(in: CGSize(width: 320, height: 4000)).height
    }
    @MainActor func testErrorBannerAllocatesHeightForTheFullDiagnosticMessage() {
        let short = bannerHeight("Cloud could not be read.")
        let long = bannerHeight(String(repeating: "The cloud service returned data that could not be read. ", count: 5) + "Response field: $[42].hash.")
        XCTAssertGreaterThan(long, short + 80, "A two-line cap hides the response field the user needs to report")
    }
    @MainActor func testErrorBannerExpandsForAccessibilityText() {
        let message = "Real-Debrid returned an unexpected data format while checking the existing cloud. Response field: $[42].hash."
        XCTAssertGreaterThan(bannerHeight(message, category: .accessibilityExtraExtraExtraLarge), bannerHeight(message))
    }

    @MainActor func testRejectedSourceKeepsAlternativesAndClearsBusyState() async throws {
        let model = model()
        await model.discoverSources()
        let original = model.sources
        let failed = try XCTUnwrap(original.first { $0.id == "failed" })
        let playable = await model.resolveSource(failed)
        XCTAssertNil(playable)
        XCTAssertEqual(model.sources, original)
        XCTAssertEqual(model.resolutionFailure?.sourceId, "failed")
        XCTAssertTrue(model.resolutionFailure?.diagnosticDetails?.contains("Getting the playback link") == true)
        XCTAssertNil(model.discoveryError)
        XCTAssertNil(model.resolvingSourceId)
    }

    @MainActor func testAnotherSourceCanPlayImmediatelyAfterOneIsRejected() async throws {
        let model = model()
        await model.discoverSources()
        let failed = try XCTUnwrap(model.sources.first { $0.id == "failed" })
        let good = try XCTUnwrap(model.sources.first { $0.id == "good" })
        _ = await model.resolveSource(failed)
        let playable = await model.resolveSource(good)
        XCTAssertEqual(playable?.filename, "good.mp4")
        XCTAssertNil(model.resolutionFailure)
        XCTAssertEqual(model.sources.count, 2)
    }

    @MainActor func testFailedRefreshKeepsPreviousSourcesVisible() async {
        let model = model(provider: SelectionFixtureProvider(failRefresh: true))
        await model.discoverSources()
        let original = model.sources
        await model.discoverSources()
        XCTAssertEqual(model.sources, original)
        XCTAssertEqual(model.sources.count, 2)
        XCTAssertNotNil(model.discoveryError)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor func testCancelledResolutionLeavesNoStuckSpinnerOrError() async throws {
        let provider = SelectionFixtureProvider(slow: true)
        let model = model(provider: provider)
        await model.discoverSources()
        let good = try XCTUnwrap(model.sources.first { $0.id == "good" })
        let task = Task { await model.resolveSource(good) }
        for _ in 0..<500 {
            if provider.counts.get("resolve") > 0 { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertNotNil(model.resolvingSourceId)
        task.cancel()
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertNil(model.resolvingSourceId)
        XCTAssertNil(model.resolutionFailure)
        XCTAssertEqual(model.sources.count, 2)
    }
}

private struct SelectionFixtureProvider: MediaProviderProtocol {
    let id = "selection.fixture", displayName = "Fixture", version = "test"
    let capabilities: ProviderCapabilities = [.sourceDiscovery, .directPlayback]
    let isEnabled = true, priority = 1
    let supportedTypes: [MediaType] = [.movie]
    var failRefresh = false
    var slow = false
    let counts = RequestCounts()
    func fetchCatalog(category: CatalogCategory) async throws -> [MediaItem] { [] }
    func search(query: String) async throws -> [MediaItem] { [] }
    func discoverSources(for item: MediaItem, episode: Episode?) async throws -> [SourceStream] {
        let call = counts.increment("discover")
        if failRefresh && call > 1 { throw ProviderServiceError.unavailable("Fixture refresh failed") }
        return ["failed", "good"].map { SourceStream(id: $0, title: $0, providerName: displayName, providerId: id) }
    }
    func resolve(source: SourceStream, using debridClient: RealDebridClientProtocol) async throws -> PlayableStream {
        counts.increment("resolve")
        if slow { try await Task.sleep(nanoseconds: 1_000_000_000) }
        if source.id == "failed" {
            throw RealDebridError.requestFailed(RealDebridRequestFailure(operation: .playbackLink, statusCode: 451, code: 35))
        }
        return PlayableStream(streamURL: URL(string: "https://fixture.invalid/good.mp4")!, title: "good", filename: "good.mp4")
    }
}
