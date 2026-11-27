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

    static let target = WatchSetTarget(workoutStart: Date(timeIntervalSince1970: 1_800_000_000), exerciseOrder: 0,
                                       exerciseName: "Bench press", setIndex: 3)
    static let sent = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: [
        WatchCommand.logSet(weightKg: 45, reps: 8, target: target), .logSet(weightKg: nil, reps: 12, target: target),
        .logSet(weightKg: 40, reps: 10, voice: true, target: target), .skipRest(sentAt: sent),
        .adjustRest(seconds: 15, sentAt: sent), .heartRate(bpm: 128, at: sent), .activeEnergy(kcal: 410),
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

    @Test func stateCarriesTarget() {
        var withTarget = state
        withTarget.target = Self.target
        #expect(WatchWire.state(from: WatchWire.encode(withTarget))?.target == Self.target)
    }

    // MARK: Late commands

    @Test func restCommandsExpire() {
        #expect(WatchCommandCheck.isFresh(Self.sent, now: Self.sent.addingTimeInterval(5)))
        #expect(WatchCommandCheck.isFresh(Self.sent, now: Self.sent.addingTimeInterval(-2)))   // Watch clock a bit ahead
        #expect(!WatchCommandCheck.isFresh(Self.sent, now: Self.sent.addingTimeInterval(60)))
    }

    @Test func logForAnotherWorkoutIsDropped() {
        #expect(WatchCommandCheck.isSameWorkout(Self.target, workoutStart: Self.target.workoutStart))
        #expect(!WatchCommandCheck.isSameWorkout(Self.target, workoutStart: Self.target.workoutStart.addingTimeInterval(3600)))
    }

    @Test func entryIsFoundByPositionThenName() {
        let entries: [(order: Int, name: String)] = [(0, "Bench press"), (1, "Squat")]
        #expect(WatchCommandCheck.entryIndex(for: Self.target, in: entries) == 0)
        // Reordered on the iPhone meanwhile: still found by its name.
        #expect(WatchCommandCheck.entryIndex(for: Self.target, in: [(0, "Squat"), (1, "Bench press")]) == 1)
        // Removed, or two entries with that name and neither in place: ignored.
        #expect(WatchCommandCheck.entryIndex(for: Self.target, in: [(0, "Squat")]) == nil)
        #expect(WatchCommandCheck.entryIndex(for: Self.target, in: [(1, "Bench press"), (2, "Bench press")]) == nil)
    }

    @Test func setPlacement() {
        let sets: [(index: Int, isCompleted: Bool)] = [(1, true), (2, true), (3, false)]
        #expect(WatchCommandCheck.placement(for: 3, in: sets) == .fill)
        #expect(WatchCommandCheck.placement(for: 2, in: sets) == .drop)      // already ticked on the iPhone
        #expect(WatchCommandCheck.placement(for: 4, in: [(1, true), (2, true), (3, true)]) == .append)
        #expect(WatchCommandCheck.placement(for: 6, in: sets) == .drop)      // a set that no longer exists
        #expect(WatchCommandCheck.placement(for: 1, in: []) == .append)
    }
}
