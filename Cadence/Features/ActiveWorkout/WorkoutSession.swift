//  WorkoutSession.swift
//  The workout in progress: starting it, logging sets, finishing or cancelling.
//  Every mutation saves immediately, so a killed app resumes exactly where it was.

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class WorkoutSession {
    let workout: Workout
    private let context: ModelContext
    /// The expanded exercise card.
    var currentEntryID: PersistentIdentifier?

    static let defaultSetCount = 3

    init(workout: Workout, context: ModelContext) {
        self.workout = workout
        self.context = context
        self.currentEntryID = workout.orderedExercises.first { $0.completedSets.count < $0.sets.count }?.persistentModelID
            ?? workout.orderedExercises.first?.persistentModelID
    }

    // MARK: Starting

    /// Empty when `routine` is nil; otherwise one exercise per routine item with its target sets,
    /// weights pre-filled from the last time each exercise was done.
    static func start(routine: Routine?, in context: ModelContext, at date: Date = .now) -> WorkoutSession {
        let workout = Workout(start: date, routineName: routine?.name)
        context.insert(workout)
        let session = WorkoutSession(workout: workout, context: context)
        for item in routine?.orderedItems ?? [] {
            guard let exercise = item.exercise, !exercise.isGone else { continue }
            session.append(exercise, setCount: item.targetSets, repRange: item.repRange, restSeconds: item.restSeconds)
        }
        session.currentEntryID = workout.orderedExercises.first?.persistentModelID
        session.save()
        return session
    }

    /// From a SessionPlan (NextSession → "Start this workout"): the plan's sets, rep ranges and
    /// weights, which the user has seen and accepted.
    static func start(plan: SessionPlan, in context: ModelContext, at date: Date = .now) -> WorkoutSession {
        let session = start(routine: nil, in: context, at: date)
        session.workout.routineName = plan.routineName
        let names = Set(plan.exercises.map(\.name))
        let library = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let byName = Dictionary(library.filter { names.contains($0.name) && !$0.isGone }.map { ($0.name, $0) },
                                uniquingKeysWith: { a, b in a.isCustom ? b : a })
        for planned in plan.exercises {
            guard let exercise = byName[planned.name] else { continue }
            session.append(exercise, setCount: planned.sets, repRange: planned.repRange, restSeconds: planned.restSeconds)
            if let weight = planned.weightKg, let entry = session.workout.exercises.last {
                for set in entry.sets { set.weightKg = weight }
            }
        }
        session.currentEntryID = session.workout.orderedExercises.first?.persistentModelID
        session.save()
        return session
    }

    /// "Try 42.5 kg" chip: fill the suggested weight into the sets not done yet.
    func applySuggestedWeight(_ kg: Double, to entry: WorkoutExercise) {
        for set in entry.sets where !set.isCompleted { set.weightKg = kg }
        save()
    }

    /// "Repeat workout" from History: same exercises and set counts, weights from that session.
    static func repeating(_ past: Workout, in context: ModelContext, at date: Date = .now) -> WorkoutSession {
        let session = start(routine: nil, in: context, at: date)
        session.workout.routineName = past.routineName
        for entry in past.orderedExercises {
            guard let exercise = entry.exercise, !exercise.isGone else { continue }
            session.append(exercise, setCount: max(entry.sets.count, 1), repRange: entry.repRange,
                           restSeconds: entry.restSeconds)
        }
        session.currentEntryID = session.workout.orderedExercises.first?.persistentModelID
        session.save()
        return session
    }

    // MARK: Reading

    var entries: [WorkoutExercise] { workout.orderedExercises.filter { !$0.isGone } }

    var currentEntry: WorkoutExercise? {
        entries.first { $0.persistentModelID == currentEntryID } ?? entries.first
    }

    /// First set not yet completed: the "active" row.
    func activeSet(in entry: WorkoutExercise) -> SetLog? {
        entry.orderedSets.first { !$0.isCompleted }
    }

    /// The same exercise's sets from the most recent finished workout ("Previous" column).
    func previousSets(for exercise: Exercise?) -> [SetLog] {
        guard let exercise else { return [] }
        let last = exercise.workoutEntries
            .filter { entry in
                guard let w = entry.workout, !w.isGone else { return false }
                return w.end != nil && w.persistentModelID != workout.persistentModelID
            }
            .max { ($0.workout?.start ?? .distantPast) < ($1.workout?.start ?? .distantPast) }
        return last?.completedSets ?? []
    }

    func previousSet(for entry: WorkoutExercise, index: Int) -> SetLog? {
        let previous = previousSets(for: entry.exercise)
        return previous.first { $0.index == index }
    }

    var hasCompletedSets: Bool { entries.contains { !$0.completedSets.isEmpty } }

    // MARK: Editing

    func add(_ exercises: [Exercise]) {
        let firstNew = exercises.first
        for exercise in exercises {
            let previousCount = previousSets(for: exercise).count
            append(exercise, setCount: previousCount > 0 ? previousCount : Self.defaultSetCount,
                   repRange: nil, restSeconds: nil)
        }
        if currentEntry == nil || currentEntry.map(isFinished) == true, let firstNew,
           let entry = entries.last(where: { $0.exercise?.persistentModelID == firstNew.persistentModelID }) {
            currentEntryID = entry.persistentModelID
        }
        save()
    }

    func addSet(to entry: WorkoutExercise) {
        let index = (entry.sets.map(\.index).max() ?? 0) + 1
        let above = entry.orderedSets.last
        let set = SetLog(index: index, weightKg: previousSet(for: entry, index: index)?.weightKg ?? above?.weightKg)
        entry.sets.append(set)
        save()
    }

    func removeSet(_ set: SetLog, from entry: WorkoutExercise) {
        entry.sets.removeAll { $0.persistentModelID == set.persistentModelID }
        context.delete(set)
        renumber(entry)
        save()
    }

    func remove(_ entry: WorkoutExercise) {
        let wasCurrent = entry.persistentModelID == currentEntryID
        workout.exercises.removeAll { $0.persistentModelID == entry.persistentModelID }
        context.delete(entry)
        for (i, e) in workout.orderedExercises.enumerated() { e.order = i }
        if wasCurrent { currentEntryID = entries.first { !isFinished($0) }?.persistentModelID ?? entries.first?.persistentModelID }
        save()
    }

    /// Swap with the neighbour above (-1) or below (+1).
    func move(_ entry: WorkoutExercise, by offset: Int) {
        var ordered = entries
        guard let i = ordered.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) else { return }
        let j = i + offset
        guard ordered.indices.contains(j) else { return }
        ordered.swapAt(i, j)
        for (k, e) in ordered.enumerated() { e.order = k }
        save()
    }

    func select(_ entry: WorkoutExercise) {
        currentEntryID = entry.persistentModelID
    }

    /// Ticks a set off (or back on). Empty fields are filled from the set above, then from last
    /// session's same set. Returns false if the set still lacks a required value.
    @discardableResult
    func toggleComplete(_ set: SetLog, in entry: WorkoutExercise, at date: Date = .now) -> Bool {
        if set.isCompleted {
            set.isCompleted = false
            set.completedAt = nil
            save()
            return true
        }
        let tracking = entry.exercise?.trackingType ?? .weightReps
        let above = entry.orderedSets.last { $0.index < set.index && $0.isCompleted }
        let previous = previousSet(for: entry, index: set.index)

        switch tracking {
        case .weightReps:
            if set.weightKg == nil { set.weightKg = above?.weightKg ?? previous?.weightKg }
            if set.reps == nil { set.reps = above?.reps ?? previous?.reps }
            guard set.weightKg != nil, (set.reps ?? 0) > 0 else { return false }
        case .repsOnly:
            if set.reps == nil { set.reps = above?.reps ?? previous?.reps }
            guard (set.reps ?? 0) > 0 else { return false }
        case .time:
            if set.durationSeconds == nil { set.durationSeconds = above?.durationSeconds ?? previous?.durationSeconds }
            guard (set.durationSeconds ?? 0) > 0 else { return false }
        }

        set.isCompleted = true
        set.completedAt = date
        set.source = .manual
        if isFinished(entry), let next = entries.first(where: { !isFinished($0) }) {
            currentEntryID = next.persistentModelID
        }
        save()
        return true
    }

    // MARK: Rest

    /// The routine's rest for this exercise, then the exercise's own, then the profile default.
    func restSeconds(for entry: WorkoutExercise, defaultRest: Int) -> Int {
        entry.restSeconds ?? entry.exercise?.defaultRestSeconds ?? defaultRest
    }

    /// The set the user will do next: the current exercise's first open set, else the next exercise's.
    func nextUp() -> (entry: WorkoutExercise, set: SetLog)? {
        if let entry = currentEntry, let set = activeSet(in: entry) { return (entry, set) }
        for entry in entries {
            if let set = activeSet(in: entry) { return (entry, set) }
        }
        return nil
    }

    /// What the rest screen, notification and Live Activity show after completing `set`.
    /// nil when nothing is left to do (no rest after the last set).
    func restInfo(after set: SetLog, in entry: WorkoutExercise, unit: WeightUnit) -> RestInfo? {
        guard let (nextEntry, nextSet) = nextUp() else { return nil }
        let previous = previousSet(for: nextEntry, index: nextSet.index)
        let reps = nextSet.reps ?? previous?.reps
        let lastTime = previous.flatMap { p -> String? in
            p.reps == nil ? nil : WeightFormatter.setString(kg: p.weightKg, reps: p.reps, in: unit)
        }
        return RestInfo(
            workoutName: workout.displayName,
            workoutStart: workout.start,
            exerciseName: entry.exerciseName,
            afterSet: set.index,
            nextExercise: nextEntry.exerciseName,
            nextSet: nextSet.index,
            nextWeight: nextSet.weightKg.map { WeightFormatter.number(kg: $0, in: unit) },
            unitSymbol: unit.symbol,
            nextReps: reps,
            lastTime: lastTime
        )
    }

    // MARK: Ending

    /// Drops unfinished sets and empty exercises, stamps the end time and rebuilds records.
    /// Returns nil (and deletes the workout) when nothing was logged.
    func finish(at date: Date = .now) -> Workout? {
        for entry in entries {
            for set in entry.sets where !set.isCompleted {
                entry.sets.removeAll { $0.persistentModelID == set.persistentModelID }
                context.delete(set)
            }
            if entry.sets.isEmpty {
                workout.exercises.removeAll { $0.persistentModelID == entry.persistentModelID }
                context.delete(entry)
            } else {
                renumber(entry)
            }
        }
        guard !workout.exercises.isEmpty else {
            context.delete(workout)
            save()
            return nil
        }
        for (i, e) in workout.orderedExercises.enumerated() { e.order = i }
        workout.end = date
        save()
        for exercise in Set(workout.exercises.compactMap(\.exercise)) {
            RecordBook.rebuild(for: exercise, in: context)
        }
        save()
        return workout
    }

    func cancel() {
        context.delete(workout)
        save()
    }

    // MARK: Helpers

    func isFinished(_ entry: WorkoutExercise) -> Bool {
        !entry.sets.isEmpty && entry.sets.allSatisfy(\.isCompleted)
    }

    private func append(_ exercise: Exercise, setCount: Int, repRange: ClosedRange<Int>?, restSeconds: Int?) {
        let entry = WorkoutExercise(order: workout.exercises.count, exercise: exercise,
                                    repRange: repRange, restSeconds: restSeconds)
        workout.exercises.append(entry)
        let previous = previousSets(for: exercise)
        entry.sets = (1...max(setCount, 1)).map { index in
            SetLog(index: index, weightKg: previous.first { $0.index == index }?.weightKg ?? previous.last?.weightKg)
        }
    }

    private func renumber(_ entry: WorkoutExercise) {
        for (i, set) in entry.orderedSets.enumerated() { set.index = i + 1 }
    }

    /// Field edits in the set table call this so typed values are on disk right away.
    func save() {
        try? context.save()
    }
}

/// Deletes a finished workout and repairs the records it contributed to (History → Delete).
enum WorkoutHistory {
    @MainActor
    static func delete(_ workout: Workout, in context: ModelContext) {
        let exercises = Set(workout.exercises.compactMap(\.exercise))
        for record in workout.records { context.delete(record) }
        context.delete(workout)
        try? context.save()
        for exercise in exercises where !exercise.isGone {
            RecordBook.rebuild(for: exercise, in: context)
        }
        try? context.save()
    }

    /// "Last done yesterday", "Last done 6 days ago", "Not done yet".
    static func lastDoneText(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let date else { return "Not done yet" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "Last done today"
        case 1: return "Last done yesterday"
        case 2...6: return "Last done \(days) days ago"
        default: return "Last done " + date.formatted(.dateTime.day().month(.abbreviated))
        }
    }
}
