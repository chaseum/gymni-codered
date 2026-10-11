import SwiftUI
import GymAndAIKit

struct OnboardingChoiceRow: View {
    let choice: OnboardingChoice
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: GymTheme.Space.inset) {
                VStack(alignment: .leading, spacing: GymTheme.Space.tight) {
                    Text(choice.title).font(.headline).foregroundStyle(GymTheme.text)
                    if !choice.detail.isEmpty {
                        Text(choice.detail).font(.subheadline).foregroundStyle(GymTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? GymTheme.accentText : GymTheme.muted)
                    .accessibilityHidden(true)
            }
            .padding(GymTheme.Space.inset)
            .frame(minHeight: 64)
            .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: GymTheme.controlRadius)
                    .strokeBorder(selected ? GymTheme.accentText : GymTheme.divider, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("onboarding-choice-\(choice.id)")
    }
}
