//  Planner.swift
//  Rule-based next-session planner (docs/PROJECT_GUIDE.md):
//  - pick the routine done least recently (never-done first), skipping exercises the user has no
//    equipment for;
//  - apply OverloadEngine to every exercise;
//  - at High fatigue (or when asked to lighten) cut one set per exercise and offer a rest day.
//  Explanation text is templated here; phase 7's AIPlanner may only reword it.

import Foundation

struct PlannerExerciseInput: Sendable {
    var name: String
    var muscle: MuscleGroup
    var equipment: Equipment
    var targetSets: Int
    var repRange: ClosedRange<Int>
    var restSeconds: Int?
    /// Newest first.
    var history: [ExerciseSession]
}

struct PlannerRoutineInput: Sendable {
    var name: String
    var createdAt: Date
    var lastDone: Date?
    var items: [PlannerExerciseInput]
}

struct PlannedExercise: Sendable, Equatable, Identifiable {
    var name: String
    var id: String { name }
    var muscle: MuscleGroup
    var sets: Int
    var repRange: ClosedRange<Int>
    var targetReps: Int
    var restSeconds: Int?
    /// nil without history, or for reps-only exercises.
    var weightKg: Double?
    var suggestion: OverloadSuggestion?

    /// "4 sets × 8 reps"
    var targetText: String { "\(sets) \(sets == 1 ? "set" : "sets") × \(targetReps) reps" }
    /// Row reason; "No history yet" before the first session.
    var reason: String { suggestion?.reason ?? "No history yet" }
}

struct SessionPlan: Sendable, Equatable {
    var routineName: String
    var exercises: [PlannedExercise]
    var fatigueBand: FatigueBand?
    var lightened: Bool
    var offerRestDay: Bool
    /// "planned from your last four sessions"
    var basis: String
    /// "Why this plan" text.
    var explanation: String
    /// Home card line: "Legs was yesterday, so chest is next."
    var homeReason: String

    var subtitle: String { "\(routineName) · \(basis)" }
}

enum Planner {
    static func plan(
        routines: [PlannerRoutineInput],
        availableEquipment: Set<Equipment>,
        recentWorkouts: [WorkoutDigest],
        fatigue: FatigueBand?,
        lighten: Bool = false,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SessionPlan? {
        let available = availableEquipment.union([.bodyweight])
        let candidates = routines
            .map { routine in
                var r = routine
                r.items = routine.items.filter { available.contains($0.equipment) }
                return r
            }
            .filter { !$0.items.isEmpty }
        guard let routine = candidates.min(by: { a, b in
            switch (a.lastDone, b.lastDone) {
            case (nil, nil): a.createdAt < b.createdAt
            case (nil, _): true
            case (_, nil): false
            case let (x?, y?): x < y
            }
        }) else { return nil }

        let cutSet = lighten || fatigue == .high
        let exercises = routine.items.map { item -> PlannedExercise in
            let suggestion = OverloadEngine.suggest(history: item.history, repRange: item.repRange, equipment: item.equipment)
            let sets = cutSet ? max(1, item.targetSets - 1) : item.targetSets
            return PlannedExercise(
                name: item.name, muscle: item.muscle, sets: sets, repRange: item.repRange,
                targetReps: suggestion?.targetReps ?? item.repRange.lowerBound, restSeconds: item.restSeconds,
                weightKg: suggestion?.weightKg, suggestion: suggestion
            )
        }

        let sorted = recentWorkouts.sorted { $0.date > $1.date }
        let focus = focusMuscles(exercises)
        let last = sorted.first

        var sentences: [String] = []
        if let last {
            if last.displayName == routine.name {
                sentences.append(candidates.count == 1
                    ? "\(routine.name) is your only routine, so it's next again."
                    : "\(routine.name) is your least recently trained routine, so it's next.")
            } else {
                let covered = Self.list(topMuscles(last.muscleSets))
                sentences.append(covered.isEmpty
                    ? "\(last.displayName) was your last session, so \(focus) \(verb(focus)) next."
                    : "\(last.displayName) covered \(covered), so \(focus) \(verb(focus)) next.")
            }
        } else {
            sentences.append("Your first \(routine.name) session.")
        }
        sentences.append(fatigueSentence(fatigue, lightened: cutSet))

        let homeReason: String
        if let last, last.displayName == routine.name {
            homeReason = "Last done \(relativeDay(last.date, now: now, calendar: calendar)). Weights move where you hit every rep."
        } else if let last {
            homeReason = "\(last.displayName) was \(relativeDay(last.date, now: now, calendar: calendar)), so \(focus) \(verb(focus)) next."
        } else {
            homeReason = "Start here; suggestions get personal after a few sessions."
        }

        let sessionCount = min(sorted.count, 4)
        let basis = sessionCount == 0 ? "planned from your routine"
            : sessionCount == 1 ? "planned from your last session"
            : "planned from your last \(["", "", "two", "three", "four"][sessionCount]) sessions"

        return SessionPlan(
            routineName: routine.name, exercises: exercises, fatigueBand: fatigue, lightened: cutSet,
            offerRestDay: fatigue == .high, basis: basis,
            explanation: sentences.joined(separator: " "), homeReason: homeReason
        )
    }

    static func fatigueSentence(_ band: FatigueBand?, lightened: Bool) -> String {
        switch band {
        case .high:
            return "Fatigue is high, so each exercise drops a set. A rest day first is a good option too."
        case .moderate:
            return lightened
                ? "Fatigue is moderate, so each exercise drops a set and weights only rise where you hit every rep."
                : "Fatigue is moderate, so sets stay the same and weights only rise where you hit every rep."
        case .low:
            return lightened
                ? "One set comes off each exercise; weights rise where you hit every rep."
                : "Fatigue is low, so weights rise wherever you hit every rep."
        case nil:
            return "Weights rise wherever you hit every rep last time."
        }
    }

    // MARK: Wording helpers

    static func focusMuscles(_ exercises: [PlannedExercise]) -> String {
        var counts: [MuscleGroup: Int] = [:]
        for e in exercises { counts[e.muscle, default: 0] += e.sets }
        return list(topMuscles(counts))
    }

    static func topMuscles(_ counts: [MuscleGroup: Int], limit: Int = 2) -> [String] {
        counts.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
            .prefix(limit)
            .map { $0.key.title.lowercased() }
    }

    static func list(_ items: [String]) -> String {
        items.formatted(.list(type: .and))
    }

    /// "back is next", "legs are next", "chest and back are next"
    static func verb(_ subject: String) -> String {
        subject.contains(" and ") || ["legs", "arms", "shoulders"].contains(subject) ? "are" : "is"
    }

    static func relativeDay(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case 2...6: return date.formatted(.dateTime.weekday(.wide))
        default: return "\(days) days ago"
        }
    }
}

