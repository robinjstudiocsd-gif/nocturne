#if os(iOS)
import CoreMotion
import Foundation

/// Mouvements de l'iPhone posé sur le lit, mesurés 10 fois par seconde et résumés par 30 secondes.
final class MotionSampler: @unchecked Sendable {
    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var accumulator: MotionAccumulator
    private var writer: MotionSeriesWriter?

    init(fileURL: URL, start: Date) throws {
        accumulator = MotionAccumulator(start: start)
        writer = try MotionSeriesWriter(fileURL: fileURL, start: start)
        queue.maxConcurrentOperationCount = 1
        queue.name = "nocturne.mouvements"
    }

    func start() {
        guard manager.isAccelerometerAvailable, !manager.isAccelerometerActive else { return }
        manager.accelerometerUpdateInterval = 0.1
        manager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            self.record(x: data.acceleration.x, y: data.acceleration.y, z: data.acceleration.z)
        }
    }

    func stop() {
        manager.stopAccelerometerUpdates()
        lock.lock()
        defer { lock.unlock() }
        if let last = accumulator.flush() {
            try? writer?.append([last])
        }
        try? writer?.close()
        writer = nil
    }

    private func record(x: Double, y: Double, z: Double) {
        lock.lock()
        defer { lock.unlock() }
        let windows = accumulator.add(x: x, y: y, z: z, at: Date())
        if !windows.isEmpty {
            try? writer?.append(windows)
        }
    }
}
#endif
