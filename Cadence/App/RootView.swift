//  RootView.swift
//  Native TabView (Liquid Glass on iOS 26). Tab names and order from the boards.
//  Phase 2 adds the onboarding gate; phase 3 adds the minimised-workout bar.

import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        TabView(selection: $appState.selectedTab) {
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

#Preview {
    RootView()
        .environment(AppState())
        .modelContainer(try! CadenceStore.makeContainer(inMemory: true))
        .preferredColorScheme(.dark)
}
