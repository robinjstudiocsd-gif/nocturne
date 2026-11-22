import SwiftUI

/// Anneau du score de sommeil sur 100.
public struct ScoreRing: View {
    private let score: Int
    private let size: CGFloat

    public init(score: Int, size: CGFloat = 88) {
        self.score = min(100, max(0, score))
        self.size = size
    }

    public var body: some View {
        let lineWidth = size * 0.09
        ZStack {
            Circle()
                .stroke(NocturneColor.scoreTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(NocturneColor.scoreRing, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .foregroundStyle(NocturneColor.textPrimary)
                Text("score")
                    .font(.caption2)
                    .foregroundStyle(NocturneColor.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score \(score) sur 100")
    }
}
