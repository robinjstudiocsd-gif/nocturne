import SwiftUI

/// Couleurs validées sur les maquettes de l'étape 2.
enum Theme {
    static let night = Color(red: 11 / 255, green: 16 / 255, blue: 38 / 255)        // #0B1026
    static let card = Color(red: 30 / 255, green: 42 / 255, blue: 90 / 255)         // #1E2A5A
    static let violet = Color(red: 110 / 255, green: 91 / 255, blue: 214 / 255)     // #6E5BD6
    static let lavender = Color(red: 185 / 255, green: 169 / 255, blue: 245 / 255)  // #B9A9F5
    static let moonBlue = Color(red: 143 / 255, green: 179 / 255, blue: 255 / 255)  // #8FB3FF
    static let amber = Color(red: 245 / 255, green: 185 / 255, blue: 113 / 255)     // #F5B971
    static let text = Color(red: 243 / 255, green: 244 / 255, blue: 250 / 255)      // #F3F4FA
    static let secondary = Color(red: 169 / 255, green: 177 / 255, blue: 214 / 255) // #A9B1D6
    static let ok = Color(red: 94 / 255, green: 211 / 255, blue: 155 / 255)         // #5ED39B

    static let nightScreen = Color(red: 5 / 255, green: 7 / 255, blue: 15 / 255)    // #05070F
    static let nightClock = Color(red: 154 / 255, green: 158 / 255, blue: 186 / 255) // #9A9EBA
    static let nightDim = Color(red: 126 / 255, green: 130 / 255, blue: 158 / 255)  // #7E829E
    static let red = Color(red: 224 / 255, green: 70 / 255, blue: 58 / 255)         // #E0463A
}

enum Format {
    static let french = Locale(identifier: "fr_FR")

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(french))
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(french))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
