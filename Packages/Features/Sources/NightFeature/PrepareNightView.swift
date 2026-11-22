import DesignSystem
import SwiftUI

/// Onglet Nuit : « Préparer ma nuit ». L'écoute de la nuit arrive au lot 2, le réveil au lot 5.
public struct PrepareNightView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            EmptyStateView(
                systemImage: "moon.stars",
                title: "Préparer ma nuit",
                message: "Ici, tu lanceras l'écoute de ta nuit et régleras ton réveil."
            )
            .padding(16)
        }
        .background(NocturneColor.night)
        .navigationTitle("Nuit")
    }
}
