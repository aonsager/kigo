import Foundation

// MARK: - DateProvider

/// A seam for injecting "today" into components that need the current date.
///
/// Using a protocol rather than passing `Date` directly allows production code to use
/// `SystemDateProvider` (which calls `Date()`) while tests inject a `FixedDateProvider`
/// for deterministic day-key derivation without mocking the system clock.
///
/// ADR 0006 specifies: "a protocol returning today's date as a `Date`"; this is that protocol.
public protocol DateProvider: Sendable {
    /// Returns today's date.
    var today: Date { get }
}

// MARK: - SystemDateProvider

/// Production `DateProvider` that returns `Date()` — the current system time.
public struct SystemDateProvider: DateProvider {
    public init() {}

    public var today: Date { Date() }
}

// MARK: - FixedDateProvider

/// Test-only `DateProvider` that always returns a fixed `Date`.
///
/// Inject this in unit tests to produce a deterministic day-key without
/// depending on when the tests run.
public struct FixedDateProvider: DateProvider {
    private let date: Date

    public init(date: Date) {
        self.date = date
    }

    public var today: Date { date }
}
