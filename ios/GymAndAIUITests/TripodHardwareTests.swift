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
        let watchTip = app.alerts["Start a Workout on Apple Watch"]
        if watchTip.waitForExistence(timeout: 2) { watchTip.buttons["OK"].tap() }
        let camera = app.buttons["show-camera"]
        XCTAssertTrue(camera.waitForExistence(timeout: 10), app.debugDescription)
        camera.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let frame = app.images["pi-camera-frame"]
        XCTAssertTrue(frame.waitForExistence(timeout: 25), app.debugDescription)
        // A single received JPEG expires after three seconds. Check sustained live video.
        let staleFrame = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !frame.exists }, object: nil)
        staleFrame.isInverted = true
        wait(for: [staleFrame], timeout: 6)
        print("Camera screen bounds: \(app.frame); video bounds: \(frame.frame)")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Pi camera full screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["camera-back-to-reps"].tap()
        XCTAssertTrue(camera.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Pause"].exists)
        #endif
    }
}
