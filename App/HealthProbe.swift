import Foundation
import HealthKit

/// Test n° 6 : lecture des nuits enregistrées par l'Apple Watch dans Santé.
final class HealthProbe: ObservableObject {
    @Published private(set) var status = "pas encore testée"
    @Published private(set) var nights: [String] = []

    private let store = HKHealthStore()

    func run() {
        guard HKHealthStore.isHealthDataAvailable() else {
            status = "Santé indisponible sur cet appareil"
            return
        }
        guard
            let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            let heart = HKObjectType.quantityType(forIdentifier: .heartRate)
        else { return }
        status = "demande d’accès…"
        store.requestAuthorization(toShare: [], read: [sleep, heart]) { [weak self] _, error in
            guard let self else { return }
            if let error {
                EventLog.shared.add("Santé : \(error.localizedDescription)")
                DispatchQueue.main.async { self.status = "erreur : \(error.localizedDescription)" }
                return
            }
            self.readSleep(type: sleep)
        }
    }

    private func readSleep(type: HKCategoryType) {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { [weak self] _, samples, error in
            guard let self else { return }
            let list = (samples as? [HKCategorySample]) ?? []
            let lines = HealthProbe.summarize(list)
            let text: String
            if let error {
                text = "lecture impossible : \(error.localizedDescription)"
            } else if list.isEmpty {
                text = "aucune donnée de sommeil sur 7 jours (accès refusé, ou montre non portée)"
            } else {
                text = "\(list.count) mesures de sommeil lues sur 7 jours"
            }
            EventLog.shared.add("Santé : \(text)")
            DispatchQueue.main.async {
                self.status = text
                self.nights = lines
            }
        }
        store.execute(query)
    }

    static func summarize(_ samples: [HKCategorySample]) -> [String] {
        guard !samples.isEmpty else { return [] }
        let calendar = Calendar.current
        let groups = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.endDate) }
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        return groups.keys.sorted(by: >).prefix(7).map { day in
            let items = groups[day] ?? []
            var minutes: [Int: Double] = [:]
            for item in items {
                minutes[item.value, default: 0] += item.endDate.timeIntervalSince(item.startDate) / 60
            }
            let asleep = minutes.filter { asleepValues.contains($0.key) }.values.reduce(0, +)
            let deep = minutes[HKCategoryValueSleepAnalysis.asleepDeep.rawValue] ?? 0
            let rem = minutes[HKCategoryValueSleepAnalysis.asleepREM.rawValue] ?? 0
            let core = minutes[HKCategoryValueSleepAnalysis.asleepCore.rawValue] ?? 0
            let first = items.map(\.startDate).min() ?? day
            let last = items.map(\.endDate).max() ?? day
            let sources = Set(items.map { $0.sourceRevision.source.name }).sorted().joined(separator: ", ")
            let dayText = day.formatted(Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated).locale(Format.french))
            return "\(dayText) : \(Format.time(first)) → \(Format.time(last)) · sommeil \(Format.duration(asleep * 60)) (profond \(Format.duration(deep * 60)), paradoxal \(Format.duration(rem * 60)), léger \(Format.duration(core * 60))) · \(sources)"
        }
    }
}
