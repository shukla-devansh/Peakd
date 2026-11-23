//  WatchConnector.swift
//  Watch side of WatchConnectivity: receives the workout state from the iPhone, sends commands
//  and live heart rate back, and runs the HealthKit workout session while a workout is active.

import Observation
import WatchConnectivity

@Observable
@MainActor
final class WatchConnector: NSObject {
    private(set) var state: WatchWorkoutState = .inactive
    private(set) var heartRate: Double?
    private(set) var activeEnergyKcal: Double?
    private(set) var isReachable = false

    private let live = LiveWorkoutSession()
    private var lastHeartRateSent = Date.distantPast

    override init() {
        super.init()
        live.onHeartRate = { [weak self] bpm in Task { @MainActor in self?.receiveHeartRate(bpm) } }
        live.onEnergy = { [weak self] kcal in Task { @MainActor in self?.receiveEnergy(kcal) } }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Commands go straight through when the phone is reachable, and are queued otherwise.
    func send(_ command: WatchCommand) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let payload = WatchWire.encode(command)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in session.transferUserInfo(payload) }
        } else if case .heartRate = command {
            return   // stale heart rate is useless later
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func apply(_ new: WatchWorkoutState) {
        let started = new.isActive && !state.isActive
        let ended = !new.isActive && state.isActive
        state = new
        if started {
            heartRate = nil
            activeEnergyKcal = nil
            live.start()
        }
        if ended { live.stop() }
    }

    private func receiveHeartRate(_ bpm: Double) {
        heartRate = bpm
        // Every 5 s is plenty for the phone's header and the summary average.
        guard Date.now.timeIntervalSince(lastHeartRateSent) >= 5 else { return }
        lastHeartRateSent = .now
        send(.heartRate(bpm: bpm, at: .now))
    }

    private func receiveEnergy(_ kcal: Double) {
        activeEnergyKcal = kcal
        send(.activeEnergy(kcal: kcal))
    }
}

extension WatchConnector: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        let context = WatchWire.state(from: session.receivedApplicationContext)
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            if let context { self.apply(context) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let state = WatchWire.state(from: applicationContext) else { return }
        Task { @MainActor in self.apply(state) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let state = WatchWire.state(from: message) else { return }
        Task { @MainActor in self.apply(state) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }
}
