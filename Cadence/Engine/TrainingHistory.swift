//  TrainingHistory.swift
//  Turns SwiftData models into the plain value types the engines take.

import Foundation
import SwiftData

@MainActor
enum TrainingHistory {
    /// Finished workouts, newest first.
    static func digests(from workouts: [Workout]) -> [WorkoutDigest] {
        workouts
            .filter { !$0.isGone && $0.end != nil }
            .sorted { $0.start > $1.start }
            .map(digest)
    }

    static func digest(_ workout: Workout) -> WorkoutDigest {
        var below = 0, sets = 0
        var muscles: [MuscleGroup: Int] = [:]
        for entry in workout.exercises {
            let done = entry.completedSets
            sets += done.count
            if let low = entry.repRange?.lowerBound {
                below += done.filter { ($0.reps ?? 0) < low }.count
            }
            if let muscle = entry.exercise?.primaryMuscle {
                muscles[muscle, default: 0] += done.count
            }
        }
        return WorkoutDigest(
            date: workout.start,
            routineName: workout.routineName,
            volumeKg: WorkoutMetrics.volume(of: workout),
            setCount: sets,
            setsBelowTarget: below,
            exerciseNames: workout.orderedExercises.map(\.exerciseName),
            muscleSets: muscles
        )
    }

    /// The exercise's finished sessions, newest first, optionally leaving one workout out
    /// (the one in progress).
    static func sessions(for exercise: Exercise?, excluding workoutID: PersistentIdentifier? = nil) -> [ExerciseSession] {
        guard let exercise, !exercise.isGone else { return [] }
        return exercise.workoutEntries
            .compactMap { entry -> ExerciseSession? in
                guard let workout = entry.workout, !workout.isGone, workout.end != nil,
                      workout.persistentModelID != workoutID else { return nil }
                let sets = entry.completedSets.compactMap { set -> LoggedSet? in
                    guard let reps = set.reps, reps > 0 else { return nil }
                    return LoggedSet(weightKg: set.weightKg, reps: reps)
                }
                return ExerciseSession(date: workout.start, sets: sets)
            }
            .sorted { $0.date > $1.date }
    }

    static func plannerInputs(routines: [Routine], workouts: [Workout], defaultRange: ClosedRange<Int>) -> [PlannerRoutineInput] {
        routines.filter { !$0.isGone }.map { routine in
            let lastDone = workouts
                .filter { !$0.isGone && $0.end != nil && $0.routineName == routine.name }
                .map(\.start).max()
            let items = routine.orderedItems.compactMap { item -> PlannerExerciseInput? in
                guard let exercise = item.exercise, !exercise.isGone else { return nil }
                return PlannerExerciseInput(
                    name: exercise.name, muscle: exercise.primaryMuscle, equipment: exercise.equipment,
                    targetSets: item.targetSets, repRange: item.repRange, restSeconds: item.restSeconds,
                    history: sessions(for: exercise)
                )
            }
            return PlannerRoutineInput(name: routine.name, createdAt: routine.createdAt, lastDone: lastDone, items: items)
        }
    }

    static func candidates(from exercises: [Exercise]) -> [NextExerciseSuggester.Candidate] {
        exercises.filter { !$0.isGone }.map {
            NextExerciseSuggester.Candidate(name: $0.name, muscle: $0.primaryMuscle, equipment: $0.equipment)
        }
    }
}

/// Everything the screens need from the engines, computed once per render from the queries.
@MainActor
struct CoachSnapshot {
    var fatigue: FatigueReport?
    var plan: SessionPlan?
    var digests: [WorkoutDigest]

    init(profile: UserProfile?, routines: [Routine], workouts: [Workout], lighten: Bool = false, now: Date = .now) {
        let digests = TrainingHistory.digests(from: workouts)
        self.digests = digests
        let fatigue = FatigueEngine.report(workouts: digests, plannedDaysPerWeek: profile?.daysPerWeek ?? 4, now: now)
        self.fatigue = fatigue
        let range = StarterPlan.repRange(for: profile?.goal ?? .strength)
        plan = Planner.plan(
            routines: TrainingHistory.plannerInputs(routines: routines, workouts: workouts, defaultRange: range),
            availableEquipment: profile?.availableEquipment ?? Set(Equipment.allCases),
            recentWorkouts: digests,
            fatigue: fatigue?.band,
            lighten: lighten,
            now: now
        )
    }
}
