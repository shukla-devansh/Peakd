//  DataStore.swift
//  Profile's "Export my data" (CSV of every logged set) and "Delete all data".

import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

enum DataStore {
    // MARK: Export

    static let csvHeader = "date,workout,exercise,set,weight_kg,reps,duration_s,completed,source"

    /// One row per logged set, oldest first. Weights stay in kg so the file is unit-independent.
    static func csv(for workouts: [Workout]) -> String {
        let dateFormat = Date.ISO8601FormatStyle()
        var lines = [csvHeader]
        for workout in workouts.sorted(by: { $0.start < $1.start }) {
            for entry in workout.orderedExercises {
                for set in entry.orderedSets {
                    let date: Date = set.completedAt ?? workout.start
                    let weight: String = set.weightKg.map { String($0) } ?? ""
                    let reps: String = set.reps.map { String($0) } ?? ""
                    let duration: String = set.durationSeconds.map { String($0) } ?? ""
                    let fields: [String] = [
                        date.formatted(dateFormat),
                        workout.displayName,
                        entry.exerciseName,
                        String(set.index),
                        weight,
                        reps,
                        duration,
                        set.isCompleted ? "yes" : "no",
                        set.sourceRaw,
                    ]
                    lines.append(fields.map(escape).joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: Delete

    /// Removes everything the user created (workouts, routines, records, custom exercises, profile).
    /// The built-in exercise library stays. With no profile left, the app returns to onboarding.
    @MainActor
    static func deleteAll(in context: ModelContext) throws {
        try deleteEach(PersonalRecord.self, in: context)
        try deleteEach(Workout.self, in: context)          // cascades to exercises and sets
        try deleteEach(Routine.self, in: context)          // cascades to items
        try deleteEach(Exercise.self, where: #Predicate { $0.isCustom }, in: context)
        try deleteEach(UserProfile.self, in: context)
        try context.save()
    }

    @MainActor
    private static func deleteEach<T: PersistentModel>(_ type: T.Type, where predicate: Predicate<T>? = nil, in context: ModelContext) throws {
        for model in try context.fetch(FetchDescriptor<T>(predicate: predicate)) {
            context.delete(model)
        }
    }
}

/// CSV handed to the share sheet. Written to a temporary file only when the user shares it.
struct CSVExportFile: Transferable {
    let text: String
    var filename = "Cadence export.csv"

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = URL.temporaryDirectory.appending(path: file.filename)
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
