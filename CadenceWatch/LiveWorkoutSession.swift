//  LiveWorkoutSession.swift
//  HKWorkoutSession on the Watch, for live heart rate and energy while the iPhone runs a workout.
//  The Watch doesn't save its own workout: the iPhone saves one workout to Health when you finish,
//  so nothing is counted twice.

import HealthKit

final class LiveWorkoutSession: NSObject, @unchecked Sendable {
    var onHeartRate: (@Sendable (Double) -> Void)?
    var onEnergy: (@Sendable (Double) -> Void)?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let lock = NSLock()

    private static let bpm = HKUnit.count().unitDivided(by: .minute())

    func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        Task {
            let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
            let share: Set<HKSampleType> = [HKObjectType.workoutType()]
            try? await store.requestAuthorization(toShare: share, read: read)

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
            guard let session = try? HKWorkoutSession(healthStore: store, configuration: configuration) else { return }
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            builder.delegate = self
            lock.withLock {
                self.session = session
                self.builder = builder
            }
            session.startActivity(with: .now)
            try? await builder.beginCollection(at: .now)
        }
    }

    func stop() {
        let (session, builder) = lock.withLock { () -> (HKWorkoutSession?, HKLiveWorkoutBuilder?) in
            defer { self.session = nil; self.builder = nil }
            return (self.session, self.builder)
        }
        guard let session, let builder else { return }
        session.end()
        Task {
            try? await builder.endCollection(at: .now)
            builder.discardWorkout()
        }
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
