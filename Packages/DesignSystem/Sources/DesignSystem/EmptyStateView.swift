import SwiftUI

/// Message affiché quand une rubrique n'a encore rien à montrer.
public struct EmptyStateView: View {
    private let systemImage: String
    private let title: String
    private let message: String

    public init(systemImage: String, title: String, message: String) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(NocturneColor.lavender)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(NocturneColor.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(NocturneColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
    }
}
