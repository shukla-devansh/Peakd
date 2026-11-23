//  ExerciseLibraryView.swift
//  Board 09 (Exercises): search, muscle filter chips, Recent (with best set), A to Z.
//  Rows open ExerciseDetail; + opens CustomExercise.

import SwiftData
import SwiftUI

struct ExerciseLibraryView: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var profiles: [UserProfile]
    @State private var search = ""
    @State private var muscle: MuscleGroup?
    @State private var path = NavigationPath()
    @State private var showNew = false

    private var unit: WeightUnit { profiles.first { !$0.isGone }?.unit ?? .kg }

    private var filtered: [Exercise] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return exercises.filter { e in
            guard !e.isGone else { return false }
            if let muscle, e.primaryMuscle != muscle { return false }
            guard !query.isEmpty else { return true }
            return e.name.lowercased().contains(query)
                || e.aliases.contains { $0.contains(query) }
                || e.equipment.title.lowercased().contains(query)
        }
    }

    /// Up to three exercises from the latest finished workouts, newest first.
    private var recent: [(exercise: Exercise, best: String?)] {
        let dated = filtered.compactMap { e -> (Exercise, Date)? in
            let last = e.workoutEntries.compactMap { entry -> Date? in
                guard let w = entry.workout, !w.isGone, w.end != nil, !entry.completedSets.isEmpty else { return nil }
                return w.start
            }.max()
            return last.map { (e, $0) }
        }
        return dated.sorted { $0.1 > $1.1 }.prefix(3).map { e, _ in
            let records = ExerciseStats.records(TrainingHistory.sessions(for: e))
            let best = records.bestSet.map { WeightFormatter.string(kg: $0.weightKg ?? 0, in: unit) + " × \($0.reps)" }
                ?? records.mostReps.map { "\($0) reps" }
            return (e, best)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    SearchField(text: $search, prompt: "Search exercises")
                    chips
                    let recent = recent
                    if !recent.isEmpty {
                        SectionLabel("Recent").padding(.top, Space.xxs)
                        ForEach(recent, id: \.exercise.persistentModelID) { item in
                            NavigationLink(value: item.exercise.persistentModelID) {
                                ListRowCard(title: item.exercise.name, subtitle: item.exercise.subtitle, systemImage: "dumbbell") {
                                    if let best = item.best {
                                        Text(best)
                                            .font(.cadFootnote)
                                            .monospacedDigit()
                                            .foregroundStyle(Palette.textSecondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    SectionLabel("A to Z").padding(.top, Space.xxs)
                    if filtered.isEmpty {
                        EmptyStateCard(
                            systemImage: "magnifyingglass",
                            title: "No matches",
                            message: "Try another name, or create it as a new exercise.",
                            actionTitle: "New exercise"
                        ) { showNew = true }
                    }
                    ForEach(filtered) { exercise in
                        NavigationLink(value: exercise.persistentModelID) {
                            ListRowCard(title: exercise.name, subtitle: exercise.subtitle, systemImage: "dumbbell") { EmptyView() }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Space.screenMargin)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .cadScreenBackground()
            .navigationTitle("Exercises")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Create custom exercise")
                }
            }
            .navigationDestination(for: PersistentIdentifier.self) { ExerciseDetailView(exerciseID: $0) }
            .navigationDestination(isPresented: $showNew) {
                CustomExerciseView(initialName: search) { created in
                    search = ""
                    showNew = false
                    path.append(created.persistentModelID)
                }
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                FilterChip(title: "All", isSelected: muscle == nil) { muscle = nil }
                ForEach(MuscleGroup.filterable) { m in
                    FilterChip(title: m.title, isSelected: muscle == m) { muscle = m }
                }
            }
            .padding(.horizontal, Space.screenMargin)
        }
        .padding(.horizontal, -Space.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter by muscle group")
    }
}

#Preview {
    ExerciseLibraryView()
        .modelContainer(PreviewData.container())
        .preferredColorScheme(.dark)
}
