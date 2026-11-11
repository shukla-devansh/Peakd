import Foundation
import SwiftData
import Testing
@testable import Cadence

@Suite("Exercise library seed")
struct ExerciseLibraryTests {
    @Test("Bundled JSON decodes with ~120 exercises")
    func decodes() throws {
        let seeds = try ExerciseLibrary.loadSeeds()
        #expect(seeds.count >= 110)
        #expect(Set(MuscleGroup.allCases).isSubset(of: Set(seeds.map(\.primaryMuscle))))
    }

    @Test("Names and voice aliases are unique and lower-case aliases")
    func uniqueNames() throws {
        let seeds = try ExerciseLibrary.loadSeeds()
        let spoken = seeds.map { $0.name.lowercased() } + seeds.flatMap(\.aliases)
        #expect(Set(spoken).count == spoken.count)
        #expect(seeds.flatMap(\.aliases).allSatisfy { $0 == $0.lowercased() })
    }

    @Test("Exercises named on the boards are in the library")
    func boardExercises() throws {
        let names = Set(try ExerciseLibrary.loadSeeds().map(\.name))
        for name in ["Bench press", "Incline dumbbell press", "Overhead press", "Barbell row", "Lat pulldown",
                     "Seated cable row", "Back squat", "Romanian deadlift", "Leg press", "Pull-up",
                     "Lateral raise", "Arnold press", "Cable crossover"] {
            #expect(names.contains(name), "\(name) missing")
        }
    }

    @MainActor
    @Test("Seeding is idempotent and leaves custom exercises alone")
    func seedIdempotent() throws {
        let container = try CadenceStore.makeContainer(inMemory: true)
        let context = container.mainContext
        context.insert(Exercise(name: "My cable thing", primaryMuscle: .arms, equipment: .cable, isCustom: true))

        let first = try ExerciseLibrary.seedIfNeeded(in: context)
        let second = try ExerciseLibrary.seedIfNeeded(in: context)

        #expect(first == (try ExerciseLibrary.loadSeeds().count))
        #expect(second == 0)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == first + 1)
    }
}
