import XCTest

final class PipMascotTests: XCTestCase {
    @MainActor
    func testAllCompanionsLoadAfterSelection() {
        let app = XCUIApplication()
        app.launchPastIntro()
        for name in ["Atlas", "Flex", "Pip"] {
            app.buttons["Settings"].tap()
            let choice = app.buttons[name]
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            choice.tap()
            app.buttons["Done"].tap()
            let mascot = app.buttons["celebrate-pip"]
            waitForValue("3D", on: mascot)
            XCTAssertEqual(mascot.label, "Celebrate with \(name)")
            capture(app, name: "\(name) animated companion")
        }
    }

    @MainActor
    func testTodayLoads3DAndTapReturnsToIdle() {
        let app = XCUIApplication()
        app.launchArguments = ["--gymni-ui-testing"]
        app.launchPastIntro()
        let pip = app.buttons["celebrate-pip"]
        XCTAssertTrue(pip.waitForExistence(timeout: 10))
        waitForValue("3D", on: pip)
        pip.tap()
        // UI automation may wait through the brief celebration before returning.
        waitForValue("Ready", on: pip)
        XCTAssertTrue(pip.isEnabled)
        capture(app, name: "Pip Today 3D")
    }

    @MainActor
    func testMissingModelUsesPreviewAndWorkoutStillStarts() {
        let app = XCUIApplication()
        app.launchArguments = ["--gymni-ui-testing"]
        app.launchArguments += ["-PipForceFallback"]
        app.launchPastIntro()
        let pip = app.buttons["celebrate-pip"]
        XCTAssertTrue(pip.waitForExistence(timeout: 10))
        waitForValue("Static preview", on: pip)
        capture(app, name: "Pip static fallback")
        app.buttons["Start workout"].tap()
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Pause"].isHittable)
    }

    @MainActor
    func testModelReturnsAfterBackgroundAndTabChange() {
        let app = XCUIApplication()
        app.launchArguments = ["--gymni-ui-testing"]
        app.launchPastIntro()
        waitForValue("3D", on: app.buttons["celebrate-pip"])
        XCUIDevice.shared.press(.home)
        app.activate()
        waitForValue("3D", on: app.buttons["celebrate-pip"])
        app.tabBars.buttons["Progress"].tap()
        app.tabBars.buttons["Today"].tap()
        waitForValue("3D", on: app.buttons["celebrate-pip"])
    }

    @MainActor
    func testReducedMotionKeepsRestAndRecapAccessible() {
        let app = XCUIApplication()
        app.launchArguments = ["--gymni-ui-testing"]
        app.launchArguments += ["-PipReduceMotion"]
        app.launchPastIntro()
        waitForValue("motion reduced", on: app.buttons["celebrate-pip"])
        app.buttons["Start workout"].tap()
        XCTAssertTrue(app.staticTexts["Set 1 of 3"].waitForExistence(timeout: 8))
        app.buttons["Mute coach"].tap()
        let pip = app.descendants(matching: .any)["pip-mascot"].firstMatch
        waitForValue("Ready", on: pip)
        app.buttons["Pause"].tap()
        waitForValue("Resting", on: pip)
        waitForValue("3D", on: pip)
        capture(app, name: "Pip rest reduced motion")
        app.buttons["End Workout"].tap()
        waitForValue("Celebrating", on: pip)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["celebrate-pip"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func waitForValue(_ text: String, on element: XCUIElement) {
        let matches = NSPredicate(format: "value CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: matches, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed, element.debugDescription)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
