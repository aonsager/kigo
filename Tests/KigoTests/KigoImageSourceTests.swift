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

    // MARK: - Temp cache directory fixture

    /// Real on-disk temp directories created by tests in this run, removed in
    /// `tearDown`. Slice #206's cache tests must round-trip through a genuine
    /// filesystem (not a mocked `FileManager`), so each test gets its own unique
    /// subdirectory under `FileManager.default.temporaryDirectory` to keep runs
    /// isolated and deterministic.
    private var cacheDirectoriesToClean: [URL] = []

    private func makeTempCacheDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KigoImageSourceTests-\(UUID().uuidString)", isDirectory: true)
        cacheDirectoriesToClean.append(dir)
        return dir
    }

    override func tearDown() {
        for dir in cacheDirectoriesToClean {
            try? FileManager.default.removeItem(at: dir)
        }
        cacheDirectoriesToClean = []
        super.tearDown()
    }

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
        let source = KigoImageSource(transport: transport, cacheDirectory: makeTempCacheDirectory())

        let result = await source.image(manifest: manifest, imageId: entry.imageId)
        XCTAssertNil(result, "Nil imageBaseURL must resolve to nil regardless of day")
    }

    // MARK: - AC3: resolving issues exactly one request for the derived URL, returns canned bytes

    func testResolvingImageIssuesExactlyOneRequestAndReturnsCannedBytes() async throws {
        let manifest = try loadFixture(named: "image-source-with-base-url")
        let entry = try XCTUnwrap(manifest.dailyMap["2026-01-01"])
        let cannedBytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let transport = FakeKigoImageTransport(.succeed(cannedBytes))
        let source = KigoImageSource(transport: transport, cacheDirectory: makeTempCacheDirectory())

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
        let source = KigoImageSource(transport: transport, cacheDirectory: makeTempCacheDirectory())

        _ = await source.image(manifest: manifest, imageId: entry.imageId)

        XCTAssertTrue(transport.requestedURLs.isEmpty, "Nil imageBaseURL must never reach the transport")
    }

    // MARK: - AC5: transport failure resolves to nil instead of propagating

    func testTransportFailureResolvesToNilInsteadOfThrowing() async throws {
        let manifest = try loadFixture(named: "image-source-with-base-url")
        let entry = try XCTUnwrap(manifest.dailyMap["2026-01-01"])
        let transport = FakeKigoImageTransport(.fail(FakeError.transportFailure))
        let source = KigoImageSource(transport: transport, cacheDirectory: makeTempCacheDirectory())

        let result = await source.image(manifest: manifest, imageId: entry.imageId)

        XCTAssertNil(result, "Transport failure must resolve to nil, not throw")
    }

    // MARK: - Slice #206 AC1-3: cache miss writes to disk; cache hit serves from disk with no re-fetch

    func testCacheMissWritesToDiskThenCacheHitServesFromDiskWithoutRefetch() async throws {
        let manifest = try loadFixture(named: "image-source-with-base-url")
        let entry = try XCTUnwrap(manifest.dailyMap["2026-01-01"])
        let cannedBytes = Data([0xCA, 0xFE, 0xBA, 0xBE])
        let transport = FakeKigoImageTransport(.succeed(cannedBytes))
        let cacheDirectory = makeTempCacheDirectory()
        let source = KigoImageSource(transport: transport, cacheDirectory: cacheDirectory)

        // AC1: first resolution is a cache miss — fetches through the transport.
        let firstResult = await source.image(manifest: manifest, imageId: entry.imageId)
        XCTAssertEqual(firstResult, cannedBytes, "Cache miss must return the freshly fetched bytes")
        XCTAssertEqual(transport.requestedURLs.count, 1, "Cache miss must issue exactly one transport request")

        // AC3: the miss must have written a real file to disk, readable independently
        // of KigoImageSource's in-memory state.
        let cacheFileURL = cacheDirectory.appendingPathComponent("\(entry.imageId).jpg")
        let onDiskBytes = try Data(contentsOf: cacheFileURL)
        XCTAssertEqual(onDiskBytes, cannedBytes, "Cache miss must write the fetched bytes to a file on disk")

        // AC2: a second resolution of the same day is a cache hit — identical bytes,
        // no additional transport request.
        let secondResult = await source.image(manifest: manifest, imageId: entry.imageId)
        XCTAssertEqual(secondResult, cannedBytes, "Cache hit must return identical bytes")
        XCTAssertEqual(transport.requestedURLs.count, 1, "Cache hit must not issue a second transport request")
    }

    // MARK: - Slice #206 AC4: different days get independent, individually recoverable cache files

    func testDifferentDaysProduceDistinctIndependentlyReadableCacheFiles() async throws {
        let manifest = try loadFixture(named: "image-source-with-base-url")
        let firstImageId = "kigo-01-01"
        let secondImageId = "kigo-01-02"
        let firstBytes = Data([0x01, 0x02, 0x03])
        let secondBytes = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let cacheDirectory = makeTempCacheDirectory()

        let firstTransport = FakeKigoImageTransport(.succeed(firstBytes))
        let firstSource = KigoImageSource(transport: firstTransport, cacheDirectory: cacheDirectory)
        let firstResult = await firstSource.image(manifest: manifest, imageId: firstImageId)

        let secondTransport = FakeKigoImageTransport(.succeed(secondBytes))
        let secondSource = KigoImageSource(transport: secondTransport, cacheDirectory: cacheDirectory)
        let secondResult = await secondSource.image(manifest: manifest, imageId: secondImageId)

        XCTAssertEqual(firstResult, firstBytes)
        XCTAssertEqual(secondResult, secondBytes)

        let firstFileURL = cacheDirectory.appendingPathComponent("\(firstImageId).jpg")
        let secondFileURL = cacheDirectory.appendingPathComponent("\(secondImageId).jpg")
        XCTAssertNotEqual(firstFileURL, secondFileURL, "Distinct imageIds must map to distinct cache file paths")

        let firstOnDisk = try Data(contentsOf: firstFileURL)
        let secondOnDisk = try Data(contentsOf: secondFileURL)
        XCTAssertEqual(firstOnDisk, firstBytes, "First day's cache file must hold its own bytes")
        XCTAssertEqual(secondOnDisk, secondBytes, "Second day's cache file must hold its own bytes, independent of the first")
    }
}
