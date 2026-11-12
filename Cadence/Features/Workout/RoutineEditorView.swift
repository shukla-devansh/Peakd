//  RoutineEditorView.swift
//  Board 15. Edits a draft; nothing is written until Save. Reorder uses Move up / Move down buttons.

import SwiftData
import SwiftUI

enum RoutineEditorTarget: Identifiable {
    case new
    case existing(Routine)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let routine): "\(routine.persistentModelID.hashValue)"
        }
    }
}

struct RoutineDraftItem: Identifiable, Equatable {
    let id = UUID()
    let exerciseID: PersistentIdentifier
    let name: String
    var targetSets: Int
    var repLow: Int
    var repHigh: Int
    /// nil = the exercise's rest, then the profile default
    var restSeconds: Int?
}

struct RoutineEditorView: View {
    let target: RoutineEditorTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query private var exercises: [Exercise]

    @State private var name = ""
    @State private var items: [RoutineDraftItem] = []
    @State private var original: (String, [RoutineDraftItem])?
    @State private var showAddExercise = false
    @State private var editingItem: EditingItem?
    @State private var confirmDelete = false

    private var defaultRest: Int { profiles.first(where: { !$0.isGone })?.defaultRestSeconds ?? 90 }
    private var isNew: Bool { if case .new = target { true } else { false } }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var isDirty: Bool { original.map { $0.0 != name || $0.1 != items } ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Routine name")
                            .font(.cadFootnote)
                            .foregroundStyle(Palette.textSecondary)
                        TextField("", text: $name, prompt: Text("Push day").foregroundStyle(Palette.textTertiary))
                            .font(.cadHeadline)
                            .padding(.horizontal, 14)
                            .frame(minHeight: Size.compactButton)
                            .background(Palette.elevated, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                                .strokeBorder(Palette.line, lineWidth: 1))
                            .accessibilityLabel("Routine name")
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Exercises")
                            .font(.cadHeadline)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text(summary)
                            .font(.cadFootnote)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                    }

                    VStack(spacing: Space.xs) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            RoutineItemRow(
                                number: index + 1,
                                name: item.name,
                                meta: meta(for: item),
                                isFirst: index == 0,
                                isLast: index == items.count - 1,
                                onOpen: { editingItem = EditingItem(id: item.id) },
                                onUp: { move(index, by: -1) },
                                onDown: { move(index, by: 1) },
                                onRemove: { items.remove(at: index) }
                            )
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Exercises in this routine")

                    Button {
                        showAddExercise = true
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                    .buttonStyle(.cadSecondary)

                    Text("Tap an exercise to set its sets, rep range and rest time. Suggested weights come from your history on each run.")
                        .font(.cadFootnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Palette.text)
                .padding(.horizontal, Space.screenMargin)
                .padding(.vertical, Space.sm)
                .animation(Motion.standard, value: items)
            }
            .scrollDismissesKeyboard(.interactively)
            .cadScreenBackground()
            .navigationTitle(isNew ? "New routine" : "Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if case .existing = target {
                    Button("Delete routine") { confirmDelete = true }
                        .buttonStyle(.cadDestructive)
                        .padding(.horizontal, Space.screenMargin)
                        .padding(.vertical, Space.xs)
                        .background(Palette.background)
                        .overlay(alignment: .top) { Divider().overlay(Palette.line) }
                }
            }
            .sheet(isPresented: $showAddExercise) {
                AddExerciseSheet(title: trimmedName.isEmpty ? "Add exercise" : trimmedName,
                                 excluded: Set(items.map(\.exerciseID))) { picked in
                    items += picked.map { exercise in
                        RoutineDraftItem(exerciseID: exercise.persistentModelID, name: exercise.name,
                                         targetSets: 3, repLow: 8, repHigh: 10, restSeconds: exercise.defaultRestSeconds)
                    }
                }
            }
            .sheet(item: $editingItem) { editing in
                if let index = items.firstIndex(where: { $0.id == editing.id }) {
                    RoutineItemSettingsView(item: $items[index], defaultRest: defaultRest)
                }
            }
            .confirmationDialog("Delete \(trimmedName.isEmpty ? "routine" : trimmedName)?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete routine", role: .destructive, action: deleteRoutine)
            } message: {
                Text("Past workouts from this routine stay in History.")
            }
        }
        .interactiveDismissDisabled(isDirty)
        .tint(Palette.accentText)
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
    }

    private var summary: String {
        let count = items.count
        guard count > 0 else { return "0 exercises" }
        let minutes = StarterPlan.estimatedMinutes(sets: items.map { ($0.targetSets, $0.restSeconds ?? defaultRest) })
        return "\(count) \(count == 1 ? "exercise" : "exercises") · about \(minutes) min"
    }

    private func meta(for item: RoutineDraftItem) -> String {
        "\(item.targetSets) × \(item.repLow)–\(item.repHigh) · rest \(RestFormat.clock(item.restSeconds ?? defaultRest))"
    }

    private func move(_ index: Int, by offset: Int) {
        let j = index + offset
        guard items.indices.contains(j) else { return }
        items.swapAt(index, j)
    }

    private func load() {
        guard original == nil else { return }
        if case .existing(let routine) = target {
            name = routine.name
            items = routine.orderedItems.compactMap { item in
                guard let exercise = item.exercise, !exercise.isGone else { return nil }
                return RoutineDraftItem(exerciseID: exercise.persistentModelID, name: exercise.name,
                                        targetSets: item.targetSets, repLow: item.repRangeLow,
                                        repHigh: item.repRangeHigh, restSeconds: item.restSeconds)
            }
        }
        original = (name, items)
    }

    private func save() {
        let routine: Routine
        switch target {
        case .new:
            routine = Routine(name: trimmedName)
            context.insert(routine)
        case .existing(let existing):
            routine = existing
            routine.name = trimmedName
            for item in routine.items { context.delete(item) }
            routine.items = []
        }
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.persistentModelID, $0) })
        routine.items = items.enumerated().compactMap { index, draft in
            guard let exercise = byID[draft.exerciseID] else { return nil }
            return RoutineItem(order: index, exercise: exercise, targetSets: draft.targetSets,
                               repRangeLow: draft.repLow, repRangeHigh: draft.repHigh, restSeconds: draft.restSeconds)
        }
        try? context.save()
        dismiss()
    }

    private func deleteRoutine() {
        if case .existing(let routine) = target {
            context.delete(routine)
            try? context.save()
        }
        dismiss()
    }
}

