import XCTest

final class WorkoutJourneyTests: XCTestCase {
    @MainActor
    func testCameraSwitchPauseAndExplicitResume() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--gymni-ui-testing"]
        app.launchPastIntro()
        capture(app, name: "Today")
        app.buttons["View plan"].tap()
        XCTAssertTrue(app.navigationBars["Your plan"].waitForExistence(timeout: 3))
        capture(app, name: "Plan review")
        app.buttons["Done"].tap()
        XCTAssertLessThan(app.buttons["Workout setup"].frame.maxY, app.buttons["Start workout"].frame.minY)
        app.buttons["Workout setup"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        capture(app, name: "Workout settings")
        app.buttons["Done"].tap()
        app.buttons["Start workout"].tap()
        let picker = app.segmentedControls["workout-view-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        capture(app, name: "Reps")
        picker.buttons["Camera"].tap()
        XCTAssertTrue(app.staticTexts["Camera preview unavailable"].waitForExistence(timeout: 5))
        let watch = app.descendants(matching: .any)["camera-heart-rate"]
        let reps = app.descendants(matching: .any)["camera-rep-count"]
        XCTAssertTrue(watch.exists)
        XCTAssertTrue(reps.exists)
        XCTAssertLessThan(watch.frame.midX, reps.frame.midX)
        XCTAssertLessThan(watch.frame.maxY, app.frame.midY)
        XCTAssertLessThan(reps.frame.maxY, app.frame.midY)
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        XCTAssertTrue(app.staticTexts["coach-message"].isHittable)
        XCTAssertTrue(app.buttons["Pause"].isHittable)
        XCTAssertTrue(app.buttons["End workout"].isHittable)
        capture(app, name: "Camera")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Pause"].isHittable)
        XCTAssertGreaterThanOrEqual(watch.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(reps.frame.maxX, app.frame.maxX)
        capture(app, name: "Camera landscape left")
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(app.buttons["End workout"].isHittable)
        capture(app, name: "Camera landscape right")
        app.buttons["camera-back-to-reps"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.frame.height, app.frame.width)
        XCTAssertFalse(app.staticTexts["Camera preview unavailable"].exists)
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts["Take a breath."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Resume workout"].exists)
        let restScreenshot = XCTAttachment(screenshot: app.screenshot())
        restScreenshot.name = "Rest"
        restScreenshot.lifetime = .keepAlways
        add(restScreenshot)
        app.buttons["End workout"].tap()
        XCTAssertTrue(app.staticTexts["You showed up."].waitForExistence(timeout: 3))
        capture(app, name: "Session recap")
        app.buttons["Back to Today"].tap()
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Pi or laptop camera · Counted on this iPhone"].waitForExistence(timeout: 3))
        capture(app, name: "Pi progress")
    }

    @MainActor
    func testPlanAndProgressKeepSourcesHonest() {
        let app = XCUIApplication()
        app.launchArguments = ["--gymni-ui-testing"]
        app.launchPastIntro()
        app.tabBars.buttons["Progress"].tap()
        capture(app, name: "Progress empty state")
        app.tabBars.buttons["Today"].tap()
        app.buttons["Start workout"].tap()
        XCTAssertTrue(app.segmentedControls["workout-view-picker"].waitForExistence(timeout: 8))
        app.buttons["End workout"].tap()
        app.buttons["Back to Today"].tap()
        app.buttons["Settings"].tap()
        app.segmentedControls.buttons["iPhone camera"].tap()
        app.buttons["Done"].tap()
        app.buttons["View plan"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Manual · Unmeasured")).firstMatch.waitForExistence(timeout: 3))
        capture(app, name: "iPhone camera plan")
        app.buttons["Done"].tap()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Pi or laptop camera · Counted on this iPhone"].waitForExistence(timeout: 3))
        capture(app, name: "Progress source after setup change")
    }

    @MainActor
    func testLargeTextKeepsWorkoutControlsAccessible() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--gymni-ui-testing"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchPastIntro()
        XCTAssertTrue(app.buttons["Start workout"].isHittable)
        capture(app, name: "Large text Today")
        app.swipeUp()
        app.buttons["Start workout"].tap()
        let picker = app.segmentedControls["workout-view-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.buttons["Camera"].tap()
        XCTAssertTrue(app.staticTexts["Camera preview unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Pause"].isHittable)
        XCTAssertTrue(app.buttons["End workout"].isHittable)
        let watch = app.descendants(matching: .any)["camera-heart-rate"]
        let reps = app.descendants(matching: .any)["camera-rep-count"]
        XCTAssertLessThanOrEqual(watch.frame.maxX, reps.frame.minX)
        XCTAssertLessThan(watch.frame.maxY, app.buttons["Pause"].frame.minY)
        XCTAssertLessThan(reps.frame.maxY, app.buttons["Pause"].frame.minY)
        XCTAssertTrue(app.scrollViews["camera-workout-details"].exists)
        XCTAssertGreaterThanOrEqual(watch.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(reps.frame.maxX, app.frame.maxX)
        capture(app, name: "Large text camera")
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts["Take a breath."].waitForExistence(timeout: 3))
        let rest = app.scrollViews["rest-content"]
        XCTAssertTrue(rest.waitForExistence(timeout: 3))
        let timer = app.descendants(matching: .any)["rest-countdown"]
        for _ in 0..<5 {
            if timer.frame.midY < app.buttons["Resume workout"].frame.minY { break }
            // Keep the gesture above the fixed action dock.
            let visibleHeight = app.buttons["Resume workout"].frame.minY - rest.frame.minY
            let top = rest.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            top.withOffset(CGVector(dx: 0, dy: visibleHeight - 30))
                .press(forDuration: 0.05, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 30)))
        }
        XCTAssertTrue(timer.isHittable)
        XCTAssertLessThan(timer.frame.midY, app.buttons["Resume workout"].frame.minY)
        capture(app, name: "Large text rest")
        XCTAssertTrue(app.buttons["End workout"].isHittable)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
