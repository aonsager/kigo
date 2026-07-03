import XCTest
@testable import Kigo

// MARK: - StubURLProtocol

/// Offline `URLProtocol` stub registered on the adapter's own `URLSession`
/// (via `URLSessionConfiguration.protocolClasses`) so `KigoImageSourceAdapterTests`
/// exercises the real `URLSession`/`URLRequest` code path with zero real network
/// access. Records every intercepted request's URL and replays a pre-configured
/// canned response or transport-level error.
///
/// State is static (mirroring `URLProtocol`'s own class-side dispatch model, since
/// `URLSession` instantiates protocol instances itself — tests can't inject an
/// instance directly) and guarded by a lock, since `startLoading()` runs off the
/// calling thread.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _requestedURLs: [URL] = []
    nonisolated(unsafe) private static var _handler: ((URLRequest) -> (Data?, HTTPURLResponse?, Error?))?

    static var requestedURLs: [URL] {
        lock.lock(); defer { lock.unlock() }
        return _requestedURLs
    }

    /// Resets recorded requests and the response handler. Call in `setUp()` so
    /// tests don't leak state through this shared static store.
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _requestedURLs = []
        _handler = nil
    }

    static func stub(_ handler: @escaping (URLRequest) -> (Data?, HTTPURLResponse?, Error?)) {
        lock.lock(); defer { lock.unlock() }
        _handler = handler
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        if let url = request.url { Self._requestedURLs.append(url) }
        let handler = Self._handler
        Self.lock.unlock()

        guard let handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        let (data, response, error) = handler(request)
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let httpResponse = response ?? HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        if let data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - KigoImageSourceAdapterTests

/// Slice #208 (C25/C26, ADR 0022): the production `URLSessionKigoImageTransport`
/// adapter, verified offline against a stubbed `URLProtocol` registered on the
/// adapter's own `URLSession` — no real networking, but the real `URLSession`/
/// `URLRequest` code path runs. Not wired into `KigoImageSource`'s production
/// configuration, `TodayView`, or any launch-env resolver in this slice — see
/// slice scope notes on `URLSessionKigoImageTransport`.
final class KigoImageSourceAdapterTests: XCTestCase {

    private enum StubError: Error { case simulatedTransportFailure }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    // MARK: - Temp cache directory fixture (mirrors KigoImageSourceTests)

    private var cacheDirectoriesToClean: [URL] = []

    private func makeTempCacheDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KigoImageSourceAdapterTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - Stubbed offline URLSession fixture

    /// A `URLSession` whose configuration registers only `StubURLProtocol`, so
    /// every request the adapter issues through it is intercepted offline.
    private func makeStubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func loadFixture(named name: String) throws -> Manifest {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json"),
            "\(name).json must be bundled into KigoTests"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    // MARK: - AC1+2: composed through KigoImageSource, adapter issues a request to the
    // exact derived URL and returns decoded bytes without throwing on success.

    func testAdapterIssuesRequestToDerivedURLAndReturnsDecodedBytesOnSuccess() async throws {
        let manifest = try loadFixture(named: "image-source-with-base-url")
        let entry = try XCTUnwrap(manifest.dailyMap["2026-01-01"])
        let cannedBytes = Data([0xDE, 0xAD, 0xBE, 0xEF])

        StubURLProtocol.stub { _ in (cannedBytes, nil, nil) }

        let transport = URLSessionKigoImageTransport(session: makeStubbedSession())
        let source = KigoImageSource(transport: transport, cacheDirectory: makeTempCacheDirectory())

        let result = await source.image(manifest: manifest, imageId: entry.imageId)

        XCTAssertEqual(
            StubURLProtocol.requestedURLs.map(\.absoluteString),
            ["https://images.kigo.example/photos/kigo-01-01.jpg"],
            "Adapter must issue a request to the exact derived URL (imageBaseURL + \"/\" + imageId + \".jpg\")"
        )
        XCTAssertEqual(result, cannedBytes, "Adapter must return the decoded image bytes without throwing")
    }

    // MARK: - AC3: a transport-level failure, composed with KigoImageSource, yields nil overall.

    func testAdapterFailureComposedWithKigoImageSourceYieldsNil() async throws {
        let manifest = try loadFixture(named: "image-source-with-base-url")
        let entry = try XCTUnwrap(manifest.dailyMap["2026-01-01"])

        StubURLProtocol.stub { _ in (nil, nil, StubError.simulatedTransportFailure) }

        let transport = URLSessionKigoImageTransport(session: makeStubbedSession())
        let source = KigoImageSource(transport: transport, cacheDirectory: makeTempCacheDirectory())

        let result = await source.image(manifest: manifest, imageId: entry.imageId)

        XCTAssertNil(result, "A transport-level failure must resolve to nil, matching the non-throwing/nil-on-failure contract")
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 1, "Sanity: the stubbed request must actually have been attempted")
    }
}
