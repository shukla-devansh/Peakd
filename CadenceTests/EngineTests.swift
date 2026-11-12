import Foundation
import Testing
@testable import Cadence

private let day: TimeInterval = 86_400
private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * day) }
private func session(_ daysAgo: Double, _ sets: [(Double?, Int)]) -> ExerciseSession {
    ExerciseSession(date: ago(daysAgo), sets: sets.map { LoggedSet(weightKg: $0.0, reps: $0.1) })
}

@Suite("Overload engine")
struct OverloadEngineTests {
    @Test("Every set at the top of the range: barbell +2.5 kg, reps back to the bottom")
    func barbellIncrease() throws {
        let s = try #require(OverloadEngine.suggest(history: [session(3, [(40, 10), (40, 10), (40, 10)])],
                                                    repRange: 8...10, equipment: .barbell))
        #expect(s.weightKg == 42.5)
        #expect(s.change == .increase(kg: 2.5))
        #expect(s.targetReps == 8)
        #expect(s.reason == "Hit 10 reps on every set")
        #expect(s.chipReason == "you hit 10 reps last time")
    }

    @Test("Dumbbells go up 1 kg per dumbbell")
    func dumbbellIncrease() throws {
        let s = try #require(OverloadEngine.suggest(history: [session(3, [(12, 12), (12, 12)])],
                                                    repRange: 10...12, equipment: .dumbbell))
        #expect(s.weightKg == 13)
        #expect(s.change == .increase(kg: 1))
    }

    @Test("Machines and cables use the 2.5 kg step")
    func machineIncrease() throws {
        for equipment in [Equipment.machine, .cable] {
            let s = try #require(OverloadEngine.suggest(history: [session(2, [(50, 10)])], repRange: 8...10, equipment: equipment))
            #expect(s.weightKg == 52.5)
        }
    }

    @Test("Inside the range: same weight, aim for one more rep than the weakest set")
    func sameWeight() throws {
        let s = try #require(OverloadEngine.suggest(history: [session(3, [(45, 10), (45, 9), (45, 8)])],
                                                    repRange: 8...10, equipment: .barbell))
        #expect(s.weightKg == 45)
        #expect(s.change == .same)
        #expect(s.targetReps == 9)
        #expect(s.reason == "Still building reps")
    }

    @Test("One set short of the bottom once: same weight, says which")
    func oneSetShort() throws {
        let s = try #require(OverloadEngine.suggest(history: [session(3, [(55, 10), (55, 10), (55, 9)])],
                                                    repRange: 10...12, equipment: .cable))
        #expect(s.change == .same)
        #expect(s.reason == "One set fell short last time")
        #expect(s.targetReps == 10)
    }

    @Test("Short of the bottom two sessions in a row: −5 %, rounded down to the step")
    func decreaseFive() throws {
        let history = [session(2, [(60, 8), (60, 7)]), session(6, [(60, 8), (60, 7)])]
        let s = try #require(OverloadEngine.suggest(history: history, repRange: 8...10, equipment: .barbell))
        #expect(s.change == .decrease(percent: 5))
        #expect(s.weightKg == 55)            // 57 rounded down to 2.5 kg steps
        #expect(s.targetReps == 8)
        #expect(s.reason == "Missed 8 reps two sessions running")
    }

    @Test("Missing by 2+ reps on average: −10 %")
    func decreaseTen() throws {
        let history = [session(2, [(50, 6), (50, 5)]), session(5, [(50, 7)])]
        let s = try #require(OverloadEngine.suggest(history: history, repRange: 8...10, equipment: .barbell))
        #expect(s.change == .decrease(percent: 10))
        #expect(s.weightKg == 45)
    }

    @Test("A single bad session doesn't cut the weight")
    func oneBadSession() throws {
        let history = [session(2, [(60, 6)]), session(6, [(60, 9)])]
        let s = try #require(OverloadEngine.suggest(history: history, repRange: 8...10, equipment: .barbell))
        #expect(s.change == .same)
    }

    @Test("Bodyweight progresses by reps")
    func bodyweight() throws {
        let s = try #require(OverloadEngine.suggest(history: [session(2, [(nil, 12), (nil, 10)])],
                                                    repRange: 8...12, equipment: .bodyweight))
        #expect(s.weightKg == nil)
        #expect(s.change == .addRep)
        #expect(s.targetReps == 13)
    }

    @Test("No history: no suggestion")
    func noHistory() {
        #expect(OverloadEngine.suggest(history: [], repRange: 8...10, equipment: .barbell) == nil)
        #expect(OverloadEngine.suggest(history: [session(1, [])], repRange: 8...10, equipment: .barbell) == nil)
    }

    @Test("Uses the heaviest set as the working weight")
    func topSet() throws {
        let s = try #require(OverloadEngine.suggest(history: [session(1, [(40, 10), (42.5, 10)])],
                                                    repRange: 8...10, equipment: .barbell))
        #expect(s.weightKg == 45)
    }
}

