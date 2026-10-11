import SwiftUI
import GymAndAIKit

struct OnboardingChoiceRow: View {
    let choice: OnboardingChoice
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: GymTheme.Space.inset) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.title).font(.headline)
                    if !choice.detail.isEmpty {
                        Text(choice.detail).font(.subheadline).foregroundStyle(GymTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? GymTheme.accent : GymTheme.muted)
                    .accessibilityHidden(true)
            }
            .padding(GymTheme.Space.inset)
            .frame(minHeight: 60)
            .background(selected ? GymTheme.accent.opacity(0.16) : GymTheme.surface, in: .rect(cornerRadius: GymTheme.radius))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("onboarding-choice-\(choice.id)")
    }
}
