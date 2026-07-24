// KigoCore/Tests/KigoCoreTests/SekkiBackdropTests.swift
import XCTest
@testable import KigoCore

final class SekkiBackdropTests: XCTestCase {

    func testAssetNameIsBackdropPrefixedSekkiId() {
        XCTAssertEqual(SekkiBackdrop.assetName(forSekkiId: "boshu"), "backdrop-boshu")
        XCTAssertEqual(SekkiBackdrop.assetName(forSekkiId: "risshun"), "backdrop-risshun")
    }

    func testAssetNameIsDeterministic() {
        XCTAssertEqual(
            SekkiBackdrop.assetName(forSekkiId: "boshu"),
            SekkiBackdrop.assetName(forSekkiId: "boshu")
        )
    }

    func testFallbackHueIsInUnitRange() {
        for id in ["risshun", "usui", "keichitsu", "boshu"] {
            let hue = SekkiBackdrop.fallbackHue(forSekkiId: id)
            XCTAssertGreaterThanOrEqual(hue, 0.0)
            XCTAssertLessThanOrEqual(hue, 1.0)
        }
    }

    func testFallbackHueIsDeterministicAndVariesBySekki() {
        XCTAssertEqual(
            SekkiBackdrop.fallbackHue(forSekkiId: "boshu"),
            SekkiBackdrop.fallbackHue(forSekkiId: "boshu")
        )
        XCTAssertNotEqual(
            SekkiBackdrop.fallbackHue(forSekkiId: "boshu"),
            SekkiBackdrop.fallbackHue(forSekkiId: "risshun")
        )
    }
}
