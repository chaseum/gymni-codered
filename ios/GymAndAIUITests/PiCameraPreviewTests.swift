import XCTest
import Network
import UIKit

final class PiCameraPreviewTests: XCTestCase {
    @MainActor
    func testLivePreviewExpandsAndReconnectsAfterStreamCloses() throws {
        // A JPEG transport fixture, not model observations or simulated rep counts.
        let jpeg = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48)).image { context in
            UIColor.cyan.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        }.jpegData(compressionQuality: 0.8))
        let fixture = try PreviewFixture(jpeg: jpeg)
        defer { fixture.stop() }
        let ready = expectation(description: "Preview fixture listening")
        fixture.start { ready.fulfill() }
        wait(for: [ready], timeout: 5)
        let port = try XCTUnwrap(fixture.port)
        let app = XCUIApplication()
        app.launchArguments = ["--gymni-ui-testing", "--gymni-hub", "--hub-port", "\(port - 1)",
                               "--preview-url", "http://127.0.0.1:\(port)"]
        app.launch()
        defer { app.terminate() }
        let preview = app.buttons["open-pi-camera"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10), app.debugDescription)
        let reconnected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in fixture.requests >= 2 }, object: nil)
        wait(for: [reconnected], timeout: 10)
        preview.tap()
        let back = app.buttons["camera-back-to-reps"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.images["pi-camera-frame"].waitForExistence(timeout: 10), app.debugDescription)
        back.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Pause"].exists)
    }
}

private final class PreviewFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "gymni.preview-test")
    private let response: Data
    private var requestCount = 0
    var port: UInt16? { listener.port?.rawValue }
    var requests: Int { queue.sync { requestCount } }

    init(jpeg: Data) throws {
        listener = try NWListener(using: .tcp, on: .any)
        response = Data("HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\nConnection: close\r\n\r\n--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n".utf8) + jpeg + Data("\r\n--frame--\r\n".utf8)
    }

    func start(ready: @escaping @Sendable () -> Void) {
        listener.stateUpdateHandler = { if case .ready = $0 { ready() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return connection.cancel() }
            connection.start(queue: self.queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                self.requestCount += 1
                connection.send(content: self.response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
    }

    func stop() { listener.cancel() }
}
