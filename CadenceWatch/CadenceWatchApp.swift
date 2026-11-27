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

/// What Watch dictation heard, parsed by the same VoiceSetParser as the iPhone.
struct WatchVoiceEntry: Identifiable, Hashable {
    let id = UUID()
    let transcript: String
    let weightKg: Double?
    let reps: Int?
    let missing: Set<VoiceParseResult.Field>
}

struct WatchLiveView: View {
    let state: WatchWorkoutState
    let now: Date
    @Environment(WatchConnector.self) private var connector
    @State private var voiceEntry: WatchVoiceEntry?

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
                    if let kcal = connector.activeEnergyKcal, kcal >= 1 {
                        Text("\(Int(kcal.rounded())) kcal").font(.cadLabel).foregroundStyle(Palette.textSecondary)
                    }
                    HStack(spacing: 6) {
                        NavigationLink {
                            WatchEditSetView(state: state)
                        } label: {
                            Label("Log set", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(Palette.accent)
                        if state.voiceLogging {
                            // watchOS has no speech framework for apps: Dictation gives the text,
                            // and the shared parser turns it into weight and reps.
                            TextFieldLink(prompt: Text("Say “45 kilos for 8”")) {
                                Image(systemName: "mic.fill")
                                    .frame(maxWidth: .infinity)
                            } onSubmit: { text in
                                parse(text)
                            }
                            .frame(width: 52)
                            .accessibilityLabel("Log a set by voice")
                        }
                    }
                    .padding(.top, 2)
                } else {
                    Text("Add an exercise on your iPhone.")
                        .font(.cadFootnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .navigationDestination(item: $voiceEntry) { entry in
            WatchEditSetView(state: state, voice: entry)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live workout")
    }

    private func parse(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let result = VoiceSetParser.parse(trimmed, context: VoiceParseContext(
            unit: state.unit, currentWeightKg: state.weightKg, tracksWeight: state.tracksWeight))
        voiceEntry = WatchVoiceEntry(transcript: trimmed, weightKg: result.weightKg, reps: result.reps, missing: result.missing)
    }
}

// MARK: - Screen 2: edit set

struct WatchEditSetView: View {
    let state: WatchWorkoutState
    /// Set when opened from dictation: prefilled, and missing fields marked "Needed".
    var voice: WatchVoiceEntry?
    @Environment(WatchConnector.self) private var connector
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case weight, reps }
    /// The box the Crown is changing. One Crown binding drives whichever box is selected:
    /// two bindings on two boxes only ever moved the focused one, so reps never changed.
    @State private var selected: Field = .weight
    @State private var crown: Double = 0
    @FocusState private var crownFocused: Bool
    @State private var weight: Double = 0     // in the display unit
    @State private var reps: Double = 0
    /// Fields dictation didn't catch, until the Crown sets them.
    @State private var needed: Set<VoiceParseResult.Field> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let voice {
                Text("“\(voice.transcript)”")
                    .font(.cadLabel)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .accessibilityLabel("What I heard: \(voice.transcript)")
            }
            HStack(spacing: 6) {
                if state.tracksWeight {
                    box("Weight", value: weight.formatted(.number.precision(.fractionLength(0...1))), unit: state.unit.symbol,
                        field: .weight, isNeeded: needed.contains(.weight))
                }
                box("Reps", value: "\(Int(reps))", unit: "reps", field: .reps, isNeeded: needed.contains(.reps))
            }
            Text(selected == .reps ? "Turn the Crown to change reps" : "Turn the Crown to change weight")
                .font(.cadLabel)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Button {
                let kg = state.tracksWeight ? WeightFormatter.kilograms(from: weight, in: state.unit) : nil
                connector.send(.logSet(weightKg: kg, reps: max(1, Int(reps)), voice: voice != nil))
                WKInterfaceDevice.current().play(.success)
                dismiss()
            } label: {
                Label("Save set", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .tint(Palette.accent)
            .disabled(!needed.isEmpty)
        }
        // Anchor to the top so nothing slides up under the navigation title on small Watches.
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            let kg = voice?.weightKg ?? state.weightKg
            weight = kg.map { WeightFormatter.displayValue(kg: $0, in: state.unit) } ?? 0
            reps = Double(voice?.reps ?? state.reps ?? 8)
            needed = voice?.missing ?? []
            // Point the Crown at whatever dictation missed.
            if needed.contains(.weight) && state.tracksWeight { selected = .weight }
            else if needed.contains(.reps) { selected = .reps }
            else { selected = state.tracksWeight ? .weight : .reps }
            crown = selected == .weight ? weight : reps
            crownFocused = true
        }
        // The one Crown binding for the whole screen; its range follows the selected box.
        .focusable()
        .focused($crownFocused)
        .focusEffectDisabled()
        .digitalCrownRotation($crown, from: crownRange.lowerBound, through: crownRange.upperBound,
                              by: selected == .weight ? step : 1, sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, value in
            switch selected {
            case .weight:
                if abs(value - weight) > 0.001 { weight = value; needed.remove(.weight) }
            case .reps:
                let r = value.rounded()
                if r != reps { reps = r; needed.remove(.reps) }
            }
        }
        .onChange(of: selected) { _, field in
            crown = field == .weight ? weight : reps
            crownFocused = true
        }
        // Exercise and set go in the navigation bar, beside the back button.
        .navigationTitle(state.setNumber.map { "Set \($0)" } ?? "Set")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Edit set, \(state.exerciseName ?? "")")
    }

    private var step: Double { WeightFormatter.step(for: state.unit) }

    private var crownRange: ClosedRange<Double> {
        selected == .weight ? 0...(state.unit == .kg ? 500 : 1100) : 1...100
    }

    /// VoiceOver swipe up/down on a box, and the same steps as the Crown.
    private func adjust(_ field: Field, by direction: Double) {
        switch field {
        case .weight: weight = min(max(weight + direction * step, 0), state.unit == .kg ? 500 : 1100); needed.remove(.weight)
        case .reps: reps = min(max(reps + direction, 1), 100); needed.remove(.reps)
        }
        if selected == field { crown = field == .weight ? weight : reps }
    }

    private func box(_ label: String, value: String, unit: String, field: Field, isNeeded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.cadLabel).foregroundStyle(Palette.textSecondary)
            Text(isNeeded ? "?" : value)
                .font(.system(size: 24, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isNeeded ? Palette.warning : Palette.text)
            if isNeeded {
                Label("Needed", systemImage: "exclamationmark.triangle")
                    .font(Font.cadLabel.weight(.semibold))
                    .foregroundStyle(Palette.warning)
            } else {
                Text(unit).font(.cadLabel).foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(selected == field ? Palette.accent : Palette.line, lineWidth: selected == field ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { selected = field }
        .accessibilityAddTraits(selected == field ? [.isSelected, .isButton] : .isButton)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(field, by: 1)
            case .decrement: adjust(field, by: -1)
            @unknown default: break
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isNeeded ? "\(label), needed" : "\(label) \(value) \(unit)")
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
