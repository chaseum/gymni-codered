import SwiftUI
import GymAndAIKit

struct OnboardingMatchView: View {
    @Bindable var store: OnboardingStore
    private var focus: TrainingFocus { store.draft.selectedFocus ?? store.draft.recommendedFocus }

    var body: some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.section) {
            Text("Meet \(focus.companion.capitalized)")
                .font(GymTheme.TypeStyle.title)
                .accessibilityIdentifier("onboarding-match-title")
                .accessibilityAddTraits(.isHeader)
            Text(focus.detail).foregroundStyle(GymTheme.muted)
            CompanionSceneView(state: .celebrate, companion: CompanionKind(rawValue: focus.companion) ?? .pip)
                .id(focus)
                .frame(height: 210)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: GymTheme.Space.related) {
                Text("Your training focus").font(.headline)
                ForEach(TrainingFocus.allCases) { option in
                    OnboardingChoiceRow(choice: OnboardingChoice(id: option.rawValue, title: option.title), selected: focus == option) {
                        store.draft.selectedFocus = option
                    }
                }
            }
            Text("Your goal, preferred training, and motivation guide this match. Change it here if another focus feels better.")
                .font(.subheadline).foregroundStyle(GymTheme.muted)
            Divider().overlay(GymTheme.divider)
            VStack(alignment: .leading, spacing: GymTheme.Space.related) {
                Text("Your routine").font(.headline)
                summary(.experience)
                summary(.days)
                summary(.duration)
                summary(.equipment)
            }
            Button("Edit answers") { store.draft.step = 0 }
                .frame(minHeight: 44)
            Text("Your answers and companion will be saved. You can start the app’s current single-set workouts next.")
                .font(.subheadline).foregroundStyle(GymTheme.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func summary(_ question: OnboardingQuestion) -> some View {
        let choice = question.choices.first { $0.id == store.draft.answers[question.rawValue] }
        return Text(choice?.title ?? "Not answered").font(.body).foregroundStyle(GymTheme.muted)
    }
}
