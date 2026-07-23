import Foundation
import Observation

// MARK: - LanguagePreference

/// The user's preferred UI-chrome language.
///
/// Slice #136: initial type with two cases. Persistence (UserDefaults) and the
/// `KIGO_FAKE_LANGUAGE` resolver are deferred to slice #137.
public enum LanguagePreference: String, Equatable, Sendable, CaseIterable {
    case japanese = "ja"
    case english  = "en"

    /// The language's own endonym — the label a language uses for *itself*.
    ///
    /// Deliberately **not** localised: the language picker always presents each
    /// option in its respective language ("日本語", "English") regardless of the
    /// active UI language, matching the platform convention for language pickers.
    /// This is the single carve-out from the "all UI chrome is localised" rule —
    /// see the goal note and `ChromeStrings`.
    public var selfName: String {
        switch self {
        case .japanese: return "日本語"
        case .english:  return "English"
        }
    }
}

// MARK: - ChromeStrings

/// A value type that maps a `LanguagePreference` to every concrete UI-chrome
/// label string in the app.
///
/// Mirrors `OfferDisplay`: a plain struct, no async, injected synchronously at
/// view-construction time. No String catalogs, no `.strings` files — pure Swift
/// types, consistent with how `OfferDisplay` works (ADR 0006). Views read the
/// active `LanguagePreference` from `@Environment(\.language)` and build a
/// `ChromeStrings` from it, so every label updates live when the user toggles
/// language in Settings.
///
/// **Scope.** This carries *chrome* — the text a user reads to operate the app
/// (labels, buttons, links, messages, VoiceOver labels) plus the seasonal
/// structure labels (春夏秋冬 / 候 / 節気). It does **not** carry data-driven
/// *content* — the kigo kanji, readings, descriptions, glosses and attribution
/// all localise via `LocalizedText.localized(for:)` from the manifest.
///
/// The language-picker option labels are the one deliberate exception: they use
/// `LanguagePreference.selfName` ("日本語" / "English"), never these strings.
public struct ChromeStrings: Equatable, Sendable {

    // MARK: - Well-known string constants (visible to tests via `testable import`)

    /// The Japanese "Restore Purchases" label shown on the Paywall.
    public static let japaneseRestore = "復元"

    /// The English "Restore Purchases" label shown on the Paywall.
    public static let englishRestore  = "Restore Purchases"

    // MARK: - Settings section titles

    /// The Settings sheet title (設定 / Settings).
    public let settingsTitle: String
    /// The "Language" section label and the language picker's accessibility title.
    public let languageSectionLabel: String
    /// The "Appearance" section label and the appearance picker's accessibility title.
    public let appearanceSectionLabel: String
    /// The "Reminder" section label above the daily-reminder toggle.
    public let reminderSectionLabel: String
    /// The "Daily reminder" toggle label (Slice #219, ADR 0019).
    public let dailyReminderToggleLabel: String
    /// The "Subscription" section label.
    public let subscriptionSectionLabel: String

    // MARK: - Appearance picker options (localised — NOT the language-picker exception)

    public let appearanceSystem: String
    public let appearanceLight: String
    public let appearanceDark: String

    // MARK: - Paywall / subscription

    /// The localised "Restore Purchases" button label.
    public let restore: String
    /// The "Subscription active" status label.
    public let subscriptionActive: String
    /// The "Subscribe" buy-button label.
    public let subscribe: String
    /// The paywall "Understanding" section header (the meaning-unlock product name).
    public let understandingLabel: String
    /// The single honest paywall benefit sentence.
    public let understandingBenefit: String
    /// The Settings subscription note shown to Basic users.
    public let understandingSettingsNote: String
    /// The "Subscribe to read the meaning." caption on the meaning preview.
    public let meaningPreviewSubscribe: String
    /// The "Terms of Use" legal link label.
    public let termsOfUse: String
    /// The "Privacy Policy" legal link label.
    public let privacyPolicy: String

    // MARK: - Today upsell (Basic tier)

    /// The upsell title on the Today screen bottom band.
    public let upsellTitle: String
    /// The upsell body sentence on the Today screen bottom band.
    public let upsellBody: String

    // MARK: - Content placeholders

    /// The loading placeholder caption (読み込み中… / Loading…).
    public let loading: String
    /// The content-unavailable placeholder message.
    public let contentUnavailable: String

    // MARK: - Seasonal structure labels (year-timeline axis + almanac headers)

    public let seasonSpring: String
    public let seasonSummer: String
    public let seasonAutumn: String
    public let seasonWinter: String
    /// The almanac 候 (Kō / microseason) section header.
    public let almanacKoHeader: String
    /// The almanac 節気 (Sekki / solar term) section header.
    public let almanacSekkiHeader: String

    // MARK: - VoiceOver / accessibility labels

