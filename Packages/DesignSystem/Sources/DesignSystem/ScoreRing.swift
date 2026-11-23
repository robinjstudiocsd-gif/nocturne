import SwiftUI

/// Anneau du score de sommeil sur 100 (maquettes E10, E21, E33).
/// Sans score : un tiret. Score approximatif (fiabilité faible) : précédé de « environ ».
public struct ScoreRing: View {
    private let score: Int?
    private let approximate: Bool
    private let size: CGFloat

    public init(score: Int?, approximate: Bool = false, size: CGFloat = 88) {
        self.score = score.map { min(100, max(0, $0)) }
        self.approximate = approximate
        self.size = size
    }

    public var body: some View {
        let lineWidth = size * 0.09
        ZStack {
            Circle()
                .inset(by: size * 0.073)
                .stroke(NocturneColor.scoreTrack, lineWidth: lineWidth)
            if let score {
                Circle()
                    .inset(by: size * 0.073)
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(NocturneColor.scoreRing, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                if approximate, score != nil {
                    caption("environ")
                }
                Text(score.map { "\($0)" } ?? "—")
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .foregroundStyle(NocturneColor.textPrimary)
                if !approximate || score == nil {
                    caption("score")
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(NocturneColor.textSecondary)
    }

    private var accessibilityText: String {
        guard let score else { return "Score indisponible" }
        return approximate ? "Score environ \(score) sur 100" : "Score \(score) sur 100"
    }
}

/// Petite étiquette arrondie (« Fiabilité moyenne », « iPhone seul »).
public struct InfoChip: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(NocturneColor.textSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(NocturneColor.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
