import XCTest

final class MainHubTests: XCTestCase {
    @MainActor
    func testMainAppUsesPiAndHostedElevenLabsWithMeasuredCaptions() async throws {
        let cloud = URL(string: "http://127.0.0.1:18081")!
        var request = URLRequest(url: cloud.appending(path: "api/coach/configuration"))
        request.timeoutInterval = 2
        let configuration = try? await URLSession.shared.data(for: request)
        try XCTSkipUnless((configuration?.1 as? HTTPURLResponse)?.statusCode == 200, "Run main:app on port 18081 with ElevenLabs configured.")
        let app = XCUIApplication()
        // No UI-testing flag: exercise the actual product defaults and settings.
        app.launchArguments = ["--gymni-skip-onboarding", "--gymni-preferences-suite", "main-hub-\(UUID().uuidString)"]
        app.launchPastIntro()
        XCTAssertTrue(app.staticTexts["Pi camera · Live reps"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.textFields["hosted-api-url"].waitForExistence(timeout: 5))
        let hostedURL = app.textFields["hosted-api-url"]
        hostedURL.tap()
        hostedURL.typeText(cloud.absoluteString)
        app.buttons["Check voice connection"].tap()
        XCTAssertTrue(app.staticTexts["Voice API connected"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.segmentedControls.buttons["Demo"].exists)
        XCTAssertFalse(app.staticTexts["Laptop connection"].exists)
        attach(app, "Main app hosted voice settings")
        app.buttons["Done"].tap()
        app.buttons["Start workout"].tap()
        let counter = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "0 of 8 completed reps")).firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        try await Task.sleep(for: .seconds(6))
        XCTAssertTrue(counter.exists) // no incoming observations, no simulated reps
        let phone = URL(string: "http://127.0.0.1:8000/api/sessions/phone/observations")!
        for n in 1...4 {
            if n == 4 { try await Task.sleep(for: .seconds(6.2)) }
            try await observation(phone, index: n)
        }
        XCTAssertTrue(app.staticTexts["4 reps. Halfway there."].waitForExistence(timeout: 10))
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "4 reps. Halfway there."), object: app.buttons["Mute coach"])
        await fulfillment(of: [playing], timeout: 5)
        attach(app, "Main app measured count milestone")
        try await Task.sleep(for: .seconds(6.2))
        try await observation(phone, index: 5, issues: [["code": "curl.partial_range", "evidence": ["min_elbow_angle_deg": 100]]])
        XCTAssertTrue(app.staticTexts["Curl a little higher, keeping the movement controlled."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["4 reps. Halfway there."].exists)
        attach(app, "Main app measured form correction")
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts["Take a breath."].waitForExistence(timeout: 5))
        try await observation(phone, index: 6)
        app.buttons["End workout"].tap()
        XCTAssertTrue(app.staticTexts["You showed up."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMainSettingsAtLargestAccessibilityText() {
        let app = XCUIApplication()
        app.launchArguments = ["--gymni-skip-onboarding", "--gymni-preferences-suite", "main-large-\(UUID().uuidString)",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchPastIntro()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.textFields["hosted-api-url"].waitForExistence(timeout: 5))
        attach(app, "Main settings largest accessibility text")
        for _ in 0..<5 {
            if app.buttons["Check voice connection"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["Check voice connection"].isHittable)
        attach(app, "Main voice settings scroll at accessibility size")
        app.buttons["Done"].tap()
    }

    @MainActor private func observation(_ url: URL, index: Int, issues: [[String: Any]] = []) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "schema_version": 1, "session_id": "phone", "observation_id": UUID().uuidString,
            "source": "live", "time_base": "capture_monotonic", "source_timestamp_ms": index * 2500,
            "exercise": "curl", "tracking_status": "ready", "phase": "lowered",
            "completed_rep": ["rep_index": index, "duration_ms": 2500],
            "measurements": [:], "issues": issues, "inference_provenance": "fixture"
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = name
        capture.lifetime = .keepAlways
        add(capture)
    }
}
