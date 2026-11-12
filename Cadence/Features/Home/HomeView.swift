//  HomeView.swift
//  Boards 14 (HomeEmpty) and 01 (Home). Phase 5 replaces the starter card with the suggested
//  workout and the "Not enough data" card with the fatigue ring.

import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @State private var editingRoutine: RoutineEditorTarget?
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @Query(filter: #Predicate<Workout> { $0.end != nil }, sort: \Workout.start, order: .reverse)
    private var finished: [Workout]

    // Skip objects deleted by "Delete all data" while this view is still on screen.
    private var profile: UserProfile? { profiles.first { !$0.isGone } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    let coach = CoachSnapshot(profile: profile, routines: routines, workouts: finished)
                    if !liveFinished.isEmpty, let plan = coach.plan, let profile {
                        SuggestedWorkoutCard(
                            plan: plan,
                            minutes: StarterPlan.estimatedMinutes(sets: plan.exercises.map {
                                ($0.sets, $0.restSeconds ?? profile.defaultRestSeconds)
                            }),
                            showsSuggestion: profile.aiSuggestions
                        ) {
                            appState.startWorkout(plan: plan, in: context)
                        }
                    } else if let routine = routines.first(where: { !$0.isGone }), let profile {
                        StarterPlanCard(
                            name: routine.name,
                            meta: StarterPlanCard.meta(for: routine, defaultRest: profile.defaultRestSeconds),
                            explanation: StarterPlan.explanation(daysPerWeek: profile.daysPerWeek,
                                                                 equipment: profile.availableEquipment)
                        ) {
                            appState.startWorkout(routine: routine, in: context)
                        } onEdit: {
                            editingRoutine = .existing(routine)
                        }
                    }
                    HStack(alignment: .top, spacing: 10) {
                        NavigationLink(value: HomeRoute.fatigue) {
                            if let report = coach.fatigue {
                                FatigueScoreCard(report: report)
                            } else {
                                FatigueNotEnoughDataCard(logged: liveFinished.count)
                            }
                        }
                        .buttonStyle(.plain)
                        ThisWeekCard(finished: finished, daysPerWeek: profile?.daysPerWeek ?? 4)
                    }
                    recent
                }
                .padding(.horizontal, Space.screenMargin)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.lg)
            }
            .cadStatusBarBackground()
            .cadScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .historyDestinations()
            .sheet(item: $editingRoutine) { RoutineEditorView(target: $0) }
        }
    }

    private var unit: WeightUnit { profile?.unit ?? .kg }
    private var liveFinished: [Workout] { finished.filter { !$0.isGone } }

    /// "Good afternoon" once there's history; "Welcome" before the first workout (HomeEmpty).
    private var greeting: String {
        guard !liveFinished.isEmpty else { return "Welcome" }
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.cadFootnote)
                    .foregroundStyle(Palette.textSecondary)
                Text(greeting)
                    .font(.cadScreenTitle)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            CircleIconButton(systemImage: "person", accessibilityLabel: "Profile and settings") {
                appState.selectedTab = .profile
            }
        }
    }

    @ViewBuilder
    private var recent: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if liveFinished.isEmpty {
                Text("Recent")
                    .font(.cadHeadline)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                EmptyStateCard(
                    title: "No workouts yet",
                    message: "Finished workouts show here with time and total volume. Progress charts fill in after your first week.",
                    actionTitle: "Browse routines"
                ) {
                    appState.selectedTab = .workout
                }
            } else {
                HStack {
                    Text("Recent")
                        .font(.cadHeadline)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    NavigationLink(value: HomeRoute.history) {
                        Text("See all")
                            .font(Font.cadSubhead.weight(.medium))
                            .foregroundStyle(Palette.accentText)
                            .frame(minHeight: Size.minTouch)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(liveFinished.prefix(2)) { workout in
                    NavigationLink(value: HistoryDestination(id: workout.persistentModelID)) {
                        ListRowCard(title: workout.displayName, subtitle: recentMeta(workout), systemImage: "dumbbell")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent workouts")
    }

    /// "Monday · 52 min · 9,860 kg"
    private func recentMeta(_ workout: Workout) -> String {
        [workout.start.formatted(.dateTime.weekday(.wide)),
         DurationFormat.minutes(workout.duration()),
         WeightFormatter.volume(kg: WorkoutMetrics.volume(of: workout), in: unit)].joined(separator: " · ")
    }
}

/// Takes plain values, not models: a view holding a model redraws on its own when that model is
/// deleted, and reading a deleted model traps ("Delete all data").
struct StarterPlanCard: View {
    let name: String
    let meta: String
    let explanation: String
    let onStart: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusChip("Starter plan", kind: .ai, compact: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.cadTitle)
                    .foregroundStyle(Palette.text)
                Text(meta)
                    .font(.cadSubhead)
                    .foregroundStyle(Palette.textSecondary)
            }
            Text(explanation)
                .font(.cadFootnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.xs) {
                Button("Start workout", action: onStart)
                    .buttonStyle(.cad(.primary, size: .compact))
                Button("Edit plan", action: onEdit)
                    .buttonStyle(.cad(.elevated, size: .compact, fullWidth: false))
                    .frame(minWidth: 104)
            }
            .padding(.top, 2)
        }
        .cadCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your first workout")
    }

    /// "5 exercises · about 45 min"
    @MainActor
    static func meta(for routine: Routine, defaultRest: Int) -> String {
        let count = routine.items.count
        let minutes = StarterPlan.estimatedMinutes(for: routine, defaultRest: defaultRest)
        return "\(count) \(count == 1 ? "exercise" : "exercises") · about \(minutes) min"
    }
}

