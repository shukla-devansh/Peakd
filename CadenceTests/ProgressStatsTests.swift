import Foundation
import Testing
@testable import Cadence

private let day: TimeInterval = 86_400
private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2   // Monday
    return c
}()
/// Wednesday 11 Nov 2026, 18:00 UTC
private let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 18))!

private func w(_ daysAgo: Double, volume: Double = 1000, muscles: [MuscleGroup: Int] = [.chest: 3]) -> WorkoutDigest {
    WorkoutDigest(date: now.addingTimeInterval(-daysAgo * day), routineName: "Push day", volumeKg: volume,
                  setCount: muscles.values.reduce(0, +), setsBelowTarget: 0, exerciseNames: [], muscleSets: muscles)
}

@Suite("Progress stats")
struct ProgressStatsTests {
    @Test func totalsComparePriorPeriod() {
        let workouts = [w(1, volume: 1100), w(5, volume: 1100), w(20, volume: 1000),   // last 30 days: 3200
                        w(35, volume: 1000), w(50, volume: 2000)]                         // prior 30: 3000
        let s = ProgressStats.summary(range: .month, workouts: workouts, recordDates: [now.addingTimeInterval(-2 * day), now.addingTimeInterval(-40 * day)],
                                      now: now, calendar: calendar)
        #expect(s.workouts == 3)
        #expect(s.workoutsDelta == 1)
        #expect(s.volumeKg == 3200)
        #expect(s.volumeChange == 7)
        #expect(s.records == 1)
    }

    @Test func noPriorVolumeMeansNoPercent() {
        let s = ProgressStats.summary(range: .week, workouts: [w(1)], recordDates: [], now: now, calendar: calendar)
        #expect(s.volumeChange == nil)
        #expect(s.workoutsDelta == 1)
    }

    @Test func weeklyBucketsStartOnTheCalendarWeek() {
        let s = ProgressStats.summary(range: .month, workouts: [w(0, volume: 500), w(1, volume: 500), w(8, volume: 800)],
                                      now: now, calendar: calendar)
        #expect(s.buckets.count == 6)
        let last = s.buckets[5]
        #expect(calendar.component(.weekday, from: last.start) == 2)       // Monday
        #expect(last.volumeKg == 1000)
        #expect(last.sessions == 2)
        #expect(s.buckets[4].volumeKg == 800)
        #expect(last.change == 25)
        #expect(s.buckets[0].change == nil)
    }

    @Test func dailyAndMonthlyBuckets() {
        let week = ProgressStats.summary(range: .week, workouts: [w(0), w(6)], now: now, calendar: calendar)
        #expect(week.buckets.count == 7)
        #expect(week.buckets.first?.volumeKg == 1000)
        #expect(week.range.bucket == .day)
        let year = ProgressStats.summary(range: .year, workouts: [w(0), w(40)], now: now, calendar: calendar)
        #expect(year.buckets.count == 12)
        #expect(calendar.component(.day, from: year.buckets[11].start) == 1)
        #expect(year.buckets[11].volumeKg == 1000)
    }

    @Test func emptyAfterAnEmptyBucketHasNoChange() {
        let s = ProgressStats.summary(range: .month, workouts: [w(0)], now: now, calendar: calendar)
        #expect(s.buckets.last?.change == nil)
    }

    @Test func muscleSharesAddUpToHundred() {
        let shares = ProgressStats.muscleShares([w(1, muscles: [.legs: 1, .chest: 1, .back: 1])])
        #expect(shares.map(\.percent).reduce(0, +) == 100)
        #expect(shares.count == 3)
        let skewed = ProgressStats.muscleShares([w(1, muscles: [.legs: 7, .arms: 3])])
        #expect(skewed.map(\.muscle) == [.legs, .arms])
        #expect(skewed.map(\.percent) == [70, 30])
    }

    @Test func noSetsNoShares() {
        #expect(ProgressStats.muscleShares([]).isEmpty)
    }

    @Test func changeText() {
        #expect(ProgressStats.changeText(6) == "▲ +6%")
        #expect(ProgressStats.changeText(-4) == "▼ −4%")
        #expect(ProgressStats.changeText(0) == "▲ +0%")
        #expect(ProgressStats.changeText(nil) == "–")
    }
}

@Suite("Exercise stats")
struct ExerciseStatsTests {
    let sessions = [
        ExerciseSession(date: now, sets: [LoggedSet(weightKg: 42.5, reps: 10), LoggedSet(weightKg: 42.5, reps: 10), LoggedSet(weightKg: 45, reps: 8)]),
        ExerciseSession(date: now.addingTimeInterval(-9 * day), sets: [LoggedSet(weightKg: 40, reps: 10), LoggedSet(weightKg: 40, reps: 9)]),
        ExerciseSession(date: now.addingTimeInterval(-20 * day), sets: []),
    ]

