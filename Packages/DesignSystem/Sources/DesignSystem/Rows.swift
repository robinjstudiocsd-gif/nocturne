import SwiftUI

/// Pastille d'icône colorée des lignes de liste (30 × 30 points).
public struct IconTile: View {
    private let systemName: String
    private let background: Color
    private let foreground: Color

    public init(systemName: String, background: Color, foreground: Color = .white) {
        self.systemName = systemName
        self.background = background
        self.foreground = foreground
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: 30, height: 30)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Titre d'un groupe de lignes, en capitales (« RÉVEIL »), avec une indication à droite si besoin.
public struct GroupTitle: View {
    private let title: String
    private let trailing: String?

    public init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .textCase(.uppercase)
                .tracking(0.3)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(NocturneColor.textSecondary)
        .padding(.horizontal, 16)
    }
}

/// Explication sous un groupe de lignes.
public struct GroupFootnote: View {
    private let text: String
    private let systemImage: String?

    public init(_ text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(NocturneColor.textSecondary)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Groupe de lignes sur fond de carte, coins de 12 points.
public struct RowGroup<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(NocturneColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Séparateur entre deux lignes d'un groupe, aligné sur le texte.
public struct RowDivider: View {
    private let inset: CGFloat

    public init(inset: CGFloat = 58) {
        self.inset = inset
    }

    public var body: some View {
        Rectangle()
            .fill(NocturneColor.separator)
            .frame(height: 1)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

/// Contenu d'une ligne : pastille, titre, sous-titre, valeur et chevron.
public struct RowLabel: View {
    private let icon: IconTile?
    private let title: String
    private let subtitle: String?
    private let value: String?
    private let showsChevron: Bool

    public init(icon: IconTile? = nil, title: String, subtitle: String? = nil, value: String? = nil, showsChevron: Bool = true) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.showsChevron = showsChevron
    }

    public var body: some View {
        HStack(spacing: 12) {
            if let icon {
                icon
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(NocturneColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(NocturneColor.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(NocturneColor.textSecondary)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NocturneColor.chevron)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: subtitle == nil ? 52 : 64)
        .contentShape(Rectangle())
    }
}
