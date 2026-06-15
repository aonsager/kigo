import Foundation

// MARK: - PaywallConfig

/// Static configuration constants for the Paywall screen.
///
/// **Legal URLs (placeholder):** The Terms of Use and Privacy Policy URLs below
/// are placeholder `https` constants — the legal documents themselves and their
/// hosting are out of scope for this milestone (ADR 0013 / J4). Their presence
/// and well-formedness are gated by `PaywallConfigTests`; actual document
/// authoring and hosting occur in a later milestone.
public enum PaywallConfig {

    /// Placeholder Terms of Use URL.
    ///
    /// Replace with the canonical hosted URL once legal documents are published.
    /// Must remain `https` and have a non-empty host — these invariants are gated
    /// by `KigoTests/PaywallConfigTests/testTermsURLIsHttpsWithNonEmptyHost`.
    public static let termsOfUseURL: URL = URL(string: "https://example.com/terms")!

    /// Placeholder Privacy Policy URL.
    ///
    /// Replace with the canonical hosted URL once legal documents are published.
    /// Must remain `https` and have a non-empty host — these invariants are gated
    /// by `KigoTests/PaywallConfigTests/testPrivacyURLIsHttpsWithNonEmptyHost`.
    public static let privacyPolicyURL: URL = URL(string: "https://example.com/privacy")!
}
