import ActivityKit
import GymAndAIKit
import SwiftUI
import WidgetKit

@main
struct GymAndAILiveActivityBundle: WidgetBundle {
    var body: some Widget { WorkoutLiveActivityWidget() }
}

private let accent = Color(red: 0, green: 151 / 255, blue: 178 / 255)
private typealias State = WorkoutActivityAttributes.ContentState

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Gym&AI · \(context.attributes.exercise)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    StatusText(state: context.state).font(.caption.weight(.semibold))
                }
                HStack(alignment: .firstTextBaseline) {
                    HeartRate(state: context.state).font(.title.bold())
                    Spacer()
                    Reps(state: context.state).font(.title.bold())
                }
                if let form = context.state.form { Form(text: form, issue: context.state.formIssue).font(.subheadline) }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
            .activitySystemActionForegroundColor(accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { HeartRate(state: context.state).font(.title3.bold()) }
                DynamicIslandExpandedRegion(.trailing) { Reps(state: context.state).font(.title3.bold()) }
                DynamicIslandExpandedRegion(.center) {
                    StatusText(state: context.state).font(.caption).foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let form = context.state.form { Form(text: form, issue: context.state.formIssue).font(.caption) }
                }
            } compactLeading: {
                HeartRate(state: context.state)
            } compactTrailing: {
                Text("\(context.state.reps)")
                    .foregroundStyle(context.state.formIssue ? .orange : accent).monospacedDigit()
            } minimal: {
                Image(systemName: context.state.formIssue ? "exclamationmark.triangle.fill" : "heart.fill")
                    .foregroundStyle(context.state.formIssue ? .orange : .red)
            }
        }
    }
}

private struct HeartRate: View {
    let state: State
    var body: some View {
        Label(state.bpm.map { "\($0)" } ?? "—", systemImage: "heart.fill")
            .foregroundStyle(.red).monospacedDigit()
    }
}

private struct Reps: View {
    let state: State
    var body: some View {
        Text(state.targetReps.map { "\(state.reps)/\($0)" } ?? "\(state.reps) reps")
            .foregroundStyle(accent).monospacedDigit()
    }
}

private struct StatusText: View {
    let state: State
    var body: some View {
        if let end = state.restEndsAt, end > .now {
            Text("Rest ") + Text(timerInterval: .now...end, countsDown: true)
        } else {
            Text(state.status)
        }
    }
}

private struct Form: View {
    let text: String
    let issue: Bool
    var body: some View {
        Label(text, systemImage: issue ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .foregroundStyle(issue ? .orange : .green)
            .lineLimit(2)
    }
}
