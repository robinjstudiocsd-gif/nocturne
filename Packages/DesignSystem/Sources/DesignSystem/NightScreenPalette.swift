import SwiftUI

/// Couleurs de l'écran « Nuit en cours » : très sombre, ou rouge pour ne pas éblouir.
public struct NightScreenPalette: Sendable {
    public let background: Color
    public let clock: Color
    public let text: Color
    public let dim: Color
    public let line: Color
    public let fill: Color

    private init(background: UInt32, clock: UInt32, text: UInt32, dim: UInt32, line: UInt32, fill: UInt32) {
        self.background = Color(hex: background)
        self.clock = Color(hex: clock)
        self.text = Color(hex: text)
        self.dim = Color(hex: dim)
        self.line = Color(hex: line)
        self.fill = Color(hex: fill)
    }

    public static let dark = NightScreenPalette(background: 0x05070F, clock: 0x9A9EBA, text: 0x8A8EA8, dim: 0x7E829E, line: 0x23273A, fill: 0x0A0D19)
    public static let red = NightScreenPalette(background: 0x000000, clock: 0xE0463A, text: 0xE0463A, dim: 0xD8433A, line: 0x4A1511, fill: 0x120403)
}
