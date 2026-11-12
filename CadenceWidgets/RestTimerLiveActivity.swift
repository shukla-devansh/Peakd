//  RestTimerLiveActivity.swift
//  Board 18 (LockScreen): lock-screen card, Dynamic Island (compact, minimal, expanded) and the
//  "Rest over" state. Text(timerInterval:) and ProgressView(timerInterval:) tick on their own; the
//  content's staleDate (the rest's end) flips it to "Rest over" while the app is suspended.

import ActivityKit
import SwiftUI
import WidgetKit

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            LockScreenRestView(attributes: context.attributes, state: context.state,
                               isOver: Self.isOver(context.state, isStale: context.isStale))
                .activityBackgroundTint(Palette.surface.opacity(0.92))
                .activitySystemActionForegroundColor(Palette.accentText)
                .widgetURL(CadenceLinks.workout)
        } dynamicIsland: { context in
            let over = Self.isOver(context.state, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        RestStatusLabel(isOver: over)
                        Countdown(state: context.state, isOver: over)
                            .font(.cadTitle)
                    }
                    .padding(.leading, Space.xxs)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let title = context.state.nextTitle {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Next · \(title)")
                                .font(.cadLabel)
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(1)
                            if let value = context.state.nextValue {
                                Text(value)
                                    .font(.cadHeadline)
                                    .monospacedDigit()
                            }
                        }
                        .padding(.trailing, Space.xxs)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RestProgress(state: context.state, isOver: over)
                        .padding(.horizontal, Space.xxs)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(Palette.accentText)
                    .accessibilityLabel(context.attributes.workoutName)
            } compactTrailing: {
                if over {
                    Text("Go")
                        .font(Font.cadSubhead.weight(.semibold))
                        .foregroundStyle(Palette.success)
                        .accessibilityLabel("Rest over")
                } else {
                    Countdown(state: context.state, isOver: false)
                        .font(Font.cadSubhead.weight(.semibold))
                        .frame(maxWidth: 48)
                }
            } minimal: {
                if over {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Palette.success)
                        .accessibilityLabel("Rest over")
                } else {
                    Image(systemName: "timer")
                        .foregroundStyle(Palette.accentText)
                        .accessibilityLabel("Resting")
                }
            }
            .widgetURL(CadenceLinks.workout)
            .keylineTint(Palette.accentText)
        }
    }

    static func isOver(_ state: RestTimerAttributes.ContentState, isStale: Bool) -> Bool {
        state.isOver || isStale
    }
}

struct LockScreenRestView: View {
    let attributes: RestTimerAttributes
    let state: RestTimerAttributes.ContentState
    let isOver: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "dumbbell.fill")
                    .accessibilityHidden(true)
                Text(attributes.workoutName)
                Text("·")
                // Count-up clock ("42:18"). Text(date, style: .timer) renders as "<1 minute" here.
                Text(timerInterval: attributes.workoutStart...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
            }
            .font(Font.cadFootnote.weight(.semibold))
            .foregroundStyle(Palette.accentText)
            .lineLimit(1)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    RestStatusLabel(isOver: isOver)
                    Countdown(state: state, isOver: isOver)
                        .font(.cadTimer(size: timerSize))
                        .foregroundStyle(Palette.text)
                }
                Spacer(minLength: Space.xs)
                if let title = state.nextTitle {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Next · \(title)")
                            .font(.cadFootnote)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                        if let value = state.nextValue {
                            Text(value)
                                .font(.cadTitle)
                                .monospacedDigit()
                                .foregroundStyle(Palette.text)
                        }
                    }
                }
            }

            RestProgress(state: state, isOver: isOver)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

/// "Rest" or "✓ Rest over" (green + check: never colour alone).
struct RestStatusLabel: View {
    let isOver: Bool

    var body: some View {
        if isOver {
            Label("Rest over", systemImage: "checkmark")
                .font(Font.cadFootnote.weight(.bold))
                .foregroundStyle(Palette.success)
        } else {
            Text("Rest")
                .font(.cadFootnote)
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

struct Countdown: View {
    let state: RestTimerAttributes.ContentState
    let isOver: Bool

    var body: some View {
        if isOver || state.endDate <= .now {
            Text("0:00").monospacedDigit()
        } else {
            Text(timerInterval: Date.now...state.endDate, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.leading)
        }
    }
}

struct RestProgress: View {
    let state: RestTimerAttributes.ContentState
    let isOver: Bool

    var body: some View {
        Group {
            if isOver || state.endDate <= .now {
                Capsule().fill(Palette.success)
            } else {
                let start = state.endDate.addingTimeInterval(-TimeInterval(state.totalSeconds))
                // Fills as the rest elapses, like the lock-screen board.
                ProgressView(timerInterval: start...state.endDate, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(Palette.accentText)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

#Preview("Lock screen", as: .content,
         using: RestTimerAttributes(workoutName: "Push day", workoutStart: .now.addingTimeInterval(-2538))) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState(endDate: .now.addingTimeInterval(72), totalSeconds: 120,
                                     nextTitle: "Bench press set 4", nextValue: "42.5 × 10", isOver: false)
    RestTimerAttributes.ContentState(endDate: .now, totalSeconds: 120,
                                     nextTitle: "Bench press set 4", nextValue: "42.5 × 10", isOver: true)
}

#Preview("Island compact", as: .dynamicIsland(.compact),
         using: RestTimerAttributes(workoutName: "Push day", workoutStart: .now)) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState(endDate: .now.addingTimeInterval(72), totalSeconds: 120,
                                     nextTitle: "Bench press set 4", nextValue: "42.5 × 10", isOver: false)
    RestTimerAttributes.ContentState(endDate: .now, totalSeconds: 120,
                                     nextTitle: "Bench press set 4", nextValue: "42.5 × 10", isOver: true)
}
