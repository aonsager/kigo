import XCTest
@testable import Kigo

// MARK: - LaunchDateProviderTests

/// Unit tests for the `launchDateProvider(environment:)` factory (slice #56).
///
/// The factory parses the `KIGO_FAKE_DATE=YYYY-MM-DD` launch-environment variable
/// and returns a `FixedDateProvider` for a valid value, or a `SystemDateProvider`
/// when the key is absent or malformed. The parsed date is interpreted in the same
/// UTC calendar used for day-key derivation (acceptance criterion #4).
///
/// These tests drive the public factory without launching the app — pure unit tests.
final class LaunchDateProviderTests: XCTestCase {

    // MARK: - AC3 / AC4: Valid parse returns FixedDateProvider pinned to UTC

    /// A well-formed `KIGO_FAKE_DATE=2026-06-12` must produce a provider whose
    /// `today` value resolves to day-key "06-12" via the shared UTC calendar —
    /// proving acceptance criteria #3 (valid branch covered) and #4 (UTC calendar used).
    func testValidDateEnvironmentVariableProducesFixedProvider() {
        let env = ["KIGO_FAKE_DATE": "2026-06-12"]
        let provider = launchDateProvider(environment: env)

        let key = DayKey.make(from: provider.today)
        XCTAssertEqual(
            key, "06-12",
            "A valid KIGO_FAKE_DATE=2026-06-12 must produce a provider whose today resolves to day-key '06-12' via UTC"
        )
    }

    /// Parsed date must use the UTC calendar: a YYYY-MM-DD string always maps to
    /// the same MM-DD key regardless of the runner's local time zone.
    func testParsedDateUsesUTCCalendar() {
        let env = ["KIGO_FAKE_DATE": "2026-01-15"]
        let provider = launchDateProvider(environment: env)

        // DayKey.make uses the same UTC calendar — key must be "01-15"
        let key = DayKey.make(from: provider.today)
        XCTAssertEqual(
            key, "01-15",
            "Parsed KIGO_FAKE_DATE must resolve via UTC calendar — got key: '\(key ?? "nil")'"
        )
    }

    // MARK: - AC3: Absent variable falls back to SystemDateProvider

    /// When `KIGO_FAKE_DATE` is not in the environment, the factory must return
    /// a provider that behaves like `SystemDateProvider` (day-key is today's date).
    /// We verify by checking the day-key matches what `DayKey.make(from: Date())` yields
    /// at the instant of the call — they must agree.
    func testAbsentEnvironmentVariableProducesSystemProvider() {
        let provider = launchDateProvider(environment: [:])

        // Both calls happen within the same second; day-key must match.
        let providerKey = DayKey.make(from: provider.today)
        let systemKey = DayKey.make(from: Date())
        XCTAssertEqual(
            providerKey, systemKey,
            "Absent KIGO_FAKE_DATE must fall back to system date — provider key '\(providerKey ?? "nil")' vs system key '\(systemKey ?? "nil")'"
        )
    }

    // MARK: - AC3: Malformed variable falls back to SystemDateProvider

    /// A malformed `KIGO_FAKE_DATE` (wrong format) must fall back to the system date
    /// without crashing — acceptance criterion #3 (malformed branch covered) and
    /// criterion #2 (no crash on malformed input).
    func testMalformedEnvironmentVariableProducesSystemProvider() {
        let malformedCases = [
            "not-a-date",
            "06/12/2026",
            "2026-13-01",   // month 13 — invalid
            "2026-00-12",   // month 0 — invalid
            "",
            "2026-06",      // missing day component
        ]

        for malformed in malformedCases {
            let provider = launchDateProvider(environment: ["KIGO_FAKE_DATE": malformed])

            // Must not crash and must return a key matching today's system date.
            let providerKey = DayKey.make(from: provider.today)
            let systemKey = DayKey.make(from: Date())
            XCTAssertEqual(
                providerKey, systemKey,
                "Malformed KIGO_FAKE_DATE '\(malformed)' must fall back to system date — got key '\(providerKey ?? "nil")' vs '\(systemKey ?? "nil")'"
            )
        }
    }

    /// A `KIGO_FAKE_DATE` with leading/trailing whitespace must be handled gracefully.
    /// Depending on implementation it may either parse or fall back; either way it must not crash.
    func testWhitespaceAroundDateDoesNotCrash() {
        let provider = launchDateProvider(environment: ["KIGO_FAKE_DATE": " 2026-06-12 "])
        // Just verify it returns a non-nil key (does not crash).
        let key = DayKey.make(from: provider.today)
        XCTAssertNotNil(key, "Provider must always return a date that produces a non-nil day-key")
    }
}
