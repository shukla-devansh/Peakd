//  FatigueEngine.swift
//  Fatigue score 0–100, a fitness estimate (not medical). Deterministic weighted blend of:
//    load      acute:chronic ratio — 7-day volume vs the 28-day weekly average   weight 0.35
//    frequency sessions in the last 7 days vs the user's plan                   weight 0.20
//    misses    share of last-7-day sets below their target reps                  weight 0.20
//    streak    consecutive training days up to today                             weight 0.15
//    heart     resting HR vs its 14-day baseline (only when HealthKit has it)    weight 0.10
//  Each factor maps to 0…1; the score is the weighted mean × 100 over the factors present.
//  Bands: Low 0–39, Moderate 40–69, High 70–100. Nil until 3 workouts are logged.

import Foundation

/// One finished workout, reduced to what the engines need.
struct WorkoutDigest: Sendable, Equatable {
    var date: Date
    var routineName: String?
    var volumeKg: Double
    var setCount: Int
    /// Completed sets below their exercise's target range.
    var setsBelowTarget: Int
    var exerciseNames: [String]
    /// Completed sets per primary muscle.
    var muscleSets: [MuscleGroup: Int]

    var displayName: String { routineName ?? "Workout" }
    /// For the start of a sentence: "Push day was…", or "Your last workout was…" when untitled.
    var sentenceName: String { routineName ?? "Your last workout" }
}

struct HeartRateSample: Sendable, Equatable {
    var date: Date
    var bpm: Double
}

struct FatigueFactor: Identifiable, Sendable, Equatable {
    enum Kind: String, Sendable { case load, frequency, misses, streak, heart }
    enum Status: Sendable { case ok, elevated }

    var kind: Kind
    var id: Kind { kind }
    /// "Training load vs your usual"
    var label: String
    /// "+18% over 7 days"
    var value: String
    /// "Above usual"
    var statusText: String
    var status: Status
    /// Points this factor adds to the score (they sum to the score).
    var points: Int
}

struct FatigueReport: Sendable, Equatable {
    var score: Int
    var band: FatigueBand
    var factors: [FatigueFactor]
}

enum FatigueEngine {
    static let minimumWorkouts = 3

    static let weights: [FatigueFactor.Kind: Double] = [
        .load: 0.35, .frequency: 0.20, .misses: 0.20, .streak: 0.15, .heart: 0.10,
    ]

