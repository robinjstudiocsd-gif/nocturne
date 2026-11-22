import DesignSystem
import SwiftUI

/// Accueil. Au lot 0 : la carte « Ce soir » et l'état vide ; le tableau de bord complet arrive au lot 4.
public struct DashboardView: View {
    private let onPrepareNight: () -> Void
    private let onOpenSettings: () -> Void

    public init(onPrepareNight: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.onPrepareNight = onPrepareNight
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: "moon.fill")
                            .font(.title3)
                            .foregroundStyle(NocturneColor.lavender)
                            .frame(width: 40, height: 40)
                            .background(NocturneColor.elevated, in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ce soir")
                                .font(.headline)
                            Text("Prépare ta nuit quand tu vas te coucher.")
                                .font(.subheadline)
                                .foregroundStyle(NocturneColor.textSecondary)
                        }
                    }
                    Button("Préparer ma nuit", action: onPrepareNight)
                        .buttonStyle(PrimaryButtonStyle())
                }
                EmptyStateView(
                    systemImage: "moon.zzz",
                    title: "Pas encore de nuit",
                    message: "Ta première nuit apparaîtra ici le lendemain matin."
                )
            }
            .padding(16)
        }
        .background(NocturneColor.night)
        .foregroundStyle(NocturneColor.textPrimary)
        .navigationTitle("Accueil")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onOpenSettings) {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("Réglages")
            }
        }
    }
}
