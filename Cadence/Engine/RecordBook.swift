//  RecordBook.swift
//  Personal records, rebuilt from an exercise's full history so that finishing, editing or deleting
//  a workout always leaves the records consistent.
//
//  Rules: walk finished sessions oldest first; a session sets a record when it beats the best of all
//  earlier sessions (the first session sets the baseline, not a record).
//  - heaviest: heaviest completed weight
//  - est1RM:   highest Epley estimate; bestSet stores the set that produced it (weight + reps)

import Foundation
import SwiftData

enum RecordBook {
    /// Tolerance so float noise ("42.5 vs 42.4999") never counts as a record.
    static let epsilon = 0.001

    @MainActor
    static func rebuild(for exercise: Exercise, in context: ModelContext) {
        for record in exercise.records { context.delete(record) }

        let sessions = exercise.workoutEntries
            .compactMap { entry -> (Workout, WorkoutExercise)? in
                guard let workout = entry.workout, !workout.isGone, workout.end != nil else { return nil }
                return (workout, entry)
            }
            .sorted { $0.0.start < $1.0.start }

        var bestWeight: Double?
        var best1RM: Double?

        for (workout, entry) in sessions {
            let sets = entry.completedSets.compactMap { set -> (weight: Double, reps: Int)? in
                guard let weight = set.weightKg, let reps = set.reps, weight > 0, reps > 0 else { return nil }
                return (weight, reps)
            }
            guard let heaviest = sets.map(\.weight).max(),
                  let top = sets.max(by: {
                      WorkoutMetrics.estimatedOneRepMax(weightKg: $0.weight, reps: $0.reps)
                          < WorkoutMetrics.estimatedOneRepMax(weightKg: $1.weight, reps: $1.reps)
                  })
            else { continue }
            let topEstimate = WorkoutMetrics.estimatedOneRepMax(weightKg: top.weight, reps: top.reps)
            let date = workout.end ?? workout.start

            if let previous = bestWeight, heaviest > previous + epsilon {
                context.insert(PersonalRecord(kind: .heaviest, value: heaviest, date: date,
                                              exercise: exercise, workout: workout))
            }
            if let previous = best1RM, topEstimate > previous + epsilon {
                context.insert(PersonalRecord(kind: .est1RM, value: topEstimate, date: date,
                                              exercise: exercise, workout: workout))
                context.insert(PersonalRecord(kind: .bestSet, value: top.weight, reps: top.reps, date: date,
                                              exercise: exercise, workout: workout))
            }
            bestWeight = max(bestWeight ?? 0, heaviest)
            best1RM = max(best1RM ?? 0, topEstimate)
        }
    }

    /// One line per exercise for the Summary card: the est. 1RM record if there is one, else heaviest.
    struct Highlight: Identifiable, Equatable {
        let id: String
        let exerciseName: String
        let kind: RecordKind
        /// kg
        let value: Double
    }

    @MainActor
    static func highlights(for workout: Workout) -> [Highlight] {
        let byExercise = Dictionary(grouping: workout.records.filter { !$0.isGone }) {
            $0.exercise?.name ?? ""
        }
        let order = workout.orderedExercises.map(\.exerciseName)
        return byExercise.compactMap { name, records -> Highlight? in
            guard let record = records.first(where: { $0.kind == .est1RM }) ?? records.first(where: { $0.kind == .heaviest })
            else { return nil }
            return Highlight(id: name + record.kindRaw, exerciseName: name, kind: record.kind, value: record.value)
        }
        .sorted { (order.firstIndex(of: $0.exerciseName) ?? 0) < (order.firstIndex(of: $1.exerciseName) ?? 0) }
    }
}