private func digest(_ daysAgo: Double, volume: Double = 5000, sets: Int = 15, below: Int = 0,
                    name: String = "Push day", exercises: [String] = [], muscles: [MuscleGroup: Int] = [:]) -> WorkoutDigest {
    WorkoutDigest(date: ago(daysAgo), routineName: name, volumeKg: volume, setCount: sets,
                  setsBelowTarget: below, exerciseNames: exercises, muscleSets: muscles)
}

@Suite("Fatigue engine")
struct FatigueEngineTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    @Test("Not enough data until 3 workouts")
    func notEnough() {
        #expect(FatigueEngine.report(workouts: [digest(1), digest(3)], plannedDaysPerWeek: 4, now: now, calendar: calendar) == nil)
        #expect(FatigueEngine.report(workouts: [digest(1), digest(3), digest(5)], plannedDaysPerWeek: 4, now: now, calendar: calendar) != nil)
    }

    @Test("A steady month on plan is Low")
    func low() throws {
        // 4 sessions a week for 4 weeks, same volume, rested today and yesterday.
        let workouts = (0..<16).map { i in digest(2 + Double(i) * 1.75) }
        let r = try #require(FatigueEngine.report(workouts: workouts, plannedDaysPerWeek: 4, now: now, calendar: calendar))
        #expect(r.band == .low)
    }

    @Test("A spike in load and frequency with missed reps and no rest is High")
    func high() throws {
        var workouts = (0..<6).map { i in digest(Double(i) + 0.1, volume: 9000, below: 6) }   // 6 days straight
        workouts += (8..<28).compactMap { i in i % 4 == 0 ? digest(Double(i), volume: 4000) : nil }
        let r = try #require(FatigueEngine.report(workouts: workouts, plannedDaysPerWeek: 3, now: now, calendar: calendar))
        #expect(r.band == .high)
        #expect(r.factors.first { $0.kind == .load }?.statusText == "Above usual")
        #expect(r.factors.first { $0.kind == .frequency }?.status == .elevated)
    }

    @Test("Factor points add up to the score")
    func contributionsSum() throws {
        let workouts = [digest(0.2, volume: 7000, below: 2), digest(1.2), digest(2.2), digest(9), digest(16)]
        let r = try #require(FatigueEngine.report(workouts: workouts, plannedDaysPerWeek: 4, now: now, calendar: calendar))
        #expect(r.factors.reduce(0) { $0 + $1.points } == r.score)
        #expect(r.factors.count == 4)                          // no heart-rate data: factor left out
        #expect(FatigueBand(score: r.score) == r.band)
    }

    @Test("Resting heart rate joins the blend when there's a baseline")
    func heartRate() throws {
        let workouts = [digest(1), digest(3), digest(5)]
        let samples = (1...10).map { HeartRateSample(date: ago(Double($0)), bpm: 56) } + [HeartRateSample(date: now, bpm: 64)]
        let r = try #require(FatigueEngine.report(workouts: workouts, plannedDaysPerWeek: 4,
                                                  restingHeartRate: samples, now: now, calendar: calendar))
        let heart = try #require(r.factors.first { $0.kind == .heart })
        #expect(heart.value == "+8 bpm vs baseline")
        #expect(heart.statusText == "Up")
        #expect(r.factors.reduce(0) { $0 + $1.points } == r.score)
    }

    @Test("Training streak counts consecutive days ending today or yesterday")
    func streak() {
        let days = [digest(0.1), digest(1.1), digest(2.1), digest(4.1)]
        #expect(FatigueEngine.trainingStreak(days, now: now, calendar: calendar) == 3)
        #expect(FatigueEngine.trainingStreak([digest(1.1), digest(2.1)], now: now, calendar: calendar) == 2)
        #expect(FatigueEngine.trainingStreak([digest(3)], now: now, calendar: calendar) == 0)
    }

    @Test("Load factor wording")
    func loadWording() throws {
        let workouts = [digest(1, volume: 6000), digest(10, volume: 5000), digest(17, volume: 5000), digest(24, volume: 4000)]
        let r = try #require(FatigueEngine.report(workouts: workouts, plannedDaysPerWeek: 1, now: now, calendar: calendar))
        // acute 6000 vs chronic 20000 / 4 = 5000 → +20 %
        #expect(r.factors.first { $0.kind == .load }?.value == "+20% over 7 days")
    }

    @Test("A first week of training is the baseline, not a load spike")
    func firstWeekBaseline() throws {
        let r = try #require(FatigueEngine.report(workouts: [digest(0.1), digest(0.2), digest(0.3)],
                                                  plannedDaysPerWeek: 4, now: now, calendar: calendar))
        let load = try #require(r.factors.first { $0.kind == .load })
        #expect(load.value == "Building your baseline")
        #expect(load.status == .ok)
    }

    @Test("History is nil before 3 workouts and trend text reads rising")
    func historyTrend() {
        let workouts = [digest(13), digest(12), digest(11)] + (0..<6).map { digest(Double($0) + 0.1, volume: 9000, below: 4) }
        let history = FatigueEngine.history(workouts: workouts, plannedDaysPerWeek: 3, now: now, calendar: calendar)
        #expect(history.count == 14)
        #expect(history.first?.score == nil)
        #expect(history.last?.score != nil)
        #expect(FatigueEngine.trendText(history, calendar: calendar).hasPrefix("Rising since"))
    }
}

