import XCTest
@testable import AetherMedia

final class PersistenceTests: XCTestCase {
    var persistence: PersistenceService!
    var tempURL: URL!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        persistence = PersistenceService(customStorageDirectory: tempURL)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }
    
    func testWatchlistOperations() async {
        let movie = MediaItem(id: "m_100", title: "Interstellar", type: .movie)
        
        var isPresent = await persistence.isInWatchlist(id: movie.id)
        XCTAssertFalse(isPresent)
        
        await persistence.addToWatchlist(movie)
        isPresent = await persistence.isInWatchlist(id: movie.id)
        XCTAssertTrue(isPresent)
        
        // Ensure deduplication
        await persistence.addToWatchlist(movie)
        let list = await persistence.loadWatchlist()
        XCTAssertEqual(list.filter { $0.id == movie.id }.count, 1)
        
        await persistence.removeFromWatchlist(id: movie.id)
        isPresent = await persistence.isInWatchlist(id: movie.id)
        XCTAssertFalse(isPresent)
    }
    
    func testFavoritesToggle() async {
        let show = MediaItem(id: "s_200", title: "Breaking Bad", type: .tvShow)
        
        await persistence.toggleFavorite(show)
        var isFav = await persistence.isFavorite(id: show.id)
        XCTAssertTrue(isFav)
        
        await persistence.toggleFavorite(show)
        isFav = await persistence.isFavorite(id: show.id)
        XCTAssertFalse(isFav)
    }
    
    func testWatchProgressAndResumptionLogic() async {
        let progress = UserWatchProgress(
            mediaItemId: "m_300",
            mediaTitle: "Inception",
            mediaType: .movie,
            positionSeconds: 1200,
            durationSeconds: 8400,
            lastWatchedDate: Date(),
            isCompleted: false
        )
        
        XCTAssertTrue(progress.shouldResume)
        XCTAssertEqual(progress.progressFraction, 1200.0 / 8400.0, accuracy: 0.001)
        
        await persistence.saveProgress(progress)
        let loaded = await persistence.getProgress(mediaItemId: "m_300", episodeId: nil)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.positionSeconds, 1200)
        
        // Test near completion threshold (> 92%)
        var completedProgress = progress
        completedProgress.positionSeconds = 8000 // > 95%
        XCTAssertFalse(completedProgress.shouldResume)
    }
    
    func testSearchHistoryCap() async {
        for i in 1...25 {
            await persistence.addSearchQuery("Query \(i)")
        }
        let history = await persistence.loadSearchHistory()
        XCTAssertEqual(history.count, 20, "Search history should be capped at 20 entries")
        XCTAssertEqual(history.first, "Query 25", "Most recent query should be first")
    }
}
