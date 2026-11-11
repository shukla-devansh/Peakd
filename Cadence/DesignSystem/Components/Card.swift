//  Card.swift
//  Card surfaces from the boards: standard card (surface + line border) and the AI callout ("Why this plan").

import SwiftUI

extension View {
    /// Surface fill, 1 pt line border, 16 pt radius, full width.
    func cadCard(padding: CGFloat = Space.cardPadding, radius: CGFloat = Radius.card) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            )
    }

    /// Accent-tinted card for AI explanations.
    func cadCallout(padding: CGFloat = Space.cardPadding, radius: CGFloat = Radius.card) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.calloutFill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.calloutBorder, lineWidth: 1)
            )
    }

    /// Screen background that fills behind the content. Use on every screen root.
    func cadScreenBackground() -> some View {
        self.background(Palette.background.ignoresSafeArea())
    }
}

#Preview("Cards") {
    VStack(spacing: Space.sm) {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text("Push day").font(.cadTitle)
            Text("5 exercises · about 55 min").font(.cadSubhead).foregroundStyle(Palette.textSecondary)
        }
        .cadCard()

        VStack(alignment: .leading, spacing: 6) {
            Text("Why this plan").font(.cadHeadline)
            Text("Back was last trained 5 days ago and you hit the top of the range on rows.")
                .font(.cadSubhead)
                .foregroundStyle(Palette.textSecondary)
        }
        .cadCallout(padding: Space.sm)
    }
    .previewSurface()
}
