//  RootView.swift
//  No profile → onboarding. Otherwise the native TabView (Liquid Glass on iOS 26).
//  A running workout shows as a bar above the tab bar and opens full screen.

import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if profiles.isEmpty {
                OnboardingFlow()
                    .transition(.opacity)
            } else {
                tabs
                    .transition(.opacity)
            }
        }
        // Fade in the tabs after onboarding; no fade on the way back, so no view keeps
        // reading a profile that "Delete all data" just removed.
        .animation(reduceMotion || profiles.isEmpty ? nil : Motion.slow, value: profiles.isEmpty)
        // Haptic at the end of rest, wherever the user is in the app (only counted with alerts on).
        .sensoryFeedback(.success, trigger: appState.rest.finishedCount)
        .onOpenURL { url in
            if url == CadenceLinks.workout { appState.openRunningWorkout() }
        }
    }

    private var tabs: some View {
        @Bindable var appState = appState

        return tabView
            .workoutAccessory(session: appState.session, restEnd: appState.rest.endDate) {
                appState.isWorkoutPresented = true
            }
            .fullScreenCover(isPresented: $appState.isWorkoutPresented) {
                WorkoutFlowView()
                    .environment(appState)
            }
            .task { appState.resumeUnfinishedWorkout(in: context) }
    }

    private var tabView: some View {
        @Bindable var appState = appState

        return TabView(selection: $appState.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeView()
            }
            Tab("Workout", systemImage: "dumbbell", value: AppTab.workout) {
                StartWorkoutView()
            }
            Tab("Exercises", systemImage: "list.bullet", value: AppTab.exercises) {
                ExerciseLibraryView()
            }
            Tab("Progress", systemImage: "chart.bar", value: AppTab.progress) {
                ProgressOverviewView()
            }
            Tab("Profile", systemImage: "person", value: AppTab.profile) {
                ProfileView()
            }
        }
        .tint(Palette.accentText)
    }
}

private extension View {
    /// The minimised workout above the tab bar (iOS 26 bottom accessory). Only attached while a
    /// workout runs: an empty accessory would still draw its capsule.
    @ViewBuilder
    func workoutAccessory(session: WorkoutSession?, restEnd: Date?, open: @escaping () -> Void) -> some View {
        if let session, !session.workout.isGone {
            tabViewBottomAccessory {
                MiniWorkoutBar(workoutName: session.workout.displayName,
                               startDate: session.workout.start, restEndDate: restEnd,
                               chrome: false, action: open)
            }
        } else {
            self
        }
    }
}

#Preview("Signed up") {
    RootView()
        .environment(AppState())
        .modelContainer(PreviewData.container())
        .preferredColorScheme(.dark)
}

#Preview("First launch") {
    RootView()
        .environment(AppState())
        .modelContainer(PreviewData.container(withProfile: false))
        .preferredColorScheme(.dark)
}
