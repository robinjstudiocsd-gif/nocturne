import DesignSystem
import SleepDomain
import SwiftUI
import UIKit

/// « Réécouter la nuit » (maquette E27) : lecture continue, frise du niveau sonore avec repères,
/// saut d'un événement à l'autre, vitesse, saut des silences, favori, export d'un passage.
struct ReplayView: View {
    @State private var model: ReplayViewModel

    init(session: SleepSession, dependencies: JournalDependencies) {
        _model = State(initialValue: ReplayViewModel(session: session, dependencies: dependencies))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            chartCard
                .padding(.horizontal, 16)
                .padding(.top, 12)
            controls
                .padding(.top, 12)
            options
                .padding(.top, 12)
            eventsSection
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NocturneColor.night)
        .navigationTitle("Réécouter la nuit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.export() }
                } label: {
                    if model.isExporting {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(!model.hasAudio || model.isExporting)
                .accessibilityLabel("Exporter une minute autour de la lecture")
            }
        }
        .sheet(item: exportBinding) { item in
            ShareSheet(url: item.url)
                .presentationDetents([.medium, .large])
        }
        .alert("Réécoute", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { await model.start() }
        .onDisappear { model.close() }
    }

    // MARK: - En-tête

    private var header: some View {
        VStack(spacing: 2) {
            Text(model.title)
                .font(.footnote)
                .foregroundStyle(NocturneColor.textSecondary)
            Text(model.clockText)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NocturneColor.textPrimary)
                .padding(.top, 2)
            HStack(spacing: 4) {
                Text(model.currentTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(NocturneColor.textPrimary)
                if let meta = model.currentMeta {
                    Text("· \(meta)")
                        .foregroundStyle(NocturneColor.textSecondary)
                }
            }
            .font(.subheadline)
            if !model.hasAudio && !model.isLoading {
                Text("L’audio de cette nuit n’est pas disponible : seuls la frise et les événements restent.")
                    .font(.footnote)
                    .foregroundStyle(NocturneColor.amber)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Frise

    private var chartCard: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                NightLevelChart(
                    columns: model.timeline?.columns ?? [],
                    markers: markerFractions,
                    currentMarker: currentMarkerFraction,
                    progress: progress
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            model.seek(toFraction: Double(value.location.x / max(1, proxy.size.width)))
                        }
                )
            }
            .frame(height: 84)
            .accessibilityElement()
            .accessibilityLabel("Frise du niveau sonore de la nuit, lecture à \(model.clockText)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.jump(by: 300)
                case .decrement: model.jump(by: -300)
                @unknown default: break
                }
            }

