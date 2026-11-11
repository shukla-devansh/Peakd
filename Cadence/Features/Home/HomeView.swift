//  HomeView.swift
//  Placeholder. Built in phase 3 (Home and HomeEmpty boards).

import SwiftUI

struct HomeView: View {
    var body: some View {
        PlaceholderScreen(title: "Home", systemImage: "house", phase: 3)
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}
