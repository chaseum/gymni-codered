import SwiftUI

struct UnmeasuredRepsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("—").font(.system(size: 72, weight: .bold, design: .rounded))
            Text("Rep tracking awaits trained model").foregroundStyle(GymTheme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reps not measured. Awaiting trained model.")
    }
}
