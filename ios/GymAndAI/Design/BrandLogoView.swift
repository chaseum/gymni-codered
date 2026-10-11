import SwiftUI

struct BrandLogoView: View {
    var body: some View {
        Image("GymAILogo")
            .resizable()
            .scaledToFit()
            .frame(width: 80, height: 36)
            .padding(4)
            .background(.white, in: .rect(cornerRadius: 8))
            .accessibilityLabel("Gym&AI")
    }
}
