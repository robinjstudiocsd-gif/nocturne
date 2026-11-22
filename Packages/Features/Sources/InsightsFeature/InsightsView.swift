import DesignSystem
import SwiftUI

/// Onglet Conseils. Les conseils, les objectifs et le chronotype arrivent au lot 7.
public struct InsightsView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            EmptyStateView(
                systemImage: "lightbulb",
                title: "Conseils",
                message: "Des conseils tirés de tes propres nuits apparaîtront ici."
            )
            .padding(16)
        }
        .background(NocturneColor.night)
        .navigationTitle("Conseils")
    }
}
