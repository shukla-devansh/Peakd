//  StartWorkoutView.swift
//  Board 02 (Start). Phase 5 adds the "Suggested: Push day" row (it needs the planner).

import SwiftData
import SwiftUI

struct StartWorkoutView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @Query(filter: #Predicate<Workout> { $0.end != nil }, sort: \Workout.start, order: .reverse)
    private var finished: [Workout]

    @State private var editing: RoutineEditorTarget?
    @State private var routineToDelete: Routine?

    private var liveRoutines: [Routine] { routines.filter { !$0.isGone } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        appState.startWorkout(routine: nil, in: context)
                    } label: {
                        Label(appState.session == nil ? "Start empty workout" : "Resume workout",
                              systemImage: appState.session == nil ? "plus" : "play.fill")
                    }
                    .buttonStyle(.cadPrimary)

                    VStack(alignment: .leading, spacing: Space.xxs) {
                        HStack {
                            Text("Routines")
                                .font(.cadTitle)
                                .foregroundStyle(Palette.text)
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            Button {
                                editing = .new
                            } label: {
                                Label("New", systemImage: "plus")
                                    .font(Font.cadBody.weight(.medium))
                                    .foregroundStyle(Palette.accentText)
                                    .frame(minHeight: Size.minTouch)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("New routine")
                        }
                        if liveRoutines.isEmpty {
                            EmptyStateCard(
                                systemImage: "list.bullet.rectangle",
                                title: "No routines yet",
                                message: "Save a routine to start it in one tap.",
                                actionTitle: "New routine"
                            ) { editing = .new }
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                                ForEach(liveRoutines) { routine in
                                    RoutineCard(
                                        name: routine.name,
                                        lines: lines(for: routine),
                                        lastDone: WorkoutHistory.lastDoneText(lastDone(routine))
                                    ) {
                                        appState.startWorkout(routine: routine, in: context)
                                    } onEdit: {
                                        editing = .existing(routine)
                                    } onDelete: {
                                        routineToDelete = routine
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.screenMargin)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.lg)
            }
            .cadScreenBackground()
            .navigationTitle("Workout")
            .sheet(item: $editing) { target in
                RoutineEditorView(target: target)
            }
            .confirmationDialog(
                "Delete \(routineToDelete?.name ?? "routine")?",
                isPresented: Binding(get: { routineToDelete != nil }, set: { if !$0 { routineToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete routine", role: .destructive) {
                    if let routine = routineToDelete {
                        context.delete(routine)
                        try? context.save()
                    }
                    routineToDelete = nil
                }
            } message: {
                Text("Past workouts from this routine stay in History.")
            }
        }
    }

    /// Up to three exercise names, then "+N more".
    private func lines(for routine: Routine) -> String {
        let names = routine.orderedItems.compactMap { $0.exercise?.name }
        var shown = Array(names.prefix(3))
        if names.count > 3 { shown.append("+\(names.count - 3) more") }
        return shown.isEmpty ? "No exercises" : shown.joined(separator: "\n")
    }

    private func lastDone(_ routine: Routine) -> Date? {
        finished.first { !$0.isGone && $0.routineName == routine.name }?.start
    }
}

struct RoutineCard: View {
    let name: String
    let lines: String
    let lastDone: String
    let onStart: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Button(action: onStart) {
                    Text(name)
                        .font(.cadHeadline)
                        .foregroundStyle(Palette.text)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: Size.minTouch, alignment: .topLeading)
                        .padding(.top, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start \(name)")
                Menu {
                    Button("Start workout", systemImage: "play", action: onStart)
                    Button("Edit routine", systemImage: "pencil", action: onEdit)
                    Button("Delete routine", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: Size.minTouch, height: Size.minTouch)
                        .contentShape(Rectangle())
                }
                .padding(.top, -12)
                .padding(.trailing, -12)
                .accessibilityLabel("More options for \(name)")
            }
            Button(action: onStart) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(lines)
                        .font(.cadFootnote)
                        .lineSpacing(3)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Text(lastDone)
                        .font(.cadLabel)
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .frame(minHeight: 158 - 28, alignment: .top)
        .cadCard(padding: 14)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Start") {
    StartWorkoutView()
        .environment(AppState())
        .modelContainer(PreviewData.container())
        .preferredColorScheme(.dark)
}
