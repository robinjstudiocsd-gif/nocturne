import Foundation
import SleepDomain

/// État d'une période de 30 secondes, sans montre (étude : profil « calme, agité, éveil probable »).
public enum EpochState: String, Codable, Sendable, CaseIterable {
    case calm
    case agitated
    case awake
    case unknown

    public var title: String {
        switch self {
        case .calm: "Calme"
        case .agitated: "Agité"
        case .awake: "Éveil probable"
        case .unknown: "Sans mesure"
        }
    }

    /// Calme ou agité : la personne dort probablement.
    public var isAsleep: Bool {
        self == .calm || self == .agitated
    }
}

/// Une plage d'état continue, pour le graphique de la nuit.
public struct ProfileInterval: Equatable, Codable, Sendable {
    public var start: Date
    public var end: Date
    public var state: EpochState

    public init(start: Date, end: Date, state: EpochState) {
        self.start = start
        self.end = max(start, end)
        self.state = state
    }

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

/// Ce que l'iPhone a mesuré pendant la nuit.
public struct ProfileInput: Sendable {
    public var kind: SessionKind
    public var start: Date
    public var end: Date
    /// Activité de chaque fenêtre de 30 s depuis `start`, en milli-g ; nil sans mesure.
    public var motion: [Float?]
    /// Niveau le plus fort de chaque seconde depuis `start`, en dBFS ; nil quand l'écoute était coupée.
    public var peaks: [Float?]
    /// Niveau moyen de chaque seconde, qui donne le bruit de fond.
    public var means: [Float?]
    /// Sons reconnus pendant la nuit.
    public var events: [NightEvent]

    public init(
        kind: SessionKind = .night,
        start: Date,
        end: Date,
        motion: [Float?] = [],
        peaks: [Float?] = [],
        means: [Float?] = [],
        events: [NightEvent] = []
    ) {
        self.kind = kind
        self.start = start
        self.end = max(start, end)
        self.motion = motion
        self.peaks = peaks
        self.means = means
        self.events = events
    }
}

/// Profil de la nuit : un état par période de 30 s, l'endormissement, le réveil et les réveils dans la nuit.
public struct NightProfile: Equatable, Sendable {
    public static let epoch: TimeInterval = 30
    /// Version de l'analyse, gardée avec la nuit pour pouvoir la refaire après une amélioration.
    public static let analysisVersion = 1

    public var start: Date
    public var end: Date
    public var states: [EpochState]
    public var sleepOnset: Date?
    public var wake: Date?
    public var wakeEpisodes: [WakeEpisode]
    public var reliability: Reliability
    /// Vrai si l'iPhone a senti les mouvements du lit.
    public var usedMotion: Bool
    /// Vrai si le micro a écouté au moins une partie de la nuit.
    public var usedSound: Bool

    /// Source principale des horaires : les mouvements, sinon le son.
    public var source: DataSource? {
        if usedMotion { return .motion }
        if usedSound { return .microphone }
        return nil
    }

    /// Plages d'état fusionnées, pour le graphique de la nuit.
    public var intervals: [ProfileInterval] {
        var result: [ProfileInterval] = []
        for (index, state) in states.enumerated() {
            let from = start.addingTimeInterval(Double(index) * Self.epoch)
            let to = min(end, from.addingTimeInterval(Self.epoch))
            guard to > from else { continue }
            if let last = result.last, last.state == state {
                result[result.count - 1].end = to
            } else {
                result.append(ProfileInterval(start: from, end: to, state: state))
            }
        }
        return result
    }

    /// Temps passé dans un état.
    public func duration(of state: EpochState) -> TimeInterval {
        intervals.filter { $0.state == state }.reduce(0) { $0 + $1.duration }
    }
}

/// Analyse sans montre, par périodes de 30 s : mouvements du lit sentis par l'iPhone posé sur le matelas,
/// et sons de la chambre. Les seuils sont des choix de départ, à régler sur des nuits réelles pendant les essais.
public enum NightProfiler {
    /// Mouvement au-dessus du repos de la nuit (milli-g) qui rend une période agitée.
    public static let agitatedMotion: Float = 4
    /// Mouvement qui, s'il dure plus d'une période, signale un éveil probable. Se retourner une fois reste « agité ».
    public static let awakeMotion: Float = 12
    /// Périodes agitées qu'il faut au milieu de la nuit pour croire que l'iPhone était sur le lit.
    public static let minimumMovingEpochs = 3
    /// Écart au bruit de fond qui compte comme un son, comme pendant la nuit.
    public static let soundThreshold: Float = 10
    /// Part des secondes bruyantes qui rend une période agitée, avec le son seul.
    public static let agitatedSound = 0.15
    /// Part des secondes bruyantes qui rend une période agitée quand l'iPhone sent aussi les mouvements.
    public static let agitatedSoundWithMotion = 0.3
    /// Part des secondes bruyantes qui signale un éveil probable.
    public static let awakeSound = 0.5
    /// Réveil le plus court retenu dans la nuit.
    public static let minimumWake: TimeInterval = 2 * 60
    /// Sommeil le plus court (en périodes) qui compte avant le réveil final.
    public static let minimumSleepBlock = 3

