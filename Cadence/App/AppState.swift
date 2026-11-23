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
    let notifications: NotificationService
    let rest: RestTimerService
    /// Foundation Models wording for the planner's text (falls back to the templates).
    let ai = AIPlanner()
    /// Full-screen RestTimer from the Active rest bar.
    var isRestTimerPresented = false

    init() {
        let notifications = NotificationService()
        self.notifications = notifications
        self.rest = RestTimerService(effects: notifications)
        notifications.onOpenWorkout = { [weak self] in self?.openRunningWorkout() }
    }

    /// Notification tap or Live Activity link.
    func openRunningWorkout() {
        guard session != nil else { return }
        finishedWorkout = nil
        isWorkoutPresented = true
    }

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

    /// NextSession → "Start this workout".
    func startWorkout(plan: SessionPlan, in context: ModelContext) {
        if session == nil {
            session = WorkoutSession.start(plan: plan, in: context)
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
        rest.stop()
        isRestTimerPresented = false
        finishedWorkout = session.finish()
        self.session = nil
        if finishedWorkout == nil { isWorkoutPresented = false }
    }

    func cancelWorkout() {
        rest.stop()
        isRestTimerPresented = false
        session?.cancel()
        session = nil
        isWorkoutPresented = false
    }

    /// NextSession reached from the Summary: leave the Summary before starting the next workout.
    func closeSummaryIfShown() {
        finishedWorkout = nil
    }

    /// Summary → Done.
    func closeSummary() {
        isWorkoutPresented = false
        finishedWorkout = nil
        selectedTab = .home
    }

    /// Shown on Home (until dismissed) after a forgotten workout was ended automatically.
    struct AutoEndedWorkout: Identifiable {
        let id = UUID()
        let name: String
        let startedAt: Date
        /// When it was saved (the last set); nil when nothing was logged and it was discarded.
        let savedAt: Date?
        let workout: Workout?
    }

    var autoEnded: AutoEndedWorkout?

    /// Ends the running workout if nothing happened for 12 hours: saved at the last set,
    /// or discarded if no set was ticked. Called at launch and whenever the app comes back.
    func endStaleWorkout(now: Date = .now) {
        guard let session, !session.workout.isGone else { return }
        let last = session.lastActivity
        guard WorkoutSession.isStale(lastActivity: last, now: now) else { return }
        let name = session.workout.displayName
        let start = session.workout.start
        rest.stop()
        isRestTimerPresented = false
        let saved = session.finish(at: last)
        self.session = nil
        isWorkoutPresented = false
        finishedWorkout = nil
        autoEnded = AutoEndedWorkout(name: name, startedAt: start, savedAt: saved == nil ? nil : last, workout: saved)
        selectedTab = .home   // where the note is
    }

    /// "View summary" on the auto-end note.
    func showAutoEndedSummary() {
        guard let workout = autoEnded?.workout, !workout.isGone else { autoEnded = nil; return }
        autoEnded = nil
        finishedWorkout = workout
        isWorkoutPresented = true
    }

    /// Picks up a workout left running when the app was killed.
    func resumeUnfinishedWorkout(in context: ModelContext) {
        guard session == nil else { return }
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.end == nil },
                                                  sortBy: [SortDescriptor(\.start, order: .reverse)])
        descriptor.fetchLimit = 1
        if let workout = try? context.fetch(descriptor).first {
            session = WorkoutSession(workout: workout, context: context)
            endStaleWorkout()
        } else {
            rest.stop()   // a rest or Live Activity left over from a workout that no longer exists
        }
    }

    /// Before "Delete all data": forget everything that points at models about to be deleted.
    func reset() {
        rest.stop()
        isRestTimerPresented = false
        session = nil
        finishedWorkout = nil
        isWorkoutPresented = false
        selectedTab = .home
    }
}
