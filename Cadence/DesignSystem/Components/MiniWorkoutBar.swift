//  MiniWorkoutBar.swift
//  Shown above the tab bar while a minimised workout runs: "Push day · 42:18 · Rest 1:12". Tap reopens Active.
//  Times count from dates, so the bar stays correct after backgrounding.

import SwiftUI

struct MiniWorkoutBar: View {
    let workoutName: String
    let startDate: Date
    var restEndDate: Date?
    /// false inside the tab bar accessory, which draws its own glass.
    var chrome = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(Palette.accentText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workoutName)
                        .font(.cadHeadline)
                        .foregroundStyle(Palette.text)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(detail(at: context.date))
                            .font(.cadFootnote)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, chrome ? Space.md : Space.sm)
            .padding(.vertical, chrome ? 10 : 2)
            .frame(minHeight: chrome ? 56 : Size.minTouch)
            .background(chrome ? Palette.elevated : .clear, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .strokeBorder(chrome ? Palette.line : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the workout")
    }

    private func detail(at now: Date) -> String {
        var parts = [DurationFormat.clock(now.timeIntervalSince(startDate))]
        if let restEndDate, restEndDate > now {
            parts.append("Rest " + DurationFormat.clock(restEndDate.timeIntervalSince(now).rounded(.up)))
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("Mini workout bar") {
    VStack {
        Spacer()
        MiniWorkoutBar(
            workoutName: "Push day",
            startDate: .now.addingTimeInterval(-2538),
            restEndDate: .now.addingTimeInterval(72)
        ) {}
    }
    .previewSurface()
}
