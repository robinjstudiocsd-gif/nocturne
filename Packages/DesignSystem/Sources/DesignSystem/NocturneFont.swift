import SwiftUI

/// Typographie : SF Pro pour les textes, SF Pro Rounded pour les chiffres clés.
/// Les styles suivent la taille de texte choisie dans les réglages de l'iPhone.
public enum NocturneFont {
    /// Grand chiffre arrondi (score, horloge, durées).
    public static func number(_ style: Font.TextStyle = .title2, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

    /// Chiffre arrondi de taille fixe, pour les horloges plein écran.
    public static func clock(size: CGFloat, weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
