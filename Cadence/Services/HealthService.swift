//  HealthService.swift
//  Authorization, saving finished workouts, and the reads the app uses: heart rate and active
//  energy for a workout's time span, resting heart rate for the fatigue score.
//  Reads and writes only what docs/PROJECT_GUIDE.md lists.

import HealthKit

@MainActor
final class HealthService {
    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Heart rate and active energy for summaries; resting heart rate for the fatigue score.
    static var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.activeEnergyBurned),
        ]
    }

    /// Finished workouts are saved to Health.
    static var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType()]
    }

    var state: PermissionState {
        get async {
            guard Self.isAvailable else { return .unavailable }
            if store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized {
                return .granted
            }
            // HealthKit never reveals read access. If it won't show the sheet again, the user said no.
            let status = try? await store.statusForAuthorizationRequest(toShare: Self.shareTypes, read: Self.readTypes)
            return status == .shouldRequest ? .notDetermined : .denied
        }
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
    }

    /// True once the user allowed saving workouts (read access is never revealed by HealthKit).
    var canSaveWorkouts: Bool {
        Self.isAvailable && store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    // MARK: Writing

    /// Saves a finished workout as Traditional Strength Training, with its energy when known.
    func saveWorkout(start: Date, end: Date, activeEnergyKcal: Double?) async throws {
        guard canSaveWorkouts, end > start else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)
        if let kcal = activeEnergyKcal, kcal > 0 {
            let sample = HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                          quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                                          start: start, end: end)
            try await builder.addSamples([sample])
        }
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }

    // MARK: Reading

    private static let bpm = HKUnit.count().unitDivided(by: .minute())

    /// Average and peak heart rate between two dates; nil without data or access.
    func heartRate(from start: Date, to end: Date) async -> (average: Double, max: Double)? {
        guard Self.isAvailable else { return nil }
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.heartRate),
                                       predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: [.discreteAverage, .discreteMax]
        )
        guard let stats = try? await descriptor.result(for: store),
              let average = stats.averageQuantity()?.doubleValue(for: Self.bpm),
              let max = stats.maximumQuantity()?.doubleValue(for: Self.bpm) else { return nil }
        return (average, max)
    }

    /// Active energy burned between two dates, in kcal.
    func activeEnergy(from start: Date, to end: Date) async -> Double? {
        guard Self.isAvailable else { return nil }
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.activeEnergyBurned),
                                       predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum
        )
        guard let sum = try? await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: .kilocalorie()),
              sum > 0 else { return nil }
        return sum
    }

    /// Daily resting heart rate for the last `days` days (fatigue score).
    func restingHeartRate(days: Int = 28, now: Date = .now) async -> [HeartRateSample] {
        guard Self.isAvailable else { return [] }
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.restingHeartRate),
                                         predicate: HKQuery.predicateForSamples(withStart: start, end: now))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { HeartRateSample(date: $0.startDate, bpm: $0.quantity.doubleValue(for: Self.bpm)) }
    }
}
