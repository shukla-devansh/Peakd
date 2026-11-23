import Foundation
import Testing
@testable import Cadence

@Suite("Watch messages")
struct WatchMessagesTests {
    let state = WatchWorkoutState(isActive: true, workoutName: "Push day", startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                  exerciseName: "Bench press", setNumber: 3, totalSets: 4, weightKg: 42.5, reps: 10,
                                  restEnd: Date(timeIntervalSince1970: 1_800_000_090), restTotalSeconds: 90,
                                  nextText: "Next: set 4 · 42.5 × 10")

    @Test func stateRoundTrips() {
        #expect(WatchWire.state(from: WatchWire.encode(state)) == state)
    }

    @Test(arguments: [
        WatchCommand.logSet(weightKg: 45, reps: 8), .logSet(weightKg: nil, reps: 12), .skipRest,
        .adjustRest(seconds: 15), .heartRate(bpm: 128, at: Date(timeIntervalSince1970: 1_800_000_000)), .activeEnergy(kcal: 410),
    ])
    func commandsRoundTrip(_ command: WatchCommand) {
        #expect(WatchWire.command(from: WatchWire.encode(command)) == command)
    }

    @Test func wrongPayloadsAreIgnored() {
        #expect(WatchWire.state(from: [:]) == nil)
        #expect(WatchWire.command(from: WatchWire.encode(state)) == nil)
        #expect(WatchWire.state(from: ["state": Data("nope".utf8)]) == nil)
    }

    @Test func setText() {
        #expect(state.setText == "42.5 kg × 10")
        var bodyweight = state
        bodyweight.tracksWeight = false
        #expect(bodyweight.setText == "10 reps")
        var pounds = state
        pounds.unit = .lb
        pounds.weightKg = WeightFormatter.kilograms(from: 95, in: .lb)
        #expect(pounds.setText == "95 lb × 10")
        #expect(WatchWorkoutState.inactive.setText == "–")
    }

    @Test func resting() {
        #expect(state.isResting(at: Date(timeIntervalSince1970: 1_800_000_050)))
        #expect(!state.isResting(at: Date(timeIntervalSince1970: 1_800_000_091)))
        #expect(!WatchWorkoutState.inactive.isResting(at: .now))
    }

    @Test func heartRateSummary() {
        let s = HeartRateStats.summary([100, 120, 140])
        #expect(s?.average == 120)
        #expect(s?.max == 140)
        #expect(HeartRateStats.summary([]) == nil)
    }
}
