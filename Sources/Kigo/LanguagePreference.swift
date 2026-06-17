import Foundation
import Observation

// MARK: - LanguagePreference

/// The user's preferred UI-chrome language.
///
/// Slice #136: initial type with two cases. Persistence (UserDefaults) and the
/// `KIGO_FAKE_LANGUAGE` resolver are deferred to slice #137.
public enum LanguagePreference: String, Equatable, Sendable {
    case japanese = "ja"
    case english  = "en"
}

// MARK: - ChromeStrings

/// A value type that maps a `LanguagePreference` to concrete UI-chrome label strings.
///
/// Mirrors `OfferDisplay`: a plain struct, no async, injected synchronously at
/// view-construction time. No String catalogs, no `.strings` files — pure Swift
/// types, consistent with how `OfferDisplay` works (ADR 0006).
///
/// Add more string properties (loading, unavailable, etc.) as needed in later
/// slices; this initial set covers the acceptance criteria for slice #136.
public struct ChromeStrings: Equatable, Sendable {

    // MARK: - Well-known string constants (visible to tests via `testable import`)

    /// The Japanese "Restore Purchases" label shown on the Paywall.
    public static let japaneseRestore = "復元"

    /// The English "Restore Purchases" label shown on the Paywall.
    public static let englishRestore  = "Restore Purchases"

    // MARK: - Instance properties

    /// The localised "Restore Purchases" button label.
    public let restore: String

    // MARK: - Init

    public init(_ preference: LanguagePreference) {
        switch preference {
        case .japanese:
            restore = Self.japaneseRestore
        case .english:
            restore = Self.englishRestore
        }
    }
}

// MARK: - LanguageStore protocol

/// A read/write store for the user's language preference.
///
/// Marking it `@Observable` is not possible on a protocol; instead, conformers
/// must be `@Observable` classes so SwiftUI can track mutations reactively.
/// The protocol itself is deliberately minimal — one getter, one setter.
///
/// Both requirements are `@MainActor` so conformers (which are `@Observable
/// @MainActor` classes) satisfy them without crossing actor boundaries in
/// Swift 6 strict-concurrency mode.
@MainActor
public protocol LanguageStore: AnyObject {
    var preference: LanguagePreference { get }
    func set(_ preference: LanguagePreference)
}

// MARK: - InMemoryLanguageStore

/// A fully in-memory, `@Observable` implementation of `LanguageStore`.
///
/// Used by unit tests (inject directly) and as the production store for slice
/// #136 (UserDefaults persistence is deferred to slice #137).
///
/// `InMemoryLanguageStore(rawValue:)` accepts an optional raw string from a
/// persisted/environment source and falls back to `.japanese` for nil or
/// unrecognised values.
@Observable
@MainActor
public final class InMemoryLanguageStore: LanguageStore {

    // MARK: - Observable state

    public private(set) var preference: LanguagePreference

    // MARK: - Init

    /// Creates a store with the default preference (`.japanese`).
    public init() {
        self.preference = .japanese
    }

    /// Creates a store by attempting to decode a raw string value.
    ///
    /// - Parameter rawValue: An optional string (e.g. from UserDefaults or an
    ///   env var). `nil` or any unrecognised value falls back to `.japanese`.
    public init(rawValue: String?) {
        if let raw = rawValue, let decoded = LanguagePreference(rawValue: raw) {
            self.preference = decoded
        } else {
            self.preference = .japanese
        }
    }

    // MARK: - LanguageStore

    public func set(_ preference: LanguagePreference) {
        self.preference = preference
    }
}
