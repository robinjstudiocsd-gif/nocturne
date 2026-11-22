import DesignSystem
import SwiftUI

/// Onglet Statistiques. Les graphiques et les bilans arrivent au lot 7.
public struct StatisticsView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            EmptyStateView(
                systemImage: "chart.bar",
                title: "Statistiques",
                message: "Tes tendances apparaîtront ici après quelques nuits."
            )
            .padding(16)
        }
        .background(NocturneColor.night)
        .navigationTitle("Statistiques")
    }
}
