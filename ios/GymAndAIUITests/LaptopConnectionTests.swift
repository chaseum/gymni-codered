import XCTest

final class LaptopConnectionTests: XCTestCase {
    @MainActor
    func testRealBackendCommandsAndRepEvents() async throws {
        let baseURL = try XCTUnwrap(URL(string: "http://localhost:8000"))
        var health = URLRequest(url: baseURL.appending(path: "health"))
        health.timeoutInterval = 1
        let available = try? await URLSession.shared.data(for: health)
        try XCTSkipUnless((available?.1 as? HTTPURLResponse)?.statusCode == 200, "Run the local backend to enable this integration check.")
        let healthData = try XCTUnwrap(available?.0)
        let metadata = try JSONSerialization.jsonObject(with: healthData) as? [String: Any]
        try XCTSkipUnless(metadata?["schema_version"] as? Int == 1, "Port 8000 must be the Gym&AI backend.")
        let sessionId = "ios-test-\(UUID().uuidString)"
        _ = try await post(baseURL.appending(path: "api/sessions"), body: ["session_id": sessionId])

        let app = XCUIApplication()
        app.launch()
        app.buttons["Settings"].tap()
        app.segmentedControls.buttons["Laptop"].tap()
        let sessionField = app.textFields["Existing session ID"]
        sessionField.tap()
        sessionField.typeText(sessionId)
        app.buttons["Done"].tap()
        app.buttons["Start workout"].tap()
        XCTAssertTrue(app.segmentedControls["workout-view-picker"].waitForExistence(timeout: 10))

        let observation: [String: Any] = [
            "schema_version": 1, "observation_id": UUID().uuidString,
            "session_id": sessionId, "set_id": NSNull(), "source": "recorded",
            "clip_id": "integration-fixture", "time_base": "video_pts", "source_timestamp_ms": 2300,
            "exercise": "curl", "exercise_confidence": NSNull(), "tracking_status": "ready",
            "phase": "raised", "completed_rep": ["rep_index": 1, "duration_ms": 2300],
            "measurement_basis": "image_2d", "measurements": [:], "issues": [],
            "inference_provenance": "fixture", "model_version": NSNull()
        ]
        _ = try await post(baseURL.appending(path: "api/sessions/\(sessionId)/observations"), body: observation)
        let counter = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "1 of 8 completed reps")).firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Camera"].tap()
        XCTAssertTrue(app.staticTexts["Camera preview unavailable"].waitForExistence(timeout: 5))
        let sample: [String: Any] = [
            "sample_id": UUID().uuidString, "session_id": sessionId,
            "participant_id": "integration-fixture", "bpm": 112,
            "sample_timestamp_ms": Int64(Date().timeIntervalSince1970 * 1_000),
            "source": "apple_watch"
        ]
        _ = try await post(baseURL.appending(path: "api/sessions/\(sessionId)/heart_rate"), body: sample)
        let watch = app.descendants(matching: .any)["camera-heart-rate"]
        let fresh = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "112 bpm"), object: watch)
        await fulfillment(of: [fresh], timeout: 5)
        let stale = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Waiting for a fresh sample"), object: watch)
        await fulfillment(of: [stale], timeout: 12)
        XCTAssertFalse(watch.label.contains("112 bpm"))
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts["Take a breath."].waitForExistence(timeout: 5))
        app.buttons["Resume workout"].tap()
        XCTAssertTrue(app.staticTexts["Camera preview unavailable"].waitForExistence(timeout: 5))
        app.buttons["End workout"].tap()
        XCTAssertTrue(app.staticTexts["You showed up."].waitForExistence(timeout: 5))
    }

    @MainActor
    private func post(_ url: URL, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertTrue([200, 201].contains((response as? HTTPURLResponse)?.statusCode ?? 0))
        return data
    }
}
