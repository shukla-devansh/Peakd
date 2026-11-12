//  WorkoutSummaryView.swift
//  Board 05. Right after Finish (with Done / Plan next session) or read-only from History.
//  Heart-rate and energy tiles appear only when the workout has that data (phase 9).

import SwiftData
import SwiftUI

struct WorkoutSummaryView: View {
    let workout: Workout
    var isJustFinished = false

    @Environment(AppState.self) private var appState
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<Workout> { $0.end != nil }, sort: \Workout.start, order: .reverse)
    private var finished: [Workout]

    private var unit: WeightUnit { profiles.first(where: { !$0.isGone })?.unit ?? .kg }

    var body: some View {
        if workout.isGone {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(workout.displayName) · \(workout.start.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                        .font(.cadFootnote)
                        .foregroundStyle(Palette.textSecondary)
                    Text(isJustFinished ? "Workout complete" : workout.displayName)
                        .font(.cadScreenTitle)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3), spacing: Space.xs) {
                    ForEach(tiles) { tile in
                        SummaryTile(tile: tile)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Workout totals")

                let highlights = RecordBook.highlights(for: workout)
                if !highlights.isEmpty {
                    RecordsCard(highlights: highlights, unit: unit)
                }

                VolumeBarsCard(rows: volumeRows, unit: unit)
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.lg)
        }
        .cadStatusBarBackground()
        .cadScreenBackground()
        .toolbar(isJustFinished ? .hidden : .automatic, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isJustFinished {
                HStack(spacing: Space.xs) {
                    Button("Done") { appState.closeSummary() }
                        .buttonStyle(.cad(.elevated, fullWidth: false))
                        .frame(minWidth: 104)
                    Button {
                        // Phase 5 opens NextSession here.
                        appState.closeSummary()
                        appState.selectedTab = .workout
                    } label: {
                        Label("Plan next session", systemImage: "sparkle")
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
    }

    // MARK: Data

    struct Tile: Identifiable {
        let id: String
        let label: String
        let value: String
        var unit: String = ""
        let detail: String
        var detailTone: StatusTone?
    }

    private var tiles: [Tile] {
        let duration = workout.duration()
        let setCount = WorkoutMetrics.completedSetCount(of: workout)
        let volume = WorkoutMetrics.volume(of: workout)
        let exerciseCount = workout.exercises.count

        var volumeDetail = "Total"
        var volumeTone: StatusTone?
        if let previous = previousSameRoutine,
           let change = WorkoutMetrics.percentChange(from: WorkoutMetrics.volume(of: previous), to: volume) {
            volumeDetail = "\(change >= 0 ? "+" : "−")\(abs(change))% vs last"
            volumeTone = change > 0 ? .success : nil
        }
        let volumeText = WeightFormatter.volume(kg: volume, in: unit)

        var result: [Tile] = [
            Tile(id: "duration", label: "Duration", value: DurationFormat.clock(duration),
                 detail: "\(setCount) \(setCount == 1 ? "set" : "sets")"),
            Tile(id: "volume", label: "Volume", value: String(volumeText.dropLast(unit.symbol.count + 1)),
                 unit: unit.symbol, detail: volumeDetail, detailTone: volumeTone),
            Tile(id: "reps", label: "Reps", value: "\(WorkoutMetrics.completedReps(of: workout))",
                 detail: "\(exerciseCount) \(exerciseCount == 1 ? "exercise" : "exercises")"),
        ]
        if let avg = workout.avgHR {
            result.append(Tile(id: "avgHR", label: "Avg heart rate", value: "\(Int(avg.rounded()))", unit: "bpm", detail: "Apple Watch"))
        }
        if let max = workout.maxHR {
            result.append(Tile(id: "maxHR", label: "Peak heart rate", value: "\(Int(max.rounded()))", unit: "bpm", detail: "Apple Watch"))
        }
        if let energy = workout.activeEnergy {
            result.append(Tile(id: "energy", label: "Active energy", value: "\(Int(energy.rounded()))", unit: "kcal", detail: "Apple Watch"))
        }
        return result
    }

    /// The previous finished workout of the same routine, for "+6% vs last".
    private var previousSameRoutine: Workout? {
        guard let name = workout.routineName else { return nil }
        return finished.first { other in
            !other.isGone && other.routineName == name && other.start < workout.start
                && other.persistentModelID != workout.persistentModelID
        }
    }

    private var volumeRows: [VolumeBarsCard.Row] {
        workout.orderedExercises.map { entry in
            VolumeBarsCard.Row(id: entry.persistentModelID.hashValue, name: entry.exerciseName,
                               kg: WorkoutMetrics.volume(of: entry))
        }
        .filter { $0.kg > 0 }
    }
}

struct SummaryTile: View {
    let tile: WorkoutSummaryView.Tile

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.label)
                .font(.cadLabel)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(tile.value)
                    .font(Font.cadSetNumber.weight(.bold))
                    .foregroundStyle(Palette.text)
                if !tile.unit.isEmpty {
                    Text(tile.unit)
                        .font(Font.cadLabel.weight(.medium))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(tile.detail)
                .font(Font.cadLabel.weight(.semibold))
                .foregroundStyle(tile.detailTone?.foreground ?? Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Space.sm)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct RecordsCard: View {
    let highlights: [RecordBook.Highlight]
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label {
                Text(highlights.count == 1 ? "1 new record" : "\(highlights.count) new records")
                    .font(.cadHeadline)
            } icon: {
                Image(systemName: "trophy")
            }
            .foregroundStyle(Palette.record)
            .accessibilityAddTraits(.isHeader)
            ForEach(highlights) { highlight in
                HStack(alignment: .firstTextBaseline) {
                    Text("\(highlight.exerciseName) · \(highlight.kind.title)")
                        .font(.cadSubhead)
                        .foregroundStyle(Palette.text)
                    Spacer(minLength: Space.xs)
                    Text(value(for: highlight))
                        .font(Font.cadSubhead.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.recordCalloutFill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(Palette.recordCalloutBorder, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Personal records")
    }

    private func value(for highlight: RecordBook.Highlight) -> String {
        let shown = WeightFormatter.displayValue(kg: highlight.value, in: unit)
        // est. 1RM reads like the board ("57.0 kg"); heaviest like any weight ("45 kg").
        let number = highlight.kind == .est1RM
            ? shown.formatted(.number.precision(.fractionLength(1)))
            : WeightFormatter.number(kg: highlight.value, in: unit)
        return "\(number) \(unit.symbol)"
    }
}

struct VolumeBarsCard: View {
    struct Row: Identifiable {
        let id: Int
        let name: String
        let kg: Double
    }

    let rows: [Row]
    let unit: WeightUnit

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let top = rows.map(\.kg).max() ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Volume by exercise")
                    .font(.cadHeadline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(unit.symbol)
                    .font(.cadLabel)
                    .foregroundStyle(Palette.textSecondary)
            }
            if rows.isEmpty {
                Text("Bodyweight and timed sets don't add volume.")
                    .font(.cadFootnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(rows) { row in
                let shown = WeightFormatter.volume(kg: row.kg, in: unit)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    HStack {
                        Text(row.name)
                        Spacer()
                        Text(String(shown.dropLast(unit.symbol.count + 1)))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .font(.cadFootnote)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.line)
                            Capsule().fill(Palette.accentText)
                                .frame(width: top > 0 ? proxy.size.width * row.kg / top : 0)
                        }
                    }
                    .frame(height: 8)
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.name), \(shown)")
            }
        }
        .foregroundStyle(Palette.text)
        .cadCard(padding: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Volume by exercise")
    }
}
