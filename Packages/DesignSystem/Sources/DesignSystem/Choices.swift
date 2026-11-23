import SwiftUI

/// Sélecteur à segments (« Nuit | Sieste »).
public struct SegmentedControl<Value: Hashable>: View {
    private let options: [Value]
    private let label: (Value) -> String
    @Binding private var selection: Value

    public init(_ options: [Value], selection: Binding<Value>, label: @escaping (Value) -> String) {
        self.options = options
        self.label = label
        _selection = selection
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? NocturneColor.textPrimary : NocturneColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(isSelected ? NocturneColor.segmentSelected : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Puce de choix (« Aucune », « 1 », « 2 »…).
public struct ChoiceChip: View {
    private let label: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ label: String, isSelected: Bool, action: @escaping () -> Void) {
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? NocturneColor.night : NocturneColor.textSoft)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(isSelected ? NocturneColor.lavender : NocturneColor.elevated, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Dispose les éléments à la suite, en passant à la ligne quand la place manque.
public struct FlowLayout: Layout {
    private let spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty && current.width + spacing + size.width > maxWidth {
                rows.append(current)
                current = Row(indices: [], y: current.y + current.height + spacing, width: 0, height: 0)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

/// Échelle de 1 à 5 (énergie, stress) : les cases jusqu'au choix se remplissent.
/// Toucher à nouveau le choix l'efface.
public struct LevelScale: View {
    @Binding private var value: Int?
    private let name: String
    private let lowLabel: String
    private let highLabel: String

    public init(value: Binding<Int?>, name: String, lowLabel: String, highLabel: String) {
        _value = value
        self.name = name
        self.lowLabel = lowLabel
        self.highLabel = highLabel
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { level in
                    let isFilled = (value ?? 0) >= level
                    Button {
                        value = value == level ? nil : level
                    } label: {
                        Text("\(level)")
                            .font(NocturneFont.number(.body))
                            .foregroundStyle(isFilled ? NocturneColor.night : NocturneColor.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(isFilled ? NocturneColor.lavender : NocturneColor.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(name) \(level) sur 5")
                    .accessibilityAddTraits(value == level ? .isSelected : [])
                }
            }
            HStack {
                Text(lowLabel)
                Spacer()
                Text(highLabel)
            }
            .font(.caption)
            .foregroundStyle(NocturneColor.textSecondary)
            .accessibilityHidden(true)
        }
    }
}

/// Visage d'humeur, de 1 (très mal) à 5 (très bien), dessiné au trait.
public struct MoodFace: View {
    private let level: Int

    public init(level: Int) {
        self.level = min(5, max(1, level))
    }

    public var body: some View {
        ZStack {
            MoodFaceStroke(level: level)
                .stroke(style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
            MoodFaceEyes()
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

/// Contour et bouche, dans une grille de 24 × 24.
private struct MoodFaceStroke: Shape {
    let level: Int

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + 3 * scale, y: rect.minY + 3 * scale, width: 18 * scale, height: 18 * scale))
        switch level {
        case 1:
            path.move(to: point(8, 16.6))
            path.addCurve(to: point(12, 14.2), control1: point(9.2, 14.9), control2: point(10.5, 14.2))
            path.addCurve(to: point(16, 16.6), control1: point(13.5, 14.2), control2: point(14.8, 14.9))
        case 2:
            path.move(to: point(8.5, 16.1))
            path.addCurve(to: point(12, 14.8), control1: point(9.5, 15.2), control2: point(10.7, 14.8))
            path.addCurve(to: point(15.5, 16.1), control1: point(13.3, 14.8), control2: point(14.5, 15.2))
        case 3:
            path.move(to: point(8.5, 15.3))
            path.addLine(to: point(15.5, 15.3))
        case 4:
            path.move(to: point(8.5, 14.6))
            path.addCurve(to: point(12, 15.9), control1: point(9.5, 15.5), control2: point(10.7, 15.9))
            path.addCurve(to: point(15.5, 14.6), control1: point(13.3, 15.9), control2: point(14.5, 15.5))
        default:
            path.move(to: point(8, 14.1))
            path.addCurve(to: point(12, 16.7), control1: point(9.2, 15.9), control2: point(10.5, 16.7))
            path.addCurve(to: point(16, 14.1), control1: point(13.5, 16.7), control2: point(14.8, 15.9))
        }
        return path
    }
}

/// Les deux yeux, pleins.
private struct MoodFaceEyes: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let radius = 1.3 * scale
        var path = Path()
        for x in [CGFloat(9), CGFloat(15)] {
            path.addEllipse(in: CGRect(x: rect.minX + x * scale - radius, y: rect.minY + 10 * scale - radius, width: radius * 2, height: radius * 2))
        }
        return path
    }
}
