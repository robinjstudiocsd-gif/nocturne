import Foundation
import Testing
@testable import SleepDomain

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 11) -> Date {
    paris.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private func night(_ day: Int, bed: (Int, Int), wake: (Int, Int), comment: String? = nil, kind: SessionKind = .night) -> SleepSession {
    let bedtime = date(day, bed.0, bed.1)
    var wakeDate = date(day, wake.0, wake.1)
    if wakeDate < bedtime {
        wakeDate = paris.date(byAdding: .day, value: 1, to: wakeDate)!
    }
    return SleepSession(kind: kind, state: .finished, detected: SessionTimes(bedtime: bedtime, wake: wakeDate, getUp: wakeDate), comment: comment)
}

private let organizer = JournalOrganizer(calendar: paris)

@Suite("Journal · liste et calendrier")
struct JournalTests {
    @Test("Semaines du lundi au dimanche, selon le matin de chaque nuit")
    func weeks() {
        let now = date(23, 9, 0)
        let sessions = [
            night(22, bed: (23, 41), wake: (6, 58)),
            night(21, bed: (23, 58), wake: (7, 52)),
            night(14, bed: (23, 5), wake: (6, 58)),
            night(8, bed: (23, 0), wake: (7, 0)),
            night(1, bed: (23, 0), wake: (7, 0))
        ]

        let weeks = organizer.weeks(sessions, now: now)

        #expect(weeks.map(\.title) == ["Cette semaine", "La semaine dernière", "Semaine du 9 novembre", "Semaine du 2 novembre"])
        #expect(weeks.map(\.sessions.count) == [1, 1, 2, 1])
        #expect(weeks[1].sessions.first?.id == sessions[1].id)
    }

    @Test("Lignes : jour du matin, durée, horaires, coupures")
    func rows() {
        let session = night(21, bed: (23, 58), wake: (7, 52))
        let day = organizer.rowDay(session)
        #expect(day.weekday == "dim.")
        #expect(day.number == "22")
        #expect(organizer.rowTitle(session) == "Nuit · 7 h 54")
        #expect(organizer.rowSubtitle(session) == "23:58 → 07:52")

        var manual = night(20, bed: (14, 10), wake: (14, 38), kind: .nap)
        manual.state = .manual
        #expect(organizer.rowDay(manual).number == "20")
        #expect(organizer.rowTitle(manual) == "Sieste · 28 min")
        #expect(organizer.rowSubtitle(manual) == "14:10 → 14:38 · saisie")

        let call = RecordingGap(sessionID: session.id, start: date(22, 2, 31), end: date(22, 2, 43), cause: .phoneCall)
        #expect(organizer.gapLine([call]) == "Écoute coupée 12 min (appel)")
        #expect(organizer.gapLine([call, call]) == "Écoute coupée 2 fois, 24 min en tout")
        #expect(organizer.gapLine([]) == nil)
    }

    @Test("Recherche dans les commentaires et les titres, sans accents")
    func search() {
        let session = night(21, bed: (23, 58), wake: (7, 52), comment: "Soirée chez des amis")

        #expect(organizer.matches(session, query: "soiree"))
        #expect(organizer.matches(session, query: "dimanche 22"))
        #expect(organizer.matches(session, query: "  "))
        #expect(!organizer.matches(session, query: "ronflement"))
        #expect(JournalFilter.naps.includes(session) == false)
        #expect(JournalFilter.nights.includes(session))
    }

    @Test("Calendrier : semaines complètes du lundi, nuit rangée au jour où elle se termine")
    func month() throws {
        let sessions = [night(21, bed: (23, 58), wake: (7, 52)), night(22, bed: (23, 41), wake: (6, 58))]
        let month = organizer.month(containing: date(23, 9, 0))
        let days = organizer.days(ofMonth: month, sessions: sessions, now: date(23, 9, 0))

        #expect(organizer.monthTitle(month) == "Novembre 2026")
        #expect(days.count == 42)
        #expect(days.first?.dayNumber == 26)
        #expect(days.first?.isInMonth == false)
        let sunday = try #require(days.first { $0.isInMonth && $0.dayNumber == 22 })
        #expect(sunday.sessions.map(\.id) == [sessions[0].id])
        let today = try #require(days.first { $0.isToday })
        #expect(today.dayNumber == 23)
        #expect(today.sessions.map(\.id) == [sessions[1].id])
        #expect(days.first { $0.isInMonth && $0.dayNumber == 24 }?.isFuture == true)
        #expect(days.last?.dayNumber == 6)
    }

    @Test("Nuit saisie : chaque heure se place après la précédente")
    func manualNight() {
        let times = organizer.manualTimes(
            kind: .night,
            day: date(20, 0, 0),
            bedtime: ClockTime(hour: 23, minute: 30),
            sleepOnset: ClockTime(hour: 23, minute: 50),
            wake: ClockTime(hour: 7, minute: 5),
            getUp: ClockTime(hour: 7, minute: 15)
        )
        #expect(times.bedtime == date(20, 23, 30))
        #expect(times.sleepOnset == date(20, 23, 50))
        #expect(times.wake == date(21, 7, 5))
        #expect(times.getUp == date(21, 7, 15))

        let late = organizer.manualTimes(kind: .night, day: date(20, 0, 0), bedtime: ClockTime(hour: 0, minute: 40), sleepOnset: nil, wake: ClockTime(hour: 8, minute: 0), getUp: nil)
        #expect(late.bedtime == date(21, 0, 40))
        #expect(late.wake == date(21, 8, 0))

        let nap = organizer.manualTimes(kind: .nap, day: date(20, 0, 0), bedtime: ClockTime(hour: 14, minute: 10), sleepOnset: ClockTime(hour: 14, minute: 13), wake: ClockTime(hour: 14, minute: 38), getUp: ClockTime(hour: 14, minute: 40))
        #expect(nap.bedtime == date(20, 14, 10))
        #expect(nap.getUp == date(20, 14, 40))
    }
}

@Suite("Fiche de nuit")
struct NightDetailTests {
    private let text = NightDetailText(calendar: paris)

    @Test("En-tête de la nuit et de la sieste")
    func header() {
        let session = night(21, bed: (23, 58), wake: (7, 52))
        #expect(text.header(session).title == "Samedi 21 → dimanche 22")
        #expect(text.header(session).subtitle == "novembre 2026")

        let monthEnd = SleepSession(state: .finished, detected: SessionTimes(bedtime: date(31, 23, 0, month: 10), wake: date(1, 7, 0)))
        #expect(text.header(monthEnd).subtitle == "octobre et novembre 2026")

        let nap = night(20, bed: (14, 10), wake: (14, 38), kind: .nap)
        #expect(text.header(nap).title == "Sieste du vendredi 20")
    }

    @Test("Résumé : endormissement et réveils de plus de 5 min")
    func summary() {
        var session = night(21, bed: (23, 41), wake: (7, 0))
        #expect(text.summary(session) == nil)

        session.corrected.sleepOnset = date(21, 23, 59)
        session.wakeEpisodes = [WakeEpisode(start: date(22, 4, 46), end: date(22, 4, 53)), WakeEpisode(start: date(22, 5, 0), end: date(22, 5, 3))]
        #expect(text.summary(session) == "Endormissement en 18 min. Un réveil de plus de 5 min, à 04:46, pendant 7 min.")
        #expect(session.efficiency.map { Int(($0 * 100).rounded()) } == 94)
    }

    @Test("Écoute : durée, coupures, taille")
    func listening() {
        let session = night(21, bed: (23, 0), wake: (7, 0))
        let gap = RecordingGap(sessionID: session.id, start: date(22, 2, 0), end: date(22, 2, 12), cause: .phoneCall)

        #expect(text.listening(session, gaps: [], bytes: 123_000_000, now: date(22, 9, 0)) == "8 h enregistrées · aucune coupure · 123 Mo")
        #expect(text.listening(session, gaps: [gap], bytes: 0, now: date(22, 9, 0)) == "7 h 48 enregistrées · 1 coupure (12 min)")
        #expect(text.gap(gap) == "Coupure à 02:00 · 12 min · appel")
    }

    @Test("Journal du soir lisible")
    func eveningTexts() {
        let log = EveningLog(day: date(21, 0, 0), caffeine: .one, lastCaffeine: date(21, 16, 0), exercise: EveningLog.Exercise.none, screens: .untilBedtime, stress: 2, meal: .heavy, mealEnd: date(21, 22, 0), calendar: paris)

        #expect(text.caffeine(log) == "1 café à 16:00")
        #expect(text.exercise(log) == "Non")
        #expect(text.screens(log) == "Jusqu’au coucher")
        #expect(text.stress(log) == "Faible")
        #expect(text.meal(log) == "Copieux, fini à 22:00")
        #expect(WakeFeeling.moodLabel(4) == "Bien")
    }

    @Test("Modifier puis supprimer une nuit, jamais une nuit en cours")
    func editAndDelete() async throws {
        let session = night(21, bed: (23, 41), wake: (7, 0))
        let running = SleepSession(state: .running, detected: SessionTimes(bedtime: date(22, 23, 0)))
        let repository = InMemorySleepSessionRepository([session, running])
        let recordings = InMemoryRecordingRepository()
        try await recordings.save(RecordingGap(sessionID: session.id, start: date(22, 2, 0), end: date(22, 2, 5), cause: .siri))
        let lifecycle = SessionLifecycle(repository: repository)

        let edited = try await lifecycle.saveEdit(
            id: session.id,
            corrected: SessionTimes(sleepOnset: date(21, 23, 59)),
            wakeEpisodes: [WakeEpisode(start: date(22, 4, 46), end: date(22, 4, 53))],
            kind: .night,
            feeling: WakeFeeling(mood: nil, energy: 3),
            comment: "Couché tard"
        )
        #expect(edited.times.sleepOnset == date(21, 23, 59))
        #expect(edited.detected.sleepOnset == nil)
        #expect(edited.significantWakeCount == 1)
        #expect(edited.feeling?.energy == 3)

        let eraser = RepositoryDataEraser(recordings: recordings)
        await #expect(throws: SessionError.stillRunning) {
            try await lifecycle.delete(id: running.id, erasing: eraser)
        }
        try await lifecycle.delete(id: session.id, erasing: eraser)
        #expect(try await repository.session(id: session.id) == nil)
        #expect(try await recordings.gaps(sessionID: session.id).isEmpty)
    }
}

@Suite("Événements de la nuit")
struct NightEventTests {
    @Test("Correction : le type d'origine reste connu ; confiance affichée")
    func reclassify() {
        let event = NightEvent(sessionID: UUID(), kind: .snoring, start: date(22, 3, 12), duration: 130, confidence: 0.92, intensity: 14)

        let corrected = event.reclassified(as: .breathing)
        #expect(corrected.kind == .breathing)
        #expect(corrected.detectedKind == .snoring)
        #expect(corrected.origin == .reclassified)
        #expect(corrected.reclassified(as: .snoring).origin == .confirmed)
        #expect(event.confidenceLevel == .high)
        #expect(ConfidenceLevel(0.6).title == "moyenne")
        #expect(ConfidenceLevel(0.2) == .low)
        #expect(event.end == date(22, 3, 14).addingTimeInterval(10))
        #expect(EventKind.snoring.mergeGap == 30)
    }
}
