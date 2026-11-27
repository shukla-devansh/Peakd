//  WatchConnector.swift
//  Watch side of WatchConnectivity: receives the workout state from the iPhone, sends commands
//  and live heart rate back, and runs the HealthKit workout session while a workout is active.

import HealthKit
import Observation
import WatchConnectivity

@Observable
@MainActor
final class WatchConnector: NSObject {
    /// One per app: the app delegate (launch from the iPhone, workout recovery) and the views share it.
    static let shared = WatchConnector()

    private(set) var state: WatchWorkoutState = .inactive
    private(set) var heartRate: Double?
    private(set) var activeEnergyKcal: Double?
    private(set) var isReachable = false

    private let live = LiveWorkoutSession()
    private var lastHeartRateSent = Date.distantPast
    private var isActivating = false

    override init() {
        super.init()
        live.onHeartRate = { [weak self] bpm in Task { @MainActor in self?.receiveHeartRate(bpm) } }
        live.onEnergy = { [weak self] kcal in Task { @MainActor in self?.receiveEnergy(kcal) } }
        live.onEnd = { [weak self] in Task { @MainActor in self?.liveSessionEnded() } }
    }

    /// Safe to call more than once (app launch and the first view both call it).
    func activate() {
        guard WCSession.isSupported(), !isActivating else { return }
        isActivating = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// The iPhone started a workout and launched this app (HKHealthStore.startWatchApp): start
    /// the heart-rate session now, before the workout state has even arrived.
    func startFromPhone(_ configuration: HKWorkoutConfiguration) {
        activate()
        if !live.isRunning {
            heartRate = nil
            activeEnergyKcal = nil
        }
        live.start(activityType: configuration.activityType, locationType: configuration.locationType)
    }

    /// The app was relaunched mid-workout: take the running session back, then line it up with
    /// the iPhone's state (it may have finished meanwhile).
    func recoverWorkout() {
        activate()
        live.recover { [weak self] _ in Task { @MainActor in self?.syncLiveSession() } }
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
        // An unchanged state (e.g. the stale context replayed at activation, just after the
        // iPhone launched us for a new workout) must not stop a session startFromPhone began.
        guard new != state else { return }
        let started = new.isActive && !state.isActive
        state = new
        if started && !live.isRunning {
            heartRate = nil
            activeEnergyKcal = nil
        }
        syncLiveSession()
    }

    /// The heart-rate session runs exactly while the iPhone's workout does. Called on every
    /// state change, so a session that ended or failed is retried on the next update.
    private func syncLiveSession() {
        if state.isActive { live.start() } else { live.stop() }
    }

    private func liveSessionEnded() {
        heartRate = nil
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
