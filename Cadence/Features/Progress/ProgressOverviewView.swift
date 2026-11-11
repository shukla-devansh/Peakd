//  ProgressOverviewView.swift
//  Placeholder. Built in phase 8 (Progress board; named to avoid shadowing SwiftUI.ProgressView).

import SwiftUI

struct ProgressOverviewView: View {
    var body: some View {
        PlaceholderScreen(title: "Progress", systemImage: "chart.bar", phase: 8)
    }
}

#Preview {
    ProgressOverviewView()
        .preferredColorScheme(.dark)
}
