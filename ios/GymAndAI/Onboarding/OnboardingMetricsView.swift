import SwiftUI
import GymAndAIKit

struct OnboardingMetricsView: View {
    @Bindable var store: OnboardingStore
    var fieldFocus: FocusState<OnboardingMetric?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.page) {
            Text("A little about you")
                .font(GymTheme.TypeStyle.title)
                .accessibilityAddTraits(.isHeader)
            Text("Add your starting measurements, then tell us how you want to train.")
                .foregroundStyle(GymTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: GymTheme.Space.section) {
                Picker("Measurement units", selection: $store.usesImperial) {
                    Text("Metric").tag(false)
                    Text("Imperial").tag(true)
                }
                .pickerStyle(.segmented)
                metricField("Weight", unit: store.draft.imperial ? "lb" : "kg", value: $store.draft.weight, identifier: "onboarding-weight", metric: .weight)
                metricField("Height", unit: store.draft.imperial ? "in" : "cm", value: $store.draft.height, identifier: "onboarding-height", metric: .height)
                VStack(alignment: .leading, spacing: GymTheme.Space.small) {
                    Text("Sex").font(.headline)
                    Picker("Sex", selection: $store.draft.sex) {
                        Text("Choose or leave blank").tag(String?.none)
                        Text("Female").tag(String?("female"))
                        Text("Male").tag(String?("male"))
                        Text("Intersex").tag(String?("intersex"))
                        Text("Prefer not to say").tag(String?("not_shared"))
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(.horizontal, GymTheme.Space.inset)
                    .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.controlRadius))
                    .accessibilityIdentifier("onboarding-sex")
                }
            }
            if !store.draft.metricsAreValid {
                Text("Check your measurements and units. Weight should be 20–500 kg and height 80–260 cm, or the equivalent in pounds and inches.")
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.text)
                    .accessibilityIdentifier("onboarding-metrics-error")
            }
            Label("Optional. Saved on this iPhone. You can edit these later.", systemImage: "lock")
                .font(.subheadline)
                .foregroundStyle(GymTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("These measurements don’t decide your training focus.")
                .font(.subheadline)
                .foregroundStyle(GymTheme.muted)
        }
    }

    private func metricField(_ title: String, unit: String, value: Binding<Double?>, identifier: String, metric: OnboardingMetric) -> some View {
        VStack(alignment: .leading, spacing: GymTheme.Space.small) {
            Text(title).font(.headline)
            HStack {
                TextField(title, value: value, format: .number.precision(.fractionLength(0...1)), prompt: Text("Optional").foregroundStyle(GymTheme.muted))
                    .focused(fieldFocus, equals: metric)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier(identifier)
                Text(unit).foregroundStyle(GymTheme.muted).accessibilityHidden(true)
            }
            .padding(GymTheme.Space.inset)
            .frame(minHeight: GymTheme.controlHeight)
            .background(GymTheme.surface, in: .rect(cornerRadius: GymTheme.controlRadius))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(title) in \(unit)")
            .id(metric)
        }
    }
}
