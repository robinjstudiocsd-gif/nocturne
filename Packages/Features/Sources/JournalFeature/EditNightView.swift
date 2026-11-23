import DesignSystem
import SleepDomain
import SwiftUI

/// « Modifier une nuit » (maquette E22).
struct EditNightView: View {
    @State private var model: EditNightViewModel
    @State private var editing: TimeField?
    @State private var addsWake = false
    @State private var confirmsDeletion = false
    @Environment(\.dismiss) private var dismiss
    private let onSaved: () -> Void
    private let onDeleted: () -> Void

    init(session: SleepSession, dependencies: JournalDependencies, onSaved: @escaping () -> Void, onDeleted: @escaping () -> Void) {
        _model = State(initialValue: EditNightViewModel(session: session, dependencies: dependencies))
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(model.title)
                        .font(.subheadline)
                        .foregroundStyle(NocturneColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)

                    timesSection
                    wakesSection

                    VStack(alignment: .leading, spacing: 6) {
                        GroupTitle("Type")
                        SegmentedControl([SessionKind.night, .nap], selection: $model.kind) { $0 == .night ? "Nuit" : "Sieste" }
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("Type")
                    }

                    feelingSection(mood: $model.mood, energy: $model.energy)

                    VStack(alignment: .leading, spacing: 6) {
                        GroupTitle("Commentaire")
                        TextField(
                            "Commentaire",
                            text: $model.comment,
                            prompt: Text("Facultatif").foregroundStyle(NocturneColor.placeholder),
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                        .font(.body)
                        .foregroundStyle(NocturneColor.textPrimary)
                        .padding(12)
                        .frame(minHeight: 96, alignment: .topLeading)
                        .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NocturneColor.separator, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            confirmsDeletion = true
                        } label: {
                            Text(model.kind == .nap ? "Supprimer cette sieste" : "Supprimer cette nuit")
                                .font(.headline)
                                .foregroundStyle(NocturneColor.destructive)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        GroupFootnote("L’audio, les extraits et les événements sont supprimés avec elle. L’app demande une confirmation.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(NocturneColor.night)
            .navigationTitle(model.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        Task {
                            if await model.save() {
                                onSaved()
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
            .sheet(isPresented: $addsWake) {
                WakeEpisodeSheet(initial: model.wakeSuggestion) { hour, minute, minutes in
                    model.addWake(hour: hour, minute: minute, minutes: minutes)
                }
            }
            .confirmationDialog(
                model.kind == .nap ? "Supprimer cette sieste ?" : "Supprimer cette nuit ?",
                isPresented: $confirmsDeletion,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    Task {
                        if await model.delete() {
                            onDeleted()
                            dismiss()
                        }
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Les sons et les extraits enregistrés seront supprimés aussi. Cette action est définitive.")
            }
            .alert("Impossible d’enregistrer", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .presentationBackground(NocturneColor.night)
    }

    // MARK: - Horaires

    private var timesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupTitle("Horaires")
            RowGroup {
                ForEach(Array(TimeField.allCases.enumerated()), id: \.element) { index, field in
                    if index > 0 {
                        RowDivider(inset: 16)
                    }
                    timeRow(field)
                }
            }
            GroupFootnote("Une correction n’efface jamais l’heure détectée : « Rétablir » la remet. Les durées sont recalculées.")
        }
    }

    private func timeRow(_ field: TimeField) -> some View {
        let corrected = model.isCorrected(field)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.title(for: model.kind))
                    .font(.body)
                    .foregroundStyle(NocturneColor.textPrimary)
                Text(model.detail(field))
                    .font(.footnote)
                    .foregroundStyle(corrected ? NocturneColor.amber : NocturneColor.textSecondary)
            }
            Spacer(minLength: 8)
            if corrected {
                Button("Rétablir") { model.restore(field) }
                    .font(.subheadline)
                    .foregroundStyle(NocturneColor.lavender)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Rétablir l’heure détectée")
            }
            Button {
                editing = field
            } label: {
                Text(model.valueText(field))
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(NocturneColor.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(NocturneColor.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(corrected ? NocturneColor.amber : Color.clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(field.title(for: model.kind)), \(model.valueText(field))\(corrected ? ", corrigée" : "")")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
    }

    // MARK: - Réveils dans la nuit

    private var wakesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupTitle("Réveils dans la nuit")
            RowGroup {
                ForEach(model.wakeEpisodes) { episode in
                    HStack(spacing: 12) {
                        Text(model.wakeText(episode))
                            .font(.body)
                            .monospacedDigit()
                            .foregroundStyle(NocturneColor.textPrimary)
                        Spacer()
                        Button {
                            model.removeWake(episode)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(NocturneColor.destructive)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Supprimer le réveil de \(model.wakeText(episode))")
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .frame(minHeight: 52)
                    RowDivider(inset: 16)
                }
                Button {
                    addsWake = true
                } label: {
                    Label("Ajouter un réveil", systemImage: "plus.circle")
                        .font(.body)
                        .foregroundStyle(NocturneColor.lavender)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            GroupFootnote("Seuls les réveils de plus de 5 minutes comptent.")
        }
    }

    // MARK: - Ressenti

    private func feelingSection(mood: Binding<Int?>, energy: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupTitle("Ressenti au réveil")
            RowGroup {
                Menu {
                    Picker("Humeur", selection: mood) {
                        Text("Non renseignée").tag(Int?.none)
                        ForEach(1...5, id: \.self) { level in
                            Text(WakeFeeling.moodLabel(level)).tag(Int?.some(level))
                        }
                    }
                } label: {
                    RowLabel(title: "Humeur", value: model.moodText)
                }
                .buttonStyle(.plain)
                RowDivider(inset: 16)
                Menu {
                    Picker("Énergie", selection: energy) {
                        Text("Non renseignée").tag(Int?.none)
                        ForEach(1...5, id: \.self) { level in
                            Text("\(level) sur 5").tag(Int?.some(level))
                        }
                    }
                } label: {
                    RowLabel(title: "Énergie", value: model.energyText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

/// Ajout d'un réveil : heure de début et durée.
struct WakeEpisodeSheet: View {
    private let onDone: (Int, Int, Int) -> Void
    @State private var start: Date
    @State private var minutes = 10
    @Environment(\.dismiss) private var dismiss

    init(initial: Date, onDone: @escaping (Int, Int, Int) -> Void) {
        self.onDone = onDone
        _start = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                DatePicker("Début du réveil", selection: $start, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "fr_FR"))
                RowGroup {
                    Stepper(value: $minutes, in: 1...180) {
                        Text("Durée : \(minutes) min")
                            .font(.body)
                            .monospacedDigit()
                            .foregroundStyle(NocturneColor.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                }
                .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .background(NocturneColor.night)
            .navigationTitle("Ajouter un réveil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: start)
                        onDone(parts.hour ?? 0, parts.minute ?? 0, minutes)
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
