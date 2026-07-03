import XCTest
@testable import Kigo

// MARK: - FakeKigoImageTransport

/// In-memory fake `KigoImageTransport`: records every requested URL and either
/// returns pre-configured canned bytes or throws a pre-configured error. Mirrors
/// `FakeRemoteManifestSource`/`EntitlementTransactionSource` fakes elsewhere in
/// this suite — no real networking, deterministic, headless.
final class FakeKigoImageTransport: KigoImageTransport, @unchecked Sendable {
    enum Behavior {
        case succeed(Data)
        case fail(Error)
    }

    private let behavior: Behavior
    private(set) var requestedURLs: [URL] = []

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func fetchData(from url: URL) async throws -> Data {
        requestedURLs.append(url)
        switch behavior {
        case .succeed(let data): return data
        case .fail(let error): throw error
        }
    }
}

// MARK: - KigoImageSourceTests

/// Slice #205 (C25 slice 1, ADR 0022): the KigoImageSource walking skeleton —
/// manifest field, URL derivation, injected-transport fetch, nil-safe fallback.
final class KigoImageSourceTests: XCTestCase {

    private enum FakeError: Error { case transportFailure }

    // MARK: - Fixture loading

    /// Loads a committed Manifest fixture bundled into KigoTests (Tests/Fixtures,
    /// see project.yml) via `Bundle(for: Self.self)` — same pattern as
    /// `C24AssembledManifestScreenshotTests`.
    private func loadFixture(named name: String) throws -> Manifest {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json"),
            "\(name).json must be bundled into KigoTests"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    // MARK: - AC1: fixture with imageBaseURL decodes and matches the source string

    func testFixtureWithImageBaseURLDecodesAndMatchesSourceString() throws {
        let manifest = try loadFixture(named: "image-source-with-base-url")
        XCTAssertEqual(
            manifest.imageBaseURL,
            "https://images.kigo.example/photos",
            "Decoded imageBaseURL must match the fixture's source string exactly"
        )
    }

    // MARK: - AC2: fixture without imageBaseURL decodes, and resolving any day returns nil

    func testFixtureWithoutImageBaseURLDecodesAndResolvesNil() async throws {
        let manifest = try loadFixture(named: "image-source-without-base-url")
        XCTAssertNil(manifest.imageBaseURL, "Fixture omits imageBaseURL, so decoding must yield nil")

        let entry = try XCTUnwrap(manifest.dailyMap["2026-01-01"])
        let transport = FakeKigoImageTransport(.succeed(Data([0x01])))
        let source = KigoImageSource(transport: transport)

        let result = await source.image(manifest: manifest, imageId: entry.imageId)
        XCTAssertNil(result, "Nil imageBaseURL must resolve to nil regardless of day")
    }

    // MARK: - AC3: resolving issues exactly one request for the derived URL, returns canned bytes

    func testResolvingImageIssuesExactlyOneRequestAndReturnsCannedBytes() async throws {
        let manifest = try loadFixture(named: "image-source-with-base-url")
        let entry = try XCTUnwrap(manifest.dailyMap["2026-01-01"])
        let cannedBytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let transport = FakeKigoImageTransport(.succeed(cannedBytes))
        let source = KigoImageSource(transport: transport)

        let result = await source.image(manifest: manifest, imageId: entry.imageId)

        XCTAssertEqual(transport.requestedURLs.count, 1, "Must issue exactly one request to the transport")
        XCTAssertEqual(
            transport.requestedURLs.first?.absoluteString,
            "https://images.kigo.example/photos/kigo-01-01.jpg",
            "URL must be formed as imageBaseURL + \"/\" + imageId + \".jpg\""
        )
        XCTAssertEqual(result, cannedBytes, "Must return the transport's canned bytes")
    }

    // MARK: - AC4: nil imageBaseURL means zero transport requests

    func testNilImageBaseURLRecordsZeroTransportRequests() async throws {
        let manifest = try loadFixture(named: "image-source-without-base-url")
        let entry = try XCTUnwrap(manifest.dailyMap["2026-01-01"])
        let transport = FakeKigoImageTransport(.succeed(Data([0x01])))
        let source = KigoImageSource(transport: transport)

        _ = await source.image(manifest: manifest, imageId: entry.imageId)

        XCTAssertTrue(transport.requestedURLs.isEmpty, "Nil imageBaseURL must never reach the transport")
    }

    // MARK: - AC5: transport failure resolves to nil instead of propagating

    func testTransportFailureResolvesToNilInsteadOfThrowing() async throws {
        let manifest = try loadFixture(named: "image-source-with-base-url")
        let entry = try XCTUnwrap(manifest.dailyMap["2026-01-01"])
        let transport = FakeKigoImageTransport(.fail(FakeError.transportFailure))
        let source = KigoImageSource(transport: transport)

        let result = await source.image(manifest: manifest, imageId: entry.imageId)

        XCTAssertNil(result, "Transport failure must resolve to nil, not throw")
    }
}
