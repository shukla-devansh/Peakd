//  RadioCard.swift
//  Goal picker card from the Onboarding board.

import SwiftUI

struct RadioCard: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.cadHeadline)
                        .foregroundStyle(Palette.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(.cadFootnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Palette.accentText : Palette.outline, lineWidth: isSelected ? 2 : 1.5)
                    Circle()
                        .fill(isSelected ? Palette.accentText : .clear)
                        .frame(width: 10, height: 10)
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(minHeight: 60)
            .background(isSelected ? Palette.calloutFill : Palette.surface,
                        in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .strokeBorder(isSelected ? Palette.accentText : Palette.line, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .animation(reduceMotion ? nil : Motion.quick, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("Radio cards") {
    @Previewable @State var goal = TrainingGoal.strength
    VStack(spacing: Space.xs) {
        ForEach(TrainingGoal.allCases) { option in
            RadioCard(title: option.title, subtitle: option.subtitle, isSelected: goal == option) {
                goal = option
            }
        }
    }
    .previewSurface()
}
