import XCTest
import StoreKitTest
@testable import Kigo

/// Tests for EntitlementProvider — the seam that derives subscription entitlement
/// state from StoreKit's verified transactions.
///
/// Uses SKTestSession to control StoreKit state in-process without hitting Apple's
/// servers. The configuration file "Kigo" resolves to Kigo.storekit in the project.
final class EntitlementTests: XCTestCase {

    // MARK: - Inactive with no transactions

    /// C6 slice 1: With a fresh SKTestSession holding no transactions,
    /// EntitlementProvider must report the entitlement as inactive.
    ///
    /// This is the foundational invariant: no purchase → no entitlement.
    func testEntitlementIsInactiveWithNoTransactions() async throws {
        // Arrange: fresh StoreKit test session, no transactions.
        let session = try SKTestSession(configurationFileNamed: "Kigo")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true

        // Act: check entitlement through the provider.
        let provider = EntitlementProvider()
        let isActive = await provider.isEntitlementActive()

        // Assert: no purchase → not entitled.
        XCTAssertFalse(
            isActive,
            "EntitlementProvider must report inactive when no transactions exist"
        )
    }
}