    @Test func records() {
        let r = ExerciseStats.records(sessions)
        #expect(r.heaviestKg == 45)
        #expect(r.bestSet == LoggedSet(weightKg: 45, reps: 8))
        #expect(r.est1RMKg == 57)
        #expect(r.sessions == 2)
    }

    @Test func repsOnlyRecords() {
        let r = ExerciseStats.records([ExerciseSession(date: now, sets: [LoggedSet(weightKg: nil, reps: 12), LoggedSet(weightKg: 0, reps: 15)])])
        #expect(r.heaviestKg == nil)
        #expect(r.bestSet == nil)
        #expect(r.mostReps == 15)
    }

    @Test func topSetsOldestFirst() {
        let points = ExerciseStats.topSets(sessions)
        #expect(points.map(\.weightKg) == [40, 45])
    }

    @Test func historyText() {
        #expect(ExerciseStats.setsText(sessions[0], unit: .kg) == "42.5 × 10, 42.5 × 10, 45 × 8")
        #expect(ExerciseStats.volumeKg(sessions[0]) == 1210)
        #expect(ExerciseStats.setsText(ExerciseSession(date: now, sets: [LoggedSet(weightKg: nil, reps: 12)]), unit: .kg) == "12")
    }

    @Test func nextTimeStay() {
        let s = OverloadSuggestion(weightKg: 45, repRange: 8...10, targetReps: 9, change: .same, reason: "", chipReason: "")
        let t = ExerciseStats.nextTime(s, last: sessions[0], step: 2.5, unit: .kg)
        #expect(t.title == "Next time: 45 kg × 8–10")
        #expect(t.detail == "You reached 8 reps at 45 kg. Stay at this weight until you hit 10 reps on every set, then add 2.5 kg.")
    }

    @Test func nextTimeIncrease() {
        let s = OverloadSuggestion(weightKg: 47.5, repRange: 8...10, targetReps: 8, change: .increase(kg: 2.5), reason: "", chipReason: "")
        let t = ExerciseStats.nextTime(s, last: sessions[0], step: 2.5, unit: .kg)
        #expect(t.title == "Next time: 47.5 kg × 8–10")
        #expect(t.detail == "You hit 10 reps on every set at 45 kg. Add 2.5 kg and start back at 8 reps.")
    }

    @Test func nextTimeDecreaseAndReps() {
        let d = OverloadSuggestion(weightKg: 40, repRange: 8...10, targetReps: 8, change: .decrease(percent: 10), reason: "", chipReason: "")
        #expect(ExerciseStats.nextTime(d, last: nil, step: 2.5, unit: .kg).detail.contains("comes down 10%"))
        let r = OverloadSuggestion(weightKg: nil, repRange: 8...12, targetReps: 13, change: .addRep, reason: "", chipReason: "")
        #expect(ExerciseStats.nextTime(r, last: nil, step: nil, unit: .kg).title == "Next time: 13 reps")
    }
}

@Suite("Training calendar")
struct TrainingCalendarTests {
    @Test func gridShapeAndAlignment() {
        let cols = TrainingCalendar.columns(workouts: [], weeks: 18, now: now, calendar: calendar)
        #expect(cols.count == 18)
        #expect(cols.allSatisfy { $0.count == 7 })
        #expect(calendar.component(.weekday, from: cols[0][0].date) == 2)   // Monday first
        let days = cols.flatMap { $0 }
        #expect(days.filter(\.isFuture).count == 4)                         // Thu–Sun after Wednesday
        #expect(days.allSatisfy { $0.level == 0 })
    }

    @Test func bluerWithMoreVolume() {
        let workouts = [w(0, volume: 4000), w(1, volume: 1000), w(2, volume: 2100), w(2.1, volume: 900), w(3, volume: 0)]
        let days = TrainingCalendar.columns(workouts: workouts, weeks: 2, now: now, calendar: calendar).flatMap { $0 }
        func level(_ daysAgo: Int) -> Int? {
            let target = calendar.startOfDay(for: now.addingTimeInterval(-Double(daysAgo) * day))
            return days.first { $0.date == target }?.level
        }
        #expect(level(0) == 4)          // busiest
        #expect(level(1) == 1)          // 25%
        #expect(level(2) == 3)          // two workouts, 3000 kg = 75%
        #expect(level(3) == 1)          // bodyweight-only still shows
        #expect(level(4) == 0)          // rest day
    }

    @Test func workoutsOutsideTheWindowAreIgnored() {
        let days = TrainingCalendar.columns(workouts: [w(100, volume: 9000), w(0, volume: 500)], weeks: 4, now: now, calendar: calendar)
            .flatMap { $0 }
        #expect(days.filter { $0.level > 0 }.count == 1)
        #expect(days.first { $0.level > 0 }?.level == 4)
    }
}
