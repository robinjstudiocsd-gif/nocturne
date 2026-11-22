import SwiftUI
import UIKit

/// Écran principal de la phase 0 : les sept essais, le rapport et le journal.
struct LabView: View {
    @ObservedObject var lab: LabModel
    @ObservedObject var recorder: NightRecorder
    @ObservedObject var alarm: AlarmController
    @ObservedObject var notifications: NotificationProbe
    @ObservedObject var health: HealthProbe
    @ObservedObject var log = EventLog.shared
    @State private var copied = false

    init(lab: LabModel) {
        _lab = ObservedObject(wrappedValue: lab)
        _recorder = ObservedObject(wrappedValue: lab.recorder)
        _alarm = ObservedObject(wrappedValue: lab.alarm)
        _notifications = ObservedObject(wrappedValue: lab.notifications)
        _health = ObservedObject(wrappedValue: lab.health)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Phase 0 · preuve de faisabilité")
                            .font(.headline)
                        Text("Sept essais à faire sur ton iPhone. Copie ensuite le rapport et colle-le dans notre conversation.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.card)

                nightSection
                alarmSection
                notificationSection
                liveActivitySection
                widgetSection
                healthSection
                renewalSection
                reportSection
                journalSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
            .navigationTitle("Nocturne")
        }
        .tint(Theme.lavender)
        .fullScreenCover(isPresented: Binding(get: { recorder.isRunning }, set: { _ in })) {
            NightScreen(lab: lab, recorder: recorder, alarm: alarm)
        }
    }

    private var alarmText: String {
        String(format: "%02d:%02d", alarm.hour, alarm.minute)
    }

    private var nightSection: some View {
        Section {
            Button {
                lab.startNight()
            } label: {
                Label("Commencer la nuit (réveil à \(alarmText))", systemImage: "moon.fill")
            }
            Button {
                lab.startNight(testAlarmIn: 120)
            } label: {
                Label("Essai express : réveil dans 2 min", systemImage: "timer")
            }
            if let night = lab.lastNight {
                Text("Dernière nuit : " + NightStore.describe(night))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
            if let message = lab.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.amber)
            }
        } header: {
            Text("1 · Nuit enregistrée écran verrouillé")
        } footer: {
            Text("Lance la nuit, branche l’iPhone, puis verrouille l’écran. Le matin, arrête la nuit depuis l’app.")
        }
        .listRowBackground(Theme.card)
    }

    private var alarmSection: some View {
        Section {
            DatePicker("Heure du réveil", selection: $alarm.alarmTime, displayedComponents: .hourAndMinute)
                .environment(\.locale, Format.french)
            Text("Dernier essai : " + alarm.lastResult)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
        } header: {
            Text("2 · Alarme d’iOS 18")
        } footer: {
            Text("Sous iOS 18, c’est l’app qui sonne. Une notification de secours part une minute plus tard si elle n’a pas pu sonner.")
        }
        .listRowBackground(Theme.card)
    }

    private var notificationSection: some View {
        Section {
            LabeledContent("État", value: notifications.status)
            Button("Autoriser les notifications") {
                notifications.request()
            }
            Button("Envoyer une notification de test (10 s)") {
                notifications.sendTest()
            }
            if let last = notifications.lastReceived {
                Text("Dernière reçue : " + last)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
        } header: {
            Text("3 · Notification")
        } footer: {
            Text("Après « Envoyer », verrouille l’écran : la notification doit apparaître.")
        }
        .listRowBackground(Theme.card)
    }

    private var liveActivitySection: some View {
        Section {
            LabeledContent("Live Activities", value: lab.liveActivityStatus)
        } header: {
            Text("4 · Live Activity")
        } footer: {
            Text("Pendant la nuit, l’écran verrouillé affiche « Nuit en cours » et l’heure du réveil.")
        }
        .listRowBackground(Theme.card)
    }

    private var widgetSection: some View {
        Section {
            Text(lab.widgetStatus)
            Button("Vérifier à nouveau") {
                lab.checkWidgets()
            }
        } header: {
            Text("5 · Widget")
        } footer: {
            Text("Appuie longuement sur l’écran d’accueil, touche « Modifier » puis « Ajouter un widget », choisis Nocturne, puis reviens ici.")
        }
        .listRowBackground(Theme.card)
    }

    private var healthSection: some View {
        Section {
            Text(health.status)
            Button("Tester l’accès à Santé") {
                health.run()
            }
            ForEach(health.nights, id: \.self) { night in
                Text(night)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
        } header: {
            Text("6 · Lecture de Santé")
        } footer: {
            Text("Autorise la lecture du sommeil. Les nuits de ta montre apparaissent ici si elle les a enregistrées.")
        }
        .listRowBackground(Theme.card)
    }

    private var renewalSection: some View {
        Section {
            LabeledContent("Signature", value: lab.launch.expiry.map { "jusqu’au \(Format.dateTime($0))" } ?? "introuvable")
            LabeledContent("Renouvellements", value: "\(lab.launch.renewals.count)")
            LabeledContent("Première ouverture", value: Format.dateTime(lab.launch.firstLaunch))
            LabeledContent("Lancements", value: "\(lab.launch.launchCount)")
        } header: {
            Text("7 · Renouvellement après 7 jours")
        } footer: {
            Text("Avant l’expiration, renouvelle avec Sideloadly : la date doit changer et tes nuits doivent rester là.")
        }
        .listRowBackground(Theme.card)
    }

    private var reportSection: some View {
        Section {
            Button {
                UIPasteboard.general.string = lab.report()
                copied = true
            } label: {
                Label(copied ? "Rapport copié" : "Copier le rapport", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            ShareLink(item: EventLog.shared.fileURL) {
                Label("Partager le journal complet", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Rapport")
        } footer: {
            Text("Le rapport ne contient ni ton identifiant Apple ni aucun mot de passe.")
        }
        .listRowBackground(Theme.card)
    }

    private var journalSection: some View {
        Section {
            ForEach(Array(log.recent.suffix(25).reversed().enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.secondary)
            }
        } header: {
            Text("Journal")
        }
        .listRowBackground(Theme.card)
    }
}
