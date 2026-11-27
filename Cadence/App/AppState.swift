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
    /// Saving workouts to Health and reading heart rate / energy.
    let health = HealthService()
    /// Last 28 days of resting heart rate, for the fatigue score (empty without Health).
    private(set) var restingHeartRate: [HeartRateSample] = []

    var watch: WatchSyncService { permissions.watch }
    /// Full-screen RestTimer from the Active rest bar.
    var isRestTimerPresented = false

    init() {
        let notifications = NotificationService()
        self.notifications = notifications
        self.rest = RestTimerService(effects: notifications)
        notifications.onOpenWorkout = { [weak self] in self?.openRunningWorkout() }
        permissions.watch.onCommand = { [weak self] in self?.handle($0) }
        permissions.watch.activate()
        observeForWatch()
    }

    // MARK: Apple Watch

    /// Pushes the workout state to the Watch now and again whenever anything it reads changes
    /// (the session, its sets, the rest timer).
    private func observeForWatch() {
        let state = withObservationTracking {
            // Read the connection too, so the state is resent once the Watch connects.
            _ = (watch.isActivated, watch.isConnected)
            return watchState()
        } onChange: {
            Task { @MainActor [weak self] in self?.observeForWatch() }
        }
        watch.push(state)
    }

    func watchState() -> WatchWorkoutState {
        guard let session, !session.workout.isGone else { return .inactive }
        let profile = (try? session.workout.modelContext?.fetch(FetchDescriptor<UserProfile>()))?.first { !$0.isGone }
        let unit = profile?.unit ?? .kg
        var state = WatchWorkoutState(isActive: true, workoutName: session.workout.displayName, startedAt: session.workout.start)
        state.unit = unit
        state.voiceLogging = profile?.voiceLogging ?? true
        state.weightStepKg = WeightFormatter.kilograms(from: WeightFormatter.step(for: unit), in: unit)
        if let entry = session.currentEntry, !entry.isGone {
            let sets = entry.orderedSets
            let active = session.activeSet(in: entry)
            let index = active?.index ?? ((sets.map(\.index).max() ?? 0) + 1)
            let above = sets.last { $0.index < index && $0.isCompleted }
            let previous = session.previousSet(for: entry, index: index)
            state.exerciseName = entry.exerciseName
            state.setNumber = index
            state.totalSets = max(sets.count, index)
            state.tracksWeight = (entry.exercise?.trackingType ?? .weightReps) == .weightReps
            state.weightKg = active?.weightKg ?? above?.weightKg ?? previous?.weightKg
            state.reps = active?.reps ?? above?.reps ?? previous?.reps ?? entry.repRange?.lowerBound
            state.target = WatchSetTarget(workoutStart: session.workout.start, exerciseOrder: entry.order,
                                          exerciseName: entry.exerciseName, setIndex: index)
        }
        if let end = rest.endDate {
            state.restEnd = end
            state.restTotalSeconds = rest.totalSeconds
            if let info = rest.info {
                let parts = [info.nextSet.map { "set \($0)" }, info.upNextValue].compactMap { $0 }
                state.nextText = parts.isEmpty ? nil : "Next: " + parts.joined(separator: " · ")
            }
        }
        return state
    }

    /// A set logged or a rest change on the Watch. Commands can arrive late (queued while the
    /// iPhone was out of reach), so each is checked against what it was meant for first.
    private func handle(_ command: WatchCommand) {
        switch command {
        case .logSet(let weightKg, let reps, let voice, let target):
            guard let session, !session.workout.isGone,
                  WatchCommandCheck.isSameWorkout(target, workoutStart: session.workout.start) else { return }
            let entries = session.entries
            guard let position = WatchCommandCheck.entryIndex(
                for: target, in: entries.map { (order: $0.order, name: $0.exerciseName) }) else { return }
            let entry = entries[position]
            let placement = WatchCommandCheck.placement(
                for: target.setIndex, in: entry.orderedSets.map { (index: $0.index, isCompleted: $0.isCompleted) })
            switch placement {
            case .drop: return
            case .append: session.addSet(to: entry)
            case .fill: break
            }
            guard let set = entry.orderedSets.first(where: { $0.index == target.setIndex }) else { return }
            if (entry.exercise?.trackingType ?? .weightReps) == .weightReps { set.weightKg = weightKg }
            set.reps = reps
            guard session.toggleComplete(set, in: entry, source: voice ? .voice : .watch) else { return }
            let profile = (try? session.workout.modelContext?.fetch(FetchDescriptor<UserProfile>()))?.first { !$0.isGone }
            didComplete(set, in: entry, session: session, profile: profile, unit: profile?.unit ?? .kg)
        case .skipRest(let sentAt):
            guard WatchCommandCheck.isFresh(sentAt) else { return }
            rest.skip()
        case .adjustRest(let seconds, let sentAt):
            guard WatchCommandCheck.isFresh(sentAt) else { return }
            rest.adjust(by: seconds)
        case .heartRate, .activeEnergy:
            break   // kept by WatchSyncService
        }
    }

    // MARK: Apple Health

    /// Resting heart rate for the fatigue score. Called at launch and when the app comes back.
    func refreshHealth() async {
        restingHeartRate = await health.restingHeartRate()
    }

    /// After a workout is saved: heart rate and energy from Health (or the Watch's live samples),
    /// then the workout itself is saved to Health.
    private func recordHealth(for workout: Workout) {
        let start = workout.start
        let end = workout.end ?? .now
        let liveHeartRate = HeartRateStats.summary(watch.workoutHeartRates)
        let liveEnergy = watch.liveEnergyKcal
        watch.resetLiveData()
        Task { @MainActor in
            // The Watch's own workout-session samples (every 5 s) first: Health may hold only
            // sparse background readings for this span, since the Watch discards its workout.
            var heartRate = liveHeartRate
            if heartRate == nil { heartRate = await health.heartRate(from: start, to: end) }
            let healthEnergy = await health.activeEnergy(from: start, to: end)
            if !workout.isGone {
                if let heartRate {
                    workout.avgHR = heartRate.average
                    workout.maxHR = heartRate.max
                }
                if let energy = healthEnergy ?? liveEnergy { workout.activeEnergy = energy }
                try? workout.modelContext?.save()
            }
            // Only add the Watch's energy when Health doesn't already have it, so it isn't counted twice.
            try? await health.saveWorkout(start: start, end: end, activeEnergyKcal: healthEnergy == nil ? liveEnergy : nil)
        }
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
            didStartSession()
        }
        finishedWorkout = nil
        isWorkoutPresented = true
    }

    /// NextSession → "Start this workout".
    func startWorkout(plan: SessionPlan, in context: ModelContext) {
        if session == nil {
            session = WorkoutSession.start(plan: plan, in: context)
            didStartSession()
        }
        finishedWorkout = nil
        isWorkoutPresented = true
    }

    func repeatWorkout(_ past: Workout, in context: ModelContext) {
        if session == nil {
            session = WorkoutSession.repeating(past, in: context)
            didStartSession()
        }
        finishedWorkout = nil
        isWorkoutPresented = true
    }

    /// A new workout: forget the last one's live data and open the Watch app, so live heart
    /// rate starts without the user having to open it on their wrist.
    private func didStartSession() {
        watch.resetLiveData()
        if watch.isConnected {
            Task { await health.startWatchApp() }
        }
    }

    func finishWorkout() {
        guard let session else { return }
        rest.stop()
        isRestTimerPresented = false
        finishedWorkout = session.finish()
        self.session = nil
        if let finishedWorkout { recordHealth(for: finishedWorkout) }
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
        if let saved { recordHealth(for: saved) }
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
