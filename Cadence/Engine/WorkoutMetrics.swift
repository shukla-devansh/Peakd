//  WorkoutMetrics.swift
//  Deterministic numbers from logged sets (docs/PROJECT_GUIDE.md engine rules).

import Foundation

enum WorkoutMetrics {
    /// Epley: w × (1 + reps / 30).
    static func estimatedOneRepMax(weightKg: Double, reps: Int) -> Double {
        weightKg * (1 + Double(reps) / 30)
    }

    /// Weight × reps of one set, 0 unless it's completed with both values.
    static func volume(of set: SetLog) -> Double {
        guard set.isCompleted, let weight = set.weightKg, let reps = set.reps else { return 0 }
        return weight * Double(reps)
    }

    /// Σ weight × reps of completed sets.
    static func volume(of entry: WorkoutExercise) -> Double {
        entry.sets.reduce(0) { $0 + volume(of: $1) }
    }

    static func volume(of workout: Workout) -> Double {
        workout.exercises.reduce(0) { $0 + volume(of: $1) }
    }

    static func completedSetCount(of workout: Workout) -> Int {
        workout.exercises.reduce(0) { $0 + $1.completedSets.count }
    }

    static func completedReps(of workout: Workout) -> Int {
        workout.exercises.flatMap(\.completedSets).reduce(0) { $0 + ($1.reps ?? 0) }
    }

    /// Percent change vs a previous value, rounded: +6, -4. `nil` without a usable baseline.
    static func percentChange(from previous: Double, to current: Double) -> Int? {
        guard previous > 0 else { return nil }
        return Int(((current - previous) / previous * 100).rounded())
    }
}
