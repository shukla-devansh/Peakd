//  RestTimerView.swift
//  Board 17 (RestTimer) and the rest bar on the Active board. Both read RestTimerService, which
//  counts toward an end date, so they're correct after backgrounding.

import SwiftData
import SwiftUI

struct RestTimerView: View {
    let session: WorkoutSession
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var profiles: [UserProfile]

    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 260
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 64

    private var rest: RestTimerService { appState.rest }
    private var profile: UserProfile? { profiles.first { !$0.isGone } }
    private var restingEntry: WorkoutExercise? {
        session.entries.first { $0.exerciseName == rest.info?.exerciseName }
    }

    var body: some View {
        VStack(spacing: Space.md) {
            header
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ring(at: context.date)
            }
            controls
            Spacer(minLength: 0)
            if let info = rest.info, let title = info.upNextTitle {
                upNext(info, title: title)
            }
            settings
        }
        .padding(.horizontal, Space.screenMargin)
        .padding(.bottom, Space.xs)
        .foregroundStyle(Palette.text)
        .cadScreenBackground()
        .onChange(of: rest.isRunning) { _, running in
            if !running { dismiss() }   // reached zero or skipped: back to the workout
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: Size.minTouch, height: Size.minTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -10)
            .accessibilityLabel("Back to workout")
            Spacer()
            VStack(spacing: 0) {
                Text("Rest").font(.cadHeadline)
                if let info = rest.info {
                    Text(info.subtitle)
                        .font(.cadFootnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Color.clear.frame(width: Size.minTouch, height: Size.minTouch)
        }
        .padding(.top, Space.xxs)
    }

    private func ring(at date: Date) -> some View {
        let left = rest.remaining(at: date).rounded(.up)
        return ZStack {
            ProgressRing(progress: rest.progress(at: date), lineWidth: 12)
                .animation(reduceMotion ? nil : .linear(duration: 1), value: left)
            VStack(spacing: 2) {
                Text(RestFormat.clock(Int(left)))
                    .font(.cadTimer(size: timerSize))
                    .tracking(-1)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("of \(RestFormat.clock(rest.totalSeconds))")
                    .font(.cadSubhead)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(Space.lg)
        }
        .frame(width: ringSize, height: ringSize)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rest timer, \(RestFormat.spoken(Int(left))) left")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button("−15 s") { rest.adjust(by: -RestTimerService.step) }
                .buttonStyle(.cad(.secondary, fullWidth: false))
                .frame(minWidth: 88)
                .accessibilityLabel("15 seconds less")
            Button("+15 s") { rest.adjust(by: RestTimerService.step) }
                .buttonStyle(.cad(.secondary, fullWidth: false))
                .frame(minWidth: 88)
                .accessibilityLabel("15 seconds more")
            Button("Skip rest") { rest.skip() }
                .buttonStyle(.cad(.primary, fullWidth: false))
                .frame(minWidth: 104)
        }
    }

    private func upNext(_ info: RestInfo, title: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel("Up next")
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.cadHeadline)
                    if let last = info.lastTime {
                        Text("Last time \(last)")
                            .font(.cadFootnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer(minLength: Space.xs)
                if let value = info.upNextValue {
                    Text(value)
                        .font(.cadTitle)
                        .monospacedDigit()
                }
            }
        }
        .cadCard(padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Up next")
    }

    private var settings: some View {
        VStack(spacing: 0) {
            if let entry = restingEntry, let profile {
                HStack {
                    Text("Rest for \(entry.exerciseName.lowercased())")
                        .font(.cadBody)
                        .lineLimit(2)
                    Spacer(minLength: Space.xs)
                    RestStepper(restSeconds: Binding(
                        get: { session.restSeconds(for: entry, defaultRest: profile.defaultRestSeconds) },
                        set: { seconds in
                            // This workout and future ones for this exercise.
                            entry.restSeconds = seconds
                            entry.exercise?.defaultRestSeconds = seconds
                            try? context.save()
                        }
                    ))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(minHeight: 52)
                Divider().overlay(Palette.line)
            }
            Toggle(isOn: Binding(
                get: { profile?.restAlerts ?? rest.alertsEnabled },
                set: { enabled in
                    profile?.restAlerts = enabled
                    try? context.save()
                    rest.setAlertsEnabled(enabled)
                }
            )) {
                Text("Sound and haptic at zero").font(.cadBody)
            }
            .tint(Palette.success)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
        }
        .cadCard(padding: 0)
    }
}

/// Rest card at the top of the Active screen: time left, −15 / +15 / Skip, thin progress bar.
struct RestBar: View {
    @Environment(AppState.self) private var appState

    private var rest: RestTimerService { appState.rest }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = Int(rest.remaining(at: context.date).rounded(.up))
            VStack(spacing: Space.xs) {
                HStack {
                    Button {
                        appState.isRestTimerPresented = true
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                            Text("Rest")
                                .font(.cadFootnote)
                                .foregroundStyle(Palette.textSecondary)
                            Text(String(format: "%02d:%02d", left / 60, left % 60))
                                .font(Font.cadScreenTitle)
                                .monospacedDigit()
                                .foregroundStyle(Palette.text)
                        }
                        .frame(minHeight: Size.minTouch)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rest \(RestFormat.spoken(left)) left. Open rest timer")

                    Spacer(minLength: Space.xs)
                    HStack(spacing: 6) {
                        Button("−15") { rest.adjust(by: -RestTimerService.step) }
                            .buttonStyle(.cad(.neutral, size: .small, fullWidth: false))
                            .accessibilityLabel("15 seconds less")
                        Button("+15") { rest.adjust(by: RestTimerService.step) }
                            .buttonStyle(.cad(.neutral, size: .small, fullWidth: false))
                            .accessibilityLabel("15 seconds more")
                        Button("Skip") { rest.skip() }
                            .buttonStyle(.cad(.tinted, size: .small, fullWidth: false))
                            .accessibilityLabel("Skip rest")
                    }
                }
                LinearProgressBar(progress: rest.progress(at: context.date))
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.top, 10)
        .padding(.bottom, Space.sm)
        .cadCard(padding: 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rest timer")
    }
}
