import Foundation
import Testing
@testable import SleepDomain

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    paris.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private let format = SleepFormat(calendar: paris)

@Suite("Textes de l'app")
struct SleepFormatTests {
    @Test("Heures, durées et jours")
    func clockDurationDay() {
        #expect(format.clock(date(23, 7, 0)) == "07:00")
        #expect(format.clock(date(22, 23, 41)) == "23:41")
        #expect(format.duration(4 * 3_600 + 13 * 60) == "4 h 13")
        #expect(format.duration(3_600 + 5 * 60) == "1 h 05")
        #expect(format.duration(7 * 3_600) == "7 h")
        #expect(format.duration(45 * 60) == "45 min")
        #expect(format.duration(-10) == "0 min")
        #expect(format.shortDuration(7 * 3_600 + 51 * 60) == "7h51")
        #expect(format.shortDuration(25 * 60) == "25 min")
        #expect(format.weekdayDay(date(21, 23, 0)) == "samedi 21")
        #expect(format.monthYear(date(21, 23, 0)) == "novembre 2026")
        #expect(format.longDay(date(23, 2, 47)) == "lundi 23 novembre")
        #expect(format.dayTitle(date(22, 22, 40)) == "Dimanche 22 novembre")
        #expect(format.weekdayAndClock(date(23, 7, 0)) == "lun. 07:00")
        #expect(format.weekdayAndDay(date(26, 9, 0)) == "jeu. 26")
    }

    @Test("Tailles comme dans les réglages de l'iPhone")
    func bytes() {
        #expect(format.bytes(41_200_000_000) == "41 Go")
        #expect(format.bytes(4_240_000_000) == "4,2 Go")
        #expect(format.bytes(130_000_000) == "130 Mo")
        #expect(format.bytes(10) == "1 Mo")
    }
}

@Suite("Préparer ma nuit")
struct NightPlanTests {
    @Test("Réveil du lendemain matin, fenêtre du réveil intelligent")
    func nightAlarm() throws {
        let plan = NightPlan(alarmHour: 7, alarmMinute: 0, smartWake: true, smartWindowMinutes: 30)
        let alarm = try #require(plan.alarm(startingAt: date(22, 22, 40), calendar: paris))

        #expect(alarm.date == date(23, 7, 0))
        #expect(alarm.smartWindowStart == date(23, 6, 30))
    }

    @Test("Après minuit, le réveil reste le matin même")
    func afterMidnight() throws {
        let plan = NightPlan(alarmHour: 7, alarmMinute: 0, smartWake: false)
        let alarm = try #require(plan.alarm(startingAt: date(23, 1, 15), calendar: paris))

        #expect(alarm.date == date(23, 7, 0))
        #expect(alarm.smartWindowStart == nil)
    }

    @Test("Sieste : réveil au bout de la durée, sans réveil intelligent ; réveil désactivé")
    func napAndDisabled() throws {
        var plan = NightPlan(kind: .nap, smartWake: true, napMinutes: 25)
        let nap = try #require(plan.alarm(startingAt: date(22, 14, 0), calendar: paris))
        #expect(nap.date == date(22, 14, 25))
        #expect(nap.smartWindowStart == nil)

        plan.kind = .night
        plan.alarmEnabled = false
        #expect(plan.alarm(startingAt: date(22, 22, 40), calendar: paris) == nil)
    }

    @Test("Le réveil intelligent ne commence jamais avant le coucher")
    func windowAfterStart() throws {
        let plan = NightPlan(alarmHour: 7, alarmMinute: 0, smartWake: true, smartWindowMinutes: 30)
        let alarm = try #require(plan.alarm(startingAt: date(23, 6, 45), calendar: paris))

        #expect(alarm.smartWindowStart == date(23, 6, 45))
    }

    @Test("Valeurs bornées")
    func clamped() {
        var plan = NightPlan(alarmHour: 30, alarmMinute: -4, napMinutes: 1)
        #expect(plan.alarmHour == 23)
        #expect(plan.alarmMinute == 0)
        #expect(plan.napMinutes == 5)
        plan.napMinutes = 500
        #expect(plan.napMinutes == 180)
    }
}

