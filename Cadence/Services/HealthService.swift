//  HealthService.swift
//  Phase 2: authorization only. Phase 9 adds heart-rate / energy queries and saving HKWorkout.
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
}
