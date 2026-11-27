//  LiveWorkoutSession.swift
//  HKWorkoutSession on the Watch, for live heart rate and energy while the iPhone runs a workout.
//  The Watch doesn't save its own workout: the iPhone saves one workout to Health when you finish,
//  so nothing is counted twice.
//
//  start() and stop() can be called in any order and any number of times. start() waits for
//  authorization before it creates the session, so every start and stop bumps `generation`; a
//  start that finds the generation changed while it waited gives up instead of starting a
//  session nothing would ever end.

import HealthKit

final class LiveWorkoutSession: NSObject, @unchecked Sendable {
    var onHeartRate: (@Sendable (Double) -> Void)?
    var onEnergy: (@Sendable (Double) -> Void)?
    /// The session ended or failed on its own (not through stop()): e.g. the system ended it.
    var onEnd: (@Sendable () -> Void)?

    private let store = HKHealthStore()
    private let lock = NSLock()
    // Guarded by `lock`.
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var wantsRunning = false
    private var generation = 0

    private static let bpm = HKUnit.count().unitDivided(by: .minute())


    /// True from start() until stop() or the session ending.
    var isRunning: Bool { lock.withLock { wantsRunning } }

    /// Plain values rather than an HKWorkoutConfiguration, so nothing non-Sendable crosses into the Task.
    func start(activityType: HKWorkoutActivityType = .traditionalStrengthTraining,
               locationType: HKWorkoutSessionLocationType = .indoor) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let ticket: Int? = lock.withLock {
            guard !wantsRunning else { return nil }   // already running or starting
            wantsRunning = true
            generation += 1
            return generation
        }
        guard let ticket else { return }

        Task {
            let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
            let share: Set<HKSampleType> = [HKObjectType.workoutType()]
            try? await store.requestAuthorization(toShare: share, read: read)

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = activityType
            configuration.locationType = locationType
            guard let session = try? HKWorkoutSession(healthStore: store, configuration: configuration) else {
                lock.withLock { if generation == ticket { wantsRunning = false } }
                return
            }
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            builder.delegate = self
            session.delegate = self

            // Start only if no stop() came in while authorization was pending. Starting under the
            // lock means a stop() can't slip in between the check and the start.
            let started = lock.withLock { () -> Bool in
                guard generation == ticket, wantsRunning else { return false }
                self.session = session
                self.builder = builder
                session.startActivity(with: .now)
                return true
            }
            guard started else { return }
            try? await builder.beginCollection(at: .now)
        }
    }

    func stop() {
        let (session, builder) = lock.withLock { () -> (HKWorkoutSession?, HKLiveWorkoutBuilder?) in
            wantsRunning = false
            generation += 1
            defer { self.session = nil; self.builder = nil }
            return (self.session, self.builder)
        }
        guard let session else { return }
        session.end()
        Task {
            try? await builder?.endCollection(at: .now)
            builder?.discardWorkout()
        }
    }

    /// After the Watch app was relaunched mid-workout (crash or system kill), takes the running
    /// session back. `completion(true)` when one was recovered.
    func recover(completion: @escaping @Sendable (Bool) -> Void) {
        store.recoverActiveWorkoutSession { [self] session, _ in
            guard let session else { completion(false); return }
            let builder = session.associatedWorkoutBuilder()
            builder.delegate = self
            session.delegate = self
            let adopted = lock.withLock { () -> Bool in
                guard self.session == nil else { return false }
                self.session = session
                self.builder = builder
                wantsRunning = true
                generation += 1
                return true
            }
            if !adopted {
                // A fresh session was started meanwhile: end the old one.
                session.end()
                builder.discardWorkout()
            }
            completion(adopted)
        }
    }

    /// Forgets `session` if it's still the current one. Returns whether it was.
    private func clear(_ session: HKWorkoutSession) -> Bool {
        lock.withLock {
            guard self.session === session else { return false }
            self.session = nil
            self.builder = nil
            wantsRunning = false
            generation += 1
            return true
        }
    }
}

extension LiveWorkoutSession: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        // stop() clears the session before ending it, so this only fires for an end we didn't ask for.
        guard toState == .ended, clear(workoutSession) else { return }
        onEnd?()
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        guard clear(workoutSession) else { return }
        workoutSession.end()
        onEnd?()
    }
}

extension LiveWorkoutSession: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        if collectedTypes.contains(HKQuantityType(.heartRate)),
           let bpm = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: Self.bpm) {
            onHeartRate?(bpm)
        }
        if collectedTypes.contains(HKQuantityType(.activeEnergyBurned)),
           let kcal = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
            onEnergy?(kcal)
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
