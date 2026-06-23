import XCTest
import SwiftUI
@testable import Kigo

// MARK: - FakeRemoteManifestSource

/// In-memory fake that returns a pre-configured manifest or throws a given error.
final class FakeRemoteManifestSource: RemoteManifestSource, @unchecked Sendable {
    enum Behavior {
        case succeed(Manifest)
        case fail(Error)
    }
    let behavior: Behavior

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func fetchLatest() async throws -> Manifest {
        switch behavior {
        case .succeed(let m): return m
        case .fail(let e): throw e
        }
    }
}

// MARK: - CheckpointRemoteManifestSource

/// A fake that suspends in `fetchLatest()` until explicitly resumed.
/// Used to verify non-blocking: store reaches `.loaded` before remote completes.
final class CheckpointRemoteManifestSource: RemoteManifestSource, @unchecked Sendable {
    private let manifest: Manifest
    private var continuation: AsyncStream<Void>.Continuation?
    private let stream: AsyncStream<Void>

    init(manifest: Manifest) {
        self.manifest = manifest
        var cap: AsyncStream<Void>.Continuation?
        self.stream = AsyncStream { cap = $0 }
        self.continuation = cap
    }

    func resume() {
        continuation?.yield(())
        continuation?.finish()
    }

    func fetchLatest() async throws -> Manifest {
        for await _ in stream { break }
        return manifest
    }
}

// MARK: - RemoteManifestUpdateTests

final class RemoteManifestUpdateTests: XCTestCase {

    // MARK: - Helpers

    private func makeManifest(version: Int, kanji: String = "款冬華") -> Manifest {
        let dailyMap: [String: DailyMapEntry] = [
            "2026-01-01": DailyMapEntry(
                kanji: kanji,
                reading: LocalizedText(ja: "ふきのはなさく"),
                description: LocalizedText(ja: "Butterbur blooms."),
                imageId: "img-0101",
                attribution: Attribution(
                    title: LocalizedText(ja: "季語の風景"),
                    credit: LocalizedText(ja: "撮影者不明"),
                    license: LocalizedText(ja: "パブリックドメイン")
                )
            )
        ]
        let ko = [
            Ko(
                kanji: "款冬華",
                reading: LocalizedText(ja: "ふきのはなさく"),
                gloss: "Butterbur blooms",
                sekkiId: "sekki-01",
                dateRange: DateRange(start: "01-01", end: "01-05"),
                description: LocalizedText(ja: "フキノトウが花を咲かせる。")
            )
        ]
        let sekki = [
            Sekki(
                id: "sekki-01",
                kanji: "小寒",
                reading: LocalizedText(ja: "しょうかん"),
                gloss: LocalizedText(ja: "寒さの始まり"),
                description: LocalizedText(ja: "寒さが厳しくなる時期。")
            )
        ]
        return Manifest(schemaVersion: "1.0", version: version, dailyMap: dailyMap, ko: ko, sekki: sekki)
    }

    private enum FakeError: Error { case network, decode }

    // MARK: - Test 1: Newer remote version replaces local

    @MainActor
    func testNewerRemoteVersionReplacesLocal() async throws {
        let localManifest = makeManifest(version: 1, kanji: "款冬華")
        let remoteManifest = makeManifest(version: 2, kanji: "遠雷")

        let source = FakeContentSource(manifest: localManifest)
        let remoteSource = FakeRemoteManifestSource(.succeed(remoteManifest))
        let store = ContentStore(
            source: source,
            dateProvider: FixedDateProvider(date: makeUTCDate(month: 1, day: 1)),
            remoteSource: remoteSource
        )

        await store.waitForLoad()
        await store.waitForRemoteUpdate()

        guard case .loaded(let manifest) = store.state else {
            XCTFail("Expected .loaded, got \(store.state)")
            return
        }
        XCTAssertEqual(manifest.version, 2, "Remote version 2 should replace local version 1")
        XCTAssertEqual(store.todayEntry()?.kanji, "遠雷", "todayEntry() should reflect N+1 content")
    }

    // MARK: - Test 2: Equal remote version leaves local unchanged

    @MainActor
    func testEqualRemoteVersionLeavesLocalUnchanged() async throws {
        let localManifest = makeManifest(version: 5, kanji: "款冬華")
        let remoteManifest = makeManifest(version: 5, kanji: "遠雷")

        let source = FakeContentSource(manifest: localManifest)
        let remoteSource = FakeRemoteManifestSource(.succeed(remoteManifest))
        let store = ContentStore(
            source: source,
            dateProvider: FixedDateProvider(date: makeUTCDate(month: 1, day: 1)),
            remoteSource: remoteSource
        )

        await store.waitForLoad()
        await store.waitForRemoteUpdate()

        guard case .loaded(let manifest) = store.state else {
            XCTFail("Expected .loaded, got \(store.state)")
            return
        }
        XCTAssertEqual(manifest.version, 5, "Version unchanged when remote == local")
        XCTAssertEqual(store.todayEntry()?.kanji, "款冬華", "todayEntry() should keep original content")
    }

    // MARK: - Test 3: Older remote version leaves local unchanged

