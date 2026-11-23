#if os(iOS)
import AVFoundation
import Foundation
import SleepDomain
import UIKit
import UserNotifications

/// Mesures de l'iPhone pour « Préparer ma nuit » : batterie, volume, espace libre, autorisations, signature.
@MainActor
public final class DevicePreflight: PreflightProvider {
    private let storage: RecordingStorage
    private let signatureExpiry: Date?

    public init(storage: RecordingStorage, signatureExpiry: Date?) {
        self.storage = storage
        self.signatureExpiry = signatureExpiry
    }

    public func readings() async -> PreflightReadings {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        let state = device.batteryState
        let free = try? storage.root
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        let notifications = await Self.notificationState()
        return PreflightReadings(
            batteryLevel: level >= 0 ? Double(level) : nil,
            isPluggedIn: state == .charging || state == .full,
            volume: Double(AVAudioSession.sharedInstance().outputVolume),
            freeBytes: free,
            microphone: Self.microphoneState(),
            notifications: notifications,
            signatureExpiry: signatureExpiry
        )
    }

    public func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    public func requestNotifications() async -> Bool {
        await Self.askForNotifications()
    }

    private static func microphoneState() -> PermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .undetermined
        }
    }

    nonisolated private static func notificationState() async -> PermissionState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }

    nonisolated private static func askForNotifications() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
}
#endif
