import SwiftUI

struct BrandLogoView: View {
    var body: some View {
        Image("GymAILogo")
            .resizable()
            .scaledToFill()
            .frame(width: 80, height: 36)
            .clipped()
            .padding(4)
            .accessibilityLabel("Gym&I")
    }
}