/// Home board: "Suggested for today" with the planner's routine.
struct SuggestedWorkoutCard: View {
    let plan: SessionPlan
    let minutes: Int
    let showsSuggestion: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsSuggestion {
                StatusChip("Suggested for today", kind: .ai, compact: true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.routineName)
                    .font(.cadTitle)
                    .foregroundStyle(Palette.text)
                Text("\(plan.exercises.count) \(plan.exercises.count == 1 ? "exercise" : "exercises") · about \(minutes) min")
                    .font(.cadSubhead)
                    .foregroundStyle(Palette.textSecondary)
            }
            if showsSuggestion {
                Text(plan.homeReason)
                    .font(.cadFootnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Space.xs) {
                Button("Start workout", action: onStart)
                    .buttonStyle(.cad(.primary, size: .compact))
                NavigationLink(value: HomeRoute.nextSession(lighten: false)) {
                    Text("Edit plan")
                }
                .buttonStyle(.cad(.elevated, size: .compact, fullWidth: false))
                .frame(minWidth: 104)
            }
            .padding(.top, 2)
        }
        .cadCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested workout")
    }
}

/// Home board fatigue card: ring + band word (colour plus text).
struct FatigueScoreCard: View {
    let report: FatigueReport

    var body: some View {
        HStack(spacing: Space.sm) {
            FatigueRing(score: report.score)
            VStack(alignment: .leading, spacing: 2) {
                Text("Fatigue")
                    .font(.cadFootnote)
                    .foregroundStyle(Palette.textSecondary)
                Text(report.band.title)
                    .font(Font.cadHeadline.weight(.bold))
                    .foregroundStyle(report.band.tone.foreground)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .cadCard(padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fatigue \(report.score), \(report.band.title)")
        .accessibilityHint("Shows what is driving it")
    }
}

/// Fatigue card before 3 workouts are logged.
struct FatigueNotEnoughDataCard: View {
    let logged: Int
    static let required = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fatigue")
                .font(.cadFootnote)
                .foregroundStyle(Palette.textSecondary)
            Text("Not enough data")
                .font(Font.cadHeadline.weight(.bold))
                .foregroundStyle(Palette.text)
            Text("Log 3 workouts to see your score")
                .font(.cadLabel)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            StepProgressBar(
                step: min(logged, Self.required),
                total: Self.required,
                spacing: Space.xxs,
                accessibilityText: "\(min(logged, Self.required)) of \(Self.required) workouts logged"
            )
            .padding(.top, 2)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .cadCard(padding: 14)
    }
}

struct ThisWeekCard: View {
    let finished: [Workout]
    let daysPerWeek: Int

    private var days: [WeekDay] { WeekDay.week(trainedDates: finished.map(\.start)) }
    private var trainedCount: Int { days.filter { $0.status == .trained }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(.cadFootnote)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: Space.xxs)
                Text("\(trainedCount) of \(daysPerWeek)")
                    .font(Font.cadHeadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
            }
            .accessibilityElement(children: .combine)
            WeekDots(days: days)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .cadCard(padding: 14)
    }
}

#Preview("HomeEmpty") {
    HomeView()
        .environment(AppState())
        .modelContainer(PreviewData.container())
        .preferredColorScheme(.dark)
}
