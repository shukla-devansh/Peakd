//  ProgressStats.swift
//  Numbers for the Progress board (08) and its table (20): totals vs the prior period, volume per
//  day/week/month, and each muscle group's share of working sets. Pure and deterministic.

import Foundation

enum ProgressRange: String, CaseIterable, Identifiable, Sendable {
    case week, month, threeMonths, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .threeMonths: "3 months"
        case .year: "Year"
        }
    }

    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        case .year: 365
        }
    }

    /// "last 30 days" (muscle card, tile group label)
    var periodText: String {
        switch self {
        case .week: "last 7 days"
        case .month: "last 30 days"
        case .threeMonths: "last 3 months"
        case .year: "last 12 months"
        }
    }

    /// Records tile detail: "this month".
    var recordsText: String {
        switch self {
        case .week: "this week"
        case .month: "this month"
        case .threeMonths: "in 3 months"
        case .year: "this year"
        }
    }

    var bucket: VolumeBucket.Size {
        switch self {
        case .week: .day
        case .month, .threeMonths: .week
        case .year: .month
        }
    }

    var bucketCount: Int {
        switch self {
        case .week: 7
        case .month: 6
        case .threeMonths: 13
        case .year: 12
        }
    }
}

struct VolumeBucket: Sendable, Equatable, Identifiable {
    enum Size: Sendable {
        case day, week, month

        /// Chart caption: "kg per week".
        func perText(_ unit: WeightUnit) -> String {
            switch self {
            case .day: "\(unit.symbol) per day"
            case .week: "\(unit.symbol) per week"
            case .month: "\(unit.symbol) per month"
            }
        }

        /// Table first column: "Week of".
        var columnTitle: String {
            switch self {
            case .day: "Day"
            case .week: "Week of"
            case .month: "Month"
            }
        }

        var chartTitle: String {
            switch self {
            case .day: "Daily volume"
            case .week: "Weekly volume"
            case .month: "Monthly volume"
            }
        }
    }

    var start: Date
    var volumeKg: Double
    var sessions: Int
    /// Percent change from the bucket before; nil for the first or after an empty bucket.
    var change: Int?

    var id: Date { start }
}

struct MuscleShare: Sendable, Equatable, Identifiable {
    var muscle: MuscleGroup
    var sets: Int
    var percent: Int
    var id: MuscleGroup { muscle }
}

struct ProgressSummary: Sendable, Equatable {
    var range: ProgressRange
    var workouts: Int
    /// Workouts minus the prior period's.
    var workoutsDelta: Int
    var volumeKg: Double
    /// Percent vs the prior period; nil when the prior period had no volume.
    var volumeChange: Int?
    var records: Int
    /// Oldest first.
    var buckets: [VolumeBucket]
    /// Largest share first; percents add up to 100.
    var muscles: [MuscleShare]
}

enum ProgressStats {
    /// `recordDates`: one date per exercise that set a record in a workout.
    static func summary(range: ProgressRange, workouts: [WorkoutDigest], recordDates: [Date] = [],
                        now: Date = .now, calendar: Calendar = .current) -> ProgressSummary {
        let day: TimeInterval = 86_400
        let start = now.addingTimeInterval(-Double(range.days) * day)
        let priorStart = now.addingTimeInterval(-Double(range.days * 2) * day)
        let current = workouts.filter { $0.date > start && $0.date <= now }
        let prior = workouts.filter { $0.date > priorStart && $0.date <= start }

        let volume = current.reduce(0) { $0 + $1.volumeKg }
        let priorVolume = prior.reduce(0) { $0 + $1.volumeKg }

        return ProgressSummary(
            range: range,
            workouts: current.count,
            workoutsDelta: current.count - prior.count,
            volumeKg: volume,
            volumeChange: WorkoutMetrics.percentChange(from: priorVolume, to: volume),
            records: recordDates.filter { $0 > start && $0 <= now }.count,
            buckets: buckets(range: range, workouts: workouts, now: now, calendar: calendar),
            muscles: muscleShares(current)
        )
    }

