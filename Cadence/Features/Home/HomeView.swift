//  HomeView.swift
//  Board 14 (HomeEmpty). Phase 3 adds the recent list and in-progress bar; phase 5 the suggested
//  workout and the fatigue ring (Home board).

import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Query private var profiles: [UserProfile]
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @Query(filter: #Predicate<Workout> { $0.end != nil }, sort: \Workout.start, order: .reverse)
    private var finished: [Workout]

    // Skip objects deleted by "Delete all data" while this view is still on screen.
    private var profile: UserProfile? { profiles.first { !$0.isDeleted } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if let routine = routines.first(where: { !$0.isDeleted }), let profile {
                        StarterPlanCard(routine: routine, profile: profile) {
                            appState.selectedTab = .workout
                        } onEdit: {
                            appState.selectedTab = .workout
                        }
                    }
                    HStack(alignment: .top, spacing: 10) {
                        FatigueNotEnoughDataCard(logged: finished.count)
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
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.cadFootnote)
                    .foregroundStyle(Palette.textSecondary)
                Text("Welcome")
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

    private var recent: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
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
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent workouts")
    }
}

struct StarterPlanCard: View {
    let routine: Routine
    let profile: UserProfile
    let onStart: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusChip("Starter plan", kind: .ai, compact: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .font(.cadTitle)
                    .foregroundStyle(Palette.text)
                Text(meta)
                    .font(.cadSubhead)
                    .foregroundStyle(Palette.textSecondary)
            }
            Text(StarterPlan.explanation(daysPerWeek: profile.daysPerWeek, equipment: profile.availableEquipment))
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

    private var meta: String {
        let count = routine.items.count
        let minutes = StarterPlan.estimatedMinutes(for: routine, defaultRest: profile.defaultRestSeconds)
        return "\(count) \(count == 1 ? "exercise" : "exercises") · about \(minutes) min"
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
