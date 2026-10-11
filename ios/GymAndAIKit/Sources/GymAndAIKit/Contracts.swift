// Swift mirror of contracts/gymai.schema.json (v1). The schema is authoritative; keep this in sync.
// Wire format is snake_case; use `Contracts.decoder` / `Contracts.encoder`.
import Foundation

public enum Contracts {
    public static let schemaVersion = 1
    public static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d
    }
    public static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.keyEncodingStrategy = .convertToSnakeCase; return e
    }
}

public enum Exercise: String, Codable, Sendable, CaseIterable { case curl, squat, deadlift }
public enum SessionState: String, Codable, Sendable { case ready, active, paused, complete }
public enum InputSource: String, Codable, Sendable { case live, recorded }
public enum TrackingStatus: String, Codable, Sendable { case ready, lowVisibility = "low_visibility", lost, unassessable }
public enum CoachState: String, Codable, Sendable { case idle, observing, correcting, encouraging, resting }

public struct Load: Codable, Sendable, Equatable {
    public enum Unit: String, Codable, Sendable { case lb, kg }
    public var value: Double
    public var unit: Unit
    public init(value: Double, unit: Unit) { self.value = value; self.unit = unit }
}

public struct HeartRateView: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case live, stale, unavailable }
    public var status: Status
    public var bpm: Double?          // nil whenever unavailable; never synthesize
    public var sampleId: String?
    public var sampleTimestampMs: Int64?
    public var source: String?
    /// Apple Health syncs Watch samples in irregular batches, so readings can be minutes old on arrival.
    // ponytail: one window for all sources; split per source if the Gym&AI Watch app ever installs again.
    public static let maxSampleAge: TimeInterval = 600
    public static let unavailable = HeartRateView(status: .unavailable, bpm: nil, sampleId: nil, sampleTimestampMs: nil, source: nil)
}

public struct RestView: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case resting, ended }
    public var status: Status
    public var endsAtMs: Int64?      // epoch; reaching it does NOT resume the session
}

// MARK: Backend -> phone events

public struct Snapshot: Codable, Sendable, Equatable {
    public var state: SessionState
    public var source: InputSource?
    public var exercise: Exercise?
    public var setId: String?
    public var repCount: Int
    public var targetReps: Int?
    public var trackingStatus: TrackingStatus?
    public var heartRate: HeartRateView
    public var rest: RestView?
    public var activeIssues: [String]
}
public struct SessionStatePayload: Codable, Sendable { public var state: SessionState; public var commandId: String? }
public struct ExerciseChanged: Codable, Sendable { public var exercise: Exercise; public var setId: String; public var targetReps: Int? }
public struct TrackingPayload: Codable, Sendable { public var status: TrackingStatus; public var source: InputSource }
public struct RepCompleted: Codable, Sendable {
    public var exercise: Exercise; public var setId: String; public var repCount: Int
    public var targetReps: Int?; public var durationMs: Double?
}
public struct CoachPayload: Codable, Sendable { public var coach: CoachState }
public struct FeedbackIssued: Codable, Sendable {
    public var feedbackId: String; public var issueCode: String; public var cueId: String?
    public var text: String; public var setId: String; public var repCount: Int
}
public struct FeedbackImproved: Codable, Sendable {
    public var feedbackId: String; public var issueCode: String; public var setId: String; public var repCount: Int
}
public struct UserFeedbackAck: Codable, Sendable { public var inputId: String; public var kind: String; public var value: String? }
public struct SetCompleted: Codable, Sendable { public var setId: String; public var exercise: Exercise; public var repCount: Int; public var load: Load? }
public struct PRAchieved: Codable, Sendable {
    public var exercise: Exercise; public var metric: String; public var value: Double
    public var previousBest: Double?; public var load: Load?
}
public struct DeviceStatus: Codable, Sendable { public var device: String; public var status: String }

public enum EventPayload: Sendable {
    case snapshot(Snapshot), sessionState(SessionStatePayload), exerciseChanged(ExerciseChanged)
    case tracking(TrackingPayload), repCompleted(RepCompleted), coach(CoachPayload)
    case feedbackIssued(FeedbackIssued), feedbackImproved(FeedbackImproved), heartRate(HeartRateView)
    case userFeedbackAcknowledged(UserFeedbackAck), rest(RestView), setCompleted(SetCompleted)
    case prAchieved(PRAchieved), deviceStatus(DeviceStatus)
    case unknown(String)  // future event types: ignore, don't crash
}

