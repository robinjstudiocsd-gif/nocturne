import DesignSystem
import SleepDomain
import SwiftUI

/// « Ajouter une nuit » (maquette E23) : saisie à la main d'une nuit ou d'une sieste.
struct AddNightView: View {
    @State private var model: AddNightViewModel
    @State private var editing: TimeField?
    @Environment(\.dismiss) private var dismiss
    private let onAdded: () -> Void

    init(model: AddNightViewModel, onAdded: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onAdded = onAdded
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SegmentedControl([SessionKind.night, .nap], selection: kindBinding) { $0 == .night ? "Nuit" : "Sieste" }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Type")

                    VStack(alignment: .leading, spacing: 6) {
                        RowGroup {
                            HStack(spacing: 12) {
                                Text(model.dayLabel)
                                    .font(.body)
                                    .foregroundStyle(NocturneColor.textPrimary)
                                Spacer()
                                DatePicker(model.dayLabel, selection: $model.day, in: ...model.latestDay, displayedComponents: .date)
                                    .labelsHidden()
                                    .environment(\.locale, Locale(identifier: "fr_FR"))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .frame(minHeight: 48)
                            ForEach(TimeField.allCases) { field in
                                RowDivider(inset: 16)
                                timeRow(field)
                            }
                        }
                        GroupFootnote(model.summary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        GroupTitle("Commentaire")
                        TextField(
                            "Commentaire",
                            text: $model.comment,
                            prompt: Text("Facultatif : où, comment, ce qui t’a réveillé…").foregroundStyle(NocturneColor.placeholder),
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

                    GroupFootnote("Une nuit ajoutée à la main n’a ni sons ni phases. Elle compte dans tes statistiques, avec la mention « saisie ».")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(NocturneColor.night)
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        Task {
                            if await model.save() {
                                onAdded()
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(model.isSaving)
                }
            }
            .sheet(item: $editing) { field in
                TimeWheelSheet(title: field.title(for: model.kind), initial: model.initialTime(field)) { hour, minute in
                    model.set(field, hour: hour, minute: minute)
                }
            }
            .alert("Impossible d’ajouter", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .presentationBackground(NocturneColor.night)
    }

    private func timeRow(_ field: TimeField) -> some View {
        HStack(spacing: 12) {
            Text(field.title(for: model.kind))
                .font(.body)
                .foregroundStyle(NocturneColor.textPrimary)
            Spacer()
            Button {
                editing = field
            } label: {
                Text(model.text(field))
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(NocturneColor.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(NocturneColor.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(field.title(for: model.kind)), \(model.text(field))")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 48)
    }

    private var kindBinding: Binding<SessionKind> {
        Binding(get: { model.kind }, set: { model.setKind($0) })
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}
