//  PermissionsService.swift
//  The four optional permissions on the Permissions board, with one state each.

import AVFAudio
import Observation
import Speech
import UserNotifications

enum PermissionState: Sendable, Equatable {
    case notDetermined, granted, denied, unavailable
}

enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case voice, health, notifications, watch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice:         "Microphone and speech"
        case .health:        "Apple Health"
        case .notifications: "Notifications"
        case .watch:         "Apple Watch"
        }
    }

    var reason: String {
        switch self {
        case .voice:         "Log a set by saying “45 kilos for 8 reps”."
        case .health:        "Heart rate and energy in summaries; saves workouts to Health."
        case .notifications: "Tells you when rest is over, even when the phone is locked."
        case .watch:         "See your set and rest timer on your wrist. Needs the Watch app."
        }
    }

    var systemImage: String {
        switch self {
        case .voice:         "mic"
        case .health:        "heart"
        case .notifications: "bell"
        case .watch:         "applewatch"
        }
    }
}

@Observable
@MainActor
final class PermissionsService {
    private(set) var states: [PermissionKind: PermissionState] = [:]

    let watch = WatchSyncService()
    private let health = HealthService()

    func state(_ kind: PermissionKind) -> PermissionState {
        if kind == .watch { return watchState }
        return states[kind] ?? .notDetermined
    }

    /// Re-read every status. Call on appear and when the app returns to the foreground
    /// (the user may have changed something in Settings).
    func refresh() async {
        states[.voice] = Self.voiceState
        states[.health] = await health.state
        states[.notifications] = await Self.notificationState()
        watch.activate()
    }

    /// Shows the system prompt. Returns `false` if the system won't prompt again
    /// (already denied): the caller should send the user to Settings instead.
    @discardableResult
    func request(_ kind: PermissionKind) async -> Bool {
        defer { Task { await refresh() } }
        switch kind {
        case .voice:
            guard Self.voiceState == .notDetermined else { return Self.voiceState != .denied }
            if AVAudioApplication.shared.recordPermission == .undetermined {
                _ = await AVAudioApplication.requestRecordPermission()
            }
            if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                _ = await Self.requestSpeechAuthorization()
            }
            return true
        case .health:
            guard await health.state == .notDetermined else { return await health.state != .denied }
            try? await health.requestAuthorization()
            return true
        case .notifications:
            guard await Self.notificationState() == .notDetermined else {
                return await Self.notificationState() != .denied
            }
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return true
        case .watch:
            watch.activate()
            return true
        }
    }

    // MARK: - Status readers

    private var watchState: PermissionState {
        guard watch.isSupported else { return .unavailable }
        return watch.isConnected ? .granted : .notDetermined
    }

    private static var voiceState: PermissionState {
        let mic = AVAudioApplication.shared.recordPermission
        let speech = SFSpeechRecognizer.authorizationStatus()
        if speech == .restricted { return .unavailable }
        if mic == .denied || speech == .denied { return .denied }
        if mic == .granted && speech == .authorized { return .granted }
        return .notDetermined
    }

    private static func notificationState() async -> PermissionState {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .granted
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    /// Nonisolated with an explicitly @Sendable callback: Speech calls back on a background queue,
    /// and a closure that inherited main-actor isolation would trap there under Swift 6.
    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }
    }
}
