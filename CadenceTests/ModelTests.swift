import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
@Suite("SwiftData models")
struct ModelTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try CadenceStore.makeContainer(inMemory: true)
    }

    @Test("Profile defaults match the onboarding boards")
    func profileDefaults() throws {
        let profile = UserProfile()
        context.insert(profile)
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(stored.goal == .strength)
        #expect(stored.experience == .intermediate)
        #expect(stored.daysPerWeek == 4)
        #expect(stored.unit == .kg)
        #expect(stored.defaultRestSeconds == 90)
        #expect(stored.restAlerts && stored.voiceLogging && stored.aiSuggestions)
        #expect(stored.availableEquipment.contains(.bodyweight))
        #expect(!stored.availableEquipment.contains(.kettlebell))
    }

    @Test("Typed accessors write raw values")
    func typedAccessors() {
        let profile = UserProfile()
        profile.unit = .lb
        profile.goal = .lean
        #expect(profile.unitRaw == "lb")
        #expect(profile.goalRaw == "lean")

        let set = SetLog(index: 1)
        set.source = .voice
        #expect(set.sourceRaw == "voice")
    }

    @Test("Routine items come back in order")
    func routineOrder() throws {
        let bench = Exercise(name: "Bench press", primaryMuscle: .chest, equipment: .barbell)
        let press = Exercise(name: "Overhead press", primaryMuscle: .shoulders, equipment: .barbell)
        let routine = Routine(name: "Push day")
        context.insert(routine)
        routine.items = [RoutineItem(order: 1, exercise: press), RoutineItem(order: 0, exercise: bench)]
        try context.save()

        #expect(routine.orderedItems.map { $0.exercise?.name } == ["Bench press", "Overhead press"])
        #expect(routine.orderedItems[0].repRange == 8...10)
    }

    @Test("Deleting a workout cascades to exercises and sets but keeps the exercise")
    func workoutCascade() throws {
        let bench = Exercise(name: "Bench press", primaryMuscle: .chest, equipment: .barbell)
        context.insert(bench)
        let workout = Workout(routineName: "Push day")
        context.insert(workout)
        let entry = WorkoutExercise(order: 0, exercise: bench, repRange: 8...10)
        workout.exercises.append(entry)
        entry.sets = [
            SetLog(index: 2, weightKg: 42.5, reps: 9, isCompleted: true, completedAt: .now),
            SetLog(index: 1, weightKg: 42.5, reps: 10, isCompleted: true, completedAt: .now),
            SetLog(index: 3, weightKg: 42.5),
        ]
        try context.save()

        #expect(entry.orderedSets.map(\.index) == [1, 2, 3])
        #expect(entry.completedSets.count == 2)
        #expect(entry.exerciseName == "Bench press")
        #expect(workout.isInProgress)

        context.delete(workout)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<WorkoutExercise>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SetLog>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 1)
    }

    @Test("Fatigue bands use the board's boundaries", arguments: [
        (0, FatigueBand.low), (39, .low), (40, .moderate), (69, .moderate), (70, .high), (100, .high),
    ])
    func fatigueBands(score: Int, band: FatigueBand) {
        #expect(FatigueBand(score: score) == band)
    }
}