    public let a11yLoading: String
    public let a11yContentUnavailable: String
    public let a11yUnlockMeaning: String
    public let a11yDismiss: String
    public let a11yBackgroundImage: String

    // MARK: - Interpolated accessibility labels

    /// VoiceOver label for the tappable year timeline (`microseason.timeline`).
    public func a11yMicroseasonTimeline(ko: Int, of total: Int) -> String {
        switch preference {
        case .japanese: return "候のタイムライン：\(total)候中\(ko)候目"
        case .english:  return "Microseason timeline: Kō \(ko) of \(total)"
        }
    }

    /// VoiceOver label for the day-within-Kō gauge in the almanac.
    public func a11yDayInMicroseason(day: Int, of total: Int) -> String {
        switch preference {
        case .japanese: return "この候の\(total)日中\(day)日目"
        case .english:  return "Day \(day) of \(total) in this microseason"
        }
    }

    /// VoiceOver label for the Kō-within-Sekki gauge in the almanac.
    public func a11yKoInSolarTerm(ko: Int, of total: Int) -> String {
        switch preference {
        case .japanese: return "この節気の\(total)候中\(ko)候目"
        case .english:  return "Kō \(ko) of \(total) in this solar term"
        }
    }

    // MARK: - Stored preference (for the interpolated accessors)

    /// The preference this instance was built from — retained so the interpolated
    /// accessibility accessors can switch on it.
    public let preference: LanguagePreference

    // MARK: - Init

    public init(_ preference: LanguagePreference) {
        self.preference = preference
        switch preference {
        case .japanese:
            restore                   = Self.japaneseRestore
            settingsTitle             = "設定"
            languageSectionLabel      = "言語"
            appearanceSectionLabel    = "表示"
            reminderSectionLabel      = "リマインダー"
            dailyReminderToggleLabel  = "毎日のリマインダー"
            subscriptionSectionLabel  = "購読"
            appearanceSystem          = "システム"
            appearanceLight           = "ライト"
            appearanceDark            = "ダーク"
            subscriptionActive        = "購読中"
            subscribe                 = "購読する"
            understandingLabel        = "意味"
            understandingBenefit      = "一日ごとの季語、その候、そして巡る一年の意味を読み解く。"
            understandingSettingsNote = "「意味」は今日の季語からひらく、買い切りの機能です。"
            meaningPreviewSubscribe   = "購読して意味を読む。"
            termsOfUse                = "利用規約"
            privacyPolicy             = "プライバシーポリシー"
            upsellTitle               = "意味をひらく"
            upsellBody                = "今日の季語、その候、そして巡る一年の意味をひらく。"
            loading                   = "読み込み中…"
            contentUnavailable        = "コンテンツは現在利用できません"
            seasonSpring              = "春"
            seasonSummer              = "夏"
            seasonAutumn              = "秋"
            seasonWinter              = "冬"
            almanacKoHeader           = "候"
            almanacSekkiHeader        = "節気"
            a11yLoading               = "読み込み中"
            a11yContentUnavailable    = "コンテンツは利用できません"
            a11yUnlockMeaning         = "意味をひらく"
            a11yDismiss               = "閉じる"
            a11yBackgroundImage       = "季語の背景画像"
        case .english:
            restore                   = Self.englishRestore
            settingsTitle             = "Settings"
            languageSectionLabel      = "Language"
            appearanceSectionLabel    = "Appearance"
            reminderSectionLabel      = "Reminder"
            dailyReminderToggleLabel  = "Daily reminder"
            subscriptionSectionLabel  = "Subscription"
            appearanceSystem          = "System"
            appearanceLight           = "Light"
            appearanceDark            = "Dark"
            subscriptionActive        = "Subscription active"
            subscribe                 = "Subscribe"
            understandingLabel        = "Understanding"
            understandingBenefit      = "Read the meaning behind each day’s kigo, its microseason, and the year’s turning."
            understandingSettingsNote = "Understanding is a one-time unlock, offered from today’s kigo."
            meaningPreviewSubscribe   = "Subscribe to read the meaning."
            termsOfUse                = "Terms of Use"
            privacyPolicy             = "Privacy Policy"
            upsellTitle               = "Open the meaning"
            upsellBody                = "Unlock the meaning behind today’s kigo, its microseason, and the year’s turning."
            loading                   = "Loading…"
            contentUnavailable        = "Content is currently unavailable"
            seasonSpring              = "Spring"
            seasonSummer              = "Summer"
            seasonAutumn              = "Autumn"
            seasonWinter              = "Winter"
            almanacKoHeader           = "Microseason"
            almanacSekkiHeader        = "Solar term"
            a11yLoading               = "Loading content"
            a11yContentUnavailable    = "Content unavailable"
            a11yUnlockMeaning         = "Unlock the meaning"
            a11yDismiss               = "Dismiss"
            a11yBackgroundImage       = "Kigo background image"
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
