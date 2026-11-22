import SwiftUI
import WidgetKit

@main
struct NocturneWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TestWidget()
        NightLiveActivity()
    }
}

enum WidgetPalette {
    static let night = Color(red: 11 / 255, green: 16 / 255, blue: 38 / 255)
    static let lavender = Color(red: 185 / 255, green: 169 / 255, blue: 245 / 255)
    static let amber = Color(red: 245 / 255, green: 185 / 255, blue: 113 / 255)
    static let secondary = Color(red: 169 / 255, green: 177 / 255, blue: 214 / 255)
}
