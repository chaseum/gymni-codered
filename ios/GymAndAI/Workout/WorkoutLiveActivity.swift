import ActivityKit
import Foundation
import GymAndAIKit

/// Mirrors the current workout onto the Lock Screen and Dynamic Island.
enum WorkoutLiveActivity {
    typealias State = WorkoutActivityAttributes.ContentState

    @MainActor static func state(for session: WorkoutSession) -> State {
        let rate = session.heartRate
        let snapshot = session.snapshot
        let activeCue = session.store.lastFeedback.flatMap { feedback in
            feedback.setId == snapshot?.setId && snapshot?.activeIssues.contains(feedback.issueCode) == true ? feedback.text : nil
        }
        let measuresForm = !session.isPhone && session.hasConnection && snapshot?.trackingStatus == .ready
        let status = switch snapshot?.state {
        case .active: snapshot?.trackingStatus == .ready || session.isPhone ? "Active" : session.trackingMessage
        case .paused: "Resting"
        case .complete: "Done"
        default: "Getting ready"
        }
        return State(
            bpm: rate.status == .live ? rate.bpm.map { Int($0.rounded()) } : nil,
            reps: session.repCount, targetReps: session.targetReps, status: status,
            form: activeCue ?? (measuresForm ? "Good form" : nil),
            formIssue: activeCue != nil,
            restEndsAt: snapshot?.state == .paused ? snapshot?.rest?.endsAtMs.map { Date(timeIntervalSince1970: Double($0) / 1_000) } : nil
        )
    }

    static func update(_ state: State, exercise: String) async {
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity = Activity<WorkoutActivityAttributes>.activities.first {
            await activity.update(content)
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity.request(attributes: WorkoutActivityAttributes(exercise: exercise), content: content)
        }
    }

    static func end(_ state: State) async {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }
}