    /// Calme qui marque l'endormissement : 15 minutes la nuit, 5 minutes pour une sieste.
    public static func onsetCalm(for kind: SessionKind) -> TimeInterval {
        kind == .nap ? 5 * 60 : 15 * 60
    }

    public static func analyze(_ input: ProfileInput) -> NightProfile {
        let count = max(1, Int((input.end.timeIntervalSince(input.start) / NightProfile.epoch).rounded(.up)))
        let motion = motionLevels(input.motion, count: count)
        let sound = soundActivity(input, count: count)
        let marks = EpochMarks(events: input.events, start: input.start, count: count)
        let states = (0..<count).map { index in
            classify(index, motion: motion, sound: sound[index], marks: marks)
        }

        let usedMotion = motion != nil
        let usedSound = sound.contains { $0 != nil }
        let onsetLength = max(1, Int(onsetCalm(for: input.kind) / NightProfile.epoch))
        var sleepOnset: Date?
        var wake: Date?
        var episodes: [WakeEpisode] = []
        if let onset = firstSleepStretch(states, length: onsetLength) {
            let wakeIndex = lastSleepEnd(states, from: onset) ?? count
            let source: DataSource = usedMotion ? .motion : .microphone
            sleepOnset = date(ofEpoch: onset, in: input)
            wake = date(ofEpoch: wakeIndex, in: input)
            episodes = wakeRuns(states, from: onset, to: wakeIndex)
                .filter { Double($0.count) * NightProfile.epoch >= minimumWake }
                .map { run in
                    WakeEpisode(start: date(ofEpoch: run.lowerBound, in: input), end: date(ofEpoch: run.upperBound, in: input), source: source)
                }
        }
        return NightProfile(
            start: input.start,
            end: input.end,
            states: states,
            sleepOnset: sleepOnset,
            wake: wake,
            wakeEpisodes: episodes,
            reliability: usedMotion && usedSound ? .medium : .low,
            usedMotion: usedMotion,
            usedSound: usedSound
        )
    }

    // MARK: - Une période

    static func classify(_ index: Int, motion: [Float?]?, sound: Double?, marks: EpochMarks) -> EpochState {
        let moved: Float? = motion.flatMap { $0[index] }
        if marks.snoring[index], moved != nil || sound != nil {
            // On ronfle en dormant : calme, ou agité si le lit bouge beaucoup.
            return (moved ?? 0) >= awakeMotion ? .agitated : .calm
        }
        if let moved {
            let noisy = sound ?? 0
            let lasting = moved >= awakeMotion && hasMovingNeighbor(index, motion: motion)
            if lasting || (moved >= agitatedMotion && (marks.speech[index] || noisy >= awakeSound)) {
                return .awake
            }
            if moved >= agitatedMotion || marks.speech[index] || marks.cough[index] || noisy >= agitatedSoundWithMotion {
                return .agitated
            }
            return .calm
        }
        if let sound {
            if marks.speech[index] || sound >= awakeSound {
                return .awake
            }
            if marks.cough[index] || sound >= agitatedSound {
                return .agitated
            }
            return .calm
        }
        return .unknown
    }

    /// Vrai si la période d'avant ou d'après bouge aussi : le mouvement dure plus de 30 secondes.
    static func hasMovingNeighbor(_ index: Int, motion: [Float?]?) -> Bool {
        guard let motion else { return false }
        return [index - 1, index + 1].contains { neighbor in
            neighbor >= 0 && neighbor < motion.count && (motion[neighbor] ?? 0) >= agitatedMotion
        }
    }

    // MARK: - Mesures

    /// Mouvement de chaque période au-dessus du repos de la nuit, ou nil si l'iPhone n'était pas sur le lit :
    /// posé sur la table de nuit, il ne sent presque rien en dehors du coucher et du lever.
    static func motionLevels(_ values: [Float?], count: Int) -> [Float?]? {
        let measured = values.prefix(count).compactMap { $0 }
        guard !measured.isEmpty else { return nil }
        let rest = percentile(measured, 0.1)
        let levels = (0..<count).map { index -> Float? in
            guard index < values.count, let value = values[index] else { return nil }
            return max(0, value - rest)
        }
        let margin = min(20, count / 5)
        let moving = levels.indices.filter { index in
            index >= margin && index < count - margin && (levels[index] ?? 0) >= agitatedMotion
        }
        return moving.count >= minimumMovingEpochs ? levels : nil
    }

