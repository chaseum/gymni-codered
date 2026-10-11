// Single source of UI state: mirrors the backend session. Never increments reps locally.
import Foundation
import Observation

@MainActor @Observable
public final class WorkoutStore {
    public enum Connection: Equatable, Sendable { case disconnected, connecting, connected, failed(String) }

    public private(set) var connection: Connection = .disconnected
    public private(set) var snapshot: Snapshot?
    public private(set) var coach: CoachState = .idle
    public private(set) var lastFeedback: FeedbackIssued?
    public private(set) var lastCoachingCue: CoachingCue?
    public private(set) var lastEventId = -1
    /// Hook for coach playback and haptics.
    public var onEvent: ((WorkoutEvent) -> Void)?

    public let baseURL: URL          // e.g. http://192.168.1.20:8000 — user-configured, never hardcoded
    public let sessionId: String
    private let token: String?
    private var task: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?

    public init(baseURL: URL, sessionId: String, token: String? = nil) {
        self.baseURL = baseURL; self.sessionId = sessionId; self.token = token
    }

    public func connect() {
        task?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        task = Task { [weak self] in
            var delay: UInt64 = 500_000_000
            while !Task.isCancelled, let self {
                await self.listenOnce()
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: delay)   // reconnect; backend resends a snapshot
                delay = min(delay * 2, 8_000_000_000)
            }
        }
    }

    public func disconnect() {
        task?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        task = nil
        socket = nil
        connection = .disconnected
    }

    private func listenOnce() async {
        var comps = URLComponents(url: baseURL.appending(path: "ws/workout"), resolvingAgainstBaseURL: false)!
        comps.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        comps.queryItems = [URLQueryItem(name: "session_id", value: sessionId)] + (token.map { [URLQueryItem(name: "token", value: $0)] } ?? [])
        let ws = URLSession.shared.webSocketTask(with: comps.url!)
        socket = ws
        connection = .connecting
        ws.resume()
        defer { ws.cancel(with: .goingAway, reason: nil) }
        do {
            while !Task.isCancelled {
                let msg = try await ws.receive()
                guard !Task.isCancelled else { return }
                connection = .connected
                guard case .string(let text) = msg else { continue }
                apply(try Contracts.decoder.decode(WorkoutEvent.self, from: Data(text.utf8)))
            }
        } catch {
            if !Task.isCancelled { connection = .failed(error.localizedDescription) }
        }
    }

    /// Public so previews/tests can feed fixture events.
    public func apply(_ event: WorkoutEvent) {
        if case .snapshot(let snap) = event.payload {   // snapshot always wins, then resets the dedupe cursor
            snapshot = snap; lastEventId = event.eventId; lastCoachingCue = nil
            onEvent?(event); return
        }
        guard event.eventId > lastEventId else { return }  // duplicate/replayed
        lastEventId = event.eventId
        guard var s = snapshot else { return }
        switch event.payload {
        case .sessionState(let p): s.state = p.state; if p.state != .active { lastCoachingCue = nil }
        case .exerciseChanged(let p): s.exercise = p.exercise; s.setId = p.setId; s.targetReps = p.targetReps; s.repCount = 0; s.activeIssues = []; lastFeedback = nil; lastCoachingCue = nil
        case .tracking(let p): s.trackingStatus = p.status; s.source = p.source; if p.status != .ready { lastCoachingCue = nil }
        case .repCompleted(let p): s.repCount = p.repCount; lastCoachingCue = nil
        case .coach(let p): coach = p.coach
        case .coachingCue(let p): if p.isCurrent(in: s) { lastCoachingCue = p }
        case .feedbackIssued(let p):
            lastFeedback = p; lastCoachingCue = nil
            if !s.activeIssues.contains(p.issueCode) { s.activeIssues.append(p.issueCode) }
        case .feedbackImproved(let p): s.activeIssues.removeAll { $0 == p.issueCode }
        case .heartRate(let hr): s.heartRate = hr
        case .rest(let r): s.rest = r.status == .resting ? r : nil
        default: break
        }
        snapshot = s
        onEvent?(event)
    }

    @discardableResult
    public func send(_ intent: Intent, args: CommandArgs? = nil) async throws -> CommandAck {
        try await post("commands", Command(sessionId: sessionId, intent: intent, args: args))
    }

    public func fetchCueAudio(cueID: String) async throws -> Data {
        let filename: String
        if cueID.hasPrefix("dynamic/"),
           let dynamicID = cueID.split(separator: "/").last,
           dynamicID.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil {
            filename = "dynamic/\(dynamicID).mp3"
        } else if cueID.range(of: #"^[a-z_]+\.[a-z_]+$"#, options: .regularExpression) != nil {
            filename = "\(cueID).mp3"
        } else {
            throw URLError(.badURL, userInfo: [NSLocalizedDescriptionKey: "Invalid generated cue ID."])
        }

        return try await fetchAudio(path: "audio/\(filename)")
    }

    public func fetchCoachAudio(cue: CoachVoiceCue) async throws -> Data {
        try await fetchAudio(path: "api/coach/audio/\(cue.rawValue)")
    }

    public func fetchCoachingAudio(cue: CoachingCue) async throws -> Data {
        guard cue.cueId.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            throw URLError(.badURL)
        }
        return try await fetchAudio(path: "api/sessions/\(sessionId)/coaching/\(cue.cueId)/audio")
    }

    private func fetchAudio(path: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.timeoutInterval = 9
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              response.mimeType?.hasPrefix("audio/") == true, !data.isEmpty else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Generated coach audio is unavailable."])
        }
        return data
    }

    public func post<Body: Encodable, Response: Decodable>(_ route: String, _ body: Body) async throws -> Response {
        var req = URLRequest(url: baseURL.appending(path: "api/sessions/\(sessionId)/\(route)"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try Contracts.encoder.encode(body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self)])
        }
        return try Contracts.decoder.decode(Response.self, from: data)
    }
}
