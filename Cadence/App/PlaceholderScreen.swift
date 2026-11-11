//  PlaceholderScreen.swift
//  Temporary tab content until each screen's phase lands. Delete once every tab is built.

import SwiftUI

struct PlaceholderScreen: View {
    let title: String
    let systemImage: String
    let phase: Int

    var body: some View {
        NavigationStack {
            ScrollView {
                EmptyStateCard(
                    systemImage: systemImage,
                    title: title,
                    message: "This screen is built in phase \(phase)."
                )
                .padding(.horizontal, Space.screenMargin)
                .padding(.top, Space.xs)
            }
            .cadScreenBackground()
            .navigationTitle(title)
        }
    }
}

#Preview {
    PlaceholderScreen(title: "Progress", systemImage: "chart.bar", phase: 8)
        .preferredColorScheme(.dark)
}
