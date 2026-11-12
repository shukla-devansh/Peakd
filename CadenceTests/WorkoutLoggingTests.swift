import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
@Suite("Workout logging")
struct WorkoutLoggingTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let bench: Exercise
    let row: Exercise

    init() throws {
        container = try CadenceStore.makeContainer(inMemory: true)
        bench = Exercise(name: "Bench press", primaryMuscle: .chest, equipment: .barbell)
        row = Exercise(name: "Barbell row", primaryMuscle: .back, equipment: .barbell)
        container.mainContext.insert(bench)
        container.mainContext.insert(row)
    }

    /// Logs and finishes a workout with the given (weight, reps) sets for bench.
    @discardableResult
    func logBench(_ sets: [(Double, Int)], daysAgo: Int) -> Workout {
        let start = Date.now.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        let session = WorkoutSession.start(routine: nil, in: context, at: start)
        session.add([bench])
        let entry = session.entries[0]
        while entry.sets.count < sets.count { session.addSet(to: entry) }
        for (set, values) in zip(entry.orderedSets, sets) {
            set.weightKg = values.0
            set.reps = values.1
            session.toggleComplete(set, in: entry, at: start)
        }
        return session.finish(at: start.addingTimeInterval(3600))!
    }

    // MARK: Metrics

    @Test("Epley 1RM and volume")
    func metrics() {
        #expect(WorkoutMetrics.estimatedOneRepMax(weightKg: 45, reps: 8) == 45 * (1 + 8.0 / 30))
        #expect(abs(WorkoutMetrics.estimatedOneRepMax(weightKg: 100, reps: 10) - 133.333) < 0.001)
        let done = SetLog(index: 1, weightKg: 40, reps: 10, isCompleted: true)
        let pending = SetLog(index: 2, weightKg: 40, reps: 10)
        #expect(WorkoutMetrics.volume(of: done) == 400)
        #expect(WorkoutMetrics.volume(of: pending) == 0)
        #expect(WorkoutMetrics.percentChange(from: 100, to: 106) == 6)
        #expect(WorkoutMetrics.percentChange(from: 0, to: 50) == nil)
    }

    // MARK: Session

    @Test("Starting a routine creates its sets with last session's weights")
    func startFromRoutine() {
        logBench([(40, 10), (40, 10), (40, 9)], daysAgo: 3)
        let routine = Routine(name: "Push day")
        context.insert(routine)
        routine.items = [RoutineItem(order: 0, exercise: bench, targetSets: 4, repRangeLow: 8, repRangeHigh: 10)]

        let session = WorkoutSession.start(routine: routine, in: context)
        let entry = session.entries[0]
        #expect(session.workout.routineName == "Push day")
        #expect(entry.sets.count == 4)
        #expect(entry.orderedSets.map(\.weightKg) == [40, 40, 40, 40])
        #expect(entry.orderedSets.allSatisfy { $0.reps == nil && !$0.isCompleted })
        #expect(entry.repRange == 8...10)
        #expect(session.previousSet(for: entry, index: 3)?.reps == 9)
    }

    @Test("Completing an empty set fills it from the set above, then last session")
    func autofill() {
        logBench([(40, 10), (40, 8)], daysAgo: 2)
        let session = WorkoutSession.start(routine: nil, in: context)
        session.add([bench])
        let entry = session.entries[0]
        let first = entry.orderedSets[0], second = entry.orderedSets[1]

        #expect(session.toggleComplete(first, in: entry))      // from last session
        #expect(first.weightKg == 40 && first.reps == 10)
        first.reps = 12
        #expect(session.toggleComplete(second, in: entry))     // from the set above
        #expect(second.reps == 12)
    }

    @Test("A set with nothing to fill from can't be completed")
    func incompleteSetRejected() {
        let session = WorkoutSession.start(routine: nil, in: context)
        session.add([bench])
        let entry = session.entries[0]
        #expect(!session.toggleComplete(entry.orderedSets[0], in: entry))
        #expect(!entry.orderedSets[0].isCompleted)
    }

    @Test("Finishing an exercise moves focus to the next one")
    func advancesCurrent() {
        let session = WorkoutSession.start(routine: nil, in: context)
        session.add([bench, row])
        let entry = session.entries[0]
        for set in entry.orderedSets { set.weightKg = 40; set.reps = 10; session.toggleComplete(set, in: entry) }
        #expect(session.currentEntry?.exerciseName == "Barbell row")
    }

    @Test("Finish drops unfinished sets and empty exercises")
    func finishCleansUp() {
        let session = WorkoutSession.start(routine: nil, in: context)
        session.add([bench, row])
        let entry = session.entries[0]
        let set = entry.orderedSets[1]
        set.weightKg = 50; set.reps = 5
        session.toggleComplete(set, in: entry)

        let workout = session.finish()
        #expect(workout?.exercises.count == 1)
        #expect(workout?.exercises.first?.sets.map(\.index) == [1])
        #expect(workout?.end != nil)
    }

    @Test("Finishing with nothing logged discards the workout")
    func finishEmpty() throws {
        let session = WorkoutSession.start(routine: nil, in: context)
        session.add([bench])
        #expect(session.finish() == nil)
        #expect(try context.fetchCount(FetchDescriptor<Workout>()) == 0)
    }

    @Test("Moving and removing exercises keeps order contiguous")
    func moveAndRemove() {
        let session = WorkoutSession.start(routine: nil, in: context)
        session.add([bench, row])
        session.move(session.entries[1], by: -1)
        #expect(session.entries.map(\.exerciseName) == ["Barbell row", "Bench press"])
        session.move(session.entries[0], by: -1)   // already first: no-op
        #expect(session.entries.map(\.exerciseName) == ["Barbell row", "Bench press"])
        session.remove(session.entries[0])
        #expect(session.entries.map(\.order) == [0])
    }

    // MARK: Records

    @Test("The first session sets a baseline, not a record")
    func firstSessionNoRecord() {
        let workout = logBench([(40, 10)], daysAgo: 1)
        #expect(workout.records.isEmpty)
    }

    @Test("Beating the earlier best creates heaviest and est. 1RM records")
    func recordsDetected() {
        logBench([(40, 10)], daysAgo: 7)
        let workout = logBench([(45, 8)], daysAgo: 1)
        let kinds = Set(workout.records.map(\.kind))
        #expect(kinds == [.heaviest, .est1RM, .bestSet])
        let est = workout.records.first { $0.kind == .est1RM }!
        #expect(abs(est.value - 57) < 0.001)                   // 45 × (1 + 8/30) = 57.0 (Summary board)
        let highlights = RecordBook.highlights(for: workout)
        #expect(highlights.count == 1 && highlights[0].kind == .est1RM)
    }

    @Test("Heavier but lower estimate is only a heaviest record")
    func heaviestOnly() {
        logBench([(40, 12)], daysAgo: 7)                         // est 56
        let workout = logBench([(42.5, 5)], daysAgo: 1)          // est 49.6
        #expect(workout.records.map(\.kind) == [.heaviest])
        #expect(RecordBook.highlights(for: workout).first?.kind == .heaviest)
    }

    @Test("Deleting a workout rebuilds the records of the ones after it")
    func deleteRebuilds() {
        logBench([(40, 10)], daysAgo: 10)
        let middle = logBench([(50, 5)], daysAgo: 5)
        let last = logBench([(45, 5)], daysAgo: 1)
        #expect(last.records.isEmpty)                            // 45 < 50

        WorkoutHistory.delete(middle, in: context)
        #expect(last.records.contains { $0.kind == .heaviest }) // 45 > 40 now
    }

    @Test("Last-done wording")
    func lastDone() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cal = Calendar(identifier: .gregorian)
        #expect(WorkoutHistory.lastDoneText(nil, now: now, calendar: cal) == "Not done yet")
        #expect(WorkoutHistory.lastDoneText(now, now: now, calendar: cal) == "Last done today")
        #expect(WorkoutHistory.lastDoneText(now.addingTimeInterval(-86_400), now: now, calendar: cal) == "Last done yesterday")
        #expect(WorkoutHistory.lastDoneText(now.addingTimeInterval(-6 * 86_400), now: now, calendar: cal) == "Last done 6 days ago")
    }

    @Test("Volume and duration strings")
    func formatting() {
        let en = Locale(identifier: "en_US")
        #expect(WeightFormatter.volume(kg: 12_480, in: .kg, locale: en) == "12,480 kg")
        #expect(WeightFormatter.volume(kg: 178_400, in: .kg, compact: true, locale: en) == "178.4k kg")
        #expect(WeightFormatter.fieldString(kg: 1250, in: .kg, locale: en) == "1250")
        #expect(DurationFormat.clock(58 * 60 + 12) == "58:12")
        #expect(DurationFormat.clock(3725) == "1:02:05")
        #expect(DurationFormat.minutes(58 * 60 + 12) == "58 min")
    }
}
