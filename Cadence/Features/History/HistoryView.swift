//  HistoryView.swift
//  Board 21. Routine filter chips, month sections with totals, record badges, row menu (Repeat, Delete).

import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<Workout> { $0.end != nil }, sort: \Workout.start, order: .reverse)
    private var finished: [Workout]

    @State private var filter: String?
    @State private var toDelete: Workout?

    private var unit: WeightUnit { profiles.first(where: { !$0.isGone })?.unit ?? .kg }
    private var workouts: [Workout] { finished.filter { !$0.isGone } }

    private var routineNames: [String] {
        var seen = Set<String>()
        return workouts.map(\.displayName).filter { seen.insert($0).inserted }
    }

    private var filtered: [Workout] {
        guard let filter else { return workouts }
        return workouts.filter { $0.displayName == filter }
    }

    private var months: [(start: Date, workouts: [Workout])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) {
            calendar.dateInterval(of: .month, for: $0.start)?.start ?? $0.start
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if workouts.isEmpty {
                    EmptyStateCard(
                        title: "No workouts yet",
                        message: "Finished workouts show here with time and total volume.",
                        actionTitle: "Browse routines"
                    ) { appState.selectedTab = .workout }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.xs) {
                            FilterChip(title: "All", isSelected: filter == nil) { filter = nil }
                            ForEach(routineNames, id: \.self) { name in
                                FilterChip(title: name, isSelected: filter == name) { filter = name }
                            }
                        }
                    }
                    .scrollClipDisabled()
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Filter by routine")

                    ForEach(months, id: \.start) { month in
                        monthSection(month.start, month.workouts)
                    }
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.lg)
        }
        .cadScreenBackground()
        .navigationTitle("History")
        .confirmationDialog("Delete this workout?", isPresented: Binding(
            get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) {
                if let workout = toDelete { WorkoutHistory.delete(workout, in: context) }
                toDelete = nil
            }
        } message: {
            Text("Its sets and any records it set are removed. This can't be undone.")
        }
    }

    private func monthSection(_ start: Date, _ items: [Workout]) -> some View {
        let isCurrentMonth = Calendar.current.isDate(start, equalTo: .now, toGranularity: .month)
        let count = "\(items.count) \(items.count == 1 ? "workout" : "workouts")"
        let total = items.reduce(0) { $0 + WorkoutMetrics.volume(of: $1) }
        let meta = isCurrentMonth ? "\(count) so far" : "\(count) · \(WeightFormatter.volume(kg: total, in: unit, compact: true))"
        let title = start.formatted(.dateTime.month(.wide))

        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.cadHeadline)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(meta)
                    .font(.cadFootnote)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(items) { workout in
                HistoryRow(
                    dayOfWeek: workout.start.formatted(.dateTime.weekday(.abbreviated)),
                    day: workout.start.formatted(.dateTime.day()),
                    name: workout.displayName,
                    meta: Self.meta(for: workout, unit: unit),
                    recordCount: RecordBook.highlights(for: workout).count,
                    destination: HistoryDestination(id: workout.persistentModelID),
                    onRepeat: { appState.repeatWorkout(workout, in: context) },
                    onDelete: { toDelete = workout }
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    /// "58 min · 12,480 kg · 18 sets"
    static func meta(for workout: Workout, unit: WeightUnit) -> String {
        let sets = WorkoutMetrics.completedSetCount(of: workout)
        return [DurationFormat.minutes(workout.duration()),
                WeightFormatter.volume(kg: WorkoutMetrics.volume(of: workout), in: unit),
                "\(sets) \(sets == 1 ? "set" : "sets")"].joined(separator: " · ")
    }
}

/// Push a past workout's Summary. Registered once, on Home's NavigationStack (see `historyDestinations()`).
struct HistoryDestination: Hashable {
    let id: PersistentIdentifier
}

enum HomeRoute: Hashable {
    case history
}

extension View {
    func historyDestinations() -> some View {
        modifier(HistoryDestinations())
    }
}

private struct HistoryDestinations: ViewModifier {
    @Query(filter: #Predicate<Workout> { $0.end != nil }) private var finished: [Workout]

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .history: HistoryView()
                }
            }
            .navigationDestination(for: HistoryDestination.self) { destination in
                if let workout = finished.first(where: { !$0.isGone && $0.persistentModelID == destination.id }) {
                    WorkoutSummaryView(workout: workout)
                }
            }
    }
}

struct HistoryRow: View {
    let dayOfWeek: String
    let day: String
    let name: String
    let meta: String
    let recordCount: Int
    let destination: HistoryDestination
    let onRepeat: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Space.xxs) {
            NavigationLink(value: destination) {
                HStack(spacing: Space.sm) {
                    VStack(spacing: 0) {
                        Text(dayOfWeek)
                            .textCase(.uppercase)
                            .font(.cadCaption)
                            .foregroundStyle(Palette.textSecondary)
                        Text(day)
                            .font(.cadTitle)
                            .monospacedDigit()
                            .foregroundStyle(Palette.text)
                    }
                    .frame(width: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.cadHeadline)
                            .foregroundStyle(Palette.text)
                        Text(meta)
                            .font(.cadFootnote)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                        if recordCount > 0 {
                            Label(recordCount == 1 ? "1 record" : "\(recordCount) records", systemImage: "trophy")
                                .labelStyle(CompactLabelStyle())
                                .font(Font.cadLabel.weight(.semibold))
                                .foregroundStyle(Palette.record)
                                .padding(.leading, 6)
                                .padding(.trailing, Space.xs)
                                .frame(minHeight: 22)
                                .background(Palette.recordTint, in: Capsule())
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)

            Menu {
                Button("Repeat workout", systemImage: "arrow.clockwise", action: onRepeat)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: Size.minTouch, height: Size.minTouch)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More options for \(name), \(dayOfWeek) \(day)")
        }
        .padding(.leading, 14)
        .padding(.trailing, Space.xxs)
        .padding(.vertical, 10)
        .frame(minHeight: 72)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.xxs) {
            configuration.icon
            configuration.title
        }
    }
}