@Suite("Planner")
struct PlannerTests {
    func item(_ name: String, _ muscle: MuscleGroup, _ equipment: Equipment = .barbell, sets: Int = 3,
              history: [ExerciseSession] = []) -> PlannerExerciseInput {
        PlannerExerciseInput(name: name, muscle: muscle, equipment: equipment, targetSets: sets,
                             repRange: 8...10, restSeconds: nil, history: history)
    }

    var routines: [PlannerRoutineInput] {
        [
            PlannerRoutineInput(name: "Push day", createdAt: ago(60), lastDone: ago(1), items: [
                item("Bench press", .chest, history: [session(1, [(40, 10), (40, 10)])]),
            ]),
            PlannerRoutineInput(name: "Pull day", createdAt: ago(60), lastDone: ago(5), items: [
                item("Barbell row", .back, sets: 4, history: [session(5, [(57.5, 10), (57.5, 10)])]),
                item("Lat pulldown", .back, .cable, history: [session(5, [(55, 10), (55, 9)])]),
                item("Kettlebell swing", .legs, .kettlebell),
            ]),
        ]
    }

    @Test("Picks the least recently done routine and applies overload")
    func picksLeastRecent() throws {
        let last = digest(1, name: "Push day", muscles: [.chest: 9, .shoulders: 6])
        let plan = try #require(Planner.plan(routines: routines, availableEquipment: [.barbell, .cable],
                                             recentWorkouts: [last], fatigue: .moderate, now: now))
        #expect(plan.routineName == "Pull day")
        #expect(plan.exercises.map(\.name) == ["Barbell row", "Lat pulldown"])   // no kettlebell
        #expect(plan.exercises[0].weightKg == 60)
        #expect(plan.exercises[0].sets == 4)
        #expect(plan.exercises[1].weightKg == 55)
        #expect(plan.exercises[1].suggestion?.change == .same)
        #expect(plan.explanation.hasPrefix("Push day covered chest and shoulders, so back is next."))
        #expect(plan.explanation.contains("sets stay the same"))
        #expect(!plan.offerRestDay)
        #expect(plan.basis == "planned from your last session")
    }

    @Test("A single routine done last reads as 'next again', not 'covered X so Y is next'")
    func singleRoutine() throws {
        let only = [routines[1]]
        let last = digest(0, name: "Pull day", muscles: [.back: 8])
        let plan = try #require(Planner.plan(routines: only, availableEquipment: [.barbell, .cable],
                                             recentWorkouts: [last], fatigue: .low, now: now))
        #expect(plan.explanation.hasPrefix("Pull day is your only routine, so it's next again."))
        #expect(plan.homeReason.hasPrefix("Last done today."))
    }

    @Test("Never-done routines come first")
    func neverDoneFirst() throws {
        var rs = routines
        rs.append(PlannerRoutineInput(name: "Legs", createdAt: ago(1), lastDone: nil, items: [item("Back squat", .legs)]))
        let plan = try #require(Planner.plan(routines: rs, availableEquipment: [.barbell], recentWorkouts: [], fatigue: nil, now: now))
        #expect(plan.routineName == "Legs")
        #expect(plan.exercises[0].reason == "No history yet")
    }

    @Test("High fatigue cuts one set per exercise and offers a rest day")
    func highFatigue() throws {
        let plan = try #require(Planner.plan(routines: routines, availableEquipment: [.barbell, .cable],
                                             recentWorkouts: [], fatigue: .high, now: now))
        #expect(plan.exercises.map(\.sets) == [3, 2])
        #expect(plan.offerRestDay)
        #expect(plan.lightened)
    }

    @Test("Lighten cuts a set without high fatigue")
    func lighten() throws {
        let plan = try #require(Planner.plan(routines: routines, availableEquipment: [.barbell, .cable],
                                             recentWorkouts: [], fatigue: .moderate, lighten: true, now: now))
        #expect(plan.exercises.map(\.sets) == [3, 2])
        #expect(!plan.offerRestDay)
    }

    @Test("Routines with no usable exercise are skipped; none at all gives no plan")
    func equipmentFilter() {
        #expect(Planner.plan(routines: routines, availableEquipment: [], recentWorkouts: [], fatigue: nil, now: now) == nil)
    }

    @Test("Targets read like the board")
    func targetText() throws {
        let plan = try #require(Planner.plan(routines: routines, availableEquipment: [.barbell, .cable],
                                             recentWorkouts: [], fatigue: nil, now: now))
        #expect(plan.exercises[0].targetText == "4 sets × 8 reps")
    }
}

