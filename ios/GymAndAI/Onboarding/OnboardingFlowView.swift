import SwiftUI
import GymAndAIKit

struct OnboardingFlowView: View {
    @Bindable var store: OnboardingStore
    var isEditing = false
    let onComplete: () -> Void
    @AppStorage("companion") private var companion = CompanionKind.pip
    @FocusState private var fieldFocused: OnboardingMetric?
    @State private var savingError = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var headingFocused: Bool
    private let questions = OnboardingQuestion.allCases
    private var isReview: Bool { store.draft.step == questions.count + 1 }
    private var question: OnboardingQuestion? {
        questions.indices.contains(store.draft.step - 1) ? questions[store.draft.step - 1] : nil
    }
    private var canContinue: Bool {
        if store.draft.step == 0 { return store.draft.metricsAreValid }
        if isReview { return store.draft.isComplete }
        guard let question else { return false }
        return question.choices.contains { $0.id == store.draft.answers[question.rawValue] }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: GymTheme.Space.section) {
                        if store.draft.step == 0 {
                            OnboardingMetricsView(store: store, fieldFocus: $fieldFocused)
                        } else if let question {
                            questionContent(question)
                        } else {
                            OnboardingMatchView(store: store)
                        }
                        if savingError { Text("Your profile could not be saved. Try again.") }
                    }
                    .padding(GymTheme.Space.page)
                    .frame(maxWidth: GymTheme.contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .id("onboarding-top")
                }
                .scrollDismissesKeyboard(.interactively)
                .task(id: fieldFocused) {
                    guard let metric = fieldFocused else { return }
                    do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                    reader.scrollTo(metric, anchor: .center)
                }
                .onChange(of: store.draft.step) {
                    reader.scrollTo("onboarding-top", anchor: .top)
                    headingFocused = true
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GymActionDock {
                Button(isReview ? "Start with \(currentFocus.companion.capitalized)" : "Continue", action: advance)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canContinue)
                    .accessibilityIdentifier("onboarding-continue")
            }
        }
        .background(GymTheme.background.ignoresSafeArea())
        .foregroundStyle(GymTheme.text)
        .tint(GymTheme.accentText)
        .sensoryFeedback(.selection, trigger: store.draft.step)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldFocused = nil }
            }
        }
    }

    private var currentFocus: TrainingFocus { store.draft.selectedFocus ?? store.draft.recommendedFocus }
    private var header: some View {
        VStack(spacing: GymTheme.Space.related) {
            HStack {
                if store.draft.step > 0 {
                    Button("Back", systemImage: "chevron.left") { fieldFocused = nil; store.draft.step -= 1 }
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Image("GymAILogo").resizable().scaledToFit().frame(width: 100, height: 44).accessibilityLabel("Gym&I")
                }
                Spacer()
                Button(isEditing ? "Cancel" : dynamicTypeSize.isAccessibilitySize ? "Later" : "Set up later") {
                    if !isEditing { store.skip() }
                    onComplete()
                }
                .font(.subheadline)
                .frame(minHeight: 44)
            }
            HStack {
                Text(store.draft.step == 0 ? "About you" : isReview ? "Your match" : "Question \(store.draft.step) of \(questions.count)")
                    .font(.subheadline)
                Spacer()
                if store.draft.step > 0, !isReview, !dynamicTypeSize.isAccessibilitySize { Text("Your training").font(.subheadline).foregroundStyle(GymTheme.muted) }
            }
            ProgressView(value: Double(store.draft.step), total: Double(questions.count + 1))
                .tint(GymTheme.accentText)
                .accessibilityLabel("Profile progress")
                .accessibilityValue(isReview ? "Ready to review" : store.draft.step == 0 ? "Personal measurements" : "Question \(store.draft.step) of eight")
        }
        .padding(.horizontal, GymTheme.Space.page)
        .padding(.vertical, GymTheme.Space.small)
        .frame(maxWidth: GymTheme.contentWidth)
        .frame(maxWidth: .infinity)
    }

    private func questionContent(_ question: OnboardingQuestion) -> some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.section) {
            Text(question.title)
                .font(GymTheme.TypeStyle.title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
            Text(question.detail).foregroundStyle(GymTheme.muted).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: GymTheme.Space.related) {
                ForEach(question.choices) { choice in
                    OnboardingChoiceRow(choice: choice, selected: store.draft.answers[question.rawValue] == choice.id) {
                        store.choose(choice, for: question)
                    }
                }
            }
        }
    }

    private func advance() {
        fieldFocused = nil
        if isReview {
            guard store.complete() else { savingError = true; return }
            companion = CompanionKind(rawValue: currentFocus.companion) ?? .pip
            onComplete()
        } else {
            store.draft.step += 1
        }
    }
}
