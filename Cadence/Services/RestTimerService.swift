//  RestTimerService.swift
//  The rest countdown. Runs toward an end Date (never a counting Timer), so it's right after
//  backgrounding, and persists that date so a rest survives the app being killed.
//  Side effects (notification, Live Activity) go through RestTimerEffects so the logic is testable.

import Foundation
import Observation

/// What the rest is for and what comes next. Strings are pre-formatted in the user's unit.
struct RestInfo: Codable, Equatable, Sendable {
    var workoutName: String
    var workoutStart: Date
    /// The exercise just done: "Bench press"
    var exerciseName: String
    /// The set just completed.
    var afterSet: Int
    var nextExercise: String?
    var nextSet: Int?
    /// "42.5" (no unit), nil for bodyweight/timed sets
    var nextWeight: String?
    var unitSymbol: String
    var nextReps: Int?
    /// "40 × 9"
    var lastTime: String?

    /// "Bench press · after set 3"
    var subtitle: String { "\(exerciseName) · after set \(afterSet)" }

    /// "Bench press · set 4"
    var upNextTitle: String? {
        guard let nextExercise, let nextSet else { return nil }
        return "\(nextExercise) · set \(nextSet)"
    }

    /// "42.5 × 10", "12", nil when nothing is known yet.
    var upNextValue: String? {
        switch (nextWeight, nextReps) {
        case let (weight?, reps?): "\(weight) × \(reps)"
        case let (weight?, nil): "\(weight) \(unitSymbol)"
        case let (nil, reps?): "\(reps)"
        default: nil
        }
    }

    /// Notification body: "Bench press, set 4: 42.5 kg × 10. Last time 40 × 9."
    var notificationBody: String {
        guard let nextExercise, let nextSet else { return "Time for your next set." }
        var body = "\(nextExercise), set \(nextSet)"
        switch (nextWeight, nextReps) {
        case let (weight?, reps?): body += ": \(weight) \(unitSymbol) × \(reps)"
        case let (weight?, nil): body += ": \(weight) \(unitSymbol)"
        case let (nil, reps?): body += ": \(reps) reps"
        default: break
        }
        body += "."
        if let lastTime { body += " Last time \(lastTime)." }
        return body
    }
}

@MainActor
protocol RestTimerEffects: AnyObject {
    func scheduleRestOverNotification(at date: Date, info: RestInfo)
    func cancelRestOverNotification()
    func showActivity(info: RestInfo, endDate: Date, totalSeconds: Int, isOver: Bool)
    func endActivity()
}

@Observable
@MainActor
final class RestTimerService {
    static let step = 15
    static let maxSeconds = 600

    private(set) var endDate: Date?
    private(set) var totalSeconds = 0
    private(set) var info: RestInfo?
    /// Increments each time a rest reaches zero with alerts on: the haptic trigger.
    private(set) var finishedCount = 0
    /// Sound, haptic and notification at zero (Profile "Alert when rest ends").
    private(set) var alertsEnabled = true

    private let effects: RestTimerEffects
    private let now: () -> Date
    private let defaults: UserDefaults
    private var generation = 0

    private static let storageKey = "restTimer.snapshot"

    init(effects: RestTimerEffects, now: @escaping () -> Date = Date.init, defaults: UserDefaults = .standard) {
        self.effects = effects
        self.now = now
        self.defaults = defaults
        restore()
    }

    var isRunning: Bool { endDate != nil }

    func remaining(at date: Date) -> TimeInterval {
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(date))
    }

    /// 1 → 0 over the rest.
    func progress(at date: Date) -> Double {
        guard totalSeconds > 0 else { return 0 }
        return remaining(at: date) / Double(totalSeconds)
    }

    // MARK: Control

    func start(seconds: Int, info: RestInfo, alerts: Bool) {
        let seconds = min(max(seconds, 1), Self.maxSeconds)
        self.info = info
        self.alertsEnabled = alerts
        totalSeconds = seconds
        endDate = now().addingTimeInterval(TimeInterval(seconds))
        rescheduleEffects()
    }

    /// ±15 s. Taking it to zero ends the rest; the total grows with "+" up to 10 minutes.
    func adjust(by delta: Int) {
        guard let endDate else { return }
        let left = endDate.timeIntervalSince(now())
        let newLeft = min(max(left + TimeInterval(delta), 0), TimeInterval(Self.maxSeconds))
        guard newLeft > 0 else {
            skip()
            return
        }
        let elapsed = TimeInterval(totalSeconds) - left
        totalSeconds = max(Int((elapsed + newLeft).rounded()), 1)
        self.endDate = now().addingTimeInterval(newLeft)
        rescheduleEffects()
    }

    /// Ends the rest early: no alert, and the Live Activity shows the next set.
    func skip() {
        guard let info, let endDate else { return }
        effects.cancelRestOverNotification()
        effects.showActivity(info: info, endDate: min(endDate, now()), totalSeconds: totalSeconds, isOver: true)
        clear()
    }

    /// The alert toggle on the RestTimer screen.
    func setAlertsEnabled(_ enabled: Bool) {
        alertsEnabled = enabled
        if isRunning { rescheduleEffects() }
    }

    /// Workout finished or cancelled: remove everything.
    func stop() {
        effects.cancelRestOverNotification()
        effects.endActivity()
        clear()
    }

    /// Called when the countdown reaches zero while the app is running.
    func handleZero() {
        guard let info, let endDate, endDate <= now() else { return }
        if alertsEnabled { finishedCount += 1 }
        effects.showActivity(info: info, endDate: endDate, totalSeconds: totalSeconds, isOver: true)
        clear()
    }

    // MARK: Private

    private func rescheduleEffects() {
        guard let info, let endDate else { return }
        effects.cancelRestOverNotification()
        if alertsEnabled { effects.scheduleRestOverNotification(at: endDate, info: info) }
        effects.showActivity(info: info, endDate: endDate, totalSeconds: totalSeconds, isOver: false)
        persist()
        scheduleZeroCallback(at: endDate)
    }

    private func scheduleZeroCallback(at date: Date) {
        generation += 1
        let token = generation
        let delay = max(0, date.timeIntervalSince(now()))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.generation == token else { return }
            self.handleZero()
        }
    }

    private func clear() {
        generation += 1
        endDate = nil
        totalSeconds = 0
        info = nil
        defaults.removeObject(forKey: Self.storageKey)
    }

    private struct Snapshot: Codable {
        var info: RestInfo
        var endDate: Date
        var totalSeconds: Int
        var alerts: Bool
    }

    private func persist() {
        guard let info, let endDate else { return }
        let snapshot = Snapshot(info: info, endDate: endDate, totalSeconds: totalSeconds, alerts: alertsEnabled)
        defaults.set(try? JSONEncoder().encode(snapshot), forKey: Self.storageKey)
    }

    private func restore() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        guard snapshot.endDate > now() else {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        info = snapshot.info
        endDate = snapshot.endDate
        totalSeconds = snapshot.totalSeconds
        alertsEnabled = snapshot.alerts
        scheduleZeroCallback(at: snapshot.endDate)
    }
}
