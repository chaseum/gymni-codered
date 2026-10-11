import SwiftUI

struct OctobuddyView: View {
    var resting = false

    var body: some View {
        ZStack {
            Circle().fill(GymTheme.accentText).frame(width: 58, height: 58).offset(y: -6)
            HStack(spacing: -4) {
                ForEach(0..<4) { _ in
                    Ellipse().fill(GymTheme.accentText).frame(width: 25, height: 20)
                }
            }
            .offset(y: 24)
            Text(resting ? "˘‿˘" : "•‿•")
                .font(.title3.bold())
                .foregroundStyle(GymTheme.background)
                .offset(y: -4)
        }
        .frame(width: 88, height: 80)
        .accessibilityHidden(true)
    }
}