    static func buckets(range: ProgressRange, workouts: [WorkoutDigest], now: Date, calendar: Calendar) -> [VolumeBucket] {
        let component: Calendar.Component = switch range.bucket {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
        guard let last = calendar.dateInterval(of: component, for: now) else { return [] }
        var intervals: [DateInterval] = [last]
        while intervals.count < range.bucketCount,
              let previousDay = calendar.date(byAdding: .second, value: -1, to: intervals[0].start),
              let interval = calendar.dateInterval(of: component, for: previousDay) {
            intervals.insert(interval, at: 0)
        }
        var result: [VolumeBucket] = []
        for interval in intervals {
            let inside = workouts.filter { $0.date >= interval.start && $0.date < interval.end && $0.date <= now }
            let volume = inside.reduce(0) { $0 + $1.volumeKg }
            let change = result.last.flatMap { WorkoutMetrics.percentChange(from: $0.volumeKg, to: volume) }
            result.append(VolumeBucket(start: interval.start, volumeKg: volume, sessions: inside.count, change: change))
        }
        return result
    }

    /// Share of working sets per muscle, rounded so the percents add to exactly 100.
    static func muscleShares(_ workouts: [WorkoutDigest]) -> [MuscleShare] {
        var sets: [MuscleGroup: Int] = [:]
        for w in workouts { for (m, n) in w.muscleSets { sets[m, default: 0] += n } }
        let total = sets.values.reduce(0, +)
        guard total > 0 else { return [] }
        let ordered = sets.filter { $0.value > 0 }.sorted {
            $0.value == $1.value ? $0.key.title < $1.key.title : $0.value > $1.value
        }
        let exact = ordered.map { Double($0.value) * 100 / Double(total) }
        var percents = exact.map { Int($0.rounded(.down)) }
        let leftover = 100 - percents.reduce(0, +)
        let byRemainder = exact.indices.sorted { (exact[$0] - Double(percents[$0])) > (exact[$1] - Double(percents[$1])) }
        for i in byRemainder.prefix(leftover) { percents[i] += 1 }
        return zip(ordered, percents).map { MuscleShare(muscle: $0.0.key, sets: $0.0.value, percent: $0.1) }
    }

    /// Table "Change" cell: "▲ +6%", "▼ −4%", "–".
    static func changeText(_ change: Int?) -> String {
        guard let change else { return "–" }
        return change >= 0 ? "▲ +\(change)%" : "▼ −\(abs(change))%"
    }
}

// MARK: - Training calendar (GitHub-style)

struct HeatDay: Sendable, Equatable {
    var date: Date
    var volumeKg: Double
    var workouts: Int
    /// 0 = rest day, 1…4 = share of the busiest day in the window (bluer = more volume).
    var level: Int
    /// Days after today stay blank.
    var isFuture: Bool
}

enum TrainingCalendar {
    static let levels = 4

    /// `weeks` columns of 7 days, oldest first, each column starting on the calendar's first weekday.
    static func columns(workouts: [WorkoutDigest], weeks: Int, now: Date = .now, calendar: Calendar = .current) -> [[HeatDay]] {
        guard weeks > 0, let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
              let firstWeek = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek.start) else { return [] }
        let today = calendar.startOfDay(for: now)

        var volume: [Date: Double] = [:]
        var count: [Date: Int] = [:]
        for w in workouts where w.date <= now && w.date >= firstWeek {
            let day = calendar.startOfDay(for: w.date)
            volume[day, default: 0] += w.volumeKg
            count[day, default: 0] += 1
        }
        let busiest = volume.values.max() ?? 0

        return (0..<weeks).map { week in
            (0..<7).compactMap { offset -> HeatDay? in
                guard let date = calendar.date(byAdding: .day, value: week * 7 + offset, to: firstWeek) else { return nil }
                let day = calendar.startOfDay(for: date)
                let v = volume[day] ?? 0
                let n = count[day] ?? 0
                return HeatDay(date: day, volumeKg: v, workouts: n, level: level(volume: v, workouts: n, busiest: busiest),
                               isFuture: day > today)
            }
        }
    }

    /// Relative to the busiest day: any workout is at least level 1, the busiest is 4.
    static func level(volume: Double, workouts: Int, busiest: Double) -> Int {
        guard workouts > 0 else { return 0 }
        guard busiest > 0, volume > 0 else { return 1 }
        return min(levels, max(1, Int((Double(levels) * volume / busiest).rounded(.up))))
    }
}
