//  NextSessionView.swift
//  Board 06. The planner's next session: why, what, and the weight for each exercise.
//  Numbers come from the engines; nothing here invents them.

import SwiftData
import SwiftUI

struct NextSessionView: View {
    var lighten = false

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @Query(filter: #Predicate<Workout> { $0.end != nil }) private var workouts: [Workout]
    @State private var editing: RoutineEditorTarget?
    @State private var saved = false

    private var profile: UserProfile? { profiles.first { !$0.isGone } }
    private var unit: WeightUnit { profile?.unit ?? .kg }
    private var plan: SessionPlan? {
        CoachSnapshot(profile: profile, routines: routines, workouts: workouts, lighten: lighten).plan
    }
    private var routine: Routine? {
        guard let plan else { return nil }
        return routines.first { !$0.isGone && $0.name == plan.routineName }
    }

    var body: some View {
        Group {
            if let plan {
                content(plan)
            } else {
                ScrollView {
                    EmptyStateCard(
                        systemImage: "list.bullet.rectangle",
                        title: "Nothing to plan yet",
                        message: "Save a routine with exercises you have the equipment for, and the next session shows here.",
                        actionTitle: "New routine"
                    ) { editing = .new }
                    .padding(Space.screenMargin)
                }
            }
        }
        .cadScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { RoutineEditorView(target: $0) }
    }

    private func content(_ plan: SessionPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Next session")
                        .font(.cadScreenTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text(plan.subtitle)
                        .font(.cadSubhead)
                        .foregroundStyle(Palette.textSecondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Why this plan", systemImage: "sparkle")
                        .font(Font.cadSubhead.weight(.semibold))
                        .foregroundStyle(Palette.accentText)
                    Text(plan.explanation)
                        .font(.cadFootnote)
                        .foregroundStyle(Palette.text.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Suggestions only. Change anything before you start.")
                        .font(.cadLabel)
                        .foregroundStyle(Palette.textSecondary)
                }
                .cadCallout(padding: 14)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Why this plan. \(plan.explanation)")

                HStack {
                    Text("\(plan.exercises.count) \(plan.exercises.count == 1 ? "exercise" : "exercises")")
                        .font(.cadHeadline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if let routine {
                        Button("Edit") { editing = .existing(routine) }
                            .font(Font.cadBody.weight(.medium))
                            .foregroundStyle(Palette.accentText)
                            .frame(minHeight: Size.minTouch)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)

                VStack(spacing: 6) {
                    ForEach(plan.exercises) { exercise in
                        PlannedExerciseRow(exercise: exercise, unit: unit)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Planned exercises")
            }
            .foregroundStyle(Palette.text)
            .padding(.horizontal, Space.screenMargin)
            .padding(.bottom, Space.lg)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: Space.xs) {
                Button(saved ? "Saved" : "Save routine") { save(plan) }
                    .buttonStyle(.cad(.elevated, fullWidth: false))
                    .frame(minWidth: 124)
                    .disabled(saved || routine == nil)
                Button("Start this workout") {
                    dismiss()
                    appState.closeSummaryIfShown()
                    appState.startWorkout(plan: plan, in: context)
                }
                .buttonStyle(.cadPrimary)
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xs)
            .background(Palette.tabBar)
            .overlay(alignment: .top) { Divider().overlay(Palette.line) }
        }
    }

    /// Writes the planned set counts and rep ranges back into the routine (weights stay per session).
    private func save(_ plan: SessionPlan) {
        guard let routine else { return }
        for item in routine.items {
            guard let name = item.exercise?.name, let planned = plan.exercises.first(where: { $0.name == name }) else { continue }
            item.targetSets = planned.sets
            item.repRangeLow = planned.repRange.lowerBound
            item.repRangeHigh = planned.repRange.upperBound
        }
        try? context.save()
        saved = true
    }
}

struct PlannedExerciseRow: View {
    let exercise: PlannedExercise
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.cadHeadline)
                Text(exercise.targetText)
                    .font(.cadFootnote)
                    .foregroundStyle(Palette.textSecondary)
                Text(exercise.reason)
                    .font(.cadLabel)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                if let kg = exercise.weightKg {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(WeightFormatter.number(kg: kg, in: unit))
                            .font(Font.cadSetNumber.weight(.bold))
                        Text(unit.symbol)
                            .font(Font.cadLabel.weight(.medium))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                let tag = Self.tag(for: exercise.suggestion, unit: unit)
                TagPill(text: tag.text, tone: tag.tone)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(minHeight: 72)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// "+2.5 kg" (green), "Same", "−5%" (amber), "+1 rep", "New".
    static func tag(for suggestion: OverloadSuggestion?, unit: WeightUnit) -> (text: String, tone: StatusTone) {
        switch suggestion?.change {
        case .increase(let kg)?: ("+" + WeightFormatter.string(kg: kg, in: unit), .success)
        case .same?: ("Same", .neutral)
        case .decrease(let percent)?: ("−\(percent)%", .warning)
        case .addRep?: ("+1 rep", .success)
        case nil: ("New", .neutral)
        }
    }
}
