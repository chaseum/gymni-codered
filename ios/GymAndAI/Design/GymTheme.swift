import SwiftUI

enum GymTheme {
    static let background = Color(red: 40 / 255, green: 50 / 255, blue: 57 / 255)
    static let charcoal = Color(red: 14 / 255, green: 20 / 255, blue: 24 / 255)
    static let surface = Color(red: 27 / 255, green: 39 / 255, blue: 45 / 255)
    static let accent = Color(red: 0, green: 151 / 255, blue: 178 / 255)
    static let accentText = Color(red: 110 / 255, green: 202 / 255, blue: 219 / 255)
    static let text = Color(red: 242 / 255, green: 246 / 255, blue: 245 / 255)
    static let muted = Color(red: 184 / 255, green: 197 / 255, blue: 203 / 255)
    static let divider = Color.white.opacity(0.12)

    enum Space {
        static let tight: CGFloat = 4
        static let small: CGFloat = 8
        static let related: CGFloat = 12
        static let inset: CGFloat = 16
        static let section: CGFloat = 20
        static let page: CGFloat = 24
        static let generous: CGFloat = 32
    }

    enum TypeStyle {
        static let title = Font.system(.largeTitle, design: .rounded).bold()
        static let heading = Font.title2.bold()
        static let label = Font.subheadline.bold()
        static let detail = Font.subheadline
    }

    static let spacing = Space.page
    static let radius: CGFloat = 24
    static let controlRadius: CGFloat = 16
    static let compactRadius: CGFloat = 12
    static let contentWidth: CGFloat = 600
    static let controlHeight: CGFloat = 52
}
