import Foundation
import Testing
@testable import GymAndAIKit

private final class VoiceFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var revision = "voice-one"
    private var offline = false
    private var posts = 0
    private var bodies: [Data] = []
    func reset() { lock.withLock { revision = "voice-one"; offline = false; posts = 0; bodies = [] } }
    func goOffline() { lock.withLock { offline = true } }
    func changeVoice() { lock.withLock { offline = false; revision = "voice-two" } }
    var count: Int { lock.withLock { posts } }
    var requests: [Data] { lock.withLock { bodies } }
    func response(_ request: URLRequest) throws -> (Data, String) {
        try lock.withLock {
            if offline { throw URLError(.notConnectedToInternet) }
            if request.url!.path.hasSuffix("configuration") {
                return (Data("{\"voice_provider\":\"elevenlabs\",\"voice_available\":true,\"voice_revision\":\"\(revision)\"}".utf8), "application/json")
            }
            posts += 1
            if let body = request.httpBody { bodies.append(body) }
            else if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                var data = Data()
                while stream.hasBytesAvailable {
                    let size = stream.read(&buffer, maxLength: buffer.count)
                    if size <= 0 { break }
                    data.append(contentsOf: buffer.prefix(size))
                }
                bodies.append(data)
            }
            return (Data("fixture-mp3-\(revision)".utf8), "audio/mpeg")
        }
    }
}

private final class VoiceFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let fixture = VoiceFixtureState()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "voice-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (data, type) = try Self.fixture.response(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": type])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Test func elevenLabsClipsSurviveRelaunchOfflineAndInvalidateOnVoiceChange() async throws {
    VoiceFixtureProtocol.fixture.reset()
    let directory = FileManager.default.temporaryDirectory.appending(path: "voice-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [VoiceFixtureProtocol.self]
    let network = URLSession(configuration: config)
    defer { network.invalidateAndCancel() }
    let url = URL(string: "https://voice-fixture.invalid")!
    let cue = HostedVoiceRequest(kind: "count", repCount: 4, targetReps: 8)
    let first = HostedCoachClient(baseURL: url, cacheDirectory: directory, network: network)
    try await first.prepare()
    let audio = try await first.audio(for: cue)
    #expect(try await first.audio(for: cue) == audio)
    #expect(VoiceFixtureProtocol.fixture.count == 1)
    VoiceFixtureProtocol.fixture.goOffline()
    let reopened = HostedCoachClient(baseURL: url, cacheDirectory: directory, network: network)
    #expect(try await reopened.audio(for: cue) == audio)
    #expect(VoiceFixtureProtocol.fixture.count == 1)
    VoiceFixtureProtocol.fixture.changeVoice()
    try await reopened.prepare()
    #expect(try await reopened.audio(for: cue) != audio)
    #expect(VoiceFixtureProtocol.fixture.count == 2)
    let body = try #require(VoiceFixtureProtocol.fixture.requests.first)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["rep_count"] as? Int == 4)
    #expect(json["text"] == nil && json["observations"] == nil)
}
