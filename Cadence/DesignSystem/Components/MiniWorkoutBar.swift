//  MiniWorkoutBar.swift
//  Shown above the tab bar while a minimised workout runs: "Push day · 42:18 · Rest 1:12". Tap reopens Active.
//  Times count from dates, so the bar stays correct after backgrounding.

import SwiftUI

struct MiniWorkoutBar: View {
    let workoutName: String
    let startDate: Date
    var restEndDate: Date?
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
            .padding(.horizontal, Space.md)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .background(Palette.elevated, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the workout")
    }

    private func detail(at now: Date) -> String {
        var parts = [Self.clock(now.timeIntervalSince(startDate))]
        if let restEndDate, restEndDate > now {
            parts.append("Rest " + Self.clock(restEndDate.timeIntervalSince(now).rounded(.up)))
        }
        return parts.joined(separator: " · ")
    }

    /// 42:18, or 1:02:05 past an hour.
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
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
