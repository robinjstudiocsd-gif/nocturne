import DashboardFeature
import DesignSystem
import InsightsFeature
import JournalFeature
import NightFeature
import SettingsFeature
import StatisticsFeature
import SwiftUI

/// Les cinq onglets de l'app, avec une pile de navigation par onglet.
enum AppTab: Hashable {
    case home
    case journal
    case night
    case statistics
    case insights
}

struct RootView: View {
    let container: AppContainer
    @State private var selection: AppTab = .home
    @State private var showsSettings = false
    @State private var journalModel: JournalViewModel
    @State private var nightModel: NightViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(container: AppContainer) {
        self.container = container
        _journalModel = State(initialValue: JournalViewModel(repository: container.sessions))
        _nightModel = State(initialValue: container.makeNightModel())
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Accueil", systemImage: "house", value: AppTab.home) {
                NavigationStack {
                    DashboardView(
                        onPrepareNight: { selection = .night },
                        onOpenSettings: { showsSettings = true }
                    )
                }
            }
            Tab("Journal", systemImage: "calendar", value: AppTab.journal) {
                NavigationStack {
                    JournalView(model: journalModel)
                }
            }
            Tab("Nuit", systemImage: "moon", value: AppTab.night) {
                NavigationStack {
                    PrepareNightView(model: nightModel)
                }
            }
            Tab("Statistiques", systemImage: "chart.bar", value: AppTab.statistics) {
                NavigationStack {
                    StatisticsView()
                }
            }
            Tab("Conseils", systemImage: "lightbulb", value: AppTab.insights) {
                NavigationStack {
                    InsightsView()
                }
            }
        }
        .tint(NocturneColor.lavender)
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                SettingsView(info: container.settingsInfo, loadJournal: { [journal = container.journal] in
                    await journal.recentLines(limit: 200)
                })
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { showsSettings = false }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: nightCoverBinding) {
            NightFlowView(model: nightModel) {
                selection = .home
                Task { await journalModel.load() }
            }
        }
        .task {
            await nightModel.observe()
        }
        .task {
            await container.night.recoverIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: container.journal.record("App au premier plan")
            case .background: container.journal.record("App en arrière-plan")
            default: break
            }
        }
    }

    /// L'écran de nuit recouvre l'app tant qu'une session tourne, puis jusqu'à la fin de « Bonjour ».
    private var nightCoverBinding: Binding<Bool> {
        Binding(get: { nightModel.isCoverPresented }, set: { _ in })
    }
}