private struct EditingItem: Identifiable {
    let id: UUID
}

struct RoutineItemRow: View {
    let number: Int
    let name: String
    let meta: String
    let isFirst: Bool
    let isLast: Bool
    let onOpen: () -> Void
    let onUp: () -> Void
    let onDown: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Space.xxs) {
            Button(action: onOpen) {
                HStack(spacing: Space.xxs) {
                    Text("\(number)")
                        .font(Font.cadSubhead.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 24, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.cadHeadline)
                            .foregroundStyle(Palette.text)
                        Text(meta)
                            .font(.cadFootnote)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Edits sets, rep range and rest")

            iconButton("chevron.up", label: "Move \(name) up", color: isFirst ? Palette.lineStrong : Palette.textSecondary,
                       disabled: isFirst, action: onUp)
            iconButton("chevron.down", label: "Move \(name) down", color: isLast ? Palette.lineStrong : Palette.textSecondary,
                       disabled: isLast, action: onDown)
            iconButton("trash", label: "Remove \(name)", color: Palette.danger, disabled: false, action: onRemove)
        }
        .padding(.leading, 14)
        .padding(.trailing, Space.xxs)
        .padding(.vertical, Space.xs)
        .frame(minHeight: 68)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }

    private func iconButton(_ symbol: String, label: String, color: Color, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: Size.minTouch, height: Size.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

/// Sets, rep range and rest for one routine exercise.
struct RoutineItemSettingsView: View {
    @Binding var item: RoutineDraftItem
    let defaultRest: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                settingRow("Sets") {
                    ValueStepper(value: $item.targetSets, range: 1...10, format: { "\($0)" },
                                 decrementLabel: "Fewer sets", incrementLabel: "More sets")
                }
                Divider().overlay(Palette.line)
                settingRow("Fewest reps") {
                    ValueStepper(value: Binding(get: { item.repLow },
                                                set: { item.repLow = $0; item.repHigh = max(item.repHigh, $0) }),
                                 range: 1...50, format: { "\($0)" },
                                 decrementLabel: "Fewer minimum reps", incrementLabel: "More minimum reps")
                }
                Divider().overlay(Palette.line)
                settingRow("Most reps") {
                    ValueStepper(value: Binding(get: { item.repHigh },
                                                set: { item.repHigh = $0; item.repLow = min(item.repLow, $0) }),
                                 range: 1...50, format: { "\($0)" },
                                 decrementLabel: "Fewer maximum reps", incrementLabel: "More maximum reps")
                }
                Divider().overlay(Palette.line)
                settingRow("Rest") {
                    RestStepper(restSeconds: Binding(get: { item.restSeconds ?? defaultRest },
                                                     set: { item.restSeconds = $0 }))
                }
            }
            .foregroundStyle(Palette.text)
            .cadCard(padding: 0)
            .padding(Space.screenMargin)
            .frame(maxHeight: .infinity, alignment: .top)
            .cadScreenBackground()
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .tint(Palette.accentText)
        .preferredColorScheme(.dark)
    }

    private func settingRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title).font(.cadBody)
            Spacer(minLength: Space.xs)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
    }
}

#Preview("Routine editor") {
    RoutineEditorView(target: .new)
        .modelContainer(PreviewData.container())
}
