//  AddExerciseSheet.swift
//  Board 16. Multi-select, grouped by muscle, searchable. "New" opens CustomExercise.
//  Phase 5 adds the "Suggested next" section (it needs the planner's reasons).

import SwiftData
import SwiftUI

struct AddExerciseSheet: View {
    /// Shown behind the sheet title context, e.g. "Push day".
    var title: String = "Add exercise"
    /// Exercises already in the workout or routine.
    var excluded: Set<PersistentIdentifier> = []
    let onAdd: ([Exercise]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var selected: [PersistentIdentifier] = []
    @State private var showNew = false

    private var available: [Exercise] {
        exercises.filter { !$0.isGone && !excluded.contains($0.persistentModelID) }
    }

    private var filtered: [Exercise] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return available }
        return available.filter { exercise in
            exercise.name.lowercased().contains(query)
                || exercise.aliases.contains { $0.contains(query) }
                || exercise.primaryMuscle.title.lowercased().contains(query)
                || exercise.equipment.title.lowercased().contains(query)
        }
    }

    private var sections: [(MuscleGroup, [Exercise])] {
        let grouped = Dictionary(grouping: filtered, by: \.primaryMuscle)
        return MuscleGroup.allCases.compactMap { muscle in
            grouped[muscle].map { (muscle, $0) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.xxs, pinnedViews: []) {
                    SearchField(text: $search, prompt: "Search \(available.count) exercises")
                        .padding(.bottom, Space.xs)
                    if sections.isEmpty {
                        EmptyStateCard(
                            systemImage: "magnifyingglass",
                            title: "No matches",
                            message: "Try another name, or create it as a new exercise.",
                            actionTitle: "New exercise"
                        ) { showNew = true }
                    }
                    ForEach(sections, id: \.0) { muscle, items in
                        SectionLabel(muscle.title)
                            .padding(.top, Space.sm)
                            .padding(.bottom, Space.xxs)
                        ForEach(items) { exercise in
                            ExercisePickRow(
                                name: exercise.name,
                                meta: exercise.subtitle,
                                isSelected: selected.contains(exercise.persistentModelID)
                            ) { toggle(exercise) }
                        }
                    }
                }
                .padding(.horizontal, Space.screenMargin)
                .padding(.bottom, Space.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New") { showNew = true }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(ctaTitle) {
                    let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.persistentModelID, $0) })
                    onAdd(selected.compactMap { byID[$0] })
                    dismiss()
                }
                .buttonStyle(.cadPrimary)
                .disabled(selected.isEmpty)
                .padding(.horizontal, Space.screenMargin)
                .padding(.top, Space.sm)
                .padding(.bottom, Space.xs)
                .background(Palette.surface)
                .overlay(alignment: .top) { Divider().overlay(Palette.line) }
            }
            .navigationDestination(isPresented: $showNew) {
                CustomExerciseView(initialName: search) { created in
                    selected.append(created.persistentModelID)
                    search = ""
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.surface)
        .tint(Palette.accentText)
        .preferredColorScheme(.dark)
    }

    private var ctaTitle: String {
        switch selected.count {
        case 0: "Select exercises"
        case 1: "Add 1 exercise"
        default: "Add \(selected.count) exercises"
        }
    }

    private func toggle(_ exercise: Exercise) {
        if let i = selected.firstIndex(of: exercise.persistentModelID) {
            selected.remove(at: i)
        } else {
            selected.append(exercise.persistentModelID)
        }
    }
}

/// Selectable row with a round check (AddExercise board).
struct ExercisePickRow: View {
    let name: String
    let meta: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(Font.cadBody.weight(.medium))
                        .foregroundStyle(Palette.text)
                    Text(meta)
                        .font(.cadFootnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle().fill(isSelected ? Palette.accent : .clear)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(.white)
                    } else {
                        Circle().strokeBorder(Palette.outline, lineWidth: 1.5)
                    }
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, Space.sm)
            .frame(minHeight: 56)
            .background(isSelected ? Palette.calloutFill : .clear,
                        in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .strokeBorder(isSelected ? Palette.accentText : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("Add exercise") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AddExerciseSheet { _ in }
                .modelContainer(PreviewData.container())
        }
}
