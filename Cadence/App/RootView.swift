//  RootView.swift
//  No profile → onboarding. Otherwise the native TabView (Liquid Glass on iOS 26).
//  Phase 3 adds the minimised-workout bar.

import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    }

    private var tabs: some View {
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