public struct WorkoutEvent: Decodable, Sendable {
    public var schemaVersion: Int
    public var eventId: Int
    public var sessionId: String
    public var timestampMs: Int64
    public var type: String
    public var payload: EventPayload

    enum CodingKeys: String, CodingKey { case schemaVersion, eventId, sessionId, timestampMs, type, payload }

    init(schemaVersion: Int, eventId: Int, sessionId: String, timestampMs: Int64, type: String, payload: EventPayload) {
        self.schemaVersion = schemaVersion
        self.eventId = eventId
        self.sessionId = sessionId
        self.timestampMs = timestampMs
        self.type = type
        self.payload = payload
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        eventId = try c.decode(Int.self, forKey: .eventId)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        timestampMs = try c.decode(Int64.self, forKey: .timestampMs)
        type = try c.decode(String.self, forKey: .type)
        func p<T: Decodable>(_: T.Type) throws -> T { try c.decode(T.self, forKey: .payload) }
        switch type {
        case "session.snapshot": payload = .snapshot(try p(Snapshot.self))
        case "session.state": payload = .sessionState(try p(SessionStatePayload.self))
        case "exercise.changed": payload = .exerciseChanged(try p(ExerciseChanged.self))
        case "tracking.status": payload = .tracking(try p(TrackingPayload.self))
        case "rep.completed": payload = .repCompleted(try p(RepCompleted.self))
        case "coach.state": payload = .coach(try p(CoachPayload.self))
        case "feedback.issued": payload = .feedbackIssued(try p(FeedbackIssued.self))
        case "feedback.improved": payload = .feedbackImproved(try p(FeedbackImproved.self))
        case "heart_rate.updated": payload = .heartRate(try p(HeartRateView.self))
        case "user_feedback.acknowledged": payload = .userFeedbackAcknowledged(try p(UserFeedbackAck.self))
        case "rest.updated": payload = .rest(try p(RestView.self))
        case "set.completed": payload = .setCompleted(try p(SetCompleted.self))
        case "history.pr_achieved": payload = .prAchieved(try p(PRAchieved.self))
        case "device.status": payload = .deviceStatus(try p(DeviceStatus.self))
        default: payload = .unknown(type)
        }
    }
}

// MARK: Phone/Watch -> backend

public enum Intent: String, Codable, Sendable { case start, pause, resume, end, rest, extendRest = "extend_rest", nextExercise = "next_exercise" }

public struct CommandArgs: Codable, Sendable {
    public var exercise: Exercise?
    public var targetReps: Int?
    public var source: InputSource?
    public var restSeconds: Int?
    public var load: Load?
    public init(exercise: Exercise? = nil, targetReps: Int? = nil, source: InputSource? = nil, restSeconds: Int? = nil, load: Load? = nil) {
        self.exercise = exercise; self.targetReps = targetReps; self.source = source; self.restSeconds = restSeconds; self.load = load
    }
}

public struct Command: Codable, Sendable {
    public var commandId: String     // generate once; reuse on retry so the backend dedupes
    public var sessionId: String
    public var intent: Intent
    public var origin: String
    public var args: CommandArgs?
    public init(sessionId: String, intent: Intent, args: CommandArgs? = nil, origin: String = "phone", commandId: String = UUID().uuidString) {
        self.commandId = commandId; self.sessionId = sessionId; self.intent = intent; self.origin = origin; self.args = args
    }
}

public struct CommandAck: Codable, Sendable {
    public var commandId: String
    public var accepted: Bool
    public var duplicate: Bool
    public var state: SessionState
    public var error: String?
}

/// Response to observation / heart-rate POSTs.
public struct IngestAck: Codable, Sendable { public var accepted: Bool; public var duplicate: Bool; public var ignored: String? }

public struct HeartRateSample: Codable, Sendable {
    public var sampleId: String
    public var sessionId: String
    public var participantId: String
    public var bpm: Double
    public var sampleTimestampMs: Int64   // HKQuantitySample.endDate, not "now"
    public var source: String = "apple_watch"
    public init(sampleId: String, sessionId: String, participantId: String, bpm: Double, sampleDate: Date) {
        self.sampleId = sampleId; self.sessionId = sessionId; self.participantId = participantId
        self.bpm = bpm; self.sampleTimestampMs = Int64(sampleDate.timeIntervalSince1970 * 1000)
    }
}
