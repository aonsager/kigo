import XCTest
import SwiftUI
@testable import Kigo

// MARK: - LaunchColorSchemeTests

/// Unit tests for the `launchColorScheme(environment:)` factory (slice #144).
///
/// The factory reads `KIGO_FAKE_APPEARANCE` from the launch-environment dictionary
/// and returns `.dark`, `.light`, or `nil` (system default).
///
/// These tests exercise all three branches as pure unit tests — no app launch required.
final class LaunchColorSchemeTests: XCTestCase {

    // MARK: - dark branch

    /// `KIGO_FAKE_APPEARANCE=dark` must resolve to `ColorScheme.dark`.
    func testDarkEnvironmentVariableReturnsDark() {
        let result = launchColorScheme(environment: ["KIGO_FAKE_APPEARANCE": "dark"])
        XCTAssertEqual(
            result, .dark,
            "KIGO_FAKE_APPEARANCE=dark must return ColorScheme.dark"
        )
    }

    // MARK: - light branch

    /// `KIGO_FAKE_APPEARANCE=light` must resolve to `ColorScheme.light`.
    func testLightEnvironmentVariableReturnsLight() {
        let result = launchColorScheme(environment: ["KIGO_FAKE_APPEARANCE": "light"])
        XCTAssertEqual(
            result, .light,
            "KIGO_FAKE_APPEARANCE=light must return ColorScheme.light"
        )
    }

    // MARK: - absent / unrecognised branch

    /// An absent `KIGO_FAKE_APPEARANCE` must return `nil` (let the system decide).
    func testAbsentEnvironmentVariableReturnsNil() {
        let result = launchColorScheme(environment: [:])
        XCTAssertNil(
            result,
            "Absent KIGO_FAKE_APPEARANCE must return nil so the system color scheme is used"
        )
    }

    /// An unrecognised value for `KIGO_FAKE_APPEARANCE` must fall back to `nil`.
    func testUnrecognisedEnvironmentVariableReturnsNil() {
        let unrecognisedValues = ["auto", "system", "Dark", "Light", "", "1"]
        for value in unrecognisedValues {
            let result = launchColorScheme(environment: ["KIGO_FAKE_APPEARANCE": value])
            XCTAssertNil(
                result,
                "Unrecognised KIGO_FAKE_APPEARANCE='\(value)' must return nil"
            )
        }
    }
}
