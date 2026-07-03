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

// MARK: - FakeSizedKigoImageTransport (Slice #207: eviction tests)

/// Fake transport for eviction tests: returns a fixed-size, URL-derived byte
/// buffer for every request (so cache-footprint math is exact) and records
/// every request, so a re-fetch after eviction is provable (request count for
/// a given URL going from 1 to 2).
final class FakeSizedKigoImageTransport: KigoImageTransport, @unchecked Sendable {
    private let byteCount: Int
    private(set) var requestedURLs: [URL] = []

    init(byteCount: Int) {
        self.byteCount = byteCount
    }

    func fetchData(from url: URL) async throws -> Data {
        requestedURLs.append(url)
        let fillByte = UInt8(truncatingIfNeeded: url.absoluteString.hashValue)
        return Data(repeating: fillByte, count: byteCount)
    }

    func requestCount(for url: URL) -> Int {
        requestedURLs.filter { $0 == url }.count
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

    // MARK: - Slice #207 AC1: exceeding the configured cap evicts the least-recently-used file

    /// Resolves three distinct days' images against a cap sized to fit two
    /// entries but not three. Reads the temp cache directory's *actual*
    /// contents from disk afterward (not KigoImageSource's in-memory state) to
    /// confirm the oldest (least-recently-used) file was deleted while the two
    /// more-recently-written files survive.
    func testExceedingCacheCapEvictsLeastRecentlyUsedFile() async throws {
        let manifest = try loadFixture(named: "image-source-with-base-url")
        let byteCount = 100
        let transport = FakeSizedKigoImageTransport(byteCount: byteCount)
        let cacheDirectory = makeTempCacheDirectory()
        let source = KigoImageSource(
            transport: transport,
            cacheDirectory: cacheDirectory,
            maxCacheBytes: byteCount * 2 + 50
        )

        _ = await source.image(manifest: manifest, imageId: "kigo-day-1")
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = await source.image(manifest: manifest, imageId: "kigo-day-2")
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = await source.image(manifest: manifest, imageId: "kigo-day-3")

        let file1 = cacheDirectory.appendingPathComponent("kigo-day-1.jpg")
        let file2 = cacheDirectory.appendingPathComponent("kigo-day-2.jpg")
        let file3 = cacheDirectory.appendingPathComponent("kigo-day-3.jpg")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file1.path),
            "Least-recently-used cache file must be removed from disk once the cap is exceeded"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: file2.path),
            "More-recently-used cache file must survive eviction"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: file3.path),
            "Most-recently-written cache file must survive eviction"
        )
    }

    // MARK: - Slice #207 AC2: touching (re-resolving) a cached entry protects it from eviction

    /// day-1 is written first, then day-2. day-1 is then re-resolved (a cache
    /// hit, which must count as a touch), then day-3 is written, tripping
    /// eviction. Only one entry needs evicting to get back under the cap: since
    /// day-1 was touched most recently, day-2 (older, untouched) must be the one
    /// removed — proving the LRU order is driven by access recency, not just
    /// write order.
    func testTouchedEntrySurvivesEvictionOverOlderUntouchedEntry() async throws {
        let manifest = try loadFixture(named: "image-source-with-base-url")
        let byteCount = 100
        let transport = FakeSizedKigoImageTransport(byteCount: byteCount)
        let cacheDirectory = makeTempCacheDirectory()
        let source = KigoImageSource(
            transport: transport,
            cacheDirectory: cacheDirectory,
            maxCacheBytes: byteCount * 2 + 50
        )

        _ = await source.image(manifest: manifest, imageId: "kigo-day-1")
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = await source.image(manifest: manifest, imageId: "kigo-day-2")
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = await source.image(manifest: manifest, imageId: "kigo-day-1") // touch: cache hit, now MRU
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = await source.image(manifest: manifest, imageId: "kigo-day-3") // trips eviction

        let file1 = cacheDirectory.appendingPathComponent("kigo-day-1.jpg")
        let file2 = cacheDirectory.appendingPathComponent("kigo-day-2.jpg")
        let file3 = cacheDirectory.appendingPathComponent("kigo-day-3.jpg")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: file1.path),
            "Touched entry must survive eviction as most-recently-used"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file2.path),
            "Older, untouched entry must be the one evicted"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: file3.path),
            "Most-recently-written cache file must survive eviction"
        )
    }

    // MARK: - Slice #207 AC3: resolving an evicted day re-fetches through the transport

    /// After day-1's cache file is evicted (by writing day-2 then day-3 against
    /// a two-entry cap), re-resolving day-1 must not silently return stale or
    /// missing data — it must issue a fresh transport request and get real
    /// bytes back, proving the eviction was a genuine cache miss and not a
    /// dead end.
    func testResolvingEvictedEntryIssuesFreshTransportRequest() async throws {
        let manifest = try loadFixture(named: "image-source-with-base-url")
        let base = try XCTUnwrap(manifest.imageBaseURL)
        let byteCount = 100
        let transport = FakeSizedKigoImageTransport(byteCount: byteCount)
        let cacheDirectory = makeTempCacheDirectory()
        let source = KigoImageSource(
            transport: transport,
            cacheDirectory: cacheDirectory,
            maxCacheBytes: byteCount * 2 + 50
        )
        let day1URL = try XCTUnwrap(URL(string: "\(base)/kigo-day-1.jpg"))

        _ = await source.image(manifest: manifest, imageId: "kigo-day-1")
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = await source.image(manifest: manifest, imageId: "kigo-day-2")
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = await source.image(manifest: manifest, imageId: "kigo-day-3") // evicts day-1

        let file1 = cacheDirectory.appendingPathComponent("kigo-day-1.jpg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1.path), "Sanity: day-1 must have been evicted")
        XCTAssertEqual(transport.requestCount(for: day1URL), 1, "Sanity: day-1 fetched exactly once so far")

        let refetched = await source.image(manifest: manifest, imageId: "kigo-day-1")

        XCTAssertEqual(
            transport.requestCount(for: day1URL), 2,
            "Resolving an evicted entry must issue a fresh transport request"
        )
        XCTAssertNotNil(refetched, "Re-fetch after eviction must return data, not nil")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: file1.path),
            "Re-fetch after eviction must repopulate the on-disk cache"
        )
    }

    // MARK: - Slice #207 AC4: repeated evictions keep the on-disk footprint at or under the cap

    /// Resolves ten distinct days against a cap sized for two entries, forcing
    /// several eviction passes in a row. Afterward, reads the temp cache
    /// directory's real file sizes from disk (not in-memory bookkeeping) and
    /// sums them, confirming the invariant holds after repeated evictions, not
    /// just after a single one.
    func testCacheFootprintStaysAtOrUnderCapAfterRepeatedEvictions() async throws {
        let manifest = try loadFixture(named: "image-source-with-base-url")
        let byteCount = 100
        let cap = byteCount * 2 + 50
        let transport = FakeSizedKigoImageTransport(byteCount: byteCount)
        let cacheDirectory = makeTempCacheDirectory()
        let source = KigoImageSource(transport: transport, cacheDirectory: cacheDirectory, maxCacheBytes: cap)

        for day in 1...10 {
            _ = await source.image(manifest: manifest, imageId: "kigo-day-\(day)")
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )
        let totalSize = try contents.reduce(0) { total, url -> Int in
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            return total + (values.fileSize ?? 0)
        }

        XCTAssertLessThanOrEqual(
            totalSize, cap,
            "On-disk cache footprint must stay at or under the configured cap after repeated evictions"
        )
    }
}
