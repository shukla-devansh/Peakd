//  ProgressOverviewView.swift
//  Board 08 (Progress): range control, totals vs the prior period, volume line chart, sets by
//  muscle group. "View as table" opens ProgressTable (board 20). Named to avoid SwiftUI.ProgressView.

import SwiftData
import SwiftUI

struct ProgressOverviewView: View {
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<Workout> { $0.end != nil }) private var workouts: [Workout]
    @Query private var records: [PersonalRecord]
    @AppStorage("progressRange") private var range: ProgressRange = .month

    private var unit: WeightUnit { profiles.first { !$0.isGone }?.unit ?? .kg }

    private var summary: ProgressSummary {
        ProgressStats.summary(range: range, workouts: TrainingHistory.digests(from: workouts),
                              recordDates: Self.recordDates(records))
    }

    /// One date per exercise that set a record in a workout (heaviest and est. 1RM count once).
    static func recordDates(_ records: [PersonalRecord]) -> [Date] {
        var seen = Set<String>()
        return records.compactMap { r in
            guard !r.isGone, r.kind != .bestSet else { return nil }
            let key = "\(r.exercise?.persistentModelID.hashValue ?? 0)-\(r.workout?.persistentModelID.hashValue ?? 0)"
            return seen.insert(key).inserted ? r.date : nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.sm) {
                    CadSegmentedControl(ProgressRange.allCases, selection: $range) { $0.title }
                        .accessibilityLabel("Time range")
                    let s = summary
                    if workouts.allSatisfy(\.isGone) {
                        EmptyStateCard(
                            systemImage: "chart.bar",
                            title: "No workouts yet",
                            message: "Finish a workout and your volume, records and muscle split show here."
                        )
                    } else {
                        tiles(s)
                        volumeCard(s)
                        TrainingCalendarCard(workouts: TrainingHistory.digests(from: workouts), unit: unit)
                        musclesCard(s)
                    }
                }
                .padding(.horizontal, Space.screenMargin)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.lg)
            }
            .cadScreenBackground()
            .navigationTitle("Progress")
            .navigationDestination(for: ProgressRange.self) { ProgressTableView(range: $0) }
        }
    }

    private func tiles(_ s: ProgressSummary) -> some View {
        let volume = WeightFormatter.volume(kg: s.volumeKg, in: unit, compact: true)
        let deltaText = s.workoutsDelta == 0 ? "Same as prior" : "\(s.workoutsDelta > 0 ? "+" : "−")\(abs(s.workoutsDelta)) vs prior"
        let volumeText = s.volumeChange.map { "\($0 >= 0 ? "+" : "−")\(abs($0))% vs prior" } ?? "No prior data"
        let items = [
            WorkoutSummaryView.Tile(id: "workouts", label: "Workouts", value: "\(s.workouts)", detail: deltaText,
                                    detailTone: s.workoutsDelta > 0 ? .success : nil),
            WorkoutSummaryView.Tile(id: "volume", label: "Volume", value: String(volume.dropLast(unit.symbol.count + 1)),
                                    unit: unit.symbol, detail: volumeText,
                                    detailTone: (s.volumeChange ?? 0) > 0 ? .success : nil),
            WorkoutSummaryView.Tile(id: "records", label: "Records", value: "\(s.records)", detail: range.recordsText),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3), spacing: Space.xs) {
            ForEach(items) { SummaryTile(tile: $0) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(range.periodText.prefix(1).uppercased() + range.periodText.dropFirst()) totals")
    }

    private func volumeCard(_ s: ProgressSummary) -> some View {
        let points = s.buckets.map { TrendPoint(date: $0.start, value: WeightFormatter.displayValue(kg: $0.volumeKg, in: unit)) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(range.bucket.chartTitle).font(.cadHeadline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(range.bucket.perText(unit)).font(.cadLabel).foregroundStyle(Palette.textSecondary)
            }
            TrendChart(
                points: points,
                label: Self.compact,
                dateFormat: range.bucket == .month ? .dateTime.month(.abbreviated) : .dateTime.month(.abbreviated).day(),
                accessibilitySummary: Self.volumeSummary(s, unit: unit)
            )
            NavigationLink(value: range) {
                Text("View as table")
                    .font(Font.cadSubhead.weight(.medium))
                    .foregroundStyle(Palette.accentText)
                    .frame(minHeight: Size.minTouch)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, Space.sm)
        .cadCard(padding: 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(range.bucket.chartTitle)
    }

    private func musclesCard(_ s: ProgressSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sets by muscle group").font(.cadHeadline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(range.periodText).font(.cadLabel).foregroundStyle(Palette.textSecondary)
            }
            BodyMapView(intensity: BodyMapView.intensity(from: s.muscles))
                .frame(height: 200)
                .padding(.vertical, Space.xxs)
            if s.muscles.isEmpty {
                Text("No sets in this period.")
                    .font(.cadFootnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(s.muscles) { share in
                HStack(spacing: 10) {
                    Text(share.muscle.title)
                        .font(.cadFootnote)
                        .frame(width: 76, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.line)
                            Capsule().fill(Palette.accentText)
                                .frame(width: geo.size.width * Double(share.percent) / 100)
                        }
                    }
                    .frame(height: 8)
                    Text("\(share.percent)%")
                        .font(.cadFootnote)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .frame(minHeight: 24)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(share.muscle.title), \(share.percent) percent of sets")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Space.sm)
        .cadCard(padding: 0)
        .foregroundStyle(Palette.text)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sets by muscle group")
    }

    /// "48.7k"
    static func compact(_ v: Double) -> String {
        v >= 1000 ? (v / 1000).formatted(.number.precision(.fractionLength(0...1))) + "k"
            : v.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// "Weekly volume rose from 38,200 kilograms in the week of 28 September to 48,700 kilograms in the week of 2 November"
    static func volumeSummary(_ s: ProgressSummary, unit: WeightUnit) -> String {
        guard let first = s.buckets.first, let last = s.buckets.last else { return s.range.bucket.chartTitle }
        func amount(_ kg: Double) -> String {
            WeightFormatter.displayValue(kg: kg, in: unit).formatted(.number.precision(.fractionLength(0))) + " " + unit.spokenName
        }
        func when(_ d: Date) -> String {
            switch s.range.bucket {
            case .day: "on " + d.formatted(.dateTime.weekday(.wide).day().month(.wide))
            case .week: "in the week of " + d.formatted(.dateTime.day().month(.wide))
            case .month: "in " + d.formatted(.dateTime.month(.wide).year())
            }
        }
        let verb = last.volumeKg > first.volumeKg ? "rose" : last.volumeKg < first.volumeKg ? "fell" : "stayed level"
        return "\(s.range.bucket.chartTitle) \(verb) from \(amount(first.volumeKg)) \(when(first.start)) to \(amount(last.volumeKg)) \(when(last.start))"
    }
}


#Preview {
    ProgressOverviewView()
        .modelContainer(PreviewData.container())
        .preferredColorScheme(.dark)
}
