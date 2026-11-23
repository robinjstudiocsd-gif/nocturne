import Foundation
import SleepDomain
import Testing
@testable import AppSettings

private func freshDefaults() -> UserDefaults {
    let name = "tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("Préférences")
struct AppPreferencesTests {
    @Test("Valeurs par défaut de l'étude")
    func defaults() {
        let preferences = AppPreferences(defaults: freshDefaults())

        #expect(preferences.recordingMode == .continuous)
        #expect(preferences.audioRetentionNights == 30)
        #expect(preferences.nightLighting == .dark)
        #expect(preferences.sleepNeedMinutes == 450)
    }

    @Test("Valeurs enregistrées et bornées")
    func storedAndClamped() {
        let preferences = AppPreferences(defaults: freshDefaults())
        preferences.recordingMode = .events
        preferences.audioRetentionNights = 1_000
        preferences.nightLighting = .red

        #expect(preferences.recordingMode == .events)
        #expect(preferences.audioRetentionNights == 365)
        #expect(preferences.nightLighting == .red)
    }

    @Test("Réglages de la nuit gardés d'un soir à l'autre, sauf le type de session")
    func nightPlan() {
        let defaults = freshDefaults()
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.nightPlan == NightPlan())

        preferences.nightPlan = NightPlan(kind: .nap, mode: .off, alarmEnabled: false, alarmHour: 6, alarmMinute: 45, smartWake: false, napMinutes: 20)

        let reloaded = AppPreferences(defaults: defaults).nightPlan
        #expect(reloaded.kind == .night)
        #expect(reloaded.mode == .off)
        #expect(reloaded.alarmEnabled == false)
        #expect(reloaded.alarmHour == 6)
        #expect(reloaded.alarmMinute == 45)
        #expect(reloaded.smartWake == false)
        #expect(reloaded.napMinutes == 20)
        #expect(preferences.recordingMode == .off)
    }
}

@Suite("Signature")
struct SigningTests {
    private func profile(expiring date: Date) throws -> Data {
        let plist = try PropertyListSerialization.data(fromPropertyList: ["ExpirationDate": date, "Name": "Test"], format: .xml, options: 0)
        return Data([0x30, 0x82, 0x0A]) + plist + Data([0x00, 0xA0, 0x82])
    }

    @Test("Date d'expiration lue dans un profil signé")
    func parseExpiration() throws {
        let expiry = Date(timeIntervalSince1970: 1_795_800_000)
        let parsed = SigningStatus.expiration(inProfile: try profile(expiring: expiry))

        #expect(parsed == expiry)
    }

    @Test("Jours restants et alerte de renouvellement")
    func daysRemaining() {
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let status = SigningStatus(expirationDate: now.addingTimeInterval(36 * 3_600))

        #expect(status.daysRemaining(now: now) == 1)
        #expect(status.needsRenewal(now: now))
        #expect(!SigningStatus(expirationDate: nil).needsRenewal(now: now))
    }

    @Test("Renouvellement détecté quand la date change")
    func renewalDetection() {
        let tracker = RenewalTracker(defaults: freshDefaults())
        let first = SigningStatus(expirationDate: Date(timeIntervalSince1970: 1_795_800_000))
        let renewed = SigningStatus(expirationDate: Date(timeIntervalSince1970: 1_796_400_000))

        #expect(tracker.recordLaunch(signing: first) == false)
        #expect(tracker.recordLaunch(signing: first) == false)
        #expect(tracker.recordLaunch(signing: renewed) == true)
        #expect(tracker.launchCount == 3)
        #expect(tracker.renewals.count == 1)
    }
}
