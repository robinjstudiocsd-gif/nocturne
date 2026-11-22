import SwiftUI
import WidgetKit

/// Widget de test de la phase 0 : il prouve qu'un widget de l'app s'affiche sur l'écran d'accueil.
struct TestEntry: TimelineEntry {
    let date: Date
}

struct TestProvider: TimelineProvider {
    func placeholder(in context: Context) -> TestEntry {
        TestEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (TestEntry) -> Void) {
        completion(TestEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TestEntry>) -> Void) {
        let entry = TestEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct TestWidgetView: View {
    let entry: TestEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "moon.stars.fill")
                .font(.title2)
                .foregroundStyle(WidgetPalette.lavender)
            Spacer(minLength: 0)
            Text("Nocturne")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Widget OK")
                .font(.subheadline)
                .foregroundStyle(WidgetPalette.secondary)
            Text(entry.date, style: .time)
                .font(.caption)
                .foregroundStyle(WidgetPalette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct TestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NocturneTestWidget", provider: TestProvider()) { entry in
            TestWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPalette.night }
        }
        .configurationDisplayName("Nocturne")
        .description("Widget de test de la phase 0.")
        .supportedFamilies([.systemSmall])
    }
}
