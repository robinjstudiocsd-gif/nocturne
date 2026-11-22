import SwiftUI

/// Bouton principal : fond violet, texte blanc, 50 points de haut.
public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(NocturneColor.violet.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Bouton secondaire : fond indigo clair, texte clair, 44 points de haut.
public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(NocturneColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(NocturneColor.elevated.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
