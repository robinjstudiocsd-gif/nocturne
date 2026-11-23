import DesignSystem
import SleepDomain
import SwiftUI

/// Choix de l'heure du réveil de la nuit. Les alarmes complètes (jours, sonneries) arrivent au lot 5.
struct AlarmSheet: View {
    @Binding var plan: NightPlan
    @State private var isEnabled: Bool
    @State private var time: Date
    @Environment(\.dismiss) private var dismiss

    init(plan: Binding<NightPlan>) {
        _plan = plan
        _isEnabled = State(initialValue: plan.wrappedValue.alarmEnabled)
        let initial = Calendar.current.date(
            bySettingHour: plan.wrappedValue.alarmHour,
            minute: plan.wrappedValue.alarmMinute,
            second: 0,
            of: Date()
        ) ?? Date()
        _time = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                RowGroup {
                    Toggle(isOn: $isEnabled) {
                        Text("Me réveiller")
                            .font(.body)
                            .foregroundStyle(NocturneColor.textPrimary)
                    }
                    .tint(NocturneColor.switchOn)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                }
                .padding(.horizontal, 16)

                DatePicker("Heure du réveil", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "fr_FR"))
                    .disabled(!isEnabled)
                    .opacity(isEnabled ? 1 : 0.4)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .background(NocturneColor.night)
            .navigationTitle("Réveil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                        var updated = plan
                        updated.alarmEnabled = isEnabled
                        updated.alarmHour = parts.hour ?? updated.alarmHour
                        updated.alarmMinute = parts.minute ?? updated.alarmMinute
                        plan = updated
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(NocturneColor.night)
    }
}
