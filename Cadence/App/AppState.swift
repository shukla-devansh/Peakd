//  AppState.swift
//  App-wide UI state and long-lived services, shared through the environment.

import Foundation
import Observation
import SwiftData

enum AppTab: Hashable, CaseIterable {
    case home, workout, exercises, progress, profile
}

@Observable
@MainActor
final class AppState {
    var selectedTab: AppTab = .home
    let permissions = PermissionsService()

    /// The workout in progress, if any (survives minimising).
    private(set) var session: WorkoutSession?
    /// Active workout / Summary full-screen cover.
    var isWorkoutPresented = false
    /// Set right after Finish: the cover shows this workout's Summary.
    var finishedWorkout: Workout?

    /// Starts a workout, or reopens the one already running.
    func startWorkout(routine: Routine?, in context: ModelContext) {
        if session == nil {
            session = WorkoutSession.start(routine: routine, in: context)
        }
        finishedWorkout = nil
        isWorkoutPresented = true
    }

    func repeatWorkout(_ past: Workout, in context: ModelContext) {
        if session == nil {
            session = WorkoutSession.repeating(past, in: context)
        }
        finishedWorkout = nil
        isWorkoutPresented = true
    }

    func finishWorkout() {
        guard let session else { return }
        finishedWorkout = session.finish()
        self.session = nil
        if finishedWorkout == nil { isWorkoutPresented = false }
    }

    func cancelWorkout() {
        session?.cancel()
        session = nil
        isWorkoutPresented = false
    }

    /// Summary → Done.
    func closeSummary() {
        isWorkoutPresented = false
        finishedWorkout = nil
        selectedTab = .home
    }

    /// Picks up a workout left running when the app was killed.
    func resumeUnfinishedWorkout(in context: ModelContext) {
        guard session == nil else { return }
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.end == nil },
                                                  sortBy: [SortDescriptor(\.start, order: .reverse)])
        descriptor.fetchLimit = 1
        if let workout = try? context.fetch(descriptor).first {
            session = WorkoutSession(workout: workout, context: context)
        }
    }

    /// Before "Delete all data": forget everything that points at models about to be deleted.
    func reset() {
        session = nil
        finishedWorkout = nil
        isWorkoutPresented = false
        selectedTab = .home
    }
}
