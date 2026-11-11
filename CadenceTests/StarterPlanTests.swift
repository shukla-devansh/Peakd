import Foundation
import SwiftData
import Testing
@testable import Cadence

@Suite("Starter plan")
struct StarterPlanTests {
    @Test("Every candidate exists in the exercise library")
    func candidatesExist() throws {
        let names = Set(try ExerciseLibrary.loadSeeds().map(\.name))
        for candidate in StarterPlan.slots.flatMap({ $0 }) {
            #expect(names.contains(candidate.name), "\(candidate.name) missing from library")
        }
    }

    @Test("Full gym picks the barbell lifts")
    func fullGym() {
        let names = StarterPlan.exerciseNames(available: Set(Equipment.defaultSelection))
        #expect(names == ["Back squat", "Bench press", "Barbell row", "Romanian deadlift", "Overhead press"])
    }

    @Test("Dumbbells without a bench skip the bench presses")
    func dumbbellsNoBench() {
        let names = StarterPlan.exerciseNames(available: [.dumbbell])
        #expect(names == ["Goblet squat", "Push-up", "One-arm dumbbell row", "Dumbbell Romanian deadlift",
                          "Seated dumbbell shoulder press"])
    }

    @Test("No equipment still gives five exercises")
    func bodyweightOnly() {
        let names = StarterPlan.exerciseNames(available: [])
        #expect(names == ["Bodyweight squat", "Push-up", "Inverted row", "Glute bridge", "Pike push-up"])
    }

    @Test("Rep ranges follow the goal")
    func repRanges() {
        #expect(StarterPlan.repRange(for: .strength) == 5...8)
        #expect(StarterPlan.repRange(for: .muscle) == 8...12)
    }

    @Test("Five exercises × 3 sets at 90 s rest is about 45 min")
    func estimate() {
        let sets = Array(repeating: (count: 3, restSeconds: 90), count: 5)
        #expect(StarterPlan.estimatedMinutes(sets: sets) == 45)
        #expect(StarterPlan.estimatedMinutes(sets: []) == 10)
    }

    @Test("Explanation names the equipment kind")
    func explanation() {
        let gym = StarterPlan.explanation(daysPerWeek: 4, equipment: Set(Equipment.defaultSelection))
        #expect(gym.hasPrefix("Built from your goal, 4 days a week and gym equipment."))
        #expect(StarterPlan.explanation(daysPerWeek: 3, equipment: [.bodyweight]).contains("no equipment"))
        #expect(StarterPlan.explanation(daysPerWeek: 3, equipment: [.dumbbell]).contains("your equipment"))
    }

    @MainActor
    @Test("Install creates an ordered routine from the seeded library")
    func install() throws {
        let container = try CadenceStore.makeContainer(inMemory: true)
        let context = container.mainContext
        try ExerciseLibrary.seedIfNeeded(in: context)
        let profile = UserProfile(goal: .muscle)
        context.insert(profile)

        let routine = try StarterPlan.install(for: profile, in: context)
        try context.save()

        #expect(routine.name == "Full body A")
        #expect(routine.orderedItems.map { $0.exercise?.name } == ["Back squat", "Bench press", "Barbell row",
                                                                    "Romanian deadlift", "Overhead press"])
        #expect(routine.orderedItems.allSatisfy { $0.targetSets == 3 && $0.repRange == 8...12 })
        #expect(StarterPlan.estimatedMinutes(for: routine, defaultRest: 90) == 45)
    }
}

@MainActor
@Suite("Profile data")
struct ProfileDataTests {
    @Test("equipmentSet round-trips in board order and never stores bodyweight")
    func equipmentSet() {
        let profile = UserProfile()
        profile.equipmentSet = [.band, .barbell, .bodyweight]
        #expect(profile.equipment == ["barbell", "band"])
        #expect(profile.equipmentSet == [.barbell, .band])
        #expect(profile.availableEquipment == [.barbell, .band, .bodyweight])
    }

    @Test("CSV has one row per set and escapes commas")
    func csv() throws {
        let container = try CadenceStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let bench = Exercise(name: "Bench press, paused", primaryMuscle: .chest, equipment: .barbell)
        context.insert(bench)
        let workout = Workout(start: Date(timeIntervalSince1970: 0), routineName: "Push day")
        context.insert(workout)
        let entry = WorkoutExercise(order: 0, exercise: bench)
        workout.exercises.append(entry)
        entry.sets = [
            SetLog(index: 1, weightKg: 42.5, reps: 10, isCompleted: true, completedAt: Date(timeIntervalSince1970: 60), source: .voice),
            SetLog(index: 2),
        ]
        try context.save()

        let lines = DataStore.csv(for: [workout]).split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        #expect(lines[0] == DataStore.csvHeader)
        #expect(lines[1] == "1970-01-01T00:01:00Z,Push day,\"Bench press, paused\",1,42.5,10,,yes,voice")
        #expect(lines[2] == "1970-01-01T00:00:00Z,Push day,\"Bench press, paused\",2,,,,no,manual")
    }

    @Test("Delete all keeps the built-in library and removes everything else")
    func deleteAll() throws {
        let container = try CadenceStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let seeded = try ExerciseLibrary.seedIfNeeded(in: context)
        let profile = UserProfile()
        context.insert(profile)
        try StarterPlan.install(for: profile, in: context)
        context.insert(Exercise(name: "My move", primaryMuscle: .arms, equipment: .cable, isCustom: true))
        let workout = Workout()
        context.insert(workout)
        try context.save()

        try DataStore.deleteAll(in: context)

        #expect(try context.fetchCount(FetchDescriptor<UserProfile>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Routine>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<RoutineItem>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Workout>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == seeded)
    }
}
