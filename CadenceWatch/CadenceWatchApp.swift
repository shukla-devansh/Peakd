//  CadenceWatchApp.swift
//  watchOS companion (Watch board): Live workout, Edit set (Digital Crown) and Rest.
//  The iPhone owns the workout; the Watch mirrors it and logs sets back.

import SwiftUI
import WatchKit

@main
struct CadenceWatchApp: App {
    @State private var connector = WatchConnector()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(connector)
                .task { connector.activate() }
        }
    }
}

struct WatchRootView: View {
    @Environment(WatchConnector.self) private var connector

    var body: some View {
        let state = connector.state
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Group {
                if !state.isActive {
                    WatchIdleView()
                } else if state.isResting(at: context.date) {
                    WatchRestView(state: state, now: context.date)
                } else {
                    NavigationStack { WatchLiveView(state: state, now: context.date) }
                }
            }
        }
        .containerBackground(Palette.background.gradient, for: .navigation)
    }
}

struct WatchIdleView: View {
    var body: some View {
        VStack(spacing: Space.xs) {
            Image(systemName: "dumbbell.fill")
                .font(.title2)
                .foregroundStyle(Palette.accentText)
                .accessibilityHidden(true)
            Text(AppInfo.name)
                .font(.cadHeadline)
            Text("Start a workout on your iPhone.")
                .font(.cadFootnote)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Screen 1: live workout

struct WatchLiveView: View {
    let state: WatchWorkoutState
    let now: Date
    @Environment(WatchConnector.self) private var connector

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(state.workoutName).font(Font.cadFootnote.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text(DurationFormat.clock(now.timeIntervalSince(state.startedAt)))
                        .font(.cadFootnote)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "heart.fill").foregroundStyle(Palette.danger)
                    Text(connector.heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(size: 34, weight: .bold))
                        .monospacedDigit()
                    Text("bpm").font(.cadFootnote).foregroundStyle(Palette.textSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(connector.heartRate.map { "Heart rate \(Int($0.rounded())) beats per minute" } ?? "Heart rate not available yet")

                if let exercise = state.exerciseName {
                    HStack {
                        Text(exercise).font(Font.cadSubhead.weight(.semibold)).foregroundStyle(Palette.accentText).lineLimit(1)
                        Spacer()
                        if let n = state.setNumber, let total = state.totalSets {
                            Text("Set \(n) of \(total)").font(.cadLabel).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    Text(state.setText)
                        .font(Font.cadHeadline.monospacedDigit())
                    if let kcal = connector.activeEnergyKcal {
                        Text("\(Int(kcal.rounded())) kcal").font(.cadLabel).foregroundStyle(Palette.textSecondary)
                    }
                    NavigationLink {
                        WatchEditSetView(state: state)
                    } label: {
                        Label("Log set", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(Palette.accent)
                    .padding(.top, 2)
                } else {
                    Text("Add an exercise on your iPhone.")
                        .font(.cadFootnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live workout")
    }
}

// MARK: - Screen 2: edit set

struct WatchEditSetView: View {
    let state: WatchWorkoutState
    @Environment(WatchConnector.self) private var connector
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case weight, reps }
    @FocusState private var focus: Field?
    @State private var weight: Double = 0     // in the display unit
    @State private var reps: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if state.tracksWeight {
                    box("Weight", value: weight.formatted(.number.precision(.fractionLength(0...1))), unit: state.unit.symbol, field: .weight)
                        .digitalCrownRotation($weight, from: 0, through: state.unit == .kg ? 500 : 1100,
                                              by: step, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                }
                box("Reps", value: "\(Int(reps))", unit: "reps", field: .reps)
                    .digitalCrownRotation($reps, from: 1, through: 100, by: 1, sensitivity: .low,
                                          isContinuous: false, isHapticFeedbackEnabled: true)
            }
            Text(focus == .reps ? "Turn the Crown to change reps" : "Turn the Crown to change weight")
                .font(.cadLabel)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                let kg = state.tracksWeight ? WeightFormatter.kilograms(from: weight, in: state.unit) : nil
                connector.send(.logSet(weightKg: kg, reps: max(1, Int(reps))))
                WKInterfaceDevice.current().play(.success)
                dismiss()
            } label: {
                Label("Save set", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .tint(Palette.accent)
        }
        .onAppear {
            weight = state.weightKg.map { WeightFormatter.displayValue(kg: $0, in: state.unit) } ?? 0
            reps = Double(state.reps ?? 8)
            focus = state.tracksWeight ? .weight : .reps
        }
        // Exercise and set go in the navigation bar, beside the back button.
        .navigationTitle(state.setNumber.map { "Set \($0)" } ?? "Set")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Edit set, \(state.exerciseName ?? "")")
    }

    private var step: Double { WeightFormatter.step(for: state.unit) }

    private func box(_ label: String, value: String, unit: String, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.cadLabel).foregroundStyle(Palette.textSecondary)
            Text(value).font(.system(size: 26, weight: .bold)).monospacedDigit()
            Text(unit).font(.cadLabel).foregroundStyle(Palette.textSecondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(focus == field ? Palette.accent : Palette.line, lineWidth: focus == field ? 2 : 1))
        .focusable()
        .focused($focus, equals: field)
        .onTapGesture { focus = field }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value) \(unit)")
        .accessibilityHint("Turn the Digital Crown to change it")
    }
}

// MARK: - Screen 3: rest

struct WatchRestView: View {
    let state: WatchWorkoutState
    let now: Date
    @Environment(WatchConnector.self) private var connector

    var body: some View {
        let end = state.restEnd ?? now
        let left = max(0, end.timeIntervalSince(now))
        let total = Double(max(state.restTotalSeconds ?? 1, 1))
        VStack(spacing: 6) {
            Text("Rest").font(Font.cadFootnote.weight(.semibold)).foregroundStyle(Palette.textSecondary)
            ZStack {
                Circle().stroke(Palette.line, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: left / total)
                    .stroke(Palette.accentText, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(DurationFormat.clock(left.rounded(.up)))
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
            }
            .frame(width: 104, height: 104)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest, \(DurationFormat.spoken(left.rounded(.up))) left")
            if let next = state.nextText {
                Text(next).font(.cadLabel).foregroundStyle(Palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            HStack(spacing: 6) {
                Button("+15") { connector.send(.adjustRest(seconds: 15)) }
                Button("Skip") { connector.send(.skipRest) }
                    .tint(Palette.accent)
            }
        }
        // A haptic tap marks the end of rest (skipping changes restEnd and cancels this).
        .task(id: state.restEnd) {
            guard let end = state.restEnd, end > .now else { return }
            try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            WKInterfaceDevice.current().play(.notification)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rest timer")
    }
}

#Preview("Live") {
    NavigationStack {
        WatchLiveView(state: WatchWorkoutState(isActive: true, workoutName: "Push day", startedAt: .now.addingTimeInterval(-2538),
                                               exerciseName: "Bench press", setNumber: 3, totalSets: 4, weightKg: 42.5, reps: 10),
                      now: .now)
    }
    .environment(WatchConnector())
}
