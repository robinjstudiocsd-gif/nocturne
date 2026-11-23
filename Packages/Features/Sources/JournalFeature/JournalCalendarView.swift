import DesignSystem
import SleepDomain
import SwiftUI

/// Calendrier du mois : chaque jour montre la durée de la nuit qui s'y termine.
/// Le score de la nuit prendra cette place avec l'analyse (lot 4).
struct JournalCalendarView: View {
    let model: JournalViewModel

    private static let weekdays = ["lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."]
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                monthButton(systemName: "chevron.left", label: "Mois précédent", offset: -1)
                Spacer()
                Text(model.monthTitle)
                    .font(.headline)
                    .foregroundStyle(NocturneColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                monthButton(systemName: "chevron.right", label: "Mois suivant", offset: 1)
                    .disabled(!model.canShowNextMonth)
                    .opacity(model.canShowNextMonth ? 1 : 0.3)
            }

            HStack(spacing: 4) {
                ForEach(Self.weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption)
                        .foregroundStyle(NocturneColor.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(model.days) { day in
                    if let session = day.sessions.first, day.isInMonth {
                        NavigationLink(value: NightRoute(id: session.id)) {
                            cell(day)
                        }
                        .buttonStyle(.plain)
                    } else {
                        cell(day)
                    }
                }
            }

            Text("Sous chaque jour, la durée de la nuit qui s’y termine. Touche un jour pour ouvrir sa fiche.")
                .font(.footnote)
                .foregroundStyle(NocturneColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func monthButton(systemName: String, label: String, offset: Int) -> some View {
        Button {
            model.showMonth(offset: offset)
        } label: {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(NocturneColor.lavender)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func cell(_ day: JournalDay) -> some View {
        let hasNight = day.isInMonth && !day.sessions.isEmpty
        let isDim = !day.isInMonth || day.isFuture
        return VStack(spacing: 1) {
            Text("\(day.dayNumber)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isDim ? NocturneColor.textFaint : NocturneColor.textPrimary)
            Text(hasNight ? (model.calendarValue(for: day) ?? " ") : " ")
                .font(NocturneFont.number(.caption2))
                .foregroundStyle(NocturneColor.lavender)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(hasNight ? NocturneColor.card : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(day.isToday ? NocturneColor.lavender : Color.clear, lineWidth: 2)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel(for: day))
    }
}
