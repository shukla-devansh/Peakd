//  VoiceLogSheet.swift
//  Boards 04 (Voice) and 19 (VoiceRetry). Listens, shows what it heard and the parsed set,
//  and saves only when the user taps Save set. Missing fields get the retry treatment:
//  warning colour + icon + "Needed", quick picks for reps, and Say again.

import SwiftData
import SwiftUI

struct VoiceLogSheet: View {
    let session: WorkoutSession
    let entry: WorkoutExercise
    let unit: WeightUnit

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var profiles: [UserProfile]

    @State private var speech = SpeechService()
    @State private var setIndex: Int
    @State private var weightOverride: Double?
    @State private var repsOverride: Int?
    @State private var editing: VoiceParseResult.Field?
    @State private var editText = ""
    @State private var levels = Array(repeating: 0.0, count: 25)
    #if targetEnvironment(simulator)
    @State private var typed = ""
    #endif

    init(session: WorkoutSession, entry: WorkoutExercise, unit: WeightUnit) {
        self.session = session
        self.entry = entry
        self.unit = unit
        _setIndex = State(initialValue: session.activeSet(in: entry)?.index
                          ?? (entry.orderedSets.map(\.index).max() ?? 0) + 1)
    }

    // MARK: Derived

    private var tracksWeight: Bool { (entry.exercise?.trackingType ?? .weightReps) == .weightReps }
    private var targetSet: SetLog? { entry.orderedSets.first { $0.index == setIndex } }

    /// The weight already in the row, else the set above, else last session's same set.
    private var rowWeightKg: Double? {
        targetSet?.weightKg
            ?? entry.orderedSets.last { $0.index < setIndex && $0.weightKg != nil }?.weightKg
            ?? session.previousSet(for: entry, index: setIndex)?.weightKg
    }

    private var parsed: VoiceParseResult {
        VoiceSetParser.parse(transcript, context: VoiceParseContext(
            unit: unit, currentWeightKg: rowWeightKg, tracksWeight: tracksWeight))
    }

    private var transcript: String {
        #if targetEnvironment(simulator)
        if !typed.isEmpty { return typed }
        #endif
        return speech.transcript
    }

    private var weightKg: Double? { tracksWeight ? (weightOverride ?? parsed.weightKg) : nil }
    private var reps: Int? { repsOverride ?? parsed.reps }

    private var missing: Set<VoiceParseResult.Field> {
        var m: Set<VoiceParseResult.Field> = []
        if reps == nil { m.insert(.reps) }
        if tracksWeight && weightKg == nil { m.insert(.weight) }
        return m
    }

    private enum Phase { case listening, review, retry, failed(SpeechService.Failure) }

    private var phase: Phase {
        if case .failed(let f) = speech.state {
            #if targetEnvironment(simulator)
            if !typed.isEmpty { return missing.isEmpty ? .review : .retry }
            #endif
            return .failed(f)
        }
        if speech.isListening || speech.state == .idle { return .listening }
        return missing.isEmpty ? .review : .retry
    }

    private var isRetry: Bool { if case .retry = phase { true } else { false } }

    private var title: String {
        switch phase {
        case .listening: "Listening"
        case .review: "Check the numbers"
        case .retry:
            if missing == [.reps] { "Missing the reps" }
            else if missing == [.weight] { "Missing the weight" }
            else { "Didn't catch that" }
        case .failed(.noPermission): "Voice logging needs microphone access"
        case .failed: "Voice logging isn't available"
        }
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch phase {
            case .failed(let failure):
                failureView(failure)
            default:
                if case .listening = phase { waveform }
                heard
                tiles
                if isRetry { quickPicks } else { hint }
                Spacer(minLength: 0)
                actions
            }
        }
        .padding(.horizontal, Space.screenMargin)
        .padding(.top, Space.md)
        .padding(.bottom, Space.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Palette.text)
        .background(Palette.surface.ignoresSafeArea())
        .presentationDetents([.height(560), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.surface)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isRetry ? "Voice logging, needs a check" : "Voice logging")
        .task { await begin() }
        .task(id: transcript) { await autoStop() }
        .onChange(of: speech.level) { _, value in
            levels.removeFirst()
            levels.append(value)
        }
        .onDisappear { Task { await speech.cancel() } }
        .alert(editing == .weight ? "Weight (\(unit.symbol))" : "Reps",
               isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField(editing == .weight ? "Weight" : "Reps", text: $editText)
                .keyboardType(editing == .weight ? .decimalPad : .numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Done") { applyEdit() }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.cadTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("\(entry.exerciseName) · set \(setIndex)")
                    .font(.cadFootnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: Size.minTouch, height: Size.minTouch)
                    .background(Palette.elevated, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, -8)
            .accessibilityLabel("Close voice logging")
        }
    }

