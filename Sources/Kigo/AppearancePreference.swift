import SwiftUI
import Observation

// MARK: - AppearancePreference

/// The user's preferred app appearance (System / Light / Dark).
///
/// Slice D (issue #161): mirrors `LanguagePreference`. The `system` case defers
/// to the OS appearance; `light`/`dark` force a specific `ColorScheme`.
public enum AppearancePreference: String, Equatable, Sendable, CaseIterable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    /// The `ColorScheme` to apply via `.preferredColorScheme(_:)`.
    ///
    /// `.system` maps to `nil` so the OS decides; `.light`/`.dark` force the scheme.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - AppearanceStore protocol

/// A read/write store for the user's appearance preference.
///
/// Mirrors `LanguageStore`: conformers are `@Observable @MainActor` classes so
/// SwiftUI can track mutations reactively. Both requirements are `@MainActor`.
@MainActor
public protocol AppearanceStore: AnyObject {
    var preference: AppearancePreference { get }
    func set(_ preference: AppearancePreference)
}

// MARK: - InMemoryAppearanceStore

/// A fully in-memory, `@Observable` implementation of `AppearanceStore`.
///
/// Used by unit tests (inject directly). Mirrors `InMemoryLanguageStore`:
/// `init(rawValue:)` accepts an optional raw string and falls back to `.system`
/// for nil or unrecognised values.
@Observable
@MainActor
public final class InMemoryAppearanceStore: AppearanceStore {

    public private(set) var preference: AppearancePreference

    /// Creates a store with the default preference (`.system`).
    public init() {
        self.preference = .system
    }

    /// Creates a store by attempting to decode a raw string value.
    ///
    /// - Parameter rawValue: An optional string (e.g. from UserDefaults or an
    ///   env var). `nil` or any unrecognised value falls back to `.system`.
    public init(rawValue: String?) {
        if let raw = rawValue, let decoded = AppearancePreference(rawValue: raw) {
            self.preference = decoded
        } else {
            self.preference = .system
        }
    }

    public func set(_ preference: AppearancePreference) {
        self.preference = preference
    }
}
