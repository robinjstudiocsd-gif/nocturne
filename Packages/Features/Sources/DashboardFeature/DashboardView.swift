import DesignSystem
import SleepAnalysis
import SleepDomain
import SwiftUI

/// Accueil (maquette E10) : la carte « Ce soir », puis la dernière nuit, la dette de sommeil, la régularité
/// et les 7 dernières nuits.
public struct DashboardView: View {
    @Bindable private var model: DashboardViewModel
    private let onPrepareNight: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenNight: (UUID) -> Void
    private let onReplay: (SleepSession) -> Void

    public init(
        model: DashboardViewModel,
        onPrepareNight: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenNight: @escaping (UUID) -> Void,
        onReplay: @escaping (SleepSession) -> Void
    ) {
        _model = Bindable(model)
        self.onPrepareNight = onPrepareNight
        self.onOpenSettings = onOpenSettings
        self.onOpenNight = onOpenNight
        self.onReplay = onReplay
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                tonightCard
                if let night = model.lastNight {
                    lastNightHeader(night)
                    lastNightCard(night)
                    tiles
                    weekCard
                } else if let message = model.errorMessage {
                    EmptyStateView(systemImage: "exclamationmark.triangle", title: "Lecture impossible", message: message)
                } else if model.isLoaded {
                    EmptyStateView(
                        systemImage: "moon.zzz",
                        title: "Pas encore de nuit",
                        message: "Ta première nuit apparaîtra ici le lendemain matin."
                    )
                }
            }
            .padding(16)
        }
        .background(NocturneColor.night)
        .foregroundStyle(NocturneColor.textPrimary)
        .navigationTitle("Accueil")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onOpenSettings) {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("Réglages")
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    // MARK: - Ce soir

    private var tonightCard: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "moon.fill")
                    .font(.title3)
                    .foregroundStyle(NocturneColor.lavender)
                    .frame(width: 40, height: 40)
                    .background(NocturneColor.elevated, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ce soir")
                        .font(.headline)
                    Text("Prépare ta nuit quand tu vas te coucher.")
                        .font(.subheadline)
                        .foregroundStyle(NocturneColor.textSecondary)
                }
            }
            if !model.checks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.checks) { check in
                        Label {
                            Text(check.text)
                                .foregroundStyle(check.isReady ? NocturneColor.textSecondary : NocturneColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: check.isReady ? "checkmark.circle" : "exclamationmark.triangle")
                                .foregroundStyle(check.isReady ? NocturneColor.success : NocturneColor.amber)
                                .accessibilityLabel(check.isReady ? "Prêt" : "À faire")
                        }
                        .font(.subheadline)
                    }
                }
            }
            Button("Préparer ma nuit", action: onPrepareNight)
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: - Dernière nuit

    private func lastNightHeader(_ night: SleepSession) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Dernière nuit")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Voir la fiche") { onOpenNight(night.id) }
                .font(.subheadline)
                .foregroundStyle(NocturneColor.lavender)
                .frame(minHeight: 44)
        }
        .padding(.top, 8)
    }

    private func lastNightCard(_ night: SleepSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ScoreRing(score: model.report?.score.total, approximate: model.report?.score.isApproximate ?? false, size: 88)
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.lastNightTitle)
                        .font(.footnote)
                        .foregroundStyle(NocturneColor.textSecondary)
                    Text(model.qualityLine)
                        .font(.headline)
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

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: 3),
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(model.values) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label)
                            .font(.caption)
                            .foregroundStyle(NocturneColor.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(item.value)
                            .font(NocturneFont.number(.title3))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if model.showsProfile {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Profil de la nuit, d’après les mouvements et les sons captés par l’iPhone")
                        .font(.footnote)
                        .foregroundStyle(NocturneColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                }
            }

            if let title = model.eventsTitle {
                VStack(alignment: .leading, spacing: 10) {
                    Rectangle()
                        .fill(NocturneColor.separator)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(NocturneColor.amber)
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        eventsText(title: title, detail: model.eventsDetail)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.canReplay {
                        Button {
                            onReplay(night)
                        } label: {
                            Label("Réécouter la nuit", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(NocturneColor.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(NocturneColor.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let insight = model.scoreInsight {
                Label {
                    Text(insight)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(NocturneColor.phaseREM)
                }
                .font(.subheadline)
                .foregroundStyle(NocturneColor.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func eventsText(title: String, detail: String?) -> Text {
        let main = Text(title).fontWeight(.semibold).foregroundStyle(NocturneColor.textPrimary)
        guard let detail else { return main }
        return Text("\(main) \(Text("· \(detail)").foregroundStyle(NocturneColor.textSecondary))")
    }

    // MARK: - Dette et régularité

    private var tiles: some View {
        HStack(alignment: .top, spacing: 12) {
            tile(title: "Dette de sommeil", value: model.debtValue, detail: model.debtDetail)
            tile(title: "Régularité", value: model.regularityValue, detail: model.regularityDetail)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(NocturneColor.textSecondary)
            Text(value)
                .font(NocturneFont.number(.title))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(NocturneColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - 7 dernières nuits

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("7 dernières nuits")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let average = model.weekAverageText {
                    Text(average)
                        .font(.footnote)
                        .foregroundStyle(NocturneColor.textSecondary)
                }
            }
            WeekChart(bars: model.week, objective: model.objective, format: model.format)
                .frame(height: 118)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.weekAccessibility)
            if let line = model.comparisonLine {
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(NocturneColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                Rectangle()
                    .fill(NocturneColor.separator)
                    .frame(height: 1)
                    .accessibilityHidden(true)
                Text("Objectifs")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                let objective = model.durationObjective
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(objective.title)
                        Spacer()
                        Text("\(objective.count) nuit\(objective.count > 1 ? "s" : "") sur \(objective.total)")
                            .foregroundStyle(NocturneColor.textSecondary)
                    }
                    .font(.subheadline)
                    ProgressBar(fraction: objective.total > 0 ? Double(objective.count) / Double(objective.total) : 0)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Barres de durée des 7 dernières nuits, avec la ligne de l'objectif (maquette E10).
private struct WeekChart: View {
    let bars: [WeekBar]
    let objective: TimeInterval
    let format: SleepFormat

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let gap: CGFloat = 8
            let count = CGFloat(max(1, bars.count))
            let column = (width - gap * (count - 1)) / count
            let barWidth = min(26, column)
            let baseline = height - 22
            let available = baseline - 19
            let longest = max(bars.compactMap(\.asleep).max() ?? 0, objective * 1.15)
            let scale = longest > 0 ? available / CGFloat(longest) : 0
            let objectiveY = baseline - CGFloat(objective) * scale
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: objectiveY))
                    path.addLine(to: CGPoint(x: width, y: objectiveY))
                }
                .stroke(NocturneColor.chevron, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Text("objectif \(format.duration(objective))")
                    .font(.system(size: 11))
                    .foregroundStyle(NocturneColor.textSecondary)
                    .frame(width: width, alignment: .leading)
                    .position(x: width / 2, y: objectiveY - 9)
                ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                    let center = CGFloat(index) * (column + gap) + column / 2
                    if let asleep = bar.asleep {
                        let barHeight = max(2, CGFloat(asleep) * scale)
                        UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 4, style: .continuous)
                            .fill(bar.isLast ? NocturneColor.lavender : NocturneColor.moonBlue)
                            .frame(width: barWidth, height: barHeight)
                            .position(x: center, y: baseline - barHeight / 2)
                        if bar.isLast {
                            Text(format.duration(asleep))
                                .font(.system(size: 11, weight: .semibold))
                                .fixedSize()
                                .position(x: center, y: baseline - barHeight - 12)
                        }
                    }
                    Text(bar.label)
                        .font(.system(size: 11, weight: bar.isLast ? .semibold : .regular))
                        .foregroundStyle(bar.isLast ? NocturneColor.textPrimary : NocturneColor.textSecondary)
                        .fixedSize()
                        .position(x: center, y: height - 8)
                }
            }
        }
    }
}

/// Barre de progression fine d'un objectif.
private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(NocturneColor.scoreTrack)
                Capsule()
                    .fill(NocturneColor.lavender)
                    .frame(width: proxy.size.width * CGFloat(min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
    }
}
