//  StarterPlan.swift
//  The "Full body A" starter routine on HomeEmpty: one exercise per movement pattern,
//  the first candidate the user has equipment for. Deterministic; the Planner takes over in phase 5.

import Foundation
import SwiftData

enum StarterPlan {
    static let routineName = "Full body A"
    static let setsPerExercise = 3

    struct Candidate: Sendable {
        let name: String
        let needs: Set<Equipment>
    }

    /// Squat, horizontal push, pull, hinge, vertical push. Each list ends with a no-equipment fallback.
    static let slots: [[Candidate]] = [
        [
            Candidate(name: "Back squat", needs: [.barbell]),
            Candidate(name: "Leg press", needs: [.machine]),
            Candidate(name: "Goblet squat", needs: [.dumbbell]),
            Candidate(name: "Kettlebell goblet squat", needs: [.kettlebell]),
            Candidate(name: "Banded squat", needs: [.band]),
            Candidate(name: "Bodyweight squat", needs: []),
        ],
        [
            Candidate(name: "Bench press", needs: [.barbell, .bench]),
            Candidate(name: "Dumbbell bench press", needs: [.dumbbell, .bench]),
            Candidate(name: "Machine chest press", needs: [.machine]),
            Candidate(name: "Push-up", needs: []),
        ],
        [
            Candidate(name: "Barbell row", needs: [.barbell]),
            Candidate(name: "Lat pulldown", needs: [.cable]),
            Candidate(name: "Machine row", needs: [.machine]),
            Candidate(name: "One-arm dumbbell row", needs: [.dumbbell]),
            Candidate(name: "Pull-up", needs: [.pullUpBar]),
            Candidate(name: "Kettlebell row", needs: [.kettlebell]),
            Candidate(name: "Resistance band row", needs: [.band]),
            Candidate(name: "Inverted row", needs: []),
        ],
        [
            Candidate(name: "Romanian deadlift", needs: [.barbell]),
            Candidate(name: "Dumbbell Romanian deadlift", needs: [.dumbbell]),
            Candidate(name: "Kettlebell swing", needs: [.kettlebell]),
            Candidate(name: "Cable pull-through", needs: [.cable]),
            Candidate(name: "Glute bridge", needs: []),
        ],
        [
            Candidate(name: "Overhead press", needs: [.barbell]),
            Candidate(name: "Seated dumbbell shoulder press", needs: [.dumbbell]),
            Candidate(name: "Machine shoulder press", needs: [.machine]),
            Candidate(name: "Kettlebell press", needs: [.kettlebell]),
            Candidate(name: "Pike push-up", needs: []),
        ],
    ]

    /// Exercise names for the user's equipment, one per slot.
    static func exerciseNames(available: Set<Equipment>) -> [String] {
        let available = available.union([.bodyweight])
        return slots.compactMap { slot in
            slot.first { $0.needs.isSubset(of: available) }?.name
        }
    }

    static func repRange(for goal: TrainingGoal) -> ClosedRange<Int> {
        switch goal {
        case .strength: 5...8
        case .muscle:   8...12
        case .fitness:  10...12
        case .lean:     8...12
        }
    }

    /// Inserts the starter routine. Exercises come from the seeded library.
    @MainActor
    @discardableResult
    static func install(for profile: UserProfile, in context: ModelContext) throws -> Routine {
        let names = exerciseNames(available: profile.availableEquipment)
        let library = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { !$0.isCustom }))
        let byName = Dictionary(library.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let range = repRange(for: profile.goal)

        let routine = Routine(name: routineName)
        context.insert(routine)
        routine.items = names.compactMap { byName[$0] }.enumerated().map { index, exercise in
            RoutineItem(
                order: index,
                exercise: exercise,
                targetSets: setsPerExercise,
                repRangeLow: range.lowerBound,
                repRangeHigh: range.upperBound
            )
        }
        return routine
    }

    /// "about 45 min": each set takes ~40 s plus its rest, plus 10 min to warm up, rounded to 5 min.
    static func estimatedMinutes(sets: [(count: Int, restSeconds: Int)]) -> Int {
        let seconds = sets.reduce(600) { $0 + $1.count * ($1.restSeconds + 40) }
        return max(5, Int((Double(seconds) / 60 / 5).rounded()) * 5)
    }

    @MainActor
    static func estimatedMinutes(for routine: Routine, defaultRest: Int) -> Int {
        estimatedMinutes(sets: routine.orderedItems.map {
            ($0.targetSets, $0.restSeconds ?? $0.exercise?.defaultRestSeconds ?? defaultRest)
        })
    }

    /// HomeEmpty card text: "Built from your goal, 4 days a week and gym equipment. …"
    static func explanation(daysPerWeek: Int, equipment: Set<Equipment>) -> String {
        let gear: String
        if !equipment.isDisjoint(with: [.barbell, .machine, .cable]) {
            gear = "gym equipment"
        } else if equipment.subtracting([.bodyweight]).isEmpty {
            gear = "no equipment"
        } else {
            gear = "your equipment"
        }
        return "Built from your goal, \(daysPerWeek) days a week and \(gear). "
            + "Pick weights that leave 2 reps in reserve; suggestions get personal after a few sessions."
    }
}
