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

enum WatchCommand: Codable, Equatable, Sendable {
    /// Logs the current set with these values (from the Watch's edit screen).
    /// `voice`: the values came from Watch dictation (the set is logged with source voice).
    case logSet(weightKg: Double?, reps: Int, voice: Bool = false)
    case skipRest
    case adjustRest(seconds: Int)
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

/// Average and peak heart rate from samples (Watch live data when Health has none).
enum HeartRateStats {
    static func summary(_ bpm: [Double]) -> (average: Double, max: Double)? {
        guard !bpm.isEmpty, let max = bpm.max() else { return nil }
        return (bpm.reduce(0, +) / Double(bpm.count), max)
    }
}
