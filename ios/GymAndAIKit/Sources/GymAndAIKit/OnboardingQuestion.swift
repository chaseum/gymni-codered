import Foundation

public enum OnboardingQuestion: String, Codable, CaseIterable, Sendable, Identifiable {
    case goal, experience, activity, days, duration, equipment, style, motivation
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .goal: "What do you want to work toward?"
        case .experience: "Where are you starting from?"
        case .activity: "How active is your usual day?"
        case .days: "How often can you get to the gym?"
        case .duration: "How much time can you set aside?"
        case .equipment: "What will you train with most?"
        case .style: "What kind of training appeals to you?"
        case .motivation: "What would make you feel proud?"
        }
    }
    public var detail: String {
        switch self {
        case .goal: "Choose what matters most right now. You can change it later."
        case .experience: "An honest starting point helps us understand your routine."
        case .activity: "Think about work, walking, and movement outside the gym."
        case .days: "Choose a schedule you could keep on a busy week."
        case .duration: "Include the time you need to warm up and take breaks."
        case .equipment: "Choose the setup you expect to use most often."
        case .style: "There’s no right answer. Pick the one you’d look forward to."
        case .motivation: "This helps us match your training focus and companion."
        }
    }
    public var choices: [OnboardingChoice] {
        switch self {
        case .goal: [
            .init("strength", "Get stronger", "Move more weight with control.", focus: .strength),
            .init("muscle", "Build muscle", "Focus on muscle growth.", focus: .muscle),
            .init("fitness", "Feel fitter", "Build energy and a regular routine.", focus: .fitness),
            .init("unsure", "Help me choose", "Let my other answers guide the match.")]
        case .experience: [.init("new", "Just starting"), .init("returning", "Getting back into it"), .init("regular", "Training regularly"), .init("experienced", "Training for years")]
        case .activity: [.init("seated", "Mostly sitting", "Little movement during the day."), .init("light", "Some movement", "Short walks and everyday tasks."), .init("active", "Often on my feet", "Regular walking or physical work."), .init("very_active", "Very active", "Physical work or frequent sport.")]
        case .days: [.init("1", "1 day a week"), .init("2", "2 days a week"), .init("3", "3 days a week"), .init("4", "4 days a week"), .init("5", "5 or more days a week")]
        case .duration: [.init("20", "About 20 minutes"), .init("30", "About 30 minutes"), .init("45", "About 45 minutes"), .init("60", "An hour or more")]
        case .equipment: [.init("gym", "Full gym", "Machines, cables, and free weights."), .init("dumbbells", "Dumbbells"), .init("barbell", "Barbell and plates"), .init("bodyweight", "Bodyweight or minimal equipment")]
        case .style: [.init("strength", "Focused lifts", "Work toward stronger, controlled lifts.", focus: .strength), .init("muscle", "Muscle-focused sets", "Spend time training specific muscle groups.", focus: .muscle), .init("fitness", "A mix of movement", "Combine resistance work and conditioning.", focus: .fitness)]
        case .motivation: [.init("strength", "Lifting more than I can today", focus: .strength), .init("muscle", "Seeing muscle growth", focus: .muscle), .init("fitness", "Having more energy and consistency", focus: .fitness)]
        }
    }
    public var focusWeight: Int {
        switch self { case .goal: 6; case .style: 3; case .motivation: 2; default: 0 }
    }
}