@Suite("Vérifications avant la nuit")
struct PreflightTests {
    private let ready = PreflightReadings(
        batteryLevel: 0.64,
        isPluggedIn: true,
        volume: 0.7,
        freeBytes: 41_000_000_000,
        microphone: .granted,
        notifications: .granted,
        signatureExpiry: date(26, 23, 0)
    )
    private let alarm = NightAlarm(date: date(23, 7, 0))

    private func evaluate(_ readings: PreflightReadings, kind: SessionKind = .night, mode: RecordingMode = .continuous, alarm: NightAlarm?) -> [PreflightItem] {
        Preflight.evaluate(readings, kind: kind, mode: mode, quality: .standard, alarm: alarm, now: date(22, 22, 40), format: format)
    }

    @Test("Tout est prêt")
    func allReady() {
        let items = evaluate(ready, alarm: alarm)

        #expect(items.map(\.kind) == [.battery, .volume, .storage, .permissions, .signature])
        #expect(items.allSatisfy { $0.status == .ready })
        #expect(Preflight.summary(items) == "5 sur 5 prêtes")
        #expect(items[2].value == "41 Go")
        #expect(items[4].value == "jusqu’au jeu. 26")
    }

    @Test("Batterie : une nuit d'écoute se passe branchée")
    func battery() {
        var readings = ready
        readings.isPluggedIn = false

        let night = evaluate(readings, alarm: alarm)[0]
        #expect(night.status == .warning)
        #expect(night.value == "64 %")
        #expect(night.detail == "Branche ton iPhone pour la nuit")
        #expect(evaluate(readings, kind: .nap, alarm: alarm)[0].status == .ready)
        #expect(evaluate(readings, mode: .off, alarm: alarm)[0].status == .ready)

        readings.batteryLevel = 0.12
        #expect(evaluate(readings, kind: .nap, alarm: alarm)[0].status == .warning)
        readings.batteryLevel = nil
        #expect(evaluate(readings, alarm: alarm)[0].status == .unknown)
    }

    @Test("Volume trop bas seulement s'il y a un réveil")
    func volume() {
        var readings = ready
        readings.volume = 0.3

        #expect(evaluate(readings, alarm: alarm)[1].status == .warning)
        #expect(evaluate(readings, alarm: nil)[1].status == .ready)
    }

    @Test("Espace libre selon le mode d'écoute")
    func storage() {
        var readings = ready
        readings.freeBytes = 400_000_000

        let item = evaluate(readings, alarm: alarm)[2]
        #expect(item.status == .warning)
        #expect(item.detail == "Libère de la place : une nuit prend environ 131 Mo")
        #expect(evaluate(readings, mode: .off, alarm: alarm)[2].status == .ready)
    }

    @Test("Autorisations : micro d'abord, puis notifications")
    func permissions() {
        var readings = ready
        readings.microphone = .denied
        #expect(evaluate(readings, alarm: alarm)[3].action == .openSettings)
        #expect(evaluate(readings, mode: .off, alarm: alarm)[3].status == .ready)

        readings.microphone = .undetermined
        #expect(evaluate(readings, alarm: alarm)[3].action == .requestMicrophone)

        readings.microphone = .granted
        readings.notifications = .undetermined
        let item = evaluate(readings, alarm: alarm)[3]
        #expect(item.status == .warning)
        #expect(item.action == .requestNotifications)
    }

    @Test("Signature : expirée avant le réveil, ou à renouveler bientôt")
    func signature() {
        var readings = ready
        readings.signatureExpiry = date(23, 5, 0)
        #expect(evaluate(readings, alarm: alarm)[4].detail == "Elle expire avant ton réveil : renouvelle l’app avec Sideloadly")

        readings.signatureExpiry = date(24, 9, 0)
        #expect(evaluate(readings, alarm: alarm)[4].detail == "Renouvelle bientôt l’app avec Sideloadly")

        readings.signatureExpiry = nil
        #expect(evaluate(readings, alarm: alarm)[4].status == .unknown)
        #expect(Preflight.summary(evaluate(readings, alarm: alarm)) == "4 sur 5 prêtes")
    }
}

