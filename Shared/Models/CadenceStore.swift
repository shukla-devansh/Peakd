//  CadenceStore.swift
//  Builds the SwiftData container. On iOS it lives in the App Group so the widget extension
//  can read it; falls back to the app's own container if the group isn't provisioned.

import Foundation
import SwiftData

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
