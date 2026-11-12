import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
final class FakeRestEffects: RestTimerEffects {
    var scheduled: [(Date, RestInfo)] = []
    var cancelCount = 0
    var activities: [(endDate: Date, total: Int, isOver: Bool)] = []
    var ended = 0

    func scheduleRestOverNotification(at date: Date, info: RestInfo) { scheduled.append((date, info)) }
    func cancelRestOverNotification() { cancelCount += 1 }
    func showActivity(info: RestInfo, endDate: Date, totalSeconds: Int, isOver: Bool) {
        activities.append((endDate, totalSeconds, isOver))
    }
    func endActivity() { ended += 1 }
}

@MainActor
@Suite("Rest timer")
struct RestTimerTests {
    var clock = Date(timeIntervalSince1970: 1_000_000)
    let effects = FakeRestEffects()
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: "RestTimerTests-\(UUID().uuidString)")!
    }

    static let info = RestInfo(workoutName: "Push day", workoutStart: .now, exerciseName: "Bench press", afterSet: 3,
                               nextExercise: "Bench press", nextSet: 4, nextWeight: "42.5", unitSymbol: "kg",
                               nextReps: 10, lastTime: "40 × 9")

    func makeService(now: @escaping () -> Date) -> RestTimerService {
        RestTimerService(effects: effects, now: now, defaults: defaults)
    }

    @Test("Start counts toward an end date and schedules the alert")
    func start() {
        let t0 = clock
        let rest = makeService { t0 }
        rest.start(seconds: 90, info: Self.info, alerts: true)
        #expect(rest.endDate == t0.addingTimeInterval(90))
        #expect(rest.remaining(at: t0.addingTimeInterval(30)) == 60)
        #expect(abs(rest.progress(at: t0.addingTimeInterval(45)) - 0.5) < 0.001)
        #expect(effects.scheduled.count == 1 && effects.scheduled[0].0 == t0.addingTimeInterval(90))
        #expect(effects.activities.last?.isOver == false)
    }

    @Test("No notification when alerts are off")
    func alertsOff() {
        let t0 = clock
        let rest = makeService { t0 }
        rest.start(seconds: 60, info: Self.info, alerts: false)
        #expect(effects.scheduled.isEmpty)
        #expect(effects.activities.count == 1)
    }

    @Test("+15 and −15 move the end date and reschedule")
    func adjust() {
        var now = clock
        let rest = makeService { now }
        rest.start(seconds: 120, info: Self.info, alerts: true)
        now = clock.addingTimeInterval(48)                      // 72 s left, like the board
        rest.adjust(by: 15)
        #expect(rest.remaining(at: now) == 87)
        #expect(rest.totalSeconds == 135)
        rest.adjust(by: -15)
        #expect(rest.remaining(at: now) == 72)
        #expect(rest.totalSeconds == 120)
        #expect(effects.scheduled.count == 3)
    }

    @Test("−15 past zero ends the rest like Skip")
    func adjustToZero() {
        var now = clock
        let rest = makeService { now }
        rest.start(seconds: 60, info: Self.info, alerts: true)
        now = clock.addingTimeInterval(50)
        rest.adjust(by: -15)
        #expect(!rest.isRunning)
        #expect(effects.activities.last?.isOver == true)
        #expect(rest.finishedCount == 0)                        // skipping doesn't buzz
    }

    @Test("Skip cancels the alert and shows Rest over on the Live Activity")
    func skip() {
        let t0 = clock
        let rest = makeService { t0 }
        rest.start(seconds: 60, info: Self.info, alerts: true)
        let cancels = effects.cancelCount
        rest.skip()
        #expect(!rest.isRunning)
        #expect(effects.cancelCount == cancels + 1)
        #expect(effects.activities.last?.isOver == true)
    }

    @Test("Reaching zero triggers the haptic only with alerts on")
    func zero() {
        var now = clock
        let rest = makeService { now }
        rest.start(seconds: 30, info: Self.info, alerts: true)
        now = clock.addingTimeInterval(31)
        rest.handleZero()
        #expect(rest.finishedCount == 1)
        #expect(!rest.isRunning)

        now = clock.addingTimeInterval(100)
        rest.start(seconds: 30, info: Self.info, alerts: false)
        now = clock.addingTimeInterval(131)
        rest.handleZero()
        #expect(rest.finishedCount == 1)
    }

    @Test("A rest survives relaunch until its end date")
    func persistence() {
        let t0 = clock
        let first = makeService { t0 }
        first.start(seconds: 90, info: Self.info, alerts: true)

        let relaunched = makeService { t0.addingTimeInterval(20) }
        #expect(relaunched.isRunning)
        #expect(relaunched.remaining(at: t0.addingTimeInterval(20)) == 70)
        #expect(relaunched.info == Self.info)

        let tooLate = makeService { t0.addingTimeInterval(200) }
        #expect(!tooLate.isRunning)
    }

    @Test("Stop ends the Live Activity")
    func stop() {
        let t0 = clock
        let rest = makeService { t0 }
        rest.start(seconds: 60, info: Self.info, alerts: true)
        rest.stop()
        #expect(effects.ended == 1)
        #expect(!rest.isRunning)
    }

    @Test("Notification and screen wording")
    func wording() {
        #expect(Self.info.notificationBody == "Bench press, set 4: 42.5 kg × 10. Last time 40 × 9.")
        #expect(Self.info.upNextTitle == "Bench press · set 4")
        #expect(Self.info.upNextValue == "42.5 × 10")
        #expect(Self.info.subtitle == "Bench press · after set 3")
    }

    @Test("Rest info comes from the next open set; none after the last set")
    func restInfoFromSession() throws {
        let container = try CadenceStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let bench = Exercise(name: "Bench press", primaryMuscle: .chest, equipment: .barbell, defaultRestSeconds: 120)
        context.insert(bench)
        let session = WorkoutSession.start(routine: nil, in: context)
        session.add([bench])
        let entry = session.entries[0]
        while entry.sets.count > 2 { session.removeSet(entry.orderedSets.last!, from: entry) }
        let first = entry.orderedSets[0], second = entry.orderedSets[1]
        first.weightKg = 40; first.reps = 10
        second.weightKg = 42.5
        session.toggleComplete(first, in: entry)

        let info = try #require(session.restInfo(after: first, in: entry, unit: .kg))
        #expect(info.nextSet == 2 && info.nextWeight == "42.5")
        #expect(session.restSeconds(for: entry, defaultRest: 90) == 120)

        second.reps = 8
        session.toggleComplete(second, in: entry)
        #expect(session.restInfo(after: second, in: entry, unit: .kg) == nil)
    }
}
