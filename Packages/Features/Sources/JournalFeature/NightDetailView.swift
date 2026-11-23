import DesignSystem
import SleepAnalysis
import SleepDomain
import SwiftUI

/// Fiche de nuit (maquette E21) : nuit précédente et suivante, score, horaires, durées, profil de la nuit,
/// écoute, ressenti, journal du soir et comparaison avec les nuits précédentes.
struct NightDetailView: View {
    @State private var model: NightDetailViewModel
    @State private var showsEdit = false
    @State private var wasDeleted = false
    @Environment(\.dismiss) private var dismiss

    init(route: NightRoute, dependencies: JournalDependencies, onChange: @escaping () async -> Void) {
        _model = State(initialValue: NightDetailViewModel(sessionID: route.id, dependencies: dependencies, onChange: onChange))
    }

    var body: some View {
        ScrollView {
            if let session = model.session {
                VStack(spacing: 12) {
                    switcher
                    scoreHeader
                    timesCard
                    if model.showsProfile {
                        profileCard
                    }
                    if model.showsListening {
                        listeningCard
                    }
                    feelingCard(session)
                    if model.showsComparison {
                        comparisonCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            } else if model.isMissing {
                EmptyStateView(systemImage: "moon.zzz", title: "Nuit introuvable", message: "Elle a peut-être été supprimée.")
            } else if let message = model.errorMessage {
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "Lecture impossible", message: message)
            }
        }
        .background(NocturneColor.night)
        .navigationTitle(model.session?.kind == .nap ? "Fiche de sieste" : "Fiche de nuit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Modifier") { showsEdit = true }
                    .disabled(model.session == nil || model.isRunning)
            }
        }
        .sheet(isPresented: $showsEdit, onDismiss: {
            if wasDeleted {
                dismiss()
            }
        }) {
            if let session = model.session {
                EditNightView(session: session, dependencies: model.dependencies) {
                    Task { await model.didChange() }
                } onDeleted: {
                    wasDeleted = true
                    Task { await model.didChange() }
                }
            }
        }
        .task { await model.load() }
    }

    // MARK: - Nuit précédente et suivante

    private var switcher: some View {
        HStack(spacing: 8) {
            roundButton(systemName: "chevron.left", label: "Nuit précédente", target: model.olderID)
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                Text(model.header.title)
                    .font(.headline)
                    .foregroundStyle(NocturneColor.textPrimary)
                Text(model.header.subtitle)
                    .font(.footnote)
                    .foregroundStyle(NocturneColor.textSecondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            roundButton(systemName: "chevron.right", label: "Nuit suivante", target: model.newerID)
        }
    }

    private func roundButton(systemName: String, label: String, target: UUID?) -> some View {
        Button {
            Task { await model.show(target) }
        } label: {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(NocturneColor.iconSoft)
                .frame(width: 44, height: 44)
                .background(NocturneColor.card, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .opacity(target == nil ? 0.35 : 1)
        .accessibilityLabel(label)
    }

    // MARK: - Score

    private var scoreHeader: some View {
        HStack(spacing: 16) {
            ScoreRing(score: model.scoreValue, approximate: model.scoreIsApproximate, size: 88)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.qualityLine)
                    .font(.headline)
                    .foregroundStyle(NocturneColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.chips.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(model.chips, id: \.self) { chip in
                            InfoChip(chip)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Profil de la nuit

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Profil de la nuit")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("D’après les mouvements et les sons captés par l’iPhone")
                    .font(.footnote)
                    .foregroundStyle(NocturneColor.textSecondary)
            }
            BandChart(
                rows: [
                    BandRow(title: "Éveil", color: NocturneColor.profileAwake),
                    BandRow(title: "Agité", color: NocturneColor.profileAgitated),
                    BandRow(title: "Calme", color: NocturneColor.profileCalm)
                ],
                segments: model.profileBands.map { BandSegment(start: $0.start, end: $0.end, row: $0.row) },
                ticks: model.profileTicks.map { ChartTick(label: $0.label, position: $0.fraction) },
                accessibilityLabel: model.profileAccessibility
            )
            BandLegend(items: zip(model.profileDurations, [NocturneColor.profileAwake, NocturneColor.profileAgitated, NocturneColor.profileCalm]).map { entry, color in
                BandLegend.Item(title: entry.title, value: entry.value, color: color)
            })
            VStack(alignment: .leading, spacing: 12) {
                Rectangle()
                    .fill(NocturneColor.separator)
                    .frame(height: 1)
                    .accessibilityHidden(true)
                Text("Sans montre, les phases et le cœur ne sont pas mesurés. L’estimation expérimentale des phases est désactivée dans les réglages et n’entre jamais dans le score.")
                    .font(.footnote)
                    .foregroundStyle(NocturneColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Comparaison

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Comparaison")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(model.comparisonSubtitle)
                    .font(.footnote)
                    .foregroundStyle(NocturneColor.textSecondary)
            }
            VStack(spacing: 0) {
                let rows = model.comparisonRows
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 8) {
                        Text(row.label)
                            .foregroundStyle(NocturneColor.textPrimary)
                        Spacer(minLength: 4)
                        Text(row.detail)
                            .foregroundStyle(NocturneColor.textSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(row.difference)
                            .fontWeight(.semibold)
                            .foregroundStyle(NocturneColor.textPrimary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                    .font(.subheadline)
                    .frame(minHeight: 36)
                    .accessibilityElement(children: .combine)
                    if index < rows.count - 1 {
                        Rectangle()
                            .fill(NocturneColor.separator)
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Horaires

    private var timesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Horaires")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            valueGrid(model.times, valueFont: NocturneFont.number(.body))
            Rectangle()
                .fill(NocturneColor.separator)
                .frame(height: 1)
                .accessibilityHidden(true)
            valueGrid(model.durations, valueFont: NocturneFont.number(.title3))
            if let summary = model.summary {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(NocturneColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func valueGrid(_ values: [LabeledValue], valueFont: Font) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(values) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(NocturneColor.textSecondary)
                    Text(item.value)
                        .font(valueFont)
                        .monospacedDigit()
                        .foregroundStyle(NocturneColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Sons de la nuit

    private var listeningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sons de la nuit")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(model.listeningLine)
                    .font(.footnote)
                    .foregroundStyle(NocturneColor.textSecondary)
            }
            if !model.gapLines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(model.gapLines.enumerated()), id: \.offset) { _, line in
                        Label(line, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(NocturneColor.amber)
                    }
                }
            }
            if !model.eventSummary.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.eventSummary) { item in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(NocturneColor.amber)
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            Text(item.label)
                                .font(.subheadline)
                                .foregroundStyle(NocturneColor.textPrimary)
                            Spacer()
                            Text(item.value)
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(NocturneColor.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } else if model.session?.recordingMode != .off {
                Text("Aucun événement sonore repéré.")
                    .font(.subheadline)
                    .foregroundStyle(NocturneColor.textSecondary)
            }
            if model.canReplay, let session = model.session {
                NavigationLink(value: ReplayRoute(session: session)) {
                    Label("Réécouter la nuit", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(NocturneColor.violet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Ressenti et journal du soir

    private func feelingCard(_ session: SleepSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.feelingTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            let rows = model.feelingRows
            if rows.isEmpty && model.comment == nil && model.eveningNote == nil {
                Text("Rien de noté pour cette \(session.kind == .nap ? "sieste" : "nuit"). Touche Modifier pour ajouter ton ressenti ou un commentaire.")
                    .font(.footnote)
                    .foregroundStyle(NocturneColor.textSecondary)
            }
            if !rows.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16, alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label)
                                .font(.caption)
                                .foregroundStyle(NocturneColor.textSecondary)
                            Text(row.value)
                                .font(.subheadline)
                                .foregroundStyle(NocturneColor.textPrimary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if let note = model.eveningNote {
                quote("Le soir : \(note)")
            }
            if let comment = model.comment {
                quote(comment)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func quote(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(NocturneColor.separator)
                .frame(height: 1)
                .accessibilityHidden(true)
            Text("« \(text) »")
                .font(.subheadline)
                .foregroundStyle(NocturneColor.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