            GeometryReader { proxy in
                ForEach(Array(model.ticks.enumerated()), id: \.offset) { _, tick in
                    Text(tick.label)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(NocturneColor.textSecondary)
                        .fixedSize()
                        .position(x: proxy.size.width * tick.fraction, y: 8)
                }
            }
            .frame(height: 16)
            .accessibilityHidden(true)
        }
        .padding(12)
        .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var progress: Double {
        guard model.state.duration > 0 else { return 0 }
        return model.state.position / model.state.duration
    }

    private var markerFractions: [Double] {
        guard let timeline = model.timeline, timeline.duration > 0 else { return [] }
        return model.visibleEvents.map { (timeline.offset(of: $0.start) + $0.duration / 2) / timeline.duration }
    }

    private var currentMarkerFraction: Double? {
        guard let timeline = model.timeline, timeline.duration > 0, let event = model.currentEvent else { return nil }
        return (timeline.offset(of: event.start) + event.duration / 2) / timeline.duration
    }

    // MARK: - Commandes

    private var controls: some View {
        HStack {
            iconButton("backward.end.fill", label: "Événement précédent", enabled: model.hasPrevious) { model.previous() }
            Spacer()
            textButton("−15 s", label: "Reculer de 15 secondes") { model.jump(by: -15) }
            Spacer()
            Button {
                model.togglePlay()
            } label: {
                Image(systemName: model.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(NocturneColor.violet, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!model.hasAudio)
            .opacity(model.hasAudio ? 1 : 0.4)
            .accessibilityLabel(model.state.isPlaying ? "Pause" : "Lecture")
            Spacer()
            textButton("+15 s", label: "Avancer de 15 secondes") { model.jump(by: 15) }
            Spacer()
            iconButton("forward.end.fill", label: "Événement suivant", enabled: model.hasNext) { model.next() }
        }
        .padding(.horizontal, 16)
    }

    private func iconButton(_ systemName: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(NocturneColor.textSoft)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    private func textButton(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(NocturneColor.textPrimary)
                .frame(width: 52, height: 44)
                .background(NocturneColor.card, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!model.hasAudio)
        .accessibilityLabel(label)
    }

    private var options: some View {
        HStack(spacing: 8) {
            Button {
                model.cycleRate()
            } label: {
                Text(model.rateLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(NocturneColor.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(NocturneColor.card, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Vitesse de lecture : \(model.rateLabel)")

            Button {
                model.toggleSkip()
            } label: {
                Text("Sauter les silences")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(NocturneColor.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(model.state.skipsSilences ? NocturneColor.moodSelected : NocturneColor.card, in: Capsule())
                    .overlay(Capsule().stroke(model.state.skipsSilences ? NocturneColor.lavender : NocturneColor.card, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(model.state.skipsSilences ? .isSelected : [])

            Button {
                Task { await model.toggleFavorite() }
            } label: {
                Image(systemName: model.isCurrentFavorite ? "star.fill" : "star")
                    .foregroundStyle(model.isCurrentFavorite ? NocturneColor.amber : NocturneColor.textSoft)
                    .frame(width: 44, height: 36)
                    .background(NocturneColor.card, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.currentEvent == nil)
            .opacity(model.currentEvent == nil ? 0.4 : 1)
            .accessibilityLabel("Favori")
            .accessibilityAddTraits(model.isCurrentFavorite ? .isSelected : [])
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Événements

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Événements de la nuit")
                .font(.headline)
                .foregroundStyle(NocturneColor.textPrimary)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(model.chips.enumerated()), id: \.offset) { _, chip in
                        let isSelected = model.filter == chip.kind
                        Button {
                            model.filter = chip.kind
                        } label: {
                            Text(chip.label)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(isSelected ? NocturneColor.night : NocturneColor.textSoft)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(isSelected ? NocturneColor.lavender : NocturneColor.card, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            if model.visibleEvents.isEmpty && !model.isLoading {
                Text("Aucun événement repéré cette nuit.")
                    .font(.subheadline)
                    .foregroundStyle(NocturneColor.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.visibleEvents) { event in
                        eventRow(event)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func eventRow(_ event: NightEvent) -> some View {
        let isCurrent = model.currentEvent?.id == event.id
        return Button {
            model.select(event)
        } label: {
            HStack(spacing: 12) {
                Text(model.clock(event))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 46, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(event.kind.title)
                            .font(.subheadline)
                        if event.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(NocturneColor.amber)
                                .accessibilityLabel("favori")
                        }
                    }
                    Text(model.meta(event))
                        .font(.footnote)
                        .foregroundStyle(NocturneColor.textSecondary)
                }
                Spacer(minLength: 8)
                Circle()
                    .fill(isCurrent ? NocturneColor.amber : NocturneColor.textFaint)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(NocturneColor.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 52)
            .background(isCurrent ? NocturneColor.elevated : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    // MARK: - Liaisons

    private var exportBinding: Binding<ExportedFile?> {
        Binding(
            get: { model.exportedURL.map(ExportedFile.init) },
            set: { if $0 == nil { model.exportedURL = nil } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

/// Fichier exporté, présenté dans la feuille de partage.
private struct ExportedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Feuille de partage d'iOS, pour un passage exporté.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Frise du niveau sonore : aire, partie déjà écoutée, repères d'événements et tête de lecture.
struct NightLevelChart: View {
    let columns: [Float?]
    let markers: [Double]
    let currentMarker: Double?
    let progress: Double

    /// Niveaux affichés entre ces bornes, en dB relatifs.
    private let floorDb: Float = -70
    private let ceilingDb: Float = -10

    var body: some View {
        Canvas { context, size in
            let top: CGFloat = 20
            let height = size.height
            let count = max(1, columns.count)
            func y(_ level: Float?) -> CGFloat {
                let value = CGFloat(((level ?? floorDb) - floorDb) / (ceilingDb - floorDb))
                return height - min(1, max(0.04, value)) * (height - top)
            }
            func x(_ index: Int) -> CGFloat {
                count == 1 ? 0 : CGFloat(index) / CGFloat(count - 1) * size.width
            }

            var line = Path()
            var area = Path()
            area.move(to: CGPoint(x: 0, y: height))
            for (index, level) in columns.enumerated() {
                let point = CGPoint(x: x(index), y: y(level))
                if index == 0 {
                    line.move(to: point)
                } else {
                    line.addLine(to: point)
                }
                area.addLine(to: point)
            }
            area.addLine(to: CGPoint(x: size.width, y: height))
            area.closeSubpath()

            let blue = NocturneColor.moonBlue
            context.fill(area, with: .color(blue.opacity(0.14)))
            let head = CGFloat(min(1, max(0, progress))) * size.width
            var played = context
            played.clip(to: Path(CGRect(x: 0, y: 0, width: head, height: height)))
            played.fill(area, with: .color(blue.opacity(0.4)))
            context.stroke(line, with: .color(blue), style: StrokeStyle(lineWidth: 2, lineJoin: .round))

            let amber = NocturneColor.amber
            for fraction in markers {
                let cx = CGFloat(fraction) * size.width
                var guide = Path()
                guide.move(to: CGPoint(x: cx, y: 13))
                guide.addLine(to: CGPoint(x: cx, y: height))
                context.stroke(guide, with: .color(amber.opacity(0.45)), lineWidth: 1)
                let dot = Path(ellipseIn: CGRect(x: cx - 5, y: 3, width: 10, height: 10))
                context.fill(dot, with: .color(amber))
                context.stroke(dot, with: .color(NocturneColor.card), lineWidth: 2)
            }
            if let currentMarker {
                let cx = CGFloat(currentMarker) * size.width
                let dot = Path(ellipseIn: CGRect(x: cx - 6, y: 2, width: 12, height: 12))
                context.fill(dot, with: .color(amber))
                context.stroke(dot, with: .color(NocturneColor.textPrimary), lineWidth: 2)
            }

            var playhead = Path()
            playhead.move(to: CGPoint(x: head, y: 16))
            playhead.addLine(to: CGPoint(x: head, y: height - 4))
            context.stroke(playhead, with: .color(NocturneColor.textPrimary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: head - 5, y: height - 10, width: 10, height: 10)), with: .color(NocturneColor.textPrimary))
        }
    }
}
