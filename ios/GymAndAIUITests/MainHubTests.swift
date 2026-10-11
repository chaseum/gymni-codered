import XCTest

final class MainHubTests: XCTestCase {
    /// The product path: the camera posts measured reps to this iPhone; the set ends at its target and rests.
    @MainActor
    func testMeasuredRepsFillTheSetThenRest() async throws {
        let app = XCUIApplication()
        // No UI-testing flag: real product defaults (default plan: Full Body, squats 3 × 12).
        app.launchArguments = ["--gymni-skip-onboarding", "--gymni-preferences-suite", "main-hub-\(UUID().uuidString)"]
        app.launchPastIntro()
        app.buttons["Start workout"].tap()
        let counter = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "0 of 12 reps")).firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 8))
        try await Task.sleep(for: .seconds(3))
        XCTAssertTrue(counter.exists)  // no incoming observations, no invented reps

        let phone = URL(string: "http://127.0.0.1:8000/api/sessions/phone/observations")!
        for n in 1...3 { try await observation(phone, index: n) }
        let three = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "3 of 12 reps")).firstMatch
        XCTAssertTrue(three.waitForExistence(timeout: 10))
        attach(app, "Measured reps")
        for n in 4...12 { try await observation(phone, index: n) }
        XCTAssertTrue(app.staticTexts["Rest"].waitForExistence(timeout: 10))  // target reached → rest on its own
        XCTAssertTrue(app.staticTexts["Squat · Set 2 of 3"].exists)
        attach(app, "Automatic rest")
        app.buttons["End Workout"].tap()
        XCTAssertTrue(app.staticTexts["Workout Complete"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["12"].exists)
        attach(app, "Recap")
    }

    @MainActor private func observation(_ url: URL, index: Int) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "schema_version": 1, "session_id": "phone", "observation_id": UUID().uuidString,
            "source": "live", "time_base": "capture_monotonic", "source_timestamp_ms": index * 2500,
            "exercise": "squat", "tracking_status": "ready", "phase": "lowered",
            "completed_rep": ["rep_index": index, "duration_ms": 2500],
            "measurements": [:], "issues": [], "inference_provenance": "fixture"
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
