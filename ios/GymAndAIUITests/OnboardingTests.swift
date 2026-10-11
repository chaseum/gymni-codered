import XCTest

final class OnboardingTests: XCTestCase {
    @MainActor func testFirstRunResumesMatchesAndSavesProfile() {
        let app = XCUIApplication()
        app.launchArguments = ["--gymni-ui-testing", "--gymni-onboarding-testing", "--gymni-preferences-suite", "onboard-ui-\(UUID().uuidString)"]
        app.launchPastIntro()
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 5))
        capture(app, "Onboarding welcome")
        app.buttons["Get Started"].tap()
        XCTAssertTrue(app.textFields["onboarding-name"].waitForExistence(timeout: 5))
        app.textFields["onboarding-name"].typeText("Sam")
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["About You"].waitForExistence(timeout: 5))
        capture(app, "Onboarding measurements")
        app.textFields["onboarding-weight"].tap()
        app.textFields["onboarding-weight"].typeText("78")
        app.buttons["Done"].tap()
        app.textFields["onboarding-height"].tap()
        app.textFields["onboarding-height"].typeText("178")
        app.buttons["Done"].tap()
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["What do you want to work toward?"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["onboarding-continue"].isEnabled)
        app.buttons["onboarding-choice-strength"].tap()
        capture(app, "Onboarding selected goal")
        app.buttons["onboarding-continue"].tap()
        app.buttons["onboarding-choice-returning"].tap()
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["How active is your usual day?"].exists)
        app.terminate()
        app.launchPastIntro()
        XCTAssertTrue(app.staticTexts["How active is your usual day?"].waitForExistence(timeout: 5))
        for answer in ["active", "3", "45", "gym", "muscle", "fitness"] {
            app.buttons["onboarding-choice-\(answer)"].tap()
            app.buttons["onboarding-continue"].tap()
        }
        XCTAssertTrue(app.staticTexts["Meet Atlas"].waitForExistence(timeout: 5))
        capture(app, "Onboarding Atlas match")
        app.segmentedControls.buttons["Build muscle"].tap()
        XCTAssertTrue(app.staticTexts["Meet Flex"].waitForExistence(timeout: 3))
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["Heart Rate"].waitForExistence(timeout: 3))
        capture(app, "Onboarding heart rate")
        app.buttons["Not Now"].tap()
        XCTAssertTrue(app.staticTexts["Gym&I Camera"].waitForExistence(timeout: 3))
        app.buttons["Not Now"].tap()
        XCTAssertTrue(app.staticTexts["Muscle Building"].waitForExistence(timeout: 5))
        capture(app, "Plan from the profile on Today")
        app.terminate()
        app.launchPastIntro()
        XCTAssertTrue(app.staticTexts["Muscle Building"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["About You"].exists)
        app.buttons["Settings"].tap()
        app.buttons["edit-training-profile"].tap()
        XCTAssertTrue(app.staticTexts["About You"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["onboarding-weight"].value as? String, "78")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
    }

    @MainActor func testLargeTextMetricsQuestionsAndSkipAreReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--gymni-ui-testing", "--gymni-onboarding-testing", "--gymni-preferences-suite", "onboard-large-\(UUID().uuidString)", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-PipReduceMotion"]
        app.launchPastIntro()
        app.buttons["Get Started"].tap()
        app.buttons["Not Now"].tap()  // skip the name
        XCTAssertTrue(app.buttons["onboarding-continue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding-continue"].isHittable)
        capture(app, "Onboarding large text measurements")
        app.buttons["onboarding-continue"].tap()
        capture(app, "Onboarding large text goal")
        app.swipeUp()
        let choice = app.buttons["onboarding-choice-fitness"]
        for _ in 0..<4 where !choice.isHittable { app.swipeUp() }
        XCTAssertTrue(choice.isHittable)
        choice.tap()
        XCTAssertTrue(app.buttons["onboarding-continue"].isHittable)
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 5))
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
