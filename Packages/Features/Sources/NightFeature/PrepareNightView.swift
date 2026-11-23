import DesignSystem
import SleepDomain
import SwiftUI
import UIKit

/// Onglet Nuit : « Préparer ma nuit » (maquette E30).
public struct PrepareNightView: View {
    @Bindable private var model: NightViewModel
    @State private var showsAlarm = false
    @State private var showsEveningLog = false
    @Environment(\.openURL) private var openURL

    public init(model: NightViewModel) {
        _model = Bindable(model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.dateLine)
                    .font(.subheadline)
                    .foregroundStyle(NocturneColor.textSecondary)
                    .padding(.top, -6)

                SegmentedControl([SessionKind.night, .nap], selection: $model.plan.kind) { kind in
                    kind == .night ? "Nuit" : "Sieste"
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Type de session")

                alarmSection
                listeningSection
                checksSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(NocturneColor.night)
        .navigationTitle("Préparer ma nuit")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Journal du soir") { showsEveningLog = true }
            }
        }
        .safeAreaInset(edge: .bottom) { startBar }
        .sheet(isPresented: $showsAlarm) {
            AlarmSheet(plan: $model.plan)
        }
        .sheet(isPresented: $showsEveningLog) {
            EveningLogView(repository: model.eveningLogs)
        }
        .alert("Impossible de continuer", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
        .task { await model.watchChecks() }
    }

    // MARK: - Réveil

    @ViewBuilder
    private var alarmSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupTitle("Réveil")
            if model.plan.kind == .night {
                RowGroup {
                    Button { showsAlarm = true } label: {
                        RowLabel(
                            icon: IconTile(systemName: "alarm", background: NocturneColor.amber, foreground: NocturneColor.night),
                            title: "Réveil",
                            value: model.alarmValue
                        )
                    }
                    .buttonStyle(.plain)
                    if model.plan.alarmEnabled {
                        RowDivider()
                        smartWakeRow
                    }
                }
                GroupFootnote(model.alarmNote)
            } else {
                RowGroup {
                    Menu {
                        Picker("Durée de la sieste", selection: $model.plan.napMinutes) {
                            ForEach(NightPlan.napDurations, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                    } label: {
                        RowLabel(
                            icon: IconTile(systemName: "alarm", background: NocturneColor.amber, foreground: NocturneColor.night),
                            title: "Durée de la sieste",
                            value: model.napValue
                        )
                    }
                    .buttonStyle(.plain)
                }
                GroupFootnote(model.napNote)
            }
        }
    }

    private var smartWakeRow: some View {
        HStack(spacing: 12) {
            IconTile(systemName: "rays", background: NocturneColor.violet)
            VStack(alignment: .leading, spacing: 2) {
                Text("Réveil intelligent")
                    .font(.body)
                    .foregroundStyle(NocturneColor.textPrimary)
                Text(model.smartWakeSubtitle)
                    .font(.footnote)
                    .foregroundStyle(NocturneColor.textSecondary)
            }
            Spacer(minLength: 8)
            Toggle("Réveil intelligent", isOn: $model.plan.smartWake)
                .labelsHidden()
                .tint(NocturneColor.switchOn)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Écoute

    private var listeningSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupTitle("Écoute")
            RowGroup {
                NavigationLink {
                    RecordingModeList(selection: $model.plan.mode, retentionNights: model.retentionNights)
                } label: {
                    RowLabel(
                        icon: IconTile(systemName: "mic", background: NocturneColor.violet),
                        title: "Mode d’écoute",
                        subtitle: model.modeSubtitle,
                        value: model.modeValue
                    )
                }
                .buttonStyle(.plain)
                RowDivider()
                // Les sons d'endormissement arrivent au lot 5.
                RowLabel(
                    icon: IconTile(systemName: "cloud.rain", background: NocturneColor.phaseLight),
                    title: "Sons d’endormissement",
                    subtitle: "Arrêt progressif",
                    value: "Bientôt",
                    showsChevron: false
                )
                .accessibilityElement(children: .combine)
            }
            GroupFootnote("L’écoute démarre tout de suite ; l’analyse attend que la chambre soit calme. Pendant les sons d’endormissement, la détection est moins fiable.")
        }
    }

    // MARK: - Vérifications

    private var checksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupTitle("Vérifications", trailing: model.checksSummary)
            RowGroup {
                ForEach(Array(model.checks.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        RowDivider(inset: 0)
                    }
                    checkRow(item)
                }
            }
            GroupFootnote("Apple Watch : si tu la portes, active la concentration Sommeil, sinon elle n’enregistre pas la nuit.", systemImage: "applewatch")
        }
    }

    private func checkRow(_ item: PreflightItem) -> some View {
        HStack(spacing: 12) {
            statusIcon(item.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(NocturneColor.textPrimary)
                if let detail = item.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(item.status == .warning ? NocturneColor.amber : NocturneColor.textSecondary)
                }
                if let action = item.action {
                    Button(action.title) {
                        Task {
                            if await model.perform(action), let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(NocturneColor.lavender)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            Text(item.value)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(NocturneColor.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: item.detail == nil ? 44 : 60)
    }

    private func statusIcon(_ status: PreflightItem.Status) -> some View {
        let symbol: String
        let color: Color
        let label: String
        switch status {
        case .ready:
            symbol = "checkmark.circle"
            color = NocturneColor.success
            label = "Prêt"
        case .warning:
            symbol = "exclamationmark.triangle"
            color = NocturneColor.amber
            label = "À faire"
        case .unknown:
            symbol = "questionmark.circle"
            color = NocturneColor.textTertiary
            label = "Inconnu"
        }
        return Image(systemName: symbol)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 22, height: 22)
            .accessibilityLabel(label)
    }

    // MARK: - Commencer

    private var startBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(NocturneColor.hairline)
                .frame(height: 1)
            Button {
                Task { await model.start() }
            } label: {
                HStack(spacing: 8) {
                    if model.isStarting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "moon")
                            .accessibilityHidden(true)
                    }
                    Text(model.startTitle)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isStarting)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(NocturneColor.night)
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil && !model.isCoverPresented },
            set: { if !$0 { model.alertMessage = nil } }
        )
    }
}
