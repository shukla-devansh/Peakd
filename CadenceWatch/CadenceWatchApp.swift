//  CadenceWatchApp.swift
//  watchOS companion. Phase 9 builds WatchLiveView, WatchEditSetView and WatchRestView from the Watch board.

import SwiftUI

@main
struct CadenceWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

struct WatchRootView: View {
    var body: some View {
        VStack(spacing: Space.xs) {
            Image(systemName: "dumbbell.fill")
                .font(.title2)
                .foregroundStyle(Palette.accentText)
                .accessibilityHidden(true)
            Text(AppInfo.name)
                .font(.cadHeadline)
                .foregroundStyle(Palette.text)
            Text("Start a workout on your iPhone.")
                .font(.cadFootnote)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .containerBackground(Color.black.gradient, for: .navigation)
    }
}

#Preview {
    WatchRootView()
}
