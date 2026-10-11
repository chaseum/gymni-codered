import SwiftUI
import GymAndAIKit

/// Welcome → name → About You → questions → your companion → Heart Rate → Camera.
/// Each permission page's Continue shows the system prompt; Not Now moves on.
struct OnboardingFlowView: View {
    @Bindable var store: OnboardingStore
    var isEditing = false
    let onComplete: () -> Void
    @AppStorage("companion") private var companion = CompanionKind.pip
    @AppStorage("userName") private var name = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var fieldFocused: OnboardingMetric?
    @State private var phase: Phase
    @State private var savingError = false
    private let questions = OnboardingQuestion.allCases

    enum Phase { case welcome, name, profile, heartRate, camera }

    init(store: OnboardingStore, isEditing: Bool = false, onComplete: @escaping () -> Void) {
        self.store = store
        self.isEditing = isEditing
        self.onComplete = onComplete
        _phase = State(initialValue: isEditing || store.draft.step > 0 ? .profile : .welcome)
    }

    var body: some View {
        Group {
            switch phase {
            case .welcome:
                page(button: "Get Started", action: { phase = .name }) {
                    CompanionStage(state: .celebrate).frame(maxWidth: 300)
                    Text("Gym&I").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text("A training companion that counts every rep and helps your form.")
                        .multilineTextAlignment(.center).foregroundStyle(GymTheme.muted)
                }
            case .name:
                page(button: "Continue", action: { name = name.trimmingCharacters(in: .whitespaces); phase = .profile },
                     skip: { name = ""; phase = .profile }) {
                    CompanionStage(state: .idle).frame(width: 170, height: 170)
                    Text("What should I call you?").font(.largeTitle.bold())
                        .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                    TextField("First name", text: $name)
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.continue)
                        .focused($nameFocused)
                        .onSubmit { phase = .profile }
                        .padding(GymTheme.Space.inset)
                        .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.radius))
                        .accessibilityIdentifier("onboarding-name")
                }
                .onAppear { nameFocused = true }
            case .profile:
                profile
            case .heartRate:
                page(button: "Continue", action: { await Permissions.requestHeartRate(); phase = .camera },
                     skip: { phase = .camera }) {
                    permissionIcon("heart.fill", color: .red)
                    Text("Heart Rate").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text("See your heart rate from Apple Watch while you train.")
                        .multilineTextAlignment(.center).foregroundStyle(GymTheme.muted)
                }
            case .camera:
                page(button: "Continue", action: { Permissions.requestLocalNetwork(); finish() }, skip: finish) {
                    permissionIcon("video.fill", color: GymTheme.accent)
                    Text("Gym&I Camera").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text("Gym&I finds your camera on Wi‑Fi to count reps and check your form.")
                        .multilineTextAlignment(.center).foregroundStyle(GymTheme.muted)
                }
            }
        }
        .gymPage()
        .tint(GymTheme.accent)
        .sensoryFeedback(.selection, trigger: store.draft.step)
        .alert("Couldn’t Save Your Profile", isPresented: $savingError) { Button("OK") {} }
    }

    // MARK: Profile

    private var isMatch: Bool { store.draft.step == questions.count + 1 }
    private var question: OnboardingQuestion? {
        questions.indices.contains(store.draft.step - 1) ? questions[store.draft.step - 1] : nil
    }
    private var focus: TrainingFocus { store.draft.selectedFocus ?? store.draft.recommendedFocus }
    private var canContinue: Bool {
        if store.draft.step == 0 { return store.draft.metricsAreValid }
        if isMatch { return store.draft.isComplete }
        guard let question else { return false }
        return question.choices.contains { $0.id == store.draft.answers[question.rawValue] }
    }

    private var profile: some View {
        VStack(spacing: 0) {
            HStack(spacing: GymTheme.Space.related) {
                Button("Back", systemImage: "chevron.left", action: back)
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .disabled(store.draft.step == 0 && isEditing)
                ProgressView(value: Double(store.draft.step), total: Double(questions.count + 1))
                    .accessibilityLabel("Progress")
                Button(isEditing ? "Cancel" : "Skip") {
                    if !isEditing { store.skip() }
                    onComplete()
                }
                .frame(minHeight: 44)
            }
            .padding(.horizontal, GymTheme.Space.inset)
            ScrollView {
                VStack(alignment: .leading, spacing: GymTheme.Space.section) {
                    if store.draft.step == 0 { metrics }
                    else if let question { questionContent(question) }
                    else { match }
                }
                .padding(GymTheme.Space.page)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            Button(isMatch ? "Continue with \(focus.companion.capitalized)" : "Continue", action: advance)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canContinue)
                .padding(.horizontal, GymTheme.Space.page)
                .padding(.vertical, GymTheme.Space.related)
                .accessibilityIdentifier("onboarding-continue")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldFocused = nil }
            }
        }
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.section) {
            Text("About You").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Picker("Units", selection: $store.usesImperial) {
                Text("Metric").tag(false)
                Text("Imperial").tag(true)
            }
            .pickerStyle(.segmented)
            VStack(spacing: 0) {
                metricField("Weight", unit: store.draft.imperial ? "lb" : "kg", value: $store.draft.weight, metric: .weight)
                Divider().padding(.leading, GymTheme.Space.inset)
                metricField("Height", unit: store.draft.imperial ? "in" : "cm", value: $store.draft.height, metric: .height)
                Divider().padding(.leading, GymTheme.Space.inset)
                HStack {
                    Text("Sex")
                    Spacer()
                    Picker("Sex", selection: $store.draft.sex) {
                    Text("Not Set").tag(String?.none)
                    Text("Female").tag(String?("female"))
                    Text("Male").tag(String?("male"))
                    Text("Intersex").tag(String?("intersex"))
                    Text("Prefer Not to Say").tag(String?("not_shared"))
                    }
                    .labelsHidden()
                }
                .padding(.leading, GymTheme.Space.inset)
                .padding(.trailing, GymTheme.Space.small)
                .frame(minHeight: 52)
                .accessibilityIdentifier("onboarding-sex")
            }
            .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.radius))
            if !store.draft.metricsAreValid {
                Text("Check your weight and height.")
                    .font(.footnote).foregroundStyle(GymTheme.muted)
                    .accessibilityIdentifier("onboarding-metrics-error")
            }
        }
    }

    private func metricField(_ title: String, unit: String, value: Binding<Double?>, metric: OnboardingMetric) -> some View {
        HStack {
            Text(title)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)), prompt: Text("Optional"))
                .multilineTextAlignment(.trailing)
                .focused($fieldFocused, equals: metric)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("onboarding-\(title.lowercased())")
            Text(unit).foregroundStyle(GymTheme.muted).accessibilityHidden(true)
        }
        .padding(.horizontal, GymTheme.Space.inset)
        .frame(minHeight: 52)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) in \(unit)")
    }

    private func questionContent(_ question: OnboardingQuestion) -> some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.section) {
            Text(question.title).font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: GymTheme.Space.small) {
                ForEach(question.choices) { choice in
                    OnboardingChoiceRow(choice: choice, selected: store.draft.answers[question.rawValue] == choice.id) {
                        store.choose(choice, for: question)
                        let step = store.draft.step
                        Task {  // a short beat to see the check, then on to the next question
                            try? await Task.sleep(for: .milliseconds(250))
                            if store.draft.step == step { advance() }
                        }
                    }
                }
            }
        }
    }

    private var match: some View {
        VStack(spacing: GymTheme.Space.section) {
            CompanionStage(state: .celebrate, companion: CompanionKind(rawValue: focus.companion) ?? .pip)
                .frame(maxWidth: 280)
            Text("Meet \(focus.companion.capitalized)").font(.largeTitle.bold())
                .accessibilityIdentifier("onboarding-match-title")
                .accessibilityAddTraits(.isHeader)
            Picker("Training focus", selection: Binding(get: { focus }, set: { store.draft.selectedFocus = $0 })) {
                ForEach(TrainingFocus.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: .infinity)
    }

    private func back() {
        fieldFocused = nil
        if store.draft.step == 0 { phase = .name } else { store.draft.step -= 1 }
    }

    private func advance() {
        fieldFocused = nil
        guard isMatch else { store.draft.step += 1; return }
        if isEditing { finish() } else { phase = .heartRate }
    }

    private func finish() {
        guard store.complete() else { savingError = true; return }
        companion = CompanionKind(rawValue: focus.companion) ?? .pip
        onComplete()
    }

    // MARK: Pages

    private func page<Content: View>(button: String, action: @escaping () async -> Void, skip: (() -> Void)? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: GymTheme.Space.section) {
            Spacer(minLength: 0)
            content()
            Spacer(minLength: 0)
            Button(button) { Task { await action() } }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("onboarding-continue")
            if let skip {
                Button("Not Now", action: skip).frame(minHeight: 44)
            }
        }
        .padding(.horizontal, GymTheme.Space.page)
        .padding(.bottom, GymTheme.Space.small)
    }

    private func permissionIcon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 56, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 128, height: 128)
            .background(color.opacity(0.15), in: .circle)
            .accessibilityHidden(true)
    }
}