    static func report(
        workouts: [WorkoutDigest],
        plannedDaysPerWeek: Int,
        restingHeartRate: [HeartRateSample] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> FatigueReport? {
        let past = workouts.filter { $0.date <= now }
        guard past.count >= minimumWorkouts else { return nil }

        let day: TimeInterval = 86_400
        let last7 = past.filter { $0.date > now.addingTimeInterval(-7 * day) }
        let last28 = past.filter { $0.date > now.addingTimeInterval(-28 * day) }

        var raw: [(FatigueFactor, Double)] = []

        // Load: acute (7 d) vs chronic (28 d weekly average). The baseline averages only the weeks
        // the history covers, so a new user's first week reads as their usual, not +300%.
        let acute = last7.reduce(0) { $0 + $1.volumeKg }
        let oldest = last28.map(\.date).min() ?? now
        let weeksCovered = min(4, max(1, Int((now.timeIntervalSince(oldest) / (7 * day)).rounded(.up))))
        let chronic = last28.reduce(0) { $0 + $1.volumeKg } / Double(weeksCovered)
        let ratio = chronic > 0 ? acute / chronic : 1
        let loadChange = Int(((ratio - 1) * 100).rounded())
        raw.append((FatigueFactor(
            kind: .load, label: "Training load vs your usual",
            value: weeksCovered < 2 ? "Building your baseline"
                : "\(loadChange >= 0 ? "+" : "−")\(abs(loadChange))% over 7 days",
            statusText: ratio > 1.15 ? "Above usual" : (ratio < 0.85 ? "Below usual" : "Normal"),
            status: ratio > 1.15 ? .elevated : .ok, points: 0
        ), clamp((ratio - 0.8) / 0.7)))

        // Frequency: sessions vs plan
        let plan = max(plannedDaysPerWeek, 1)
        let sessions = last7.count
        let frequencyRatio = Double(sessions) / Double(plan)
        raw.append((FatigueFactor(
            kind: .frequency, label: "Sessions in last 7 days",
            value: "\(sessions) \(sessions == 1 ? "session" : "sessions")",
            statusText: sessions > plan ? "Above usual" : (sessions < plan ? "Below plan" : "On plan"),
            status: sessions > plan ? .elevated : .ok, points: 0
        ), clamp((frequencyRatio - 0.75) / 0.75)))

        // Misses: sets below target reps this week
        let setsThisWeek = last7.reduce(0) { $0 + $1.setCount }
        let below = last7.reduce(0) { $0 + $1.setsBelowTarget }
        let missShare = setsThisWeek > 0 ? Double(below) / Double(setsThisWeek) : 0
        raw.append((FatigueFactor(
            kind: .misses, label: "Sets below target reps",
            value: "\(below) of \(setsThisWeek) this week",
            statusText: missShare > 0.15 ? "Above usual" : "Normal",
            status: missShare > 0.15 ? .elevated : .ok, points: 0
        ), clamp(missShare / 0.3)))

        // Streak: consecutive training days ending today or yesterday
        let streak = trainingStreak(past, now: now, calendar: calendar)
        raw.append((FatigueFactor(
            kind: .streak, label: "Days since last rest day",
            value: streak == 0 ? "Rested today" : "\(streak) \(streak == 1 ? "day" : "days") in a row",
            statusText: streak >= 4 ? "Above usual" : "Normal",
            status: streak >= 4 ? .elevated : .ok, points: 0
        ), clamp(Double(streak - 1) / 4)))

        // Resting heart rate vs 14-day baseline
        if let delta = restingHeartRateDelta(restingHeartRate, now: now) {
            let rounded = Int(delta.rounded())
            raw.append((FatigueFactor(
                kind: .heart, label: "Resting heart rate",
                value: "\(rounded >= 0 ? "+" : "−")\(abs(rounded)) bpm vs baseline",
                statusText: delta > 5 ? "Up" : (delta > 2 ? "Slightly up" : "Normal"),
                status: delta > 2 ? .elevated : .ok, points: 0
            ), clamp(delta / 8)))
        }

        let totalWeight = raw.reduce(0) { $0 + (weights[$1.0.kind] ?? 0) }
        let contributions = raw.map { factor, value in (factor, (weights[factor.kind] ?? 0) * value / totalWeight * 100) }
        let score = min(100, max(0, Int(contributions.reduce(0) { $0 + $1.1 }.rounded())))
        let factors = distribute(score: score, contributions)
        return FatigueReport(score: score, band: FatigueBand(score: score), factors: factors)
    }

    /// Daily scores for the last `days` days (oldest first); nil where there wasn't enough data yet.
    static func history(
        workouts: [WorkoutDigest], plannedDaysPerWeek: Int, restingHeartRate: [HeartRateSample] = [],
        days: Int = 14, now: Date = .now, calendar: Calendar = .current
    ) -> [(date: Date, score: Int?)] {
        (0..<days).reversed().map { offset in
            let dayEnd = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            let score = report(workouts: workouts, plannedDaysPerWeek: plannedDaysPerWeek,
                               restingHeartRate: restingHeartRate, now: dayEnd, calendar: calendar)?.score
            return (dayEnd, score)
        }
    }

    /// "Rising since Wednesday", "Falling since Monday", "Steady this week".
    static func trendText(_ history: [(date: Date, score: Int?)], calendar: Calendar = .current) -> String {
        let week = history.suffix(7).compactMap { point in point.score.map { (point.date, $0) } }
        guard let current = week.last?.1, week.count >= 2 else { return "Building your baseline" }
        let low = week.min { $0.1 < $1.1 }!, high = week.max { $0.1 < $1.1 }!
        let weekday = { (date: Date) in date.formatted(.dateTime.weekday(.wide)) }
        if current - low.1 >= 5, low.0 < week.last!.0 { return "Rising since \(weekday(low.0))" }
        if high.1 - current >= 5, high.0 < week.last!.0 { return "Falling since \(weekday(high.0))" }
        return "Steady this week"
    }

    // MARK: Helpers

    static func trainingStreak(_ workouts: [WorkoutDigest], now: Date, calendar: Calendar) -> Int {
        let days = Set(workouts.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            // Today isn't over: a streak can still end yesterday.
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), days.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// Latest resting HR minus the mean of the 14 days before it. Needs 3+ baseline samples.
    static func restingHeartRateDelta(_ samples: [HeartRateSample], now: Date) -> Double? {
        let sorted = samples.filter { $0.date <= now }.sorted { $0.date < $1.date }
        guard let latest = sorted.last else { return nil }
        let start = latest.date.addingTimeInterval(-14 * 86_400)
        let baseline = sorted.dropLast().filter { $0.date >= start }
        guard baseline.count >= 3 else { return nil }
        return latest.bpm - baseline.reduce(0) { $0 + $1.bpm } / Double(baseline.count)
    }

    private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    /// Rounds each factor's contribution so the shown points add up to the score exactly.
    private static func distribute(score: Int, _ contributions: [(FatigueFactor, Double)]) -> [FatigueFactor] {
        var points = contributions.map { Int($0.1.rounded(.down)) }
        var remainder = score - points.reduce(0, +)
        let order = contributions.indices.sorted {
            (contributions[$0].1 - Double(points[$0])) > (contributions[$1].1 - Double(points[$1]))
        }
        for i in order where remainder > 0 {
            points[i] += 1
            remainder -= 1
        }
        return contributions.enumerated().map { i, pair in
            var factor = pair.0
            factor.points = points[i]
            return factor
        }
    }
}
