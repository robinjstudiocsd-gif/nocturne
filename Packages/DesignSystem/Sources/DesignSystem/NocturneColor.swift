import SwiftUI

/// Couleurs validées sur les maquettes (thème sombre). Le thème clair viendra avec ses maquettes.
public enum NocturneColor {
    // Fonds
    public static let night = Color(hex: 0x0B1026)
    public static let card = Color(hex: 0x1E2A5A)
    public static let elevated = Color(hex: 0x27346A)
    public static let separator = Color(hex: 0x2B386E)
    public static let tabBar = Color(hex: 0x0E1430)

    /// Choix actif d'un sélecteur à segments.
    public static let segmentSelected = Color(hex: 0x3A4A8C)
    /// Choix actif parmi les visages d'humeur.
    public static let moodSelected = Color(hex: 0x3A3586)
    /// Filet au-dessus des barres fixées en bas d'écran.
    public static let hairline = Color(hex: 0x1B2450)
    /// Interrupteur activé.
    public static let switchOn = Color(hex: 0x34C77B)

    // Textes
    public static let textPrimary = Color(hex: 0xF3F4FA)
    public static let textSecondary = Color(hex: 0xA9B1D6)
    public static let textTertiary = Color(hex: 0x949DC8)
    /// Texte des puces non choisies.
    public static let textSoft = Color(hex: 0xD3D7EE)
    /// Texte d'exemple des champs vides.
    public static let placeholder = Color(hex: 0x8E97C4)
    /// Chevron des lignes qui ouvrent un écran.
    public static let chevron = Color(hex: 0x6F7AB0)
    /// Jours hors du mois ou à venir, dans le calendrier.
    public static let textFaint = Color(hex: 0x5C6699)
    /// Icônes des boutons ronds.
    public static let iconSoft = Color(hex: 0xC9CEEA)
    /// Actions qui suppriment.
    public static let destructive = Color(hex: 0xFF8A80)

    // Accents
    public static let violet = Color(hex: 0x6E5BD6)
    public static let lavender = Color(hex: 0xB9A9F5)
    public static let moonBlue = Color(hex: 0x8FB3FF)
    public static let amber = Color(hex: 0xF5B971)
    public static let scoreRing = Color(hex: 0x8B78F0)
    public static let scoreTrack = Color(hex: 0x2E3B73)
    public static let success = Color(hex: 0x5ED39B)

    // Phases de sommeil (graphiques), ajustées pour rester distinctes, daltonisme compris.
    public static let phaseAwake = Color(hex: 0xF5B971)
    public static let phaseREM = Color(hex: 0xC6ADF8)
    public static let phaseLight = Color(hex: 0x5592E6)
    public static let phaseDeep = Color(hex: 0x7A4EDD)

    // Profil de la nuit sans montre (maquette E21).
    public static let profileAwake = Color(hex: 0xF5B971)
    public static let profileAgitated = Color(hex: 0xA9B1D6)
    public static let profileCalm = Color(hex: 0x5C6BA8)
    /// Traits fins qui relient les bandes des graphiques de la nuit.
    public static let chartLink = Color(hex: 0x3B4884)

    // Écran de nuit
    public static let nightScreen = Color(hex: 0x05070F)
    public static let nightClock = Color(hex: 0x9A9EBA)
    public static let nightText = Color(hex: 0x8A8EA8)
    public static let nightDim = Color(hex: 0x7E829E)
    public static let nightRed = Color(hex: 0xE0463A)
}

extension Color {
    /// Couleur à partir d'une valeur hexadécimale 0xRRGGBB.
    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
