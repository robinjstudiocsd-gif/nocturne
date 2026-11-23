#if os(iOS)
import SwiftUI

/// Feuille de choix d'une heure avec la roue d'iOS, au format 24 heures.
/// Renvoie l'heure et la minute choisies ; c'est l'appelant qui les place sur le bon jour.
public struct TimeWheelSheet: View {
    private let title: String
    private let message: String?
    private let clearTitle: String?
    private let onClear: (() -> Void)?
    private let onDone: (Int, Int) -> Void
    @State private var selection: Date
    @Environment(\.dismiss) private var dismiss

    public init(
        title: String,
        initial: Date,
        message: String? = nil,
        clearTitle: String? = nil,
        onClear: (() -> Void)? = nil,
        onDone: @escaping (Int, Int) -> Void
    ) {
        self.title = title
        self.message = message
        self.clearTitle = clearTitle
        self.onClear = onClear
        self.onDone = onDone
        _selection = State(initialValue: initial)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(NocturneColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                DatePicker(title, selection: $selection, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "fr_FR"))
                if let clearTitle, let onClear {
                    Button(clearTitle, role: .destructive) {
                        onClear()
                        dismiss()
                    }
                    .font(.body)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .background(NocturneColor.night)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: selection)
                        onDone(parts.hour ?? 0, parts.minute ?? 0)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(NocturneColor.night)
    }
}
#endif
