import Foundation
import Testing
@testable import GymAndAIKit

private final class SummaryFixture: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var offline = true
    nonisolated(unsafe) private static var count = 0
    static func connect() { lock.withLock { offline = false } }
    static var posts: Int { lock.withLock { count } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "workout-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.lock.withLock({ Self.offline }) {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        Self.lock.withLock { Self.count += 1 }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"workout_id":"00000000-0000-0000-0000-000000000001","total_reps":0}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func completedJournalsRetryAfterOfflineAndSavedSummariesPreventRepeatUploads() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "workout-relay-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let completed = WorkoutJournal.Document(workoutId: "00000000-0000-0000-0000-000000000001", state: .complete)
    try Contracts.encoder.encode(completed).write(to: directory.appending(path: "done.json"))
    try Contracts.encoder.encode(WorkoutJournal.Document(state: .active)).write(to: directory.appending(path: "active.json"))
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SummaryFixture.self]
    let network = URLSession(configuration: config)
    defer { network.invalidateAndCancel() }
    let relay = HostedWorkoutRelay(baseURL: URL(string: "https://workout-fixture.invalid")!, network: network)
    do {
        try await relay.sync(directory: directory)
        Issue.record("An offline request should leave the journal pending.")
    } catch { #expect((error as? URLError)?.code == .notConnectedToInternet) }
    #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "done.summary.json").path))
    SummaryFixture.connect()
    try await relay.sync(directory: directory)
    try await relay.sync(directory: directory)
    #expect(SummaryFixture.posts == 1)
    #expect(FileManager.default.fileExists(atPath: directory.appending(path: "done.summary.json").path))
    #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "active.summary.json").path))
}
