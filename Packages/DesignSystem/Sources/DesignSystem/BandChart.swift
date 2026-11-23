import SwiftUI

/// Une ligne d'un graphique en bandes : un état de la nuit et sa couleur.
public struct BandRow: Identifiable, Sendable {
    public let title: String
    public let color: Color

    public init(title: String, color: Color) {
        self.title = title
        self.color = color
    }

    public var id: String { title }
}

/// Une plage du graphique : de `start` à `end` (fractions de la nuit, de 0 à 1), sur une ligne.
public struct BandSegment: Hashable, Sendable {
    public var start: Double
    public var end: Double
    public var row: Int

    public init(start: Double, end: Double, row: Int) {
        self.start = start
        self.end = end
        self.row = row
    }
}

/// Repère d'heure sous un graphique de la nuit.
public struct ChartTick: Identifiable, Hashable, Sendable {
    public var label: String
    /// Place du repère, de 0 (début) à 1 (fin).
    public var position: Double

    public init(label: String, position: Double) {
        self.label = label
        self.position = position
    }

    public var id: String { label }
}

/// Graphique en bandes des phases ou du profil de la nuit (maquettes E10 et E21) :
/// une ligne par état, des barres arrondies, reliées par un trait fin quand elles se suivent.
public struct BandChart: View {
    private static let rowHeight: CGFloat = 20

    private let rows: [BandRow]
    private let segments: [BandSegment]
    private let ticks: [ChartTick]
    private let summary: String

    public init(rows: [BandRow], segments: [BandSegment], ticks: [ChartTick], accessibilityLabel: String) {
        self.rows = rows
        self.segments = segments
        self.ticks = ticks
        self.summary = accessibilityLabel
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { row in
                    Text(row.title)
                        .font(.system(size: 12))
                        .foregroundStyle(NocturneColor.textSecondary)
                        .lineLimit(1)
                        .frame(height: 16, alignment: .leading)
                }
            }
            .frame(width: 76, alignment: .leading)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Canvas { context, size in
                    draw(in: &context, size: size)
                }
                .frame(height: CGFloat(rows.count) * Self.rowHeight - 4)
                .accessibilityElement()
                .accessibilityLabel(summary)
                GeometryReader { proxy in
                    ForEach(ticks) { tick in
                        Text(tick.label)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(NocturneColor.textSecondary)
                            .fixedSize()
                            .position(x: proxy.size.width * tick.position, y: 8)
                    }
                }
                .frame(height: 16)
                .accessibilityHidden(true)
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let x = { (fraction: Double) -> CGFloat in CGFloat(min(1, max(0, fraction))) * size.width }
        let center = { (row: Int) -> CGFloat in CGFloat(row) * Self.rowHeight + 8 }
        var links = Path()
        for index in segments.indices.dropFirst() {
            let previous = segments[index - 1]
            let segment = segments[index]
            guard abs(previous.end - segment.start) < 0.000_1, previous.row != segment.row else { continue }
            links.move(to: CGPoint(x: x(segment.start), y: center(previous.row)))
            links.addLine(to: CGPoint(x: x(segment.start), y: center(segment.row)))
        }
        context.stroke(links, with: .color(NocturneColor.chartLink), lineWidth: 1)
        for segment in segments where rows.indices.contains(segment.row) {
            let width = max(1.5, x(segment.end) - x(segment.start) - 1)
            let rect = CGRect(x: x(segment.start) + 0.5, y: CGFloat(segment.row) * Self.rowHeight + 2, width: width, height: 12)
            context.fill(Path(roundedRect: rect, cornerRadius: min(3, width / 2)), with: .color(rows[segment.row].color))
        }
    }
}

/// Légende d'un graphique de la nuit : couleur, état et durée, sur deux colonnes.
public struct BandLegend: View {
    public struct Item: Identifiable, Sendable {
        public let title: String
        public let value: String
        public let color: Color

        public init(title: String, value: String, color: Color) {
            self.title = title
            self.value = value
            self.color = color
        }

        public var id: String { title }
    }

    private let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    public var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(item.color)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(item.title)
                        .foregroundStyle(NocturneColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text(item.value)
                        .foregroundStyle(NocturneColor.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .font(.footnote)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
