import DesignSystem
import SleepDomain
import SwiftUI

/// Journal des nuits (maquette E20) : liste par semaine ou calendrier du mois, filtre, recherche, ajout.
public struct JournalView: View {
    @Bindable private var model: JournalViewModel
    @State private var showsAdd = false

    public init(model: JournalViewModel) {
        _model = Bindable(model)
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NocturneColor.night)
            .navigationTitle("Journal")
            .searchable(
                text: $model.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Rechercher un commentaire, un événement…"
            )
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        model.toggleDisplay()
                    } label: {
                        Image(systemName: model.display == .calendar ? "list.bullet" : "calendar")
                    }
                    .accessibilityLabel(model.display == .calendar ? "Afficher la liste" : "Afficher le calendrier")
                    Button {
                        showsAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Ajouter une nuit")
                }
            }
            .navigationDestination(for: NightRoute.self) { route in
                NightDetailView(route: route, dependencies: model.dependencies) {
                    await model.load()
                }
            }
            .navigationDestination(for: ReplayRoute.self) { route in
                ReplayView(session: route.session, dependencies: model.dependencies)
            }
            .sheet(isPresented: $showsAdd) {
                AddNightView(model: model.makeAddNight()) {
                    Task { await model.load() }
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if let message = model.errorMessage {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Lecture impossible", message: message)
        } else if model.sessions.isEmpty && !model.isLoading {
            ScrollView {
                EmptyStateView(
                    systemImage: "calendar",
                    title: "Journal vide",
                    message: "Chaque nuit enregistrée s’ajoutera ici, avec ses horaires, ses sons et ton ressenti. Tu peux aussi ajouter une nuit à la main avec +."
                )
            }
        } else if model.display == .list {
            list
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    filterControl
                    JournalCalendarView(model: model)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private var filterControl: some View {
        SegmentedControl(JournalFilter.allCases, selection: $model.filter, size: .compact) { $0.title }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Filtrer")
    }

    private var list: some View {
        List {
            Section {
                filterControl
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            let weeks = model.weeks
            if weeks.isEmpty {
                Section {
                    Text("Aucune nuit ne correspond.")
                        .font(.subheadline)
                        .foregroundStyle(NocturneColor.textSecondary)
                        .listRowBackground(NocturneColor.card)
                }
            }
            ForEach(weeks) { week in
                Section {
                    ForEach(week.sessions) { session in
                        NavigationLink(value: NightRoute(id: session.id)) {
                            JournalRow(session: session, gaps: model.gaps(for: session), organizer: model.organizer)
                        }
                        .listRowBackground(NocturneColor.card)
                    }
                } header: {
                    Text(week.title)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(NocturneColor.textSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(12)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }
}

/// Une ligne du journal : jour, titre et durée, horaires, coupures de l'écoute.
struct JournalRow: View {
    let session: SleepSession
    let gaps: [RecordingGap]
    let organizer: JournalOrganizer

    var body: some View {
        let day = organizer.rowDay(session)
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(day.weekday)
                    .font(.caption)
                    .foregroundStyle(NocturneColor.textSecondary)
                Text(day.number)
                    .font(NocturneFont.number(.title3))
                    .foregroundStyle(NocturneColor.textPrimary)
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(organizer.rowTitle(session))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NocturneColor.textPrimary)
                Text(organizer.rowSubtitle(session))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(NocturneColor.textSecondary)
                    .lineLimit(1)
                if let gap = organizer.gapLine(gaps) {
                    Text(gap)
                        .font(.caption)
                        .foregroundStyle(NocturneColor.amber)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}
