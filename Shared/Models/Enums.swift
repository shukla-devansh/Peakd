//  Enums.swift
//  Domain vocabulary. SwiftData stores the raw values; models expose these typed accessors.
//  User-facing titles are copied verbatim from the boards.

import Foundation

enum TrainingGoal: String, Codable, CaseIterable, Identifiable, Sendable {
    case strength, muscle, fitness, lean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: "Get stronger"
        case .muscle:   "Build muscle"
        case .fitness:  "General fitness"
        case .lean:     "Get leaner"
        }
    }

    var subtitle: String {
        switch self {
        case .strength: "Heavier weights, lower reps"
        case .muscle:   "Moderate weights, 8–12 reps"
        case .fitness:  "Balanced full-body training"
        case .lean:     "Keep strength while you cut"
        }
    }
}

enum Experience: String, Codable, CaseIterable, Identifiable, Sendable {
    case beginner, intermediate, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner:     "Beginner"
        case .intermediate: "Intermediate"
        case .advanced:     "Advanced"
        }
    }
}

enum WeightUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case kg, lb

    var id: String { rawValue }
    var symbol: String { rawValue }
    /// For VoiceOver: "45 kilograms".
    var spokenName: String { self == .kg ? "kilograms" : "pounds" }
}

/// Equipment an exercise needs. Onboarding (Equipment board) uses the plural `setupTitle`;
/// exercise rows use the singular `title` ("Chest · Dumbbell").
enum Equipment: String, Codable, CaseIterable, Identifiable, Sendable {
    case barbell, dumbbell, cable, machine, bench, pullUpBar, kettlebell, band, bodyweight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .barbell:    "Barbell"
        case .dumbbell:   "Dumbbell"
        case .cable:      "Cable"
        case .machine:    "Machine"
        case .bench:      "Bench"
        case .pullUpBar:  "Pull-up bar"
        case .kettlebell: "Kettlebell"
        case .band:       "Band"
        case .bodyweight: "Bodyweight"
        }
    }

    var setupTitle: String {
        switch self {
        case .barbell:    "Barbell"
        case .dumbbell:   "Dumbbells"
        case .cable:      "Cable machine"
        case .machine:    "Weight machines"
        case .bench:      "Bench"
        case .pullUpBar:  "Pull-up bar"
        case .kettlebell: "Kettlebells"
        case .band:       "Resistance bands"
        case .bodyweight: "Bodyweight"
        }
    }

    /// Options shown on the Equipment board, in board order. Bodyweight is always available.
    static let selectable: [Equipment] = [.barbell, .dumbbell, .cable, .machine, .bench, .pullUpBar, .kettlebell, .band]

    /// Pre-checked on the Equipment board.
    static let defaultSelection: [Equipment] = [.barbell, .dumbbell, .cable, .machine, .bench, .pullUpBar]

    /// Progressive-overload increment class: barbell and machines step by 2.5 kg,
    /// dumbbells by 1 kg per dumbbell.
    var usesDumbbellIncrement: Bool { self == .dumbbell || self == .kettlebell }
}

enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest, back, legs, shoulders, arms, core, fullBody

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chest:     "Chest"
        case .back:      "Back"
        case .legs:      "Legs"
        case .shoulders: "Shoulders"
        case .arms:      "Arms"
        case .core:      "Core"
        case .fullBody:  "Full body"
        }
    }

    /// Exercises board filter chips ("All" is added by the view).
    static let filterable: [MuscleGroup] = [.chest, .back, .legs, .shoulders, .arms, .core]
}

enum TrackingType: String, Codable, CaseIterable, Identifiable, Sendable {
    case weightReps, repsOnly, time

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weightReps: "Weight × reps"
        case .repsOnly:   "Reps only"
        case .time:       "Time"
        }
    }
}

enum SetSource: String, Codable, CaseIterable, Sendable {
    case manual, voice, watch
}

enum RecordKind: String, Codable, CaseIterable, Sendable {
    case heaviest, bestSet, est1RM

    var title: String {
        switch self {
        case .heaviest: "heaviest"
        case .bestSet:  "best set"
        case .est1RM:   "est. 1RM"
        }
    }
}

/// Fatigue bands from the design language board. The score itself comes from FatigueEngine.
enum FatigueBand: String, Codable, CaseIterable, Sendable {
    case low, moderate, high

    init(score: Int) {
        switch score {
        case ..<40: self = .low
        case 40..<70: self = .moderate
        default: self = .high
        }
    }

    var title: String {
        switch self {
        case .low:      "Low"
        case .moderate: "Moderate"
        case .high:     "High"
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .low:      0...39
        case .moderate: 40...69
        case .high:     70...100
        }
    }
}
