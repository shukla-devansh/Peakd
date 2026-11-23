//  ExerciseStats.swift
//  Numbers for ExerciseDetail (board 10): all-time records, the top-set series for the chart,
//  history rows, and the "Next time" card text built from OverloadEngine's suggestion.

import Foundation

struct ExerciseRecords: Sendable, Equatable {
    var heaviestKg: Double?
    /// The set with the highest est. 1RM.
    var bestSet: LoggedSet?
    var est1RMKg: Double?
    /// For reps-only exercises.
    var mostReps: Int?
    var sessions: Int
}

struct TopSetPoint: Sendable, Equatable, Identifiable {
    var date: Date
    var weightKg: Double
    var id: Date { date }
}

enum ExerciseStats {
    /// `sessions` newest first (TrainingHistory.sessions).
    static func records(_ sessions: [ExerciseSession]) -> ExerciseRecords {
        let sets = sessions.flatMap(\.sets)
        let weighted = sets.filter { ($0.weightKg ?? 0) > 0 }
        let best = weighted.max {
            WorkoutMetrics.estimatedOneRepMax(weightKg: $0.weightKg ?? 0, reps: $0.reps)
                < WorkoutMetrics.estimatedOneRepMax(weightKg: $1.weightKg ?? 0, reps: $1.reps)
        }
        return ExerciseRecords(
            heaviestKg: weighted.compactMap(\.weightKg).max(),
            bestSet: best,
            est1RMKg: best.map { WorkoutMetrics.estimatedOneRepMax(weightKg: $0.weightKg ?? 0, reps: $0.reps) },
            mostReps: sets.map(\.reps).max(),
            sessions: sessions.filter { !$0.sets.isEmpty }.count
        )
    }

    /// Heaviest set per session, oldest first, last `limit` sessions.
    static func topSets(_ sessions: [ExerciseSession], limit: Int = 12) -> [TopSetPoint] {
        sessions.prefix(limit).compactMap { s in
            s.sets.compactMap(\.weightKg).filter { $0 > 0 }.max().map { TopSetPoint(date: s.date, weightKg: $0) }
        }
        .reversed()
    }

    /// "42.5 × 10, 42.5 × 10, 45 × 8" (reps-only: "12, 10, 9").
    static func setsText(_ session: ExerciseSession, unit: WeightUnit) -> String {
        session.sets.map { WeightFormatter.setString(kg: ($0.weightKg ?? 0) > 0 ? $0.weightKg : nil, reps: $0.reps, in: unit) }
            .joined(separator: ", ")
    }

    static func volumeKg(_ session: ExerciseSession) -> Double {
        session.sets.reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.reps) }
    }

    /// "Next time: 45 kg × 8–10" and the sentence under it.
    static func nextTime(_ s: OverloadSuggestion, last: ExerciseSession?, step: Double?, unit: WeightUnit) -> (title: String, detail: String) {
        let low = s.repRange.lowerBound, high = s.repRange.upperBound
        let range = "\(low)–\(high)"
        func w(_ kg: Double) -> String { WeightFormatter.string(kg: kg, in: unit) }

        guard let kg = s.weightKg else {
            let best = last?.sets.map(\.reps).max()
            return ("Next time: \(s.targetReps) reps",
                    best.map { "Your best last time was \($0) reps. Aim for \(s.targetReps) on your first set." }
                        ?? "Aim for \(s.targetReps) reps on your first set.")
        }
        let title = "Next time: \(w(kg)) × \(range)"
        switch s.change {
        case .increase(let added):
            return (title, "You hit \(high) reps on every set at \(w(kg - added)). Add \(w(added)) and start back at \(low) reps.")
        case .same:
            let atWeight = last?.sets.filter { abs(($0.weightKg ?? 0) - kg) < 0.01 }.map(\.reps).max()
            let reached = atWeight.map { "You reached \($0) reps at \(w(kg)). " } ?? ""
            let then = step.map { "then add \(w($0))." } ?? "then add weight."
            return (title, reached + "Stay at this weight until you hit \(high) reps on every set, " + then)
        case .decrease(let percent):
            return (title, "You missed \(low) reps two sessions running, so the weight comes down \(percent)%. Build back up from \(w(kg)).")
        case .addRep:
            return (title, "Aim for \(s.targetReps) reps, one more than last time.")
        }
    }
}
