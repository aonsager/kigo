import XCTest
@testable import Kigo

// MARK: - LaunchEntitlementProviderTests

/// Unit tests for the `fakeEntitlementSource(environment:)` resolver (slice #85).
///
/// This factory reads the `KIGO_FAKE_ENTITLEMENT` launch-environment variable and
/// returns an in-memory fake `EntitlementTransactionSource`:
/// - `=active`   → a source reporting `widgetMonthlyProductID` (entitled).
/// - `=inactive` → a source reporting an empty set (not entitled).
/// - absent      → `nil` (production / StoreKit-backed path taken by caller).
///
/// The absent branch is verified by asserting the helper returns nil — so the unit
/// test never invokes `isEntitlementActive()` on a production `EntitlementProvider`,
/// never touches `Transaction.currentEntitlements`, `SKTestSession`, or `storekitd`.
/// That avoids the known hang on the `xcodebuild` CLI path (ADR 0009 / CLAUDE.md).
///
/// AC3: `=active` → provider derived from source is active.
/// AC4: `=inactive` → provider derived from source is inactive.
///       absent      → `fakeEntitlementSource` returns nil (production path taken).
final class LaunchEntitlementProviderTests: XCTestCase {

    // MARK: - AC3: active branch → provider is active

    /// `KIGO_FAKE_ENTITLEMENT=active` must produce a fake source that makes the
    /// derived `EntitlementProvider` report active entitlement.
    func testActiveEnvironmentVariableProducesActiveProvider() async {
        let env = ["KIGO_FAKE_ENTITLEMENT": "active"]
        guard let source = fakeEntitlementSource(environment: env) else {
            XCTFail("fakeEntitlementSource must return non-nil for KIGO_FAKE_ENTITLEMENT=active")
            return
        }
        let provider = EntitlementProvider(source: source)
        let isActive = await provider.isEntitlementActive()
        XCTAssertTrue(
            isActive,
            "KIGO_FAKE_ENTITLEMENT=active must yield a provider whose isEntitlementActive() is true"
        )
    }

    // MARK: - AC3: inactive branch → provider is inactive

    /// `KIGO_FAKE_ENTITLEMENT=inactive` must produce a fake source that makes the
    /// derived `EntitlementProvider` report inactive entitlement.
    func testInactiveEnvironmentVariableProducesInactiveProvider() async {
        let env = ["KIGO_FAKE_ENTITLEMENT": "inactive"]
        guard let source = fakeEntitlementSource(environment: env) else {
            XCTFail("fakeEntitlementSource must return non-nil for KIGO_FAKE_ENTITLEMENT=inactive")
            return
        }
        let provider = EntitlementProvider(source: source)
        let isActive = await provider.isEntitlementActive()
        XCTAssertFalse(
            isActive,
            "KIGO_FAKE_ENTITLEMENT=inactive must yield a provider whose isEntitlementActive() is false"
        )
    }

    // MARK: - AC4: absent → nil (production path, no StoreKit call)

    /// When `KIGO_FAKE_ENTITLEMENT` is absent from the environment, `fakeEntitlementSource`
    /// must return `nil`. The unit test only asserts `nil` — it never calls into the
    /// production `EntitlementProvider`, so no real StoreKit / `storekitd` / `SKTestSession`
    /// interaction occurs. The production default-init path is correct by inspection
    /// (it wraps `StoreKitTransactionSource`, the thin pass-through in ADR 0009).
    func testAbsentEnvironmentVariableReturnsNil() {
        let source = fakeEntitlementSource(environment: [:])
        XCTAssertNil(
            source,
            "fakeEntitlementSource must return nil when KIGO_FAKE_ENTITLEMENT is absent, " +
            "indicating the production (StoreKit-backed) path should be used"
        )
    }

    // MARK: - Robustness: unrecognised value returns nil

    /// An unrecognised value (neither "active" nor "inactive") should be treated as
    /// absent — returns nil and does not crash.
    func testUnrecognisedValueReturnsNil() {
        let source = fakeEntitlementSource(environment: ["KIGO_FAKE_ENTITLEMENT": "bogus"])
        XCTAssertNil(
            source,
            "fakeEntitlementSource must return nil for an unrecognised KIGO_FAKE_ENTITLEMENT value"
        )
    }
}
