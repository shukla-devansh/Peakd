//  ExerciseDetailView.swift
//  Board 10: records tiles, top-set weight chart (with a table fallback), the "Next time"
//  overload card, and history. Takes an ID, not the model, so a delete elsewhere can't trap it.

import SwiftData
import SwiftUI

struct ExerciseDetailView: View {
    let exerciseID: PersistentIdentifier

    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<Workout> { $0.end != nil }) private var finished: [Workout]
    @State private var showsTable = false

    private var profile: UserProfile? { profiles.first { !$0.isGone } }
    private var unit: WeightUnit { profile?.unit ?? .kg }

    private var exercise: Exercise? {
        guard let e = context.model(for: exerciseID) as? Exercise, !e.isGone else { return nil }
        return e
    }

    var body: some View {
        Group {
            if let exercise {
                content(exercise, sessions: TrainingHistory.sessions(for: exercise).filter { !$0.sets.isEmpty })
            } else {
                Color.clear
            }
        }
        .cadScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        // Re-read when workouts change (finish, edit, delete).
        .id(finished.count)
    }

    private func content(_ exercise: Exercise, sessions: [ExerciseSession]) -> some View {
        let records = ExerciseStats.records(sessions)
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(exercise.name)
                        .font(.cadScreenTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text(exercise.subtitle)
                        .font(.cadSubhead)
                        .foregroundStyle(Palette.textSecondary)
                }

                if sessions.isEmpty {
                    EmptyStateCard(
                        systemImage: "chart.line.uptrend.xyaxis",
                        title: "No sets logged yet",
                        message: "Log \(exercise.name.lowercased()) in a workout to see records and history here."
                    )
                } else {
                    recordTiles(records)
                    if records.heaviestKg != nil { topSetCard(sessions) }
                    if profile?.aiSuggestions ?? true, let card = nextTime(exercise, sessions: sessions) {
                        nextTimeCard(card)
                    }
                    history(sessions)
                }
            }
            .foregroundStyle(Palette.text)
            .padding(.horizontal, Space.screenMargin)
            .padding(.bottom, Space.lg)
        }
    }

    // MARK: Records

    private func recordTiles(_ r: ExerciseRecords) -> some View {
        var tiles: [WorkoutSummaryView.Tile] = []
        if let heaviest = r.heaviestKg, let best = r.bestSet, let est = r.est1RMKg {
            tiles = [
                .init(id: "heaviest", label: "Heaviest", value: WeightFormatter.number(kg: heaviest, in: unit),
                      unit: unit.symbol, detail: "Record", detailTone: .record),
                .init(id: "best", label: "Best set", value: WeightFormatter.setString(kg: best.weightKg, reps: best.reps, in: unit),
                      detail: "Record", detailTone: .record),
                .init(id: "1rm", label: "Est. 1RM",
                      value: WeightFormatter.displayValue(kg: est, in: unit).formatted(.number.precision(.fractionLength(1))),
                      unit: unit.symbol, detail: "Record", detailTone: .record),
            ]
        } else {
            tiles = [
                .init(id: "reps", label: "Most reps", value: "\(r.mostReps ?? 0)", detail: "Record", detailTone: .record),
                .init(id: "sessions", label: "Sessions", value: "\(r.sessions)", detail: "Logged"),
            ]
        }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3), spacing: Space.xs) {
            ForEach(tiles) { SummaryTile(tile: $0) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Records")
    }

    // MARK: Chart

    private func topSetCard(_ sessions: [ExerciseSession]) -> some View {
        let points = ExerciseStats.topSets(sessions).map {
            TrendPoint(date: $0.date, value: WeightFormatter.displayValue(kg: $0.weightKg, in: unit))
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Top set weight").font(.cadHeadline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(unit.symbol).font(.cadLabel).foregroundStyle(Palette.textSecondary)
            }
            if showsTable {
                ForEach(Array(points.reversed().enumerated()), id: \.offset) { _, p in
                    HStack {
                        Text(p.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        Spacer()
                        Text("\(Self.number(p.value)) \(unit.symbol)").monospacedDigit()
                    }
                    .font(.cadFootnote)
                    .frame(minHeight: 32)
                    .accessibilityElement(children: .combine)
                }
            } else {
                TrendChart(points: points, label: Self.number, labelsAllPoints: points.count <= 6, includesZero: false,
                           accessibilitySummary: Self.topSetSummary(points, unit: unit))
            }
            Button(showsTable ? "View as chart" : "View as table") { showsTable.toggle() }
                .font(Font.cadSubhead.weight(.medium))
                .foregroundStyle(Palette.accentText)
                .frame(minHeight: Size.minTouch)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, Space.sm)
        .cadCard(padding: 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Top set weight")
    }

    static func number(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }

    /// "Top set weight rose from 35 kilograms on 21 October to 45 kilograms on 11 November"
    static func topSetSummary(_ points: [TrendPoint], unit: WeightUnit) -> String {
        guard let first = points.first, let last = points.last else { return "Top set weight" }
        let verb = last.value > first.value ? "rose" : last.value < first.value ? "fell" : "stayed at"
        let day: (Date) -> String = { $0.formatted(.dateTime.day().month(.wide)) }
        if points.count == 1 { return "Top set weight \(number(last.value)) \(unit.spokenName) on \(day(last.date))" }
        return "Top set weight \(verb) from \(number(first.value)) \(unit.spokenName) on \(day(first.date)) to \(number(last.value)) \(unit.spokenName) on \(day(last.date))"
    }

    // MARK: Next time

    private func nextTime(_ exercise: Exercise, sessions: [ExerciseSession]) -> (title: String, detail: String)? {
        let item = exercise.routineItems.filter { !$0.isGone }.first
        let range = item.map { $0.repRangeLow...max($0.repRangeLow, $0.repRangeHigh) }
            ?? StarterPlan.repRange(for: profile?.goal ?? .strength)
        guard let s = OverloadEngine.suggest(history: sessions, repRange: range, equipment: exercise.equipment) else { return nil }
        let step = OverloadEngine.increment(for: exercise.equipment)
        return ExerciseStats.nextTime(s, last: sessions.first, step: step, unit: unit)
    }

    private func nextTimeCard(_ card: (title: String, detail: String)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(card.title, systemImage: "sparkle")
                .font(Font.cadSubhead.weight(.semibold))
                .foregroundStyle(Palette.accentText)
            Text(card.detail)
                .font(.cadFootnote)
                .foregroundStyle(Palette.text.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .cadCallout(padding: 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: History

    private func history(_ sessions: [ExerciseSession]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("History").padding(.top, Space.xxs)
            ForEach(sessions.prefix(20), id: \.date) { s in
                HStack(spacing: Space.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                            .font(Font.cadSubhead.weight(.semibold))
                        Text(ExerciseStats.setsText(s, unit: unit))
                            .font(.cadFootnote)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    let volume = ExerciseStats.volumeKg(s)
                    Text(volume > 0 ? WeightFormatter.volume(kg: volume, in: unit) : "\(s.sets.reduce(0) { $0 + $1.reps }) reps")
                        .font(.cadFootnote)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                }
                .padding(.vertical, Space.xs)
                .padding(.horizontal, 14)
                .frame(minHeight: 56)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
        }
    }
}
