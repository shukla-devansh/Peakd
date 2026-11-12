import Foundation
import Testing
@testable import Cadence

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func plan(lightened: Bool = false) -> SessionPlan {
    let row = OverloadSuggestion(weightKg: 60, repRange: 8...10, targetReps: 8, change: .increase(kg: 2.5),
                                 reason: "Hit 10 reps on every set", chipReason: "you hit 10 reps last time")
    return SessionPlan(
        routineName: "Pull day",
        exercises: [
            PlannedExercise(name: "Barbell row", muscle: .back, sets: lightened ? 3 : 4, repRange: 8...10, targetReps: 8,
                            restSeconds: nil, weightKg: 60, suggestion: row),
            PlannedExercise(name: "Face pull", muscle: .shoulders, sets: 3, repRange: 12...15, targetReps: 12,
                            restSeconds: nil, weightKg: nil, suggestion: nil),
        ],
        fatigueBand: .moderate, lightened: lightened, offerRestDay: false,
        basis: "planned from your last session",
        explanation: "Template explanation.", homeReason: "Template home."
    )
}

private func facts(lightened: Bool = false) -> PlanFacts {
    let last = WorkoutDigest(date: now.addingTimeInterval(-86_400), routineName: "Push day", volumeKg: 5000,
                             setCount: 15, setsBelowTarget: 0, exerciseNames: ["Bench press"], muscleSets: [.chest: 9])
    let fatigue = FatigueReport(score: 52, band: .moderate, factors: [])
    return PlanFacts.make(plan: plan(lightened: lightened), fatigue: fatigue, digests: [last], unit: .kg, now: now, calendar: calendar)
}

@Suite("AI planner: facts and checks")
struct PlanFactsTests {
    @Test func factsCarryTheEngineNumbers() {
        let f = facts()
        #expect(f.text.contains("Next routine: Pull day"))
        #expect(f.text.contains("Last session: Push day, yesterday, mostly chest"))
        #expect(f.text.contains("Fatigue: moderate, 52 of 100"))
        #expect(f.text.contains("- Barbell row: 4 sets × 8 reps at 60 kg; weight goes up 2.5 kg (Hit 10 reps on every set)"))
        #expect(f.text.contains("- Face pull: 3 sets × 12 reps; no history yet"))
        for n in [52.0, 4, 8, 60, 2.5, 10, 3, 12, 100, 1] { #expect(f.allowedNumbers.contains(n)) }
    }

    @Test func keyIsStableAndChangesWithThePlan() {
        #expect(facts().key == facts().key)
        #expect(facts().key != facts(lightened: true).key)
        #expect(facts(lightened: true).text.contains("one set fewer per exercise"))
    }

    @Test func acceptsWordingWithoutNumbers() {
        let w = PlanWording(explanation: "Push day worked your chest, so today is about your back.",
                            homeReason: "Your back is fresh after yesterday's push work.")
        #expect(PlanWordingValidator.isValid(w, facts: facts()))
    }

    @Test func acceptsNumbersFromTheFacts() {
        let w = PlanWording(explanation: "Barbell row goes up 2.5 kg because you hit 10 reps on every set.",
                            homeReason: "Fatigue is moderate at 52.")
        #expect(PlanWordingValidator.isValid(w, facts: facts()))
    }

    @Test func rejectsAnInventedNumber() {
        let w = PlanWording(explanation: "Add 5 kg to your row today.", homeReason: "Back day.")
        #expect(!PlanWordingValidator.isValid(w, facts: facts()))
    }

    @Test func rejectsInventedNumberWords() {
        let w = PlanWording(explanation: "Aim for seven reps on each set.", homeReason: "Back day.")
        #expect(!PlanWordingValidator.isValid(w, facts: facts()))
    }

    @Test func rejectsEmptyOrTooLong() {
        #expect(!PlanWordingValidator.isValid(PlanWording(explanation: "", homeReason: "Back day."), facts: facts()))
        let long = String(repeating: "word ", count: 80)
        #expect(!PlanWordingValidator.isValid(PlanWording(explanation: long, homeReason: "Back day."), facts: facts()))
    }

    @Test func cleanTidiesTheText() {
        let w = PlanWordingValidator.clean(PlanWording(explanation: "  \"Great work!\nBack day next.\" ", homeReason: "Go!"))
        #expect(w.explanation == "Great work. Back day next.")
        #expect(w.homeReason == "Go.")
    }
}

private final class FakeGenerator: PlanWordingGenerator, @unchecked Sendable {
    let isAvailable: Bool
    var replies: [PlanWording]
    private(set) var calls = 0

    init(available: Bool = true, replies: [PlanWording]) {
        isAvailable = available
        self.replies = replies
    }

    func generate(facts: PlanFacts) async throws -> PlanWording {
        calls += 1
        guard !replies.isEmpty else { throw CancellationError() }
        return replies.removeFirst()
    }
}

@Suite("AI planner: service")
@MainActor
struct AIPlannerServiceTests {
    let good = PlanWording(explanation: "Push day covered your chest, so your back is next.", homeReason: "Back is fresh today.")
    let invented = PlanWording(explanation: "Try 70 kg on the row.", homeReason: "Back day.")

    @Test func cachesValidWording() async {
        let fake = FakeGenerator(replies: [good])
        let ai = AIPlanner(generator: fake, defaults: nil)
        await ai.prepare(facts())
        #expect(ai.wording(for: facts()) == good)
        await ai.prepare(facts())
        #expect(fake.calls == 1)   // cached: no second call
    }

    @Test func retriesOnceThenKeepsTheTemplate() async {
        let fake = FakeGenerator(replies: [invented, invented, good])
        let ai = AIPlanner(generator: fake, defaults: nil)
        await ai.prepare(facts())
        #expect(ai.wording(for: facts()) == nil)
        #expect(fake.calls == 2)
        await ai.prepare(facts())
        #expect(fake.calls == 2)   // failed facts aren't retried on every render
    }

    @Test func secondTryCanPass() async {
        let fake = FakeGenerator(replies: [invented, good])
        let ai = AIPlanner(generator: fake, defaults: nil)
        await ai.prepare(facts())
        #expect(ai.wording(for: facts()) == good)
    }

    @Test func unavailableModelIsNeverCalled() async {
        let fake = FakeGenerator(available: false, replies: [good])
        let ai = AIPlanner(generator: fake, defaults: nil)
        await ai.prepare(facts())
        #expect(fake.calls == 0)
        #expect(ai.wording(for: facts()) == nil)
    }

    @Test func errorsFallBackToTheTemplate() async {
        let fake = FakeGenerator(replies: [])
        let ai = AIPlanner(generator: fake, defaults: nil)
        await ai.prepare(facts())
        #expect(ai.wording(for: facts()) == nil)
    }

    @Test func persistsAcrossLaunches() async throws {
        let defaults = try #require(UserDefaults(suiteName: "AIPlannerTests"))
        defaults.removePersistentDomain(forName: "AIPlannerTests")
        let first = AIPlanner(generator: FakeGenerator(replies: [good]), defaults: defaults)
        await first.prepare(facts())
        let second = AIPlanner(generator: FakeGenerator(available: false, replies: []), defaults: defaults)
        #expect(second.wording(for: facts()) == good)
        defaults.removePersistentDomain(forName: "AIPlannerTests")
    }
}
