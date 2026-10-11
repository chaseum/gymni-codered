import XCTest

final class LaptopConnectionTests: XCTestCase {
    @MainActor
    func testMeasuredRepCuesAndFormPriority() async throws {
        let baseURL = try XCTUnwrap(URL(string: "http://127.0.0.1:18081"))
        var health = URLRequest(url: baseURL.appending(path: "health"))
        health.timeoutInterval = 1
        let available = try? await URLSession.shared.data(for: health)
        try XCTSkipUnless((available?.1 as? HTTPURLResponse)?.statusCode == 200, "Run a verification backend on port 18081.")
        let sessionID = "coaching-fixture-\(UUID().uuidString)"
        _ = try await post(baseURL.appending(path: "api/sessions"), body: ["session_id": sessionID])
        _ = try await post(baseURL.appending(path: "api/sessions/\(sessionID)/commands"), body: [
            "session_id": sessionID, "command_id": UUID().uuidString, "intent": "start",
            "args": ["exercise": "curl", "source": "recorded", "target_reps": 8]
        ])
        let app = XCUIApplication()
        app.launchArguments = ["--gymni-ui-testing", "--gymni-laptop", "--backend-url", baseURL.absoluteString,
                               "--session-id", sessionID, "--exercise", "curl"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Laptop · Recorded input"].waitForExistence(timeout: 10))

        for n in 1...5 {
            if n == 4 { try await Task.sleep(for: .seconds(6.1)) } // actual backend speech cooldown
            let observation: [String: Any] = [
                "schema_version": 1, "session_id": sessionID, "observation_id": UUID().uuidString,
                "source": "recorded", "clip_id": "coaching-fixture", "time_base": "video_pts",
                "source_timestamp_ms": n * 2500, "exercise": "curl", "tracking_status": "ready",
                "phase": "lowered", "completed_rep": ["rep_index": n, "duration_ms": 2500],
                "measurement_basis": "image_2d", "measurements": [:], "inference_provenance": "fixture",
                "issues": n == 5 ? [["code": "curl.partial_range", "evidence": ["min_elbow_angle_deg": 100]]] : []
            ]
            _ = try await post(baseURL.appending(path: "api/sessions/\(sessionID)/observations"), body: observation)
            if n == 4 {
                XCTAssertTrue(app.staticTexts["4 reps. Halfway there."].waitForExistence(timeout: 5))
                capture(app, name: "Measured rep milestone caption")
            }
        }
        XCTAssertTrue(app.staticTexts["Curl a little higher, keeping the movement controlled."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["4 reps. Halfway there."].exists)
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts["Take a breath."].waitForExistence(timeout: 5))
        let (_, response) = try await URLSession.shared.data(from: baseURL.appending(path: "api/sessions/\(sessionID)/coaching/coach-set-001-4/audio"))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 409)
    }

    @MainActor
    func testLaptopSetupSurvivesRelaunchWithoutScriptArguments() async throws {
        let baseURL = try XCTUnwrap(URL(string: "http://127.0.0.1:18080"))
        let (health, response) = try await URLSession.shared.data(from: baseURL.appending(path: "health"))
        try XCTSkipUnless((response as? HTTPURLResponse)?.statusCode == 200, "Run a verification backend on port 18080.")
        let metadata = try JSONSerialization.jsonObject(with: health) as? [String: Any]
        try XCTSkipUnless(metadata?["schema_version"] as? Int == 1)
        let sessionID = "relaunch-test-\(UUID().uuidString)"
        _ = try await post(baseURL.appending(path: "api/sessions"), body: ["session_id": sessionID])

        let app = XCUIApplication()
        let isolatedSettings = ["--gymni-ui-testing", "--gymni-preferences-suite", "relaunch-settings-\(UUID().uuidString)"]
        app.launchArguments = isolatedSettings + ["--gymni-laptop", "--backend-url", baseURL.absoluteString,
                                                  "--session-id", sessionID, "--exercise", "curl"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Laptop · Live input"].waitForExistence(timeout: 10))
        app.terminate()

        // Opening from Xcode or the Simulator home screen supplies no laptop arguments.
        app.launchArguments = isolatedSettings
        app.launch()
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Laptop"].isSelected)
        app.buttons["Done"].tap()
        app.buttons["Start workout"].tap()
        XCTAssertTrue(app.staticTexts["Laptop · Live input"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Demo · Simulated data"].exists)
        let counter = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "0 of 8 completed reps")).firstMatch
        XCTAssertTrue(counter.exists)
        let simulatedRep = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "0 of 8 completed reps"), object: counter)
        simulatedRep.isInverted = true
        await fulfillment(of: [simulatedRep], timeout: 6)
        capture(app, name: "Relaunched Laptop retains real backend mode")
        app.buttons["End workout"].tap()
        XCTAssertTrue(app.staticTexts["You showed up."].waitForExistence(timeout: 5))
    }

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
        _ = try await post(baseURL.appending(path: "api/sessions/\(sessionId)/commands"), body: [
            "session_id": sessionId, "command_id": UUID().uuidString, "intent": "start",
            "args": ["exercise": "curl", "source": "recorded", "target_reps": 8]
        ])

        let app = XCUIApplication()
        app.launchArguments = ["--gymni-ui-testing"]
        app.launch()
        app.buttons["Settings"].tap()
        app.segmentedControls.buttons["Laptop"].tap()
        let sessionField = app.textFields["Existing session ID"]
        for _ in 0..<6 {
            if sessionField.exists && sessionField.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(sessionField.exists && sessionField.isHittable)
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
        capture(app, name: "Laptop reps from fixture")
        app.segmentedControls.buttons["Camera"].tap()
        XCTAssertTrue(app.staticTexts["Camera preview unavailable"].waitForExistence(timeout: 5))
        capture(app, name: "Laptop preview unavailable")
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
        capture(app, name: "Laptop stale Watch fixture")
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts["Take a breath."].waitForExistence(timeout: 5))
        app.buttons["Resume workout"].tap()
        XCTAssertTrue(app.staticTexts["Camera preview unavailable"].waitForExistence(timeout: 5))
        app.buttons["End workout"].tap()
        XCTAssertTrue(app.staticTexts["You showed up."].waitForExistence(timeout: 5))
        app.buttons["Back to Today"].tap()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Laptop · Recorded footage"].waitForExistence(timeout: 5))
        capture(app, name: "Recorded Laptop progress")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