@Suite("Nuit en cours et Bonjour")
struct NightScreenTests {
    @Test("Une heure saisie se place sur la bonne journée")
    func placeTime() {
        let calendar = NightCalendar(calendar: paris)
        let night = DateInterval(start: date(22, 23, 22), end: date(23, 6, 52))

        #expect(calendar.place(hour: 23, minute: 41, near: night) == date(22, 23, 41))
        #expect(calendar.place(hour: 0, minute: 30, near: night) == date(23, 0, 30))
        #expect(calendar.place(hour: 7, minute: 10, near: night) == date(23, 7, 10))
        #expect(calendar.place(hour: 22, minute: 0, near: night) == date(22, 22, 0))
    }

    @Test("Le soir d'un moment : avant midi, c'est la veille")
    func eveningAt() {
        let calendar = NightCalendar(calendar: paris)

        #expect(calendar.evening(at: date(22, 22, 40)) == date(22, 0, 0))
        #expect(calendar.evening(at: date(23, 1, 10)) == date(22, 0, 0))
        #expect(calendar.evening(at: date(23, 14, 0)) == date(23, 0, 0))
    }

    @Test("Temps écouté : trous et coupure en cours retirés")
    func listened() {
        var session = SleepSession(state: .running, detected: SessionTimes(bedtime: date(22, 23, 22)))
        let gap = RecordingGap(sessionID: session.id, start: date(23, 0, 10), end: date(23, 0, 20), cause: .phoneCall)
        var status = NightStatus(session: session, isListening: false, mode: .continuous, gaps: [gap], cut: ListeningCut(start: date(23, 2, 31), cause: .siri))

        // 23:22 → 02:47 = 3 h 25 ; moins 10 min de trou et 16 min de coupure en cours.
        #expect(status.listenedDuration(until: date(23, 2, 47)) == TimeInterval(2 * 3_600 + 59 * 60))

        session.state = .finished
        session.detected.wake = date(23, 2, 31)
        status.session = session
        status.cut = nil
        #expect(status.listenedDuration(until: date(23, 9, 0)) == TimeInterval(2 * 3_600 + 59 * 60))

        status.mode = .off
        #expect(status.listenedDuration(until: date(23, 9, 0)) == 0)
    }

    @Test("Bonjour : ressenti, horaires corrigés et commentaire enregistrés ensemble")
    func saveMorning() async throws {
        let session = SleepSession(
            state: .finished,
            detected: SessionTimes(bedtime: date(22, 23, 22), wake: date(23, 6, 52), getUp: date(23, 6, 52))
        )
        let repository = InMemorySleepSessionRepository([session])
        let lifecycle = SessionLifecycle(repository: repository)

        let saved = try await lifecycle.saveMorning(
            id: session.id,
            feeling: WakeFeeling(mood: 4, energy: 3),
            corrected: SessionTimes(sleepOnset: date(22, 23, 41)),
            comment: "  Un bruit vers 3 h  "
        )

        #expect(saved.times.sleepOnset == date(22, 23, 41))
        #expect(saved.detected.sleepOnset == nil)
        #expect(saved.feeling == WakeFeeling(mood: 4, energy: 3))
        #expect(saved.comment == "Un bruit vers 3 h")
        #expect(saved.asleepDuration == TimeInterval(7 * 3_600 + 11 * 60))

        let moodOnly = try await lifecycle.saveMorning(id: session.id, feeling: WakeFeeling(mood: 2, energy: nil), corrected: saved.corrected, comment: nil)
        #expect(moodOnly.feeling?.mood == 2)
        #expect(moodOnly.feeling?.energy == nil)
        #expect(moodOnly.comment == nil)

        await #expect(throws: SessionError.invalidTimes([.timesOutOfOrder])) {
            try await lifecycle.saveMorning(id: session.id, feeling: nil, corrected: SessionTimes(sleepOnset: date(22, 22, 0)), comment: nil)
        }
    }
}
