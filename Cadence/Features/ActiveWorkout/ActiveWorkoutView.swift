//  ActiveWorkoutView.swift
//  Board 03 (Active). Phase 4 adds the rest bar, phase 5 the overload chip, phase 6 the mic button.

import SwiftData
import SwiftUI

struct ActiveWorkoutView: View {
    let session: WorkoutSession
    @Environment(AppState.self) private var appState
    @Query private var profiles: [UserProfile]
    @State private var showAddExercise = false
    @State private var confirmCancel = false
    @State private var confirmEmptyFinish = false

    private var unit: WeightUnit { profiles.first(where: { !$0.isGone })?.unit ?? .kg }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Space.screenMargin)
            ScrollView {
                VStack(spacing: Space.sm) {
                    if session.entries.isEmpty {
                        EmptyStateCard(
                            title: "No exercises yet",
                            message: "Add exercises to start logging sets.",
                            actionTitle: "Add exercise"
                        ) { showAddExercise = true }
                    }
                    ForEach(session.entries) { entry in
                        if entry.persistentModelID == session.currentEntry?.persistentModelID {
                            ExerciseCard(session: session, entry: entry, unit: unit)
                        } else {
                            CollapsedExerciseCard(
                                name: entry.exerciseName,
                                meta: meta(for: entry),
                                isDone: session.isFinished(entry)
                            ) { session.select(entry) }
                        }
                    }
                }
                .padding(.horizontal, Space.screenMargin)
                .padding(.vertical, Space.sm)
                .animation(Motion.standard, value: session.currentEntryID)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .cadScreenBackground()
        .sheet(isPresented: $showAddExercise) {
            AddExerciseSheet(
                title: session.workout.displayName,
                excluded: Set(session.entries.compactMap { $0.exercise?.persistentModelID })
            ) { session.add($0) }
        }
        .confirmationDialog("Cancel workout?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel workout", role: .destructive) { appState.cancelWorkout() }
            Button("Keep logging", role: .cancel) {}
        } message: {
            Text("Sets you logged in this workout won't be saved.")
        }
        .confirmationDialog("Finish without any sets?", isPresented: $confirmEmptyFinish, titleVisibility: .visible) {
            Button("Discard workout", role: .destructive) { appState.cancelWorkout() }
            Button("Keep logging", role: .cancel) {}
        } message: {
            Text("No sets are ticked off, so there's nothing to save.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button {
                appState.isWorkoutPresented = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .frame(width: Size.minTouch, height: Size.minTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -10)
            .accessibilityLabel("Minimize workout")

            Spacer()
            VStack(spacing: 0) {
                Text(session.workout.displayName)
                    .font(.cadHeadline)
                    .foregroundStyle(Palette.text)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = context.date.timeIntervalSince(session.workout.start)
                    Text(DurationFormat.clock(elapsed))
                        .font(.cadFootnote)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityLabel("Elapsed \(DurationFormat.spoken(elapsed))")
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()

            Button("Finish") {
                if session.hasCompletedSets { appState.finishWorkout() } else { confirmEmptyFinish = true }
            }
            .buttonStyle(.cad(.primary, size: .small, fullWidth: false))
        }
        .frame(minHeight: Size.minTouch)
        .padding(.top, Space.xxs)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: Space.sm) {
            Button("Add exercise") { showAddExercise = true }
                .buttonStyle(.cadSecondary)
            Button("Cancel") { confirmCancel = true }
                .font(Font.cadSubhead.weight(.semibold))
                .foregroundStyle(Palette.danger)
                .frame(minWidth: 80, minHeight: Size.buttonHeight)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel workout")
        }
        .padding(.horizontal, Space.screenMargin)
        .padding(.top, Space.sm)
        .padding(.bottom, Space.xs)
        .background(Palette.tabBar)
        .overlay(alignment: .top) { Divider().overlay(Palette.line) }
    }

    private func meta(for entry: WorkoutExercise) -> String {
        let total = entry.sets.count, done = entry.completedSets.count
        let counts = "\(total) \(total == 1 ? "set" : "sets") · \(done) done"
        let entries = session.entries
        if let current = session.currentEntry,
           let i = entries.firstIndex(where: { $0.persistentModelID == current.persistentModelID }),
           entries.indices.contains(i + 1), entries[i + 1].persistentModelID == entry.persistentModelID {
            return "Next · " + counts
        }
        return counts
    }
}

@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

// MARK: - Expanded card

struct ExerciseCard: View {
    let session: WorkoutSession
    let entry: WorkoutExercise
    let unit: WeightUnit

    @State private var rejectedSet = 0

