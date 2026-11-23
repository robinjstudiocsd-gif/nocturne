import DesignSystem
import SleepDomain
import SwiftUI

/// Journal du soir (maquette E38) : caféine, sport, écrans, repas, stress et note, en quelques gestes.
/// Toucher une puce déjà choisie l'efface.
public struct EveningLogView: View {
    @State private var model: EveningLogViewModel
    @State private var editing: EveningLogViewModel.TimeField?
    @Environment(\.dismiss) private var dismiss

    public init(repository: any EveningLogRepository) {
        _model = State(initialValue: EveningLogViewModel(repository: repository))
    }

    public var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    VStack(spacing: 2) {
                        Text(model.headerLine)
                            .font(.subheadline)
                        Text("Quelques gestes pour voir ce qui aide tes nuits.")
                            .font(.footnote)
                    }
                    .foregroundStyle(NocturneColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)

                    choiceGroup(
                        "Caféine",
                        options: EveningLog.Caffeine.allCases,
                        selection: $model.caffeine,
                        time: .caffeine,
                        label: Self.caffeineLabel
                    )
                    choiceGroup(
                        "Sport",
                        options: EveningLog.Exercise.allCases,
                        selection: $model.exercise,
                        time: .exercise,
                        label: Self.exerciseLabel
                    )
                    choiceGroup(
                        "Écrans avant de dormir",
                        options: EveningLog.Screens.allCases,
                        selection: $model.screens,
                        time: nil,
                        label: Self.screensLabel
                    )
                    choiceGroup(
                        "Repas du soir",
                        options: EveningLog.Meal.allCases,
                        selection: $model.meal,
                        time: .meal,
                        label: Self.mealLabel
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Stress de la journée")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NocturneColor.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        LevelScale(value: $model.stress, name: "Stress", lowLabel: "calme", highLabel: "très tendu")
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    noteField(text: $model.note)

                    Button("Enregistrer") {
                        Task { await save() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isSaving)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(NocturneColor.night)
            .navigationTitle("Journal du soir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Plus tard") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(model.isSaving)
                }
            }
            .sheet(item: $editing) { field in
                TimeWheelSheet(
                    title: field.title,
                    initial: model.initialTime(field),
                    clearTitle: model.time(field) == nil ? nil : "Effacer l’heure",
                    onClear: { model.clearTime(field) },
                    onDone: { hour, minute in model.setTime(field, hour: hour, minute: minute) }
                )
            }
            .alert("Journal non enregistré", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .task { await model.load() }
        }
        .presentationBackground(NocturneColor.night)
    }

    private func save() async {
        if await model.save() {
            dismiss()
        }
    }

    private func choiceGroup<Option: Hashable>(
        _ title: String,
        options: [Option],
        selection: Binding<Option?>,
        time: EveningLogViewModel.TimeField?,
        label: @escaping (Option) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NocturneColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let time, model.showsTime(time) {
                    Button {
                        editing = time
                    } label: {
                        Text(model.timeText(time))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(NocturneColor.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(NocturneColor.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title), \(model.timeText(time))")
                }
            }
            .frame(minHeight: 36)
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    ChoiceChip(label(option), isSelected: selection.wrappedValue == option) {
                        selection.wrappedValue = selection.wrappedValue == option ? nil : option
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func noteField(text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Note (facultatif)")
                .font(.footnote)
                .foregroundStyle(NocturneColor.textSecondary)
                .padding(.horizontal, 4)
            TextField(
                "Note",
                text: text,
                prompt: Text("Une soirée particulière, un médicament, un remède contre le ronflement…").foregroundStyle(NocturneColor.placeholder),
                axis: .vertical
            )
            .lineLimit(3...6)
            .font(.body)
            .foregroundStyle(NocturneColor.textPrimary)
            .padding(12)
            .frame(minHeight: 88, alignment: .topLeading)
            .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NocturneColor.separator, lineWidth: 1))
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    nonisolated private static func caffeineLabel(_ value: EveningLog.Caffeine) -> String {
        switch value {
        case .none: "Aucune"
        case .one: "1"
        case .two: "2"
        case .threeOrMore: "3 et +"
        }
    }

    nonisolated private static func exerciseLabel(_ value: EveningLog.Exercise) -> String {
        switch value {
        case .none: "Non"
        case .light: "Léger"
        case .intense: "Intense"
        }
    }

    nonisolated private static func screensLabel(_ value: EveningLog.Screens) -> String {
        switch value {
        case .offEarly: "Coupés tôt"
        case .untilBedtime: "Jusqu’au coucher"
        case .inBed: "Au lit"
        }
    }

    nonisolated private static func mealLabel(_ value: EveningLog.Meal) -> String {
        switch value {
        case .light: "Léger"
        case .normal: "Normal"
        case .heavy: "Copieux"
        }
    }
}
