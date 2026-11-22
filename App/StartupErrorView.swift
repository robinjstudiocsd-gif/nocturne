import DesignSystem
import SwiftUI

/// Affiché si la base de données ne peut pas s'ouvrir : l'app ne plante pas, elle explique.
struct StartupErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Nocturne ne peut pas démarrer",
                message: "La base de données ne s'ouvre pas. Tes nuits ne sont pas effacées. Détail : \(message)"
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NocturneColor.night)
    }
}