    /// Part des secondes de chaque période où un son de la personne dépasse le bruit de fond de 10 dB.
    /// Ronflements et respiration (signes de sommeil), bruits extérieurs et sons d'une autre personne ne comptent pas.
    static func soundActivity(_ input: ProfileInput, count: Int) -> [Double?] {
        let seconds = min(input.peaks.count, input.means.count)
        guard seconds > 0 else { return [Double?](repeating: nil, count: count) }
        var ignored = [Bool](repeating: false, count: seconds)
        for event in input.events where event.isSomeoneElse || !countsAsActivity(event.kind) {
            let first = max(0, Int(event.start.timeIntervalSince(input.start).rounded(.down)))
            let last = min(seconds - 1, Int(event.end.timeIntervalSince(input.start).rounded(.up)) - 1)
            guard first <= last else { continue }
            for second in first...last {
                ignored[second] = true
            }
        }
        let perEpoch = Int(NightProfile.epoch)
        return (0..<count).map { index -> Double? in
            let from = index * perEpoch
            guard from < seconds else { return nil }
            let to = min(seconds, from + perEpoch)
            guard let floor = noiseFloor(input.means, from: from, to: to) else { return nil }
            var measured = 0
            var loud = 0
            for second in from..<to {
                guard let peak = input.peaks[second] else { continue }
                measured += 1
                if !ignored[second], peak >= floor + soundThreshold {
                    loud += 1
                }
            }
            return measured > 0 ? Double(loud) / Double(measured) : nil
        }
    }

    /// Bruit de fond autour d'une période : 20e centile des niveaux moyens sur dix minutes.
    static func noiseFloor(_ means: [Float?], from: Int, to: Int) -> Float? {
        let lower = max(0, from - 300)
        let upper = min(means.count, to + 300)
        guard lower < upper else { return nil }
        let window = means[lower..<upper].compactMap { $0 }
        return window.isEmpty ? nil : percentile(window, 0.2)
    }

    /// Vrai pour un son qui peut venir d'une personne éveillée ou agitée.
    static func countsAsActivity(_ kind: EventKind) -> Bool {
        switch kind {
        case .snoring, .breathing, .external: false
        default: true
        }
    }

    /// Valeur sous laquelle tombe une part des mesures (0,2 : 20e centile).
    static func percentile(_ values: [Float], _ fraction: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = Int((Double(sorted.count - 1) * fraction).rounded(.down))
        return sorted[min(sorted.count - 1, max(0, position))]
    }

    // MARK: - Horaires

    /// Première période qui ouvre `length` périodes de sommeil : calme au départ, sans éveil ni trou, calmes aux trois quarts.
    static func firstSleepStretch(_ states: [EpochState], length: Int) -> Int? {
        guard length > 0, states.count >= length else { return nil }
        for start in 0...(states.count - length) where states[start] == .calm {
            let window = states[start..<(start + length)]
            guard window.allSatisfy(\.isAsleep) else { continue }
            if Double(window.filter { $0 == .calm }.count) >= 0.75 * Double(length) {
                return start
            }
        }
        return nil
    }

    /// Fin du dernier sommeil d'au moins trois périodes : un instant calme pendant le lever ne compte pas.
    static func lastSleepEnd(_ states: [EpochState], from onset: Int) -> Int? {
        var run = 0
        for index in stride(from: states.count - 1, through: max(0, onset), by: -1) {
            if states[index].isAsleep {
                run += 1
                if run >= minimumSleepBlock {
                    return index + run
                }
            } else {
                run = 0
            }
        }
        return nil
    }

    /// Suites de périodes d'éveil, réunies quand une seule période les sépare.
    static func wakeRuns(_ states: [EpochState], from: Int, to: Int) -> [Range<Int>] {
        let upper = min(to, states.count)
        guard from >= 0, from < upper else { return [] }
        var runs: [Range<Int>] = []
        var current: Range<Int>?
        for index in from..<upper where states[index] == .awake {
            if let run = current, index - run.upperBound <= 1 {
                current = run.lowerBound..<(index + 1)
            } else {
                if let run = current {
                    runs.append(run)
                }
                current = index..<(index + 1)
            }
        }
        if let run = current {
            runs.append(run)
        }
        return runs
    }

    /// Heure du début d'une période, sans dépasser la fin de la nuit.
    static func date(ofEpoch index: Int, in input: ProfileInput) -> Date {
        min(input.end, input.start.addingTimeInterval(Double(index) * NightProfile.epoch))
    }
}

/// Périodes où un son de la personne a été reconnu.
struct EpochMarks {
    var snoring: [Bool]
    var speech: [Bool]
    var cough: [Bool]

    init(events: [NightEvent], start: Date, count: Int) {
        snoring = [Bool](repeating: false, count: count)
        speech = [Bool](repeating: false, count: count)
        cough = [Bool](repeating: false, count: count)
        for event in events where !event.isSomeoneElse {
            let first = max(0, Int((event.start.timeIntervalSince(start) / NightProfile.epoch).rounded(.down)))
            let last = min(count - 1, Int((event.end.timeIntervalSince(start) / NightProfile.epoch).rounded(.up)) - 1)
            guard first <= last else { continue }
            for index in first...last {
                switch event.kind {
                case .snoring, .breathing: snoring[index] = true
                case .speech: speech[index] = true
                case .cough: cough[index] = true
                default: break
                }
            }
        }
    }
}
