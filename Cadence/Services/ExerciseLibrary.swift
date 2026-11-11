//  ExerciseLibrary.swift
//  Loads Resources/ExerciseLibrary.json and seeds built-in exercises into SwiftData.
//  Idempotent: inserts only seeds whose name isn't stored yet, so adding entries to the JSON later just works.

import Foundation
import SwiftData

struct ExerciseSeed: Codable, Sendable, Equatable {
    let name: String
    let primaryMuscle: MuscleGroup
    let secondaryMuscles: [String]
    let equipment: Equipment
    let trackingType: TrackingType
    let aliases: [String]
}

enum ExerciseLibrary {
    enum LoadError: Error { case missingResource }

    static func loadSeeds(bundle: Bundle = .main) throws -> [ExerciseSeed] {
        guard let url = bundle.url(forResource: "ExerciseLibrary", withExtension: "json") else {
            throw LoadError.missingResource
        }
        return try JSONDecoder().decode([ExerciseSeed].self, from: Data(contentsOf: url))
    }

    /// Returns the number of exercises inserted.
    @MainActor
    @discardableResult
    static func seedIfNeeded(in context: ModelContext, bundle: Bundle = .main) throws -> Int {
        let builtIn = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { !$0.isCustom }))
        let existing = Set(builtIn.map { $0.name.lowercased() })
        let missing = try loadSeeds(bundle: bundle).filter { !existing.contains($0.name.lowercased()) }
        guard !missing.isEmpty else { return 0 }

        for seed in missing {
            context.insert(Exercise(
                name: seed.name,
                primaryMuscle: seed.primaryMuscle,
                secondaryMuscles: seed.secondaryMuscles,
                equipment: seed.equipment,
                trackingType: seed.trackingType,
                aliases: seed.aliases
            ))
        }
        try context.save()
        return missing.count
    }
}
