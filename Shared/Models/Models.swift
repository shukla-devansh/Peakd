//  Models.swift
//  SwiftData schema. Weights are always stored in kilograms; convert at display with WeightFormatter.
//  Enums are stored as raw strings (predicate-friendly) behind typed accessors.

import Foundation
import SwiftData

// MARK: - UserProfile

@Model
final class UserProfile {
    var goalRaw: String
    var experienceRaw: String
    var daysPerWeek: Int
    /// `Equipment` raw values.
    var equipment: [String]
    var unitRaw: String
    var defaultRestSeconds: Int
    var restAlerts: Bool
    var voiceLogging: Bool
    var aiSuggestions: Bool
    var createdAt: Date

    /// Defaults match the onboarding boards' pre-selected state.
    init(
        goal: TrainingGoal = .strength,
        experience: Experience = .intermediate,
        daysPerWeek: Int = 4,
        equipment: [Equipment] = Equipment.defaultSelection,
        unit: WeightUnit = .kg,
        defaultRestSeconds: Int = 90,
        restAlerts: Bool = true,
        voiceLogging: Bool = true,
        aiSuggestions: Bool = true,
        createdAt: Date = .now
    ) {
        self.goalRaw = goal.rawValue
        self.experienceRaw = experience.rawValue
        self.daysPerWeek = daysPerWeek
        self.equipment = equipment.map(\.rawValue)
        self.unitRaw = unit.rawValue
        self.defaultRestSeconds = defaultRestSeconds
        self.restAlerts = restAlerts
        self.voiceLogging = voiceLogging
        self.aiSuggestions = aiSuggestions
        self.createdAt = createdAt
    }

    var goal: TrainingGoal {
        get { TrainingGoal(rawValue: goalRaw) ?? .strength }
        set { goalRaw = newValue.rawValue }
    }

    var experience: Experience {
        get { Experience(rawValue: experienceRaw) ?? .intermediate }
        set { experienceRaw = newValue.rawValue }
    }

    var unit: WeightUnit {
        get { WeightUnit(rawValue: unitRaw) ?? .kg }
        set { unitRaw = newValue.rawValue }
    }

    /// Equipment picked on the Equipment board (bodyweight is implied, never stored).
    var equipmentSet: Set<Equipment> {
        get { Set(equipment.compactMap(Equipment.init(rawValue:))).subtracting([.bodyweight]) }
        set { equipment = Equipment.selectable.filter(newValue.contains).map(\.rawValue) }
    }

    /// Selected equipment plus bodyweight, which is always available.
    var availableEquipment: Set<Equipment> {
        Set(equipment.compactMap(Equipment.init(rawValue:))).union([.bodyweight])
    }

    /// Allowed range on the Equipment board: 30 s – 5 min in 15 s steps.
    static let restRange: ClosedRange<Int> = 30...300
    static let restStep = 15

    /// Days-per-week choices on the Onboarding board.
    static let daysOptions = [2, 3, 4, 5, 6]
}

// MARK: - Exercise

@Model
final class Exercise {
    var name: String
    var primaryMuscleRaw: String
    /// Free-form, lower case ("triceps", "front delts").
    var secondaryMuscles: [String]
    var equipmentRaw: String
    var trackingTypeRaw: String
    /// `nil` → use the profile's default rest.
    var defaultRestSeconds: Int?
    var isCustom: Bool
    /// Extra names the voice parser should match ("bench", "flat bench").
    var aliases: [String]
    var notes: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \RoutineItem.exercise)
    var routineItems: [RoutineItem] = []

    @Relationship(deleteRule: .nullify, inverse: \WorkoutExercise.exercise)
    var workoutEntries: [WorkoutExercise] = []

    @Relationship(deleteRule: .cascade, inverse: \PersonalRecord.exercise)
    var records: [PersonalRecord] = []

    init(
        name: String,
        primaryMuscle: MuscleGroup,
        secondaryMuscles: [String] = [],
        equipment: Equipment,
        trackingType: TrackingType = .weightReps,
        defaultRestSeconds: Int? = nil,
        isCustom: Bool = false,
        aliases: [String] = [],
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.name = name
        self.primaryMuscleRaw = primaryMuscle.rawValue
        self.secondaryMuscles = secondaryMuscles
        self.equipmentRaw = equipment.rawValue
        self.trackingTypeRaw = trackingType.rawValue
        self.defaultRestSeconds = defaultRestSeconds
        self.isCustom = isCustom
        self.aliases = aliases
        self.notes = notes
        self.createdAt = createdAt
    }

    var primaryMuscle: MuscleGroup {
        get { MuscleGroup(rawValue: primaryMuscleRaw) ?? .fullBody }
        set { primaryMuscleRaw = newValue.rawValue }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .bodyweight }
        set { equipmentRaw = newValue.rawValue }
    }

    var trackingType: TrackingType {
        get { TrackingType(rawValue: trackingTypeRaw) ?? .weightReps }
        set { trackingTypeRaw = newValue.rawValue }
    }

    /// "Chest · Barbell" (Exercises board row subtitle).
    var subtitle: String { "\(primaryMuscle.title) · \(equipment.title)" }
}

