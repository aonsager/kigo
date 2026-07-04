@testable import KigoCore
import XCTest
import UIKit
@testable import Kigo

/// Renders a tiny real, decodable image and encodes it as PNG data. Mirrors the
/// identically-named helper in `KigoImageSourceTests.swift` (#213): composed
/// through `KigoImageSource`, this adapter's "canned bytes" must also survive
/// the decode-validation gate, not just be arbitrary bytes.
private func makeValidImageData() -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
    let image = renderer.image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    guard let data = image.pngData() else {
        fatalError("Failed to encode fixture image as PNG — this is a test-fixture bug, not app behavior")
    }
    return data
}

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
        let cannedBytes = makeValidImageData()

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

    // MARK: - #214 AC2: a non-2xx HTTP response must cause fetchData(from:) to throw directly.

    func testFetchDataThrowsOnNon2xxStatusCode() async throws {
        let url = try XCTUnwrap(URL(string: "https://images.kigo.example/photos/kigo-01-01.jpg"))
        StubURLProtocol.stub { request in
            let response = HTTPURLResponse(url: request.url ?? url, statusCode: 404, httpVersion: nil, headerFields: nil)
            return (Data("not found".utf8), response, nil)
        }

        let transport = URLSessionKigoImageTransport(session: makeStubbedSession())

        do {
            _ = try await transport.fetchData(from: url)
            XCTFail("fetchData(from:) must throw when the HTTP response status code is outside the 2xx range")
        } catch {
            // Expected: any thrown error satisfies the seam's `throws` contract.
        }
    }

    // MARK: - #214 AC3: that same non-2xx stub, composed through KigoImageSource, resolves to nil
    // via the identical fallback path already used for outright transport errors.

    func testAdapterNon2xxResponseComposedWithKigoImageSourceYieldsNil() async throws {
        let manifest = try loadFixture(named: "image-source-with-base-url")
        let entry = try XCTUnwrap(manifest.dailyMap["2026-01-01"])

        StubURLProtocol.stub { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)
            return (Data("internal server error".utf8), response, nil)
        }

        let transport = URLSessionKigoImageTransport(session: makeStubbedSession())
        let source = KigoImageSource(transport: transport, cacheDirectory: makeTempCacheDirectory())

        let result = await source.image(manifest: manifest, imageId: entry.imageId)

        XCTAssertNil(result, "A non-2xx HTTP response must resolve to nil, matching the non-throwing/nil-on-failure contract")
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 1, "Sanity: the stubbed request must actually have been attempted")
    }
}