/// "Suggested next" in the Add exercise sheet: exercises usually done alongside the current ones,
/// and muscles that are behind their usual weekly sets.
enum NextExerciseSuggester {
    struct Candidate: Sendable {
        var name: String
        var muscle: MuscleGroup
        var equipment: Equipment
    }

    struct Suggestion: Sendable, Equatable, Identifiable {
        var name: String
        var id: String { name }
        var reason: String
    }

    static func suggest(
        current: [String],
        workouts: [WorkoutDigest],
        library: [Candidate],
        availableEquipment: Set<Equipment>,
        now: Date = .now,
        limit: Int = 2
    ) -> [Suggestion] {
        let available = availableEquipment.union([.bodyweight])
        let usable = library.filter { available.contains($0.equipment) && !current.contains($0.name) }
        let usableNames = Set(usable.map(\.name))
        var picks: [Suggestion] = []

        // 1. Often done together with what's already in the workout; for an empty workout,
        //    the exercise that usually opens a session.
        if current.isEmpty {
            var openers: [String: Int] = [:]
            for w in workouts { if let first = w.exerciseNames.first, usableNames.contains(first) { openers[first, default: 0] += 1 } }
            if let best = openers.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }) {
                picks.append(Suggestion(name: best.key, reason: "Usually starts your workouts"))
            }
        } else if let anchor = current.last {
            var counts: [String: Int] = [:]
            for w in workouts where w.exerciseNames.contains(anchor) {
                for name in w.exerciseNames where usableNames.contains(name) { counts[name, default: 0] += 1 }
            }
            if let best = counts.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }) {
                picks.append(Suggestion(name: best.key, reason: "Usually follows your \(anchor.lowercased())"))
            }
        }

        // 2. The muscle furthest under its usual weekly sets.
        let day: TimeInterval = 86_400
        let thisWeek = workouts.filter { $0.date > now.addingTimeInterval(-7 * day) }
        let month = workouts.filter { $0.date > now.addingTimeInterval(-28 * day) }
        let oldest = month.map(\.date).min() ?? now
        let weeks = Double(min(4, max(1, Int((now.timeIntervalSince(oldest) / (7 * day)).rounded(.up)))))
        var usual: [MuscleGroup: Double] = [:]
        for w in month { for (m, n) in w.muscleSets { usual[m, default: 0] += Double(n) / weeks } }
        var done: [MuscleGroup: Double] = [:]
        for w in thisWeek { for (m, n) in w.muscleSets { done[m, default: 0] += Double(n) } }
        let behind = usual.filter { $0.value > 0 }
            .map { ($0.key, (done[$0.key] ?? 0) / $0.value) }
            .filter { $0.1 < 1 }
            .sorted { $0.1 < $1.1 }
        let trained = Set(workouts.flatMap(\.exerciseNames))
        for (muscle, _) in behind {
            let options = usable.filter { candidate in
                candidate.muscle == muscle && !picks.contains { $0.name == candidate.name }
            }
            guard let pick = options.first(where: { trained.contains($0.name) }) ?? options.first else { continue }
            picks.append(Suggestion(name: pick.name,
                                    reason: "\(muscle.title) \(Planner.verb(muscle.title.lowercased())) under target this week"))
            break
        }
        return Array(picks.prefix(limit))
    }
}
