import XCTest
@testable import Kigo

// MARK: - PaywallConfigTests

/// Headless unit tests for `PaywallConfig` — verifies that the Terms of Use and
/// Privacy Policy URL constants that the Paywall links to are non-nil, use the
/// `https` scheme, and have a non-empty host.
///
/// Real legal copy and hosting are out of scope (ADR 0013 / J4). These are
/// placeholder `https` URL constants whose well-formedness is gated here; actual
/// document authoring and hosting occur in a later milestone.
///
/// No StoreKit, no launch-environment, no app launch — pure constant inspection.
final class PaywallConfigTests: XCTestCase {

    // MARK: - AC1: Terms of Use URL is https and has a non-empty host

    /// The Terms of Use URL constant must be a valid `URL` with scheme `https`
    /// and a non-empty host. This ensures the link renders as a tappable element
    /// rather than crashing or no-oping on the user's device.
    func testTermsURLIsHttpsWithNonEmptyHost() {
        let url = PaywallConfig.termsOfUseURL
        XCTAssertNotNil(url, "termsOfUseURL must not be nil")
        XCTAssertEqual(url.scheme, "https",
                       "termsOfUseURL must use the https scheme; got: '\(url.scheme ?? "nil")'")
        let host = url.host()
        XCTAssertNotNil(host, "termsOfUseURL must have a host component")
        XCTAssertFalse((host ?? "").isEmpty,
                       "termsOfUseURL host must be non-empty")
    }

    // MARK: - AC2: Privacy Policy URL is https and has a non-empty host

    /// The Privacy Policy URL constant must be a valid `URL` with scheme `https`
    /// and a non-empty host. Same rationale as the Terms URL.
    func testPrivacyURLIsHttpsWithNonEmptyHost() {
        let url = PaywallConfig.privacyPolicyURL
        XCTAssertNotNil(url, "privacyPolicyURL must not be nil")
        XCTAssertEqual(url.scheme, "https",
                       "privacyPolicyURL must use the https scheme; got: '\(url.scheme ?? "nil")'")
        let host = url.host()
        XCTAssertNotNil(host, "privacyPolicyURL must have a host component")
        XCTAssertFalse((host ?? "").isEmpty,
                       "privacyPolicyURL host must be non-empty")
    }
}
