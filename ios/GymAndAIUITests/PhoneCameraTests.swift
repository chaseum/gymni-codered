import XCTest

final class PhoneCameraTests: XCTestCase {
    @MainActor
    func testSimulatorDoesNotFakePhoneVideoOrRepCounts() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Settings"].tap()
        app.segmentedControls.buttons["iPhone"].tap()
        app.buttons["Done"].tap()
        app.buttons["Start workout"].tap()
        let unavailable = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label == %@", "phone-camera-status", "No camera available. Use a physical iPhone.")).firstMatch
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Start set"].exists)
        XCTAssertFalse(app.buttons["Start set"].isEnabled)
        XCTAssertFalse(app.staticTexts["Simulated camera view"].exists)
        capture(app, name: "iPhone positioning unavailable")
        app.swipeUp()
        app.buttons["End workout"].tap()
        XCTAssertTrue(app.staticTexts["You showed up."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Your camera session ended. Reps and form were not measured."].exists)
        capture(app, name: "Unmeasured recap")
        app.buttons["Back to Today"].tap()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["You completed a camera session"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["0 completed reps"].exists)
        capture(app, name: "Unmeasured progress")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