    private var tracking: TrackingType { entry.exercise?.trackingType ?? .weightReps }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.exerciseName)
                        .font(.cadHeadline)
                        .foregroundStyle(Palette.accentText)
                    if let exercise = entry.exercise {
                        Text("\(exercise.equipment.title) · \(exercise.primaryMuscle.title.lowercased())")
                            .font(.cadFootnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer()
                Menu {
                    Button("Move up", systemImage: "arrow.up") { session.move(entry, by: -1) }
                        .disabled(entry.persistentModelID == session.entries.first?.persistentModelID)
                    Button("Move down", systemImage: "arrow.down") { session.move(entry, by: 1) }
                        .disabled(entry.persistentModelID == session.entries.last?.persistentModelID)
                    Button("Remove exercise", systemImage: "trash", role: .destructive) { session.remove(entry) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: Size.minTouch, height: Size.minTouch)
                        .contentShape(Rectangle())
                }
                .padding(.trailing, -10)
                .accessibilityLabel("Exercise options")
            }

            SetTableHeader(unit: unit, showsWeight: tracking == .weightReps, repsTitle: tracking == .time ? "Sec" : "Reps")
            VStack(spacing: 2) {
                ForEach(entry.orderedSets) { set in
                    LoggedSetRow(
                        set: set,
                        previous: previousText(for: set),
                        state: state(of: set),
                        unit: unit,
                        tracking: tracking,
                        onEdit: { session.save() }
                    ) {
                        if !session.toggleComplete(set, in: entry) { rejectedSet += 1 }
                    }
                    .contextMenu {
                        Button("Delete set", systemImage: "trash", role: .destructive) {
                            session.removeSet(set, from: entry)
                        }
                    }
                }
            }
            HStack(spacing: Space.xs) {
                Button {
                    session.addSet(to: entry)
                } label: {
                    Label("Add set", systemImage: "plus")
                }
                .buttonStyle(.cad(.neutral, size: .small))
                if let last = entry.orderedSets.last, !last.isCompleted, entry.sets.count > 1 {
                    Button {
                        session.removeSet(last, from: entry)
                    } label: {
                        Image(systemName: "minus")
                            .frame(minWidth: 20)
                    }
                    .buttonStyle(.cad(.neutral, size: .small, fullWidth: false))
                    .accessibilityLabel("Remove last set")
                }
            }
            .padding(.bottom, Space.xxs)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, Space.xs)
        .cadCard(padding: 0)
        .sensoryFeedback(.error, trigger: rejectedSet)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.exerciseName)
    }

    private func state(of set: SetLog) -> SetRowState {
        if set.isCompleted { return .done }
        return set.persistentModelID == session.activeSet(in: entry)?.persistentModelID ? .active : .pending
    }

    private func previousText(for set: SetLog) -> String {
        guard let previous = session.previousSet(for: entry, index: set.index) else { return "–" }
        switch tracking {
        case .weightReps: return WeightFormatter.setString(kg: previous.weightKg, reps: previous.reps, in: unit)
        case .repsOnly: return previous.reps.map { "\($0)" } ?? "–"
        case .time: return previous.durationSeconds.map { "\($0) s" } ?? "–"
        }
    }
}

/// SetRow bound to a SetLog. Keeps its own text so typing "42." isn't reformatted mid-entry.
struct LoggedSetRow: View {
    let set: SetLog
    let previous: String
    let state: SetRowState
    let unit: WeightUnit
    let tracking: TrackingType
    let onEdit: () -> Void
    let onToggle: () -> Void

    @State private var weightText = ""
    @State private var repsText = ""

    var body: some View {
        SetRow(
            number: set.index,
            previous: previous,
            weight: $weightText,
            reps: $repsText,
            state: state,
            unit: unit,
            showsWeight: tracking == .weightReps,
            repsSpokenName: tracking == .time ? "seconds" : "repetitions",
            onToggleComplete: {
                // The check can fire before the field's last keystroke reaches onChange:
                // apply what's on screen first so the set is completed with the shown values.
                applyWeight(weightText)
                applyCount(repsText)
                onToggle()
            }
        )
        .onAppear(perform: syncFromModel)
        .onChange(of: set.weightKg) { syncFromModel() }
        .onChange(of: set.reps) { syncFromModel() }
        .onChange(of: set.durationSeconds) { syncFromModel() }
        .onChange(of: weightText) { _, text in
            if applyWeight(text) { onEdit() }
        }
        .onChange(of: repsText) { _, text in
            if applyCount(text) { onEdit() }
        }
    }

    /// Returns true if the model changed.
    @discardableResult
    private func applyWeight(_ text: String) -> Bool {
        let parsed = WeightFormatter.parse(text, in: unit)
        guard !nearlyEqual(parsed, set.weightKg) else { return false }
        set.weightKg = parsed
        return true
    }

    @discardableResult
    private func applyCount(_ text: String) -> Bool {
        let value = Int(text.trimmingCharacters(in: .whitespaces)).flatMap { $0 >= 0 ? $0 : nil }
        if tracking == .time {
            guard value != set.durationSeconds else { return false }
            set.durationSeconds = value
        } else {
            guard value != set.reps else { return false }
            set.reps = value
        }
        return true
    }

    private func syncFromModel() {
        if !nearlyEqual(WeightFormatter.parse(weightText, in: unit), set.weightKg) {
            weightText = WeightFormatter.fieldString(kg: set.weightKg, in: unit)
        }
        let count = tracking == .time ? set.durationSeconds : set.reps
        if Int(repsText) != count { repsText = count.map(String.init) ?? "" }
    }

    private func nearlyEqual(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (x?, y?): abs(x - y) < 0.001
        default: false
        }
    }
}

// MARK: - Collapsed card

struct CollapsedExerciseCard: View {
    let name: String
    let meta: String
    let isDone: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Palette.background)
                        .frame(width: 22, height: 22)
                        .background(Palette.success, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.cadHeadline)
                        .foregroundStyle(Palette.text)
                    Text(meta)
                        .font(.cadFootnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(minHeight: 64)
            .cadCard(padding: 0)
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDone ? "Done" : "")
        .accessibilityHint("Shows this exercise's sets")
    }
}

/// Active ↔ Summary inside the full-screen cover.
struct WorkoutFlowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            Group {
                if let finished = appState.finishedWorkout, !finished.isGone {
                    WorkoutSummaryView(workout: finished, isJustFinished: true)
                } else if let session = appState.session, !session.workout.isGone {
                    ActiveWorkoutView(session: session)
                        .toolbar(.hidden, for: .navigationBar)
                } else {
                    Color.clear
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
