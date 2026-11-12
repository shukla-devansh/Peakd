//  OverloadEngine.swift
//  Double progression (docs/PROJECT_GUIDE.md). Deterministic: the only place training numbers are produced.
//
//  - Every working set last session reached the top of the range → +2.5 kg (barbell, machine,
//    cable) or +1 kg per dumbbell/kettlebell; target reps drop to the bottom of the range.
//  - Two sessions in a row with a set below the bottom of the range → −5 % (−10 % when the
//    average shortfall is 2+ reps), rounded down to the equipment's step.
//  - Otherwise: same weight, aim for one more rep.
//  - Bodyweight, band and pull-up bar exercises progress by reps only.

import Foundation

struct LoggedSet: Sendable, Equatable {
    var weightKg: Double?
    var reps: Int
}

/// One past session of one exercise.
struct ExerciseSession: Sendable, Equatable {
    var date: Date
    /// Completed sets only.
    var sets: [LoggedSet]
}

struct OverloadSuggestion: Sendable, Equatable {
    enum Change: Sendable, Equatable {
        case increase(kg: Double)
        case same
        case decrease(percent: Int)
        /// Reps-only progression.
        case addRep
    }

    /// nil for reps-only exercises.
    var weightKg: Double?
    var repRange: ClosedRange<Int>
    var targetReps: Int
    var change: Change
    /// Row reason on NextSession: "Hit 10 reps on every set"
    var reason: String
    /// Tail of the Active chip: "you hit 10 reps last time"
    var chipReason: String
}

enum OverloadEngine {
    /// Kilograms added when every set hit the top of the range. nil = reps-only progression.
    static func increment(for equipment: Equipment) -> Double? {
        switch equipment {
        case .barbell, .machine, .cable, .bench: 2.5
        case .dumbbell, .kettlebell: 1
        case .bodyweight, .band, .pullUpBar: nil
        }
    }

    /// `history` is newest first.
    static func suggest(history: [ExerciseSession], repRange: ClosedRange<Int>, equipment: Equipment) -> OverloadSuggestion? {
        guard let last = history.first(where: { !$0.sets.isEmpty }) else { return nil }
        let sets = last.sets
        let low = repRange.lowerBound, high = repRange.upperBound
        let topWeight = sets.compactMap(\.weightKg).max()
        let step = increment(for: equipment)
        let weighted = step != nil && topWeight != nil

        let hitTop = sets.allSatisfy { $0.reps >= high }
        let missedLast = sets.contains { $0.reps < low }
        let sessionsWithSets = history.filter { !$0.sets.isEmpty }
        let missedTwice = missedLast && sessionsWithSets.count >= 2
            && sessionsWithSets[1].sets.contains { $0.reps < low }

        // Reps-only exercises
        guard weighted, let step, let topWeight else {
            let best = sets.map(\.reps).max() ?? low
            let target = best + 1
            return OverloadSuggestion(
                weightKg: nil, repRange: repRange, targetReps: target, change: .addRep,
                reason: hitTop ? "Hit \(high) reps on every set" : "Still building reps",
                chipReason: "you did \(best) last time"
            )
        }

        if hitTop {
            return OverloadSuggestion(
                weightKg: topWeight + step, repRange: repRange, targetReps: low, change: .increase(kg: step),
                reason: "Hit \(high) reps on every set",
                chipReason: "you hit \(high) reps last time"
            )
        }

        if missedTwice {
            let short = sets.filter { $0.reps < low }
            let shortfall = Double(short.reduce(0) { $0 + (low - $1.reps) }) / Double(max(short.count, 1))
            let percent = shortfall >= 2 ? 10 : 5
            let reduced = (topWeight * (1 - Double(percent) / 100) / step).rounded(.down) * step
            return OverloadSuggestion(
                weightKg: max(reduced, step), repRange: repRange, targetReps: low, change: .decrease(percent: percent),
                reason: "Missed \(low) reps two sessions running",
                chipReason: "missed \(low) reps twice"
            )
        }

        let fewest = sets.map(\.reps).min() ?? low
        let target = min(max(fewest + 1, low), high)
        let shortCount = sets.filter { $0.reps < low }.count
        let reason: String
        switch shortCount {
        case 0: reason = "Still building reps"
        case 1: reason = "One set fell short last time"
        default: reason = "\(shortCount) sets fell short last time"
        }
        return OverloadSuggestion(
            weightKg: topWeight, repRange: repRange, targetReps: target, change: .same,
            reason: reason,
            chipReason: "aim for \(target) reps"
        )
    }
}
