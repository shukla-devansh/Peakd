//  EmptyStateCard.swift
//  Dashed card from HomeEmpty. Every list uses one when it has nothing to show.

import SwiftUI

struct EmptyStateCard: View {
    var systemImage: String = "dumbbell"
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Space.xs) {
            IconTile(systemImage: systemImage, side: 48, fill: Palette.surface)
            Text(title)
                .font(.cadHeadline)
                .foregroundStyle(Palette.text)
            Text(message)
                .font(.cadFootnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Font.cadSubhead.weight(.semibold))
                    .foregroundStyle(Palette.accentText)
                    .frame(minHeight: Size.minTouch)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, Space.lg)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .accessibilityElement(children: .contain)
    }
}

#Preview("Empty state") {
    EmptyStateCard(
        title: "No workouts yet",
        message: "Finished workouts show here with time and total volume. Progress charts fill in after your first week.",
        actionTitle: "Browse routines"
    ) {}
    .previewSurface()
}
