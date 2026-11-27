//  WatchMessages.swift
//  What the iPhone and the Watch tell each other over WatchConnectivity.
//  iPhone → Watch: the whole workout state (latest wins, sent as application context).
//  Watch → iPhone: commands (log a set, rest controls) and live heart rate / energy.

import Foundation

/// Everything the Watch screens show. The iPhone owns the workout; the Watch mirrors it.
struct WatchWorkoutState: Codable, Equatable, Sendable {
    var isActive: Bool
    var workoutName = ""
    var startedAt = Date.distantPast
    var exerciseName: String?
    /// The set the Watch would log next.
    var setNumber: Int?
    var totalSets: Int?
    var weightKg: Double?
    var reps: Int?
    var tracksWeight = true
    var unit: WeightUnit = .kg
    /// Digital Crown step for weight, in kg (2.5 kg or 5 lb).
    var weightStepKg = 2.5
    var restEnd: Date?
    var restTotalSeconds: Int?
    /// "Next: set 4 · 42.5 kg × 10"
    var nextText: String?
    /// Profile → Voice set logging: shows the Watch's mic button.
    var voiceLogging = true
    /// The set "Log set" fills in. Sent back with the log so a log that arrives late can't land
    /// on a different exercise, set or workout. nil when there's no exercise yet.
    var target: WatchSetTarget?

    static let inactive = WatchWorkoutState(isActive: false)

    /// "42.5 kg × 10", "12 reps", "–".
    var setText: String {
        switch (tracksWeight ? weightKg : nil, reps) {
        case let (kg?, reps?): "\(WeightFormatter.string(kg: kg, in: unit)) × \(reps)"
        case let (nil, reps?): "\(reps) reps"
        case let (kg?, nil): WeightFormatter.string(kg: kg, in: unit)
        case (nil, nil): "–"
        }
    }

    func isResting(at date: Date) -> Bool {
        guard let restEnd else { return false }
        return restEnd > date
    }
}

/// Which set a Watch log is meant for. Commands queued while the iPhone is out of reach are
/// delivered later, when the iPhone may have moved on, so the log names its set instead of
/// meaning "whatever is current when this arrives".
struct WatchSetTarget: Codable, Equatable, Sendable {
    var workoutStart: Date
    var exerciseOrder: Int
    var exerciseName: String
    var setIndex: Int
}

enum WatchCommand: Codable, Equatable, Sendable {
    /// Logs the target set with these values (from the Watch's edit screen).
    /// `voice`: the values came from Watch dictation (the set is logged with source voice).
    case logSet(weightKg: Double?, reps: Int, voice: Bool = false, target: WatchSetTarget)
    /// Rest controls carry when they were pressed: a late one would act on a different rest.
    case skipRest(sentAt: Date)
    case adjustRest(seconds: Int, sentAt: Date)
    /// Live samples from the Watch's workout session.
    case heartRate(bpm: Double, at: Date)
    case activeEnergy(kcal: Double)
}

/// Dictionary keys and JSON coding for WCSession payloads.
enum WatchWire {
    static let stateKey = "state"
    static let commandKey = "command"

    static func encode(_ state: WatchWorkoutState) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(state) else { return [:] }
        return [stateKey: data]
    }

    static func encode(_ command: WatchCommand) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(command) else { return [:] }
        return [commandKey: data]
    }

    static func state(from payload: [String: Any]) -> WatchWorkoutState? {
        (payload[stateKey] as? Data).flatMap { try? JSONDecoder().decode(WatchWorkoutState.self, from: $0) }
    }

    static func command(from payload: [String: Any]) -> WatchCommand? {
        (payload[commandKey] as? Data).flatMap { try? JSONDecoder().decode(WatchCommand.self, from: $0) }
    }
}

/// How the iPhone checks a Watch command before acting on it. Pure, so it's unit-tested.
enum WatchCommandCheck {
    /// Rest controls older than this are dropped (they were queued while the phone was away).
    static let maxRestCommandAge: TimeInterval = 15

    static func isFresh(_ sentAt: Date, now: Date = .now) -> Bool {
        now.timeIntervalSince(sentAt) <= maxRestCommandAge
    }

    static func isSameWorkout(_ target: WatchSetTarget, workoutStart: Date) -> Bool {
        abs(target.workoutStart.timeIntervalSince(workoutStart)) < 1
    }

    /// Index of the entry the log is for: same position and name, or else the only entry with
    /// that name (the user reordered exercises meanwhile). nil when it's gone or ambiguous.
    static func entryIndex(for target: WatchSetTarget, in entries: [(order: Int, name: String)]) -> Int? {
        if let exact = entries.firstIndex(where: { $0.order == target.exerciseOrder && $0.name == target.exerciseName }) {
            return exact
        }
        let sameName = entries.indices.filter { entries[$0].name == target.exerciseName }
        return sameName.count == 1 ? sameName[0] : nil
    }

    enum SetPlacement: Equatable, Sendable {
        /// The set exists and isn't done yet: fill it in and tick it.
        case fill
        /// The set is the next one after the last: add it, then fill it in.
        case append
        /// Already done (e.g. ticked on the iPhone meanwhile) or no longer there: ignore the log.
        case drop
    }

    static func placement(for setIndex: Int, in sets: [(index: Int, isCompleted: Bool)]) -> SetPlacement {
        if let set = sets.first(where: { $0.index == setIndex }) { return set.isCompleted ? .drop : .fill }
        let next = (sets.map(\.index).max() ?? 0) + 1
        return setIndex == next ? .append : .drop
    }
}

/// Average and peak heart rate from samples (Watch live data when Health has none).
enum HeartRateStats {
    static func summary(_ bpm: [Double]) -> (average: Double, max: Double)? {
        guard !bpm.isEmpty, let max = bpm.max() else { return nil }
        return (bpm.reduce(0, +) / Double(bpm.count), max)
    }
}
