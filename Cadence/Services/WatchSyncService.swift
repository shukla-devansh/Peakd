//  WatchSyncService.swift
//  iPhone side of WatchConnectivity: pairing status (Permissions, Profile), pushing the workout
//  state to the Watch, and receiving the Watch's commands and live heart rate.

import Observation
import WatchConnectivity

@Observable
@MainActor
final class WatchSyncService: NSObject {
    private(set) var isActivated = false
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false

    /// Latest heart rate from the Watch's workout session.
    private(set) var liveHeartRate: Double?
    private(set) var liveHeartRateDate: Date?
    /// Active energy reported by the Watch for the running workout, in kcal.
    private(set) var liveEnergyKcal: Double?
    /// Every heart-rate sample of the running workout (fallback for the Summary).
    private(set) var workoutHeartRates: [Double] = []

    /// Set by AppState: what to do when the Watch logs a set or changes the rest.
    var onCommand: ((WatchCommand) -> Void)?

    private var lastSent: WatchWorkoutState?

    var isSupported: Bool { WCSession.isSupported() }
    /// "Connected" on Profile, "On" on Permissions.
    var isConnected: Bool { isPaired && isWatchAppInstalled }

    /// Heart rate shown on Active: only while it's fresh.
    func currentHeartRate(at date: Date = .now) -> Double? {
        guard let bpm = liveHeartRate, let at = liveHeartRateDate, date.timeIntervalSince(at) < 20 else { return nil }
        return bpm
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState == .activated {
            update(activated: true, paired: session.isPaired, installed: session.isWatchAppInstalled)
        } else {
            session.activate()
        }
    }

    /// Sends the workout state if it changed. Application context keeps only the latest, and is
    /// delivered when the Watch app next runs; a direct message gets there at once if it's open.
    func push(_ state: WatchWorkoutState) {
        guard state != lastSent, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        lastSent = state
        let payload = WatchWire.encode(state)
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    /// A new workout: forget the last one's live data.
    func resetLiveData() {
        liveHeartRate = nil
        liveHeartRateDate = nil
        liveEnergyKcal = nil
        workoutHeartRates = []
    }

    private func update(activated: Bool, paired: Bool, installed: Bool) {
        isActivated = activated
        isPaired = paired
        isWatchAppInstalled = installed
        if activated { lastSent = nil }   // resend on the next push
    }

    private func receive(_ command: WatchCommand) {
        switch command {
        case .heartRate(let bpm, let at):
            liveHeartRate = bpm
            liveHeartRateDate = at
            workoutHeartRates.append(bpm)
        case .activeEnergy(let kcal):
            liveEnergyKcal = kcal
        default:
            onCommand?(command)
        }
    }
}

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        let activated = state == .activated
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor in self.update(activated: activated, paired: paired, installed: installed) }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor in self.update(activated: true, paired: paired, installed: installed) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = WatchWire.command(from: message) else { return }
        Task { @MainActor in self.receive(command) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let command = WatchWire.command(from: userInfo) else { return }
        Task { @MainActor in self.receive(command) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The user switched watches: reactivate for the new one.
        session.activate()
    }
}
