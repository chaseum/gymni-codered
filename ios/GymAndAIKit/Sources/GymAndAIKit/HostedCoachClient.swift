import CryptoKit
import Foundation

/// A stateless audio gateway, with a persistent cache on the phone for cold starts and offline replay.
public actor HostedCoachClient {
    private let baseURL: URL
    private let token: String?
    private let network: URLSession
    private let directory: URL
    private var configuration: HostedVoiceConfiguration?
    private var inFlight: [String: Task<Data, Error>] = [:]

    public init(baseURL: URL, token: String? = nil, cacheDirectory: URL? = nil, network: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.network = network
        let root = cacheDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "GymAndAI/Voice")
        directory = root.appending(path: Self.hash(Data(baseURL.absoluteString.utf8)))
    }

    public func prepare() async throws {
        let (data, response) = try await network.data(for: request(path: "api/coach/configuration"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let config = try Contracts.decoder.decode(HostedVoiceConfiguration.self, from: data)
        guard config.voiceProvider == "elevenlabs", config.voiceAvailable else { throw URLError(.resourceUnavailable) }
        configuration = config
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appending(path: "configuration.json"), options: .atomic)
    }

    public func audio(for cue: HostedVoiceRequest) async throws -> Data {
        if configuration == nil {
            if let data = try? Data(contentsOf: directory.appending(path: "configuration.json")) {
                configuration = try? Contracts.decoder.decode(HostedVoiceConfiguration.self, from: data)
            }
            if configuration == nil { try await prepare() }
        }
        guard let configuration else { throw URLError(.resourceUnavailable) }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        let body = try encoder.encode(cue)
        let key = Self.hash(body + Data(configuration.voiceRevision.utf8))
        let path = directory.appending(path: key + ".mp3")
        if let cached = try? Data(contentsOf: path), !cached.isEmpty { return cached }
        if let existing = inFlight[key] { return try await existing.value }
        var request = request(path: "api/coach/voice")
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let network = network
        let task = Task<Data, Error> {
            let (data, response) = try await network.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  response.mimeType == "audio/mpeg", !data.isEmpty else { throw URLError(.badServerResponse) }
            return data
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let audio = try await task.value
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? audio.write(to: path, options: .atomic)
        return audio
    }

    public func warm(exercise: Exercise, target: Int) async {
        var cues = [CoachVoiceCue.waiting, .positioning, .trackingReady, .trackingLost, .paused, .ended, .begin].map(HostedVoiceRequest.prompt)
        cues += HubSession.cues.keys.filter { $0.hasPrefix(exercise.rawValue + ".") }.map { HostedVoiceRequest(kind: "form", code: $0) }
        cues += [HostedVoiceRequest(kind: "pace_fast"), HostedVoiceRequest(kind: "pace_slow")]
        cues += (1...target).filter { RepCoach.countText($0, target: target) != nil }.map { HostedVoiceRequest(kind: "count", repCount: $0, targetReps: target) }
        // Sequential warming bounds provider concurrency; repeated cues use the phone cache.
        for cue in cues {
            guard !Task.isCancelled else { return }
            _ = try? await audio(for: cue)
        }
    }

    private func request(path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.timeoutInterval = 35
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
