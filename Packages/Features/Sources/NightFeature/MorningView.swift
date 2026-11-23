import DesignSystem
import SleepDomain
import SwiftUI

/// « Bonjour » (maquette E33) : résumé immédiat, ressenti, correction rapide des horaires, commentaire.
/// Le score et les événements sonores s'ajouteront avec l'analyse (lots 3 et 4).
struct MorningView: View {
    @Bindable private var model: MorningViewModel
    private let onDone: () -> Void
    @State private var editing: MorningViewModel.TimeField?

    init(model: MorningViewModel, onDone: @escaping () -> Void) {
        _model = Bindable(model)
        self.onDone = onDone
    }

    private static let moodLabels = ["Très mal", "Mal", "Moyen", "Bien", "Très bien"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                summaryCard
                feelingCard
                timesCard
                commentField
                Button {
                    Task {
                        if await model.save() {
                            onDone()
                        }
                    }
                } label: {
                    if model.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text("Enregistrer")
                    }
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
        .foregroundStyle(NocturneColor.textPrimary)
        .sheet(item: $editing) { field in
            TimeWheelSheet(title: field.title, initial: model.initialTime(for: field)) { hour, minute in
                model.set(field, hour: hour, minute: minute)
            }
        }
        .alert("Vérifie les horaires", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 12) {
                Text(model.dayTitle)
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.3)
                    .foregroundStyle(NocturneColor.textSecondary)
                Spacer()
                Button("Passer", action: onDone)
                    .font(.subheadline)
                    .foregroundStyle(NocturneColor.lavender)
                    .frame(minHeight: 44)
            }
            Text("Bonjour")
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.headline)
                    .font(NocturneFont.number(.title2))
                if let times = model.timesLine {
                    Text(times)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(NocturneColor.textSecondary)
                }
                Text(model.listeningLine)
                    .font(.subheadline)
                    .foregroundStyle(NocturneColor.textSecondary)
                if let events = model.eventsLine {
                    Text(events)
                        .font(.subheadline)
                        .foregroundStyle(NocturneColor.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            if model.wasInterrupted {
                Label("L’app s’est arrêtée pendant la nuit : la fin est fixée à la dernière minute connue. Corrige le réveil si besoin.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(NocturneColor.amber)
            }
            Label("Si tu portais ta montre, ses données s’ajouteront dès leur arrivée dans Santé.", systemImage: "applewatch")
                .font(.footnote)
                .foregroundStyle(NocturneColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var feelingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comment te sens-tu ?")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 8) {
                Text("Humeur")
                    .font(.footnote)
                    .foregroundStyle(NocturneColor.textSecondary)
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { level in
                        moodButton(level: level, label: Self.moodLabels[level - 1])
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Énergie")
                    .font(.footnote)
                    .foregroundStyle(NocturneColor.textSecondary)
                LevelScale(value: $model.energy, name: "Énergie", lowLabel: "épuisé", highLabel: "en pleine forme")
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func moodButton(level: Int, label: String) -> some View {
        let isSelected = model.mood == level
        return Button {
            model.mood = isSelected ? nil : level
        } label: {
            VStack(spacing: 4) {
                MoodFace(level: level)
                Text(label)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? NocturneColor.textPrimary : NocturneColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(isSelected ? NocturneColor.moodSelected : NocturneColor.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? NocturneColor.lavender : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Humeur : \(label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var timesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Horaires détectés")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Touche une heure pour la corriger.")
                    .font(.footnote)
                    .foregroundStyle(NocturneColor.textSecondary)
            }
            VStack(spacing: 0) {
                timeRow(.sleepOnset)
                Rectangle()
                    .fill(NocturneColor.separator)
                    .frame(height: 1)
                    .accessibilityHidden(true)
                timeRow(.wake)
            }
        }
        .padding(16)
        .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func timeRow(_ field: MorningViewModel.TimeField) -> some View {
        HStack(spacing: 12) {
            Text(field.title)
                .font(.body)
            Spacer()
            Button {
                editing = field
            } label: {
                Text(model.text(for: field))
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(NocturneColor.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(NocturneColor.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.accessibilityText(for: field))
        }
        .frame(minHeight: 48)
    }

    private var commentField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Un mot sur ta nuit ? (facultatif)")
                .font(.footnote)
                .foregroundStyle(NocturneColor.textSecondary)
                .padding(.horizontal, 4)
            TextField(
                "Un mot sur ta nuit",
                text: $model.comment,
                prompt: Text("Un rêve, un bruit, une remarque…").foregroundStyle(NocturneColor.placeholder),
                axis: .vertical
            )
            .lineLimit(3...6)
            .font(.body)
            .padding(12)
            .frame(minHeight: 96, alignment: .topLeading)
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
}
