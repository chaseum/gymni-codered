import XCTest

final class WorkoutJourneyTests: XCTestCase {
    /// Today → plan → set → camera → set → pause → end → recap → Today → Progress, with no dev-facing copy anywhere.
    @MainActor
    func testWorkoutJourney() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--gymni-ui-testing"]
        app.launchPastIntro()
        XCTAssertTrue(app.staticTexts["Welcome"].waitForExistence(timeout: 5))
        capture(app, name: "Today")
        app.buttons["open-plan"].tap()
        XCTAssertTrue(app.staticTexts["Full Body"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["3 sets × 10–12 reps"].exists)
        capture(app, name: "Plan")
        app.buttons["Done"].tap()

        app.buttons["Start workout"].tap()
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Pause"].isHittable)
        capture(app, name: "Set")
        app.buttons["show-camera"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["camera-rep-count"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        capture(app, name: "Camera")
        app.buttons["camera-back-to-reps"].tap()
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].waitForExistence(timeout: 5))

        app.buttons["Next Set"].tap()
        XCTAssertTrue(app.staticTexts["Rest"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Squat · Set 2 of 3"].exists)
        capture(app, name: "Rest")
        app.buttons["Start Next Set"].tap()
        XCTAssertTrue(app.staticTexts["Set 2 of 3"].waitForExistence(timeout: 3))
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 3))
        app.buttons["End Workout"].tap()
        XCTAssertTrue(app.staticTexts["Workout Complete"].waitForExistence(timeout: 3))
        capture(app, name: "Recap")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["This Week"].waitForExistence(timeout: 3))
        capture(app, name: "Progress")

        for devText in ["Unmeasured", "Pi / laptop", "iPhone camera", "Counted on this iPhone", "Install Gym&I"] {
            XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", devText)).firstMatch.exists, devText)
        }
    }

    @MainActor
    func testLargeTextKeepsStartAndWorkoutControlsReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--gymni-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchPastIntro()
        XCTAssertTrue(app.buttons["Start workout"].isHittable)
        app.buttons["Start workout"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Pause"].isHittable)
        XCTAssertTrue(app.buttons["End Workout"].isHittable)
        capture(app, name: "Large text set")
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 3))
        capture(app, name: "Large text rest")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