    private var waveform: some View {
        HStack(spacing: 4) {
            ForEach(levels.indices, id: \.self) { i in
                let level = reduceMotion ? 0.3 : levels[i]
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.accentText)
                    .frame(width: 4, height: 6 + 54 * level)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .animation(reduceMotion ? nil : Motion.quick, value: levels)
        .accessibilityElement()
        .accessibilityLabel("Live sound level")
        .accessibilityAddTraits(.isImage)
    }

    private var heard: some View {
        VStack(spacing: 4) {
            Text("What I heard")
                .font(.cadFootnote)
                .foregroundStyle(Palette.textSecondary)
            Group {
                if transcript.isEmpty {
                    Text(speech.isListening ? "“…”" : "“ ”")
                } else if isRetry {
                    Text("“\(transcript)… ") + Text("[unclear]").foregroundStyle(Palette.textSecondary) + Text("”")
                } else {
                    Text("“\(transcript)”")
                }
            }
            .font(.cadTitle)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            #if targetEnvironment(simulator)
            TextField("Simulator: type what you'd say", text: $typed)
                .textFieldStyle(.roundedBorder)
                .font(.cadFootnote)
                .padding(.top, Space.xxs)
            #endif
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var tiles: some View {
        HStack(spacing: Space.xs) {
            if tracksWeight {
                VoiceTile(label: "Weight",
                          value: weightKg.map { WeightFormatter.number(kg: $0, in: unit) },
                          unit: unit.symbol,
                          delta: delta,
                          isMissing: isRetry && missing.contains(.weight),
                          accessibilityText: weightKg.map { "Edit weight, \(WeightFormatter.spoken(kg: $0, in: unit))" } ?? "Edit weight, needed") {
                    edit(.weight)
                }
            }
            VoiceTile(label: "Reps",
                      value: reps.map(String.init),
                      isMissing: isRetry && missing.contains(.reps),
                      accessibilityText: reps.map { "Edit repetitions, \($0)" } ?? "Edit repetitions, needed") {
                edit(.reps)
            }
            Menu {
                ForEach(entry.orderedSets, id: \.index) { set in
                    Button("Set \(set.index)\(set.isCompleted ? " (done)" : "")") { setIndex = set.index }
                }
                Button("New set \((entry.orderedSets.map(\.index).max() ?? 0) + 1)") {
                    setIndex = (entry.orderedSets.map(\.index).max() ?? 0) + 1
                }
            } label: {
                VoiceTileLabel(label: "Set", value: "\(setIndex)", unit: nil, delta: nil, isMissing: false)
            }
            .accessibilityLabel("Edit set number, \(setIndex)")
        }
        .fixedSize(horizontal: false, vertical: true)   // equal-height tiles
    }

    /// "+5 kg vs last time" (green) from the same set last session.
    private var delta: (text: String, isUp: Bool)? {
        guard let kg = weightKg, let last = session.previousSet(for: entry, index: setIndex)?.weightKg else { return nil }
        let diff = WeightFormatter.displayValue(kg: kg, in: unit) - WeightFormatter.displayValue(kg: last, in: unit)
        if abs(diff) < 0.01 { return ("Same as last time", false) }
        let amount = WeightFormatter.string(kg: WeightFormatter.kilograms(from: abs(diff), in: unit), in: unit)
        return ((diff > 0 ? "+" : "−") + amount + " vs last time", diff > 0)
    }

    private var hint: some View {
        Text("Check the numbers, then save. Try “same weight, 10 reps” or “add 2.5 kilos, 8 reps” too.")
            .font(.cadFootnote)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var quickPicks: some View {
        if missing.contains(.reps) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Tap the reps you did")
                    .font(.cadFootnote)
                    .foregroundStyle(Palette.textSecondary)
                QuickPickRow(values: [6, 7, 8, 9, 10, 12].map { ($0, "\($0)") }, selected: repsOverride) {
                    repsOverride = $0
                }
                .accessibilityLabel("Repetitions")
            }
        } else if missing.contains(.weight) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Tap the weight you lifted")
                    .font(.cadFootnote)
                    .foregroundStyle(Palette.textSecondary)
                if let picks = weightPicks {
                    QuickPickRow(values: picks.map { ($0, WeightFormatter.number(kg: $0, in: unit)) }, selected: weightOverride) {
                        weightOverride = $0
                    }
                    .accessibilityLabel("Weight in \(unit.spokenName)")
                } else {
                    Text("Tap Weight to type it.")
                        .font(.cadFootnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    /// Five weights around the row's weight, a plate step apart.
    private var weightPicks: [Double]? {
        guard let base = rowWeightKg, base > 0 else { return nil }
        let step = WeightFormatter.step(for: unit)
        let display = WeightFormatter.displayValue(kg: base, in: unit)
        return (-2...2).map { WeightFormatter.kilograms(from: max(0, display + Double($0) * step), in: unit) }
    }

    private var actions: some View {
        HStack(spacing: Space.xs) {
            Button {
                Task { await sayAgain() }
            } label: {
                Label(isRetry ? "Say again" : "Retry", systemImage: "mic")
            }
            .buttonStyle(.cad(.elevated, fullWidth: false))
            .frame(minWidth: 120)
            Button("Save set") { save() }
                .buttonStyle(.cadPrimary)
                .disabled(!missing.isEmpty)
        }
    }

    private func failureView(_ failure: SpeechService.Failure) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(failure == .noPermission
                 ? "Allow the microphone and speech recognition to log sets by voice. Speech stays on this iPhone."
                 : "Speech recognition isn't available on this device right now. Log the set by hand instead.")
                .font(.cadSubhead)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            #if targetEnvironment(simulator)
            TextField("Simulator: type what you'd say", text: $typed)
                .textFieldStyle(.roundedBorder)
            #endif
            Spacer(minLength: 0)
            if failure == .noPermission {
                Button("Allow microphone") { Task { await allow() } }
                    .buttonStyle(.cadPrimary)
            } else {
                Button("Close") { dismiss() }
                    .buttonStyle(.cadSecondary)
            }
        }
    }

    // MARK: Actions

    private func begin() async {
        if appState.permissions.state(.voice) == .notDetermined {
            await appState.permissions.request(.voice)
        }
        await speech.start()
    }

    private func allow() async {
        if await appState.permissions.request(.voice) {
            await speech.start()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    /// Stops listening once a complete set has been heard and nothing new arrives for 1.5 s,
    /// or after 4 s of silence whatever was heard.
    private func autoStop() async {
        guard speech.isListening, !transcript.isEmpty else { return }
        let wait: Duration = parsed.isComplete ? .milliseconds(1500) : .seconds(4)
        try? await Task.sleep(for: wait)
        guard !Task.isCancelled else { return }
        await speech.stop()
    }

    private func sayAgain() async {
        weightOverride = nil
        repsOverride = nil
        #if targetEnvironment(simulator)
        typed = ""
        #endif
        await speech.cancel()
        await speech.start()
    }

    private func edit(_ field: VoiceParseResult.Field) {
        switch field {
        case .weight: editText = weightKg.map { WeightFormatter.fieldString(kg: $0, in: unit) } ?? ""
        case .reps: editText = reps.map(String.init) ?? ""
        }
        editing = field
    }

    private func applyEdit() {
        switch editing {
        case .weight?: if let kg = WeightFormatter.parse(editText, in: unit) { weightOverride = kg }
        case .reps?: if let n = Int(editText.trimmingCharacters(in: .whitespaces)), (1...VoiceSetParser.maxReps).contains(n) { repsOverride = n }
        case nil: break
        }
        editing = nil
    }

    /// Writes the confirmed values into the set, ticks it off (source: voice) and starts the rest.
    private func save() {
        guard missing.isEmpty, let reps else { return }
        Task { await speech.cancel() }
        if targetSet == nil { session.addSet(to: entry) }
        guard let set = entry.orderedSets.first(where: { $0.index == setIndex }) ?? entry.orderedSets.last else { return }
        if tracksWeight { set.weightKg = weightKg }
        set.reps = reps
        if set.isCompleted {
            set.source = .voice
            session.save()
        } else if session.toggleComplete(set, in: entry, source: .voice) {
            let profile = profiles.first { !$0.isGone }
            appState.didComplete(set, in: entry, session: session, profile: profile, unit: unit)
        }
        dismiss()
    }
}

// MARK: - Pieces

/// Weight / Reps tile: tap to edit. Missing = warning tint + "?" + "Needed".
private struct VoiceTile: View {
    let label: String
    let value: String?
    var unit: String?
    var delta: (text: String, isUp: Bool)?
    let isMissing: Bool
    let accessibilityText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VoiceTileLabel(label: label, value: value, unit: unit, delta: delta, isMissing: isMissing)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }
}

private struct VoiceTileLabel: View {
    let label: String
    let value: String?
    let unit: String?
    let delta: (text: String, isUp: Bool)?
    let isMissing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.cadLabel)
                .foregroundStyle(Palette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? (isMissing ? "?" : "–"))
                    .font(Font.cadTitle.monospacedDigit())
                    .foregroundStyle(isMissing ? Palette.warning : Palette.text)
                if let unit, value != nil {
                    Text(unit)
                        .font(Font.cadFootnote.weight(.medium))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            if isMissing {
                Label("Needed", systemImage: "exclamationmark.triangle")
                    .font(Font.cadLabel.weight(.semibold))
                    .foregroundStyle(Palette.warning)
            } else if let delta {
                Text(delta.text)
                    .font(Font.cadLabel.weight(.semibold))
                    .foregroundStyle(delta.isUp ? Palette.success : Palette.textSecondary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Space.sm)
        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: .infinity, alignment: .topLeading)
        .background(isMissing ? Palette.warning.opacity(0.10) : Palette.elevated,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(isMissing ? Palette.warning : Palette.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Radio row of quick picks (VoiceRetry "Tap the reps you did").
private struct QuickPickRow<Value: Hashable>: View {
    let values: [(Value, String)]
    let selected: Value?
    let onPick: (Value) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(values, id: \.0) { value, label in
                let on = value == selected
                Button { onPick(value) } label: {
                    Text(label)
                        .font(Font.cadHeadline.monospacedDigit())
                        .foregroundStyle(on ? .white : Palette.text)
                        .frame(maxWidth: .infinity, minHeight: Size.compactButton)
                        .background(on ? Palette.accent : Palette.elevated,
                                    in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                            .strokeBorder(on ? Palette.accent : Palette.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
    }
}
