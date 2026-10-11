import XCTest

/// Requires the paired Pi on this iPhone's active Personal Hotspot.
final class TripodHardwareTests: XCTestCase {
    @MainActor
    func testPairedTripodShowsRealVideo() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This check requires the physical iPhone and Pi.")
        #else
        let app = XCUIApplication()
        app.launchArguments = ["--gymni-skip-onboarding"]
        app.launchPastIntro()
        let start = app.buttons["Start workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), app.debugDescription)
        start.tap()
        XCTAssertTrue(app.buttons["open-pi-camera"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.images["pi-camera-frame"].waitForExistence(timeout: 25), app.debugDescription)
        #endif
    }
}
