import XCTest
@testable import AetherMedia

final class MagnetValidationTests: XCTestCase {
    func testHexHashNormalizationAndLengthValidation() {
        let hash = String(repeating: "ab", count: 20)
        XCTAssertEqual(SourceStream.extractHash(from: hash), hash.uppercased())
        XCTAssertEqual(SourceStream.normalizedMagnet(hash), "magnet:?xt=urn:btih:\(hash.uppercased())")
        XCTAssertNil(SourceStream.extractHash(from: String(hash.dropLast())))
        XCTAssertNil(SourceStream.extractHash(from: String(repeating: "Z", count: 40)))
        XCTAssertNil(SourceStream.extractHash(from: "https://fixture.invalid/urn:btih:\(hash)"))
    }
    func testBase32AndEncodedXt() {
        let base32 = String(repeating: "A", count: 32)
        XCTAssertEqual(SourceStream.extractHash(from: base32), String(repeating: "0", count: 40))
        let hash = String(repeating: "F", count: 40)
        XCTAssertEqual(SourceStream.extractHash(from: "magnet:?xt=urn%3Abtih%3A\(hash)"), hash)
    }
    func testManualImportNeverClaimsUnverifiedCache() {
        let source = ManualMagnetProvider().parseMagnetLink("magnet:?xt=urn:btih:\(String(repeating: "F", count: 40))")
        XCTAssertFalse(source.isRealDebridCached)
        XCTAssertEqual(source.providerId, "builtin.magnet")
    }
}