    @MainActor
    func testOlderRemoteVersionLeavesLocalUnchanged() async throws {
        let localManifest = makeManifest(version: 10, kanji: "款冬華")
        let remoteManifest = makeManifest(version: 7, kanji: "遠雷")

        let source = FakeContentSource(manifest: localManifest)
        let remoteSource = FakeRemoteManifestSource(.succeed(remoteManifest))
        let store = ContentStore(
            source: source,
            dateProvider: FixedDateProvider(date: makeUTCDate(month: 1, day: 1)),
            remoteSource: remoteSource
        )

        await store.waitForLoad()
        await store.waitForRemoteUpdate()

        guard case .loaded(let manifest) = store.state else {
            XCTFail("Expected .loaded, got \(store.state)")
            return
        }
        XCTAssertEqual(manifest.version, 10, "Version unchanged when remote < local")
        XCTAssertEqual(store.todayEntry()?.kanji, "款冬華", "todayEntry() must keep original content when remote is older")
    }

    // MARK: - Test 4: Remote error leaves local unchanged, no propagation

    @MainActor
    func testRemoteErrorLeavesLocalUnchangedAndDoesNotPropagate() async throws {
        let localManifest = makeManifest(version: 3)
        let source = FakeContentSource(manifest: localManifest)
        // Test both error types in sequence
        for error in [FakeError.network as Error, FakeError.decode as Error] {
            let remoteSource = FakeRemoteManifestSource(.fail(error))
            let store = ContentStore(
                source: source,
                dateProvider: FixedDateProvider(date: makeUTCDate(month: 1, day: 1)),
                remoteSource: remoteSource
            )

            await store.waitForLoad()
            await store.waitForRemoteUpdate()

            guard case .loaded(let manifest) = store.state else {
                XCTFail("Expected .loaded after remote error, got \(store.state)")
                return
            }
            XCTAssertEqual(manifest.version, 3, "Error must not change local version (error: \(error))")
        }
    }

    // MARK: - Test 5: Non-blocking — store is .loaded before remote fetch unblocks

    @MainActor
    func testRemoteCheckIsNonBlocking() async throws {
        let localManifest = makeManifest(version: 1)
        let remoteManifest = makeManifest(version: 2)

        let source = FakeContentSource(manifest: localManifest)
        let checkpoint = CheckpointRemoteManifestSource(manifest: remoteManifest)

        let store = ContentStore(
            source: source,
            dateProvider: FixedDateProvider(date: makeUTCDate(month: 1, day: 1)),
            remoteSource: checkpoint
        )

        // Wait for local load only — remote has not been unblocked yet.
        await store.waitForLoad()

        // Assert store is .loaded before remote completes.
        guard case .loaded(let manifest) = store.state else {
            XCTFail("Store must be .loaded before remote update, got \(store.state)")
            checkpoint.resume()
            return
        }
        XCTAssertEqual(manifest.version, 1, "Store must carry local version before remote unblocks")

        // Unblock remote and wait for completion.
        checkpoint.resume()
        await store.waitForRemoteUpdate()

        guard case .loaded(let updatedManifest) = store.state else {
            XCTFail("Expected .loaded after remote update, got \(store.state)")
            return
        }
        XCTAssertEqual(updatedManifest.version, 2, "After unblocking, remote version 2 should replace local")
    }

    // MARK: - Test 6: Screenshot — post-update card renders N+1 content

    @MainActor
    func testScreenshotPostUpdate() async throws {
        let localManifest = makeManifest(version: 1, kanji: "款冬華")
        let remoteManifest = makeManifest(version: 2, kanji: "遠雷")

        let source = FakeContentSource(manifest: localManifest)
        let remoteSource = FakeRemoteManifestSource(.succeed(remoteManifest))
        let store = ContentStore(
            source: source,
            dateProvider: FixedDateProvider(date: makeUTCDate(month: 1, day: 1)),
            remoteSource: remoteSource
        )

        await store.waitForLoad()
        await store.waitForRemoteUpdate()

        guard case .loaded(let manifest) = store.state else {
            XCTFail("Expected .loaded after remote update")
            return
        }

        let entry = store.todayEntry()
        XCTAssertNotNil(entry, "Must have entry for screenshot")

        let kanji = entry?.kanji ?? manifest.dailyMap.values.first?.kanji ?? "—"
        let reading = entry?.reading.ja ?? "—"
        let description = entry?.description.ja ?? "—"

        // Render a card view using ImageRenderer on the main actor.
        let cardView = RemoteUpdateCardView(kanji: kanji, reading: reading, description: description)
        let renderer = ImageRenderer(content: cardView)
        renderer.scale = 2.0

        guard let uiImage = renderer.uiImage else {
            XCTFail("ImageRenderer produced nil image")
            return
        }

        guard let pngData = uiImage.pngData() else {
            XCTFail("Could not convert image to PNG data")
            return
        }

        let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: "public.png")
        attachment.name = "remote-update-card"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertEqual(manifest.version, 2, "Screenshot must show N+1 content (version 2)")
        XCTAssertEqual(kanji, "遠雷", "Screenshot kanji must be from remote N+1 manifest")
    }

    // MARK: - Helpers

    private func makeUTCDate(month: Int, day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = 2026
        comps.month = month
        comps.day = day
        comps.hour = 12
        return cal.date(from: comps)!
    }
}

// MARK: - RemoteUpdateCardView

/// Minimal SwiftUI card for screenshot evidence — shows kanji, reading, description.
private struct RemoteUpdateCardView: View {
    let kanji: String
    let reading: String
    let description: String

    var body: some View {
        VStack(spacing: 16) {
            Text(kanji)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.primary)
            Text(reading)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Text(description)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
        .padding(40)
        .background(Color(white: 0.97))
        .frame(width: 320, height: 260)
    }
}
