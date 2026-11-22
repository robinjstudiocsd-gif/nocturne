import SwiftUI

/// Petite valeur chiffrée avec son libellé (« Sommeil 7 h 51 »).
public struct StatTile: View {
    private let label: String
    private let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(NocturneColor.textSecondary)
            Text(value)
                .font(NocturneFont.number(.title3))
                .foregroundStyle(NocturneColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}
