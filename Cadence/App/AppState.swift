//  AppState.swift
//  App-wide UI state shared through the environment.

import Observation

enum AppTab: Hashable, CaseIterable {
    case home, workout, exercises, progress, profile
}

@Observable
@MainActor
final class AppState {
    var selectedTab: AppTab = .home
}