@Suite("Suggested next exercise")
struct NextExerciseTests {
    let library = [
        NextExerciseSuggester.Candidate(name: "Bench press", muscle: .chest, equipment: .barbell),
        NextExerciseSuggester.Candidate(name: "Triceps pushdown", muscle: .arms, equipment: .cable),
        NextExerciseSuggester.Candidate(name: "Overhead press", muscle: .shoulders, equipment: .barbell),
        NextExerciseSuggester.Candidate(name: "Kettlebell press", muscle: .shoulders, equipment: .kettlebell),
    ]

    @Test("Suggests what usually follows, then an under-target muscle")
    func suggestions() {
        let history = [
            digest(9, exercises: ["Bench press", "Triceps pushdown"], muscles: [.chest: 6, .arms: 3]),
            digest(16, exercises: ["Bench press", "Triceps pushdown", "Overhead press"], muscles: [.chest: 6, .arms: 3, .shoulders: 4]),
            digest(2, exercises: ["Bench press"], muscles: [.chest: 6]),
        ]
        let picks = NextExerciseSuggester.suggest(current: ["Bench press"], workouts: history, library: library,
                                                  availableEquipment: [.barbell, .cable], now: now)
        #expect(picks.map(\.name) == ["Triceps pushdown", "Overhead press"])
        #expect(picks[0].reason == "Usually follows your bench press")
        #expect(picks[1].reason == "Shoulders are under target this week")
    }

    @Test("Empty workout suggests the usual opener; a first week sets the baseline, so nothing is behind")
    func opener() {
        let history = [
            digest(0.1, exercises: ["Overhead press", "Bench press"], muscles: [.shoulders: 3, .chest: 3]),
            digest(0.2, exercises: ["Overhead press"], muscles: [.shoulders: 3]),
            digest(0.3, exercises: ["Bench press"], muscles: [.chest: 3]),
        ]
        let picks = NextExerciseSuggester.suggest(current: [], workouts: history, library: library,
                                                  availableEquipment: [.barbell], now: now)
        #expect(picks == [.init(name: "Overhead press", reason: "Usually starts your workouts")])
    }

    @Test("Nothing to go on: no suggestions")
    func empty() {
        #expect(NextExerciseSuggester.suggest(current: [], workouts: [], library: library,
                                              availableEquipment: [.barbell], now: now).isEmpty)
    }
}
