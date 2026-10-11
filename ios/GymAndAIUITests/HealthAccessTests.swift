import XCTest

final class HealthAccessTests: XCTestCase {
    @MainActor
    func testConnectHealthCompletesWithoutClaimingReadAccess() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--gymni-ui-testing"]
        app.launchPastIntro()
        app.buttons["Settings"].tap()
        let connect = app.buttons["connect-apple-health"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        XCTAssertTrue(connect.isHittable)
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Apple Health settings"
        before.lifetime = .keepAlways
        add(before)
        connect.tap()
        let permission = app.staticTexts["Heart Rate"]
        if permission.waitForExistence(timeout: 5) {
            let sheet = XCTAttachment(screenshot: app.screenshot())
            sheet.name = "Heart rate permission sheet"
            sheet.lifetime = .keepAlways
            add(sheet)
            app.buttons["UIA.Health.DoNotAllow.Button"].tap()
            let confirmation = app.alerts["Health Access"].buttons["OK"]
            if confirmation.waitForExistence(timeout: 3) { confirmation.tap() }
        }
        // HealthKit may finish without a sheet when a choice was already recorded.
        let finished = app.staticTexts.matching(NSPredicate(
            format: "identifier == %@ AND label BEGINSWITH %@",
            "health-access-status", "Permission request finished."
        )).firstMatch
        XCTAssertTrue(finished.waitForExistence(timeout: 5))
        XCTAssertTrue(connect.isEnabled)
        let result = XCTAttachment(screenshot: app.screenshot())
        result.name = "Apple Health request finished"
        result.lifetime = .keepAlways
        add(result)
    }
}