// MARK: - Routine

@Model
final class Routine {
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \RoutineItem.routine)
    var items: [RoutineItem] = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }

    var orderedItems: [RoutineItem] { items.sorted { $0.order < $1.order } }
}

@Model
final class RoutineItem {
    var order: Int
    var targetSets: Int
    var repRangeLow: Int
    var repRangeHigh: Int
    /// `nil` → the exercise's rest, then the profile default.
    var restSeconds: Int?
    var exercise: Exercise?
    var routine: Routine?

    init(
        order: Int,
        exercise: Exercise?,
        targetSets: Int = 3,
        repRangeLow: Int = 8,
        repRangeHigh: Int = 10,
        restSeconds: Int? = nil
    ) {
        self.order = order
        self.exercise = exercise
        self.targetSets = targetSets
        self.repRangeLow = repRangeLow
        self.repRangeHigh = repRangeHigh
        self.restSeconds = restSeconds
    }

    var repRange: ClosedRange<Int> { repRangeLow...max(repRangeLow, repRangeHigh) }
}

// MARK: - Workout

@Model
final class Workout {
    var start: Date
    /// `nil` while the workout is in progress.
    var end: Date?
    var routineName: String?
    var notes: String
    var avgHR: Double?
    var maxHR: Double?
    /// Kilocalories.
    var activeEnergy: Double?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    var exercises: [WorkoutExercise] = []

    @Relationship(deleteRule: .nullify, inverse: \PersonalRecord.workout)
    var records: [PersonalRecord] = []

    init(start: Date = .now, routineName: String? = nil, notes: String = "") {
        self.start = start
        self.routineName = routineName
        self.notes = notes
    }

    var isInProgress: Bool { end == nil }
    var orderedExercises: [WorkoutExercise] { exercises.sorted { $0.order < $1.order } }

    /// "Workout" when started empty.
    var displayName: String { routineName ?? "Workout" }

    func duration(at now: Date = .now) -> TimeInterval {
        (end ?? now).timeIntervalSince(start)
    }
}

@Model
final class WorkoutExercise {
    var order: Int
    /// Snapshot so history survives deleting a custom exercise.
    var exerciseName: String
    var repRangeLow: Int?
    var repRangeHigh: Int?
    var restSeconds: Int?
    var exercise: Exercise?
    var workout: Workout?

    @Relationship(deleteRule: .cascade, inverse: \SetLog.workoutExercise)
    var sets: [SetLog] = []

    init(order: Int, exercise: Exercise, repRange: ClosedRange<Int>? = nil, restSeconds: Int? = nil) {
        self.order = order
        self.exercise = exercise
        self.exerciseName = exercise.name
        self.repRangeLow = repRange?.lowerBound
        self.repRangeHigh = repRange?.upperBound
        self.restSeconds = restSeconds
    }

    var orderedSets: [SetLog] { sets.sorted { $0.index < $1.index } }
    var completedSets: [SetLog] { orderedSets.filter(\.isCompleted) }

    var repRange: ClosedRange<Int>? {
        guard let low = repRangeLow, let high = repRangeHigh else { return nil }
        return low...max(low, high)
    }
}

@Model
final class SetLog {
    /// 1-based set number within the exercise.
    var index: Int
    var weightKg: Double?
    var reps: Int?
    /// For `TrackingType.time` exercises.
    var durationSeconds: Int?
    var isCompleted: Bool
    var completedAt: Date?
    var sourceRaw: String
    var rpe: Double?
    var workoutExercise: WorkoutExercise?

    init(
        index: Int,
        weightKg: Double? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        source: SetSource = .manual,
        rpe: Double? = nil
    ) {
        self.index = index
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.sourceRaw = source.rawValue
        self.rpe = rpe
    }

    var source: SetSource {
        get { SetSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}

// MARK: - PersonalRecord

@Model
final class PersonalRecord {
    var kindRaw: String
    /// Kilograms for every kind (heaviest weight, best-set weight, est. 1RM).
    var value: Double
    /// Reps of the set that set the record ("45 × 8").
    var reps: Int?
    var date: Date
    var exercise: Exercise?
    var workout: Workout?

    init(kind: RecordKind, value: Double, reps: Int? = nil, date: Date = .now, exercise: Exercise?, workout: Workout? = nil) {
        self.kindRaw = kind.rawValue
        self.value = value
        self.reps = reps
        self.date = date
        self.exercise = exercise
        self.workout = workout
    }

    var kind: RecordKind {
        get { RecordKind(rawValue: kindRaw) ?? .heaviest }
        set { kindRaw = newValue.rawValue }
    }
}
