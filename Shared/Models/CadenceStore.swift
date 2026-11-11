//  CadenceStore.swift
//  Builds the SwiftData container. On iOS it lives in the App Group so the widget extension
//  can read it; falls back to the app's own container if the group isn't provisioned.

import Foundation
import SwiftData

extension PersistentModel {
    /// Deleted, or detached from its context once the delete was saved. `isDeleted` alone turns
    /// false after a save, yet reading the model's properties then traps. Check this before
    /// reading a model a view may still hold after "Delete all data".
    var isGone: Bool { isDeleted || modelContext == nil }
}

enum CadenceStore {
    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            Exercise.self,
            Routine.self,
            RoutineItem.self,
            Workout.self,
            WorkoutExercise.self,
            SetLog.self,
            PersonalRecord.self,
        ]
    }

    static var schema: Schema { Schema(models) }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = schema
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let group = AppGroup.identifier, AppGroup.containerURL != nil {
            configuration = ModelConfiguration("Cadence", schema: schema, groupContainer: .identifier(group))
        } else {
            configuration = ModelConfiguration("Cadence", schema: schema, groupContainer: .none)
        }
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
