//  RestTimerLiveActivity.swift
//  Skeleton rest-timer Live Activity. Phase 4 matches it to the LockScreen board.
//  The countdown uses Text(timerInterval:) against the end date, so it keeps ticking without updates.

import ActivityKit
import SwiftUI
import WidgetKit

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            HStack(spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.isOver ? "Rest over" : "Rest")
                        .font(.cadFootnote)
                        .foregroundStyle(Palette.textSecondary)
                    countdown(context.state)
                        .font(.cadTimer)
                        .foregroundStyle(Palette.text)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Up next")
                        .font(.cadFootnote)
                        .foregroundStyle(Palette.textSecondary)
                    Text(context.state.upNext)
                        .font(.cadSubhead)
                        .foregroundStyle(Palette.text)
                }
            }
            .padding(Space.md)
            .activityBackgroundTint(Palette.surface)
            .activitySystemActionForegroundColor(Palette.accentText)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Rest", systemImage: "timer")
                        .foregroundStyle(Palette.accentText)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state)
                        .font(.cadTitle)
                        .frame(maxWidth: 80, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Up next · \(context.state.upNext)")
                        .font(.cadFootnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(Palette.accentText)
            } compactTrailing: {
                countdown(context.state)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(Palette.accentText)
            }
            .keylineTint(Palette.accentText)
        }
    }

    @ViewBuilder
    private func countdown(_ state: RestTimerAttributes.ContentState) -> some View {
        if state.isOver || state.endDate <= .now {
            Text("0:00").monospacedDigit()
        } else {
            Text(timerInterval: Date.now...state.endDate, countsDown: true)
                .monospacedDigit()
        }
    }
}

#Preview("Lock screen", as: .content, using: RestTimerAttributes(workoutName: "Push day", exerciseName: "Bench press")) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState(endDate: .now.addingTimeInterval(72), totalSeconds: 90, upNext: "Bench press · set 4", isOver: false)
    RestTimerAttributes.ContentState(endDate: .now, totalSeconds: 90, upNext: "Bench press · set 4", isOver: true)
}
