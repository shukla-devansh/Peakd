//  WorkoutShareCard.swift
//  Shareable workout image in three formats: Story (9:16), Square (1:1) and Sticker (transparent,
//  to lay over your own photo). Fixed point sizes so the image looks the same on every phone;
//  rendered at 3× (1080 px wide) by WorkoutShareSheet.

import SwiftData
import SwiftUI

enum ShareStyle: String, CaseIterable, Identifiable, Sendable {
    case story, square, sticker
    var id: String { rawValue }

    var title: String {
        switch self {
        case .story: "Story"
        case .square: "Square"
        case .sticker: "Sticker"
        }
    }

    /// Points; ×3 when rendered.
    var size: CGSize {
        switch self {
        case .story: CGSize(width: 360, height: 640)
        case .square: CGSize(width: 360, height: 360)
        case .sticker: CGSize(width: 360, height: 250)
        }
    }
}

/// Everything the card shows, as plain values.
struct WorkoutShareData: Equatable {
    struct Line: Equatable, Identifiable {
        var name: String
        var detail: String
        var sets: Int = 0
        var id: String { name }
    }

    var title: String
    var date: Date
    var duration: TimeInterval
    var volumeKg: Double
    var sets: Int
    var reps: Int
    var exercises: [Line]
    var records: [Line]
    var muscles: [MuscleShare]
    var unit: WeightUnit

    @MainActor
    static func make(_ workout: Workout, unit: WeightUnit) -> WorkoutShareData {
        let entries = workout.orderedExercises.filter { !$0.isGone && !$0.completedSets.isEmpty }
        let lines = entries.map { entry -> Line in
            let done = entry.completedSets
            let best = done.filter { ($0.weightKg ?? 0) > 0 && ($0.reps ?? 0) > 0 }.max {
                WorkoutMetrics.estimatedOneRepMax(weightKg: $0.weightKg ?? 0, reps: $0.reps ?? 0)
                    < WorkoutMetrics.estimatedOneRepMax(weightKg: $1.weightKg ?? 0, reps: $1.reps ?? 0)
            }
            let detail: String
            if let best, let kg = best.weightKg, let reps = best.reps {
                detail = "\(WeightFormatter.string(kg: kg, in: unit)) × \(reps)"
            } else if let seconds = done.compactMap(\.durationSeconds).max() {
                detail = DurationFormat.clock(TimeInterval(seconds))
            } else {
                detail = "\(done.compactMap(\.reps).max() ?? 0) reps"
            }
            return Line(name: entry.exerciseName, detail: detail, sets: done.count)
        }
        let records = RecordBook.highlights(for: workout).map {
            Line(name: $0.exerciseName, detail: "\($0.kind.title) \(WeightFormatter.string(kg: $0.value, in: unit))")
        }
        return WorkoutShareData(
            title: workout.displayName,
            date: workout.start,
            duration: workout.duration(),
            volumeKg: WorkoutMetrics.volume(of: workout),
            sets: WorkoutMetrics.completedSetCount(of: workout),
            reps: WorkoutMetrics.completedReps(of: workout),
            exercises: lines,
            records: records,
            muscles: ProgressStats.muscleShares([TrainingHistory.digest(workout)]),
            unit: unit
        )
    }
}

struct WorkoutShareCard: View {
    let data: WorkoutShareData
    let style: ShareStyle
    var showsWeights = true

    var body: some View {
        Group {
            switch style {
            case .story: story
            case .square: square
            case .sticker: sticker
            }
        }
        .frame(width: style.size.width, height: style.size.height)
        .foregroundStyle(Palette.text)
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
    }

    // MARK: Formats

    private var story: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            Spacer(minLength: 18)
            // Content sits in the middle, so a short workout doesn't leave a hole.
            VStack(alignment: .leading, spacing: 18) {
                Text(data.title)
                    .font(.system(size: 40, weight: .bold))
                    .tracking(-0.8)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                stats(size: 30)
                if !data.records.isEmpty { recordsBlock(limit: 2) }
                exercisesBlock(limit: data.records.isEmpty ? 6 : 4)
                if !data.muscles.isEmpty { bodyRow }
            }
            Spacer(minLength: 18)
            footer
        }
        .padding(28)
        .background(glow)
    }

    private var square: some View {
        VStack(alignment: .leading, spacing: 14) {
            topRow
            Text(data.title)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            stats(size: 26)
            Spacer(minLength: 0)
            if let record = data.records.first {
                recordPill(record, extra: data.records.count - 1)
            } else {
                exercisesBlock(limit: 2)
            }
            footer
        }
        .padding(24)
        .background(glow)
    }

    private var sticker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppInfo.name.uppercased())
                .font(.system(size: 13, weight: .heavy))
                .tracking(4)
                .foregroundStyle(Palette.accentText)
            Text(data.title)
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            stats(size: 30)
            if !data.records.isEmpty {
                Label("\(data.records.count) new \(data.records.count == 1 ? "record" : "records")", systemImage: "trophy.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.record)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
    }

    // MARK: Pieces

    private var topRow: some View {
        HStack {
            Text(AppInfo.name.uppercased())
                .font(.system(size: 13, weight: .heavy))
                .tracking(4)
                .foregroundStyle(Palette.accentText)
            Spacer()
            Text(data.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private func stats(size: CGFloat) -> some View {
        let volume = WeightFormatter.displayValue(kg: data.volumeKg, in: data.unit)
        let volumeText = volume >= 100_000 ? (volume / 1000).formatted(.number.precision(.fractionLength(0...1))) + "k"
            : volume.formatted(.number.precision(.fractionLength(0)))
        return HStack(alignment: .top, spacing: 0) {
            stat(DurationFormat.clock(data.duration), "Time", size: size)
            if showsWeights {
                stat(volumeText, "\(data.unit.symbol) lifted", size: size)
            } else {
                stat("\(data.reps)", "reps", size: size)
            }
            stat("\(data.sets)", data.sets == 1 ? "set" : "sets", size: size)
        }
    }

    private func stat(_ value: String, _ label: String, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: size, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordsBlock(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(data.records.count) new \(data.records.count == 1 ? "record" : "records")", systemImage: "trophy.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.record)
            ForEach(data.records.prefix(limit)) { r in
                HStack {
                    Text(r.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Spacer()
                    if showsWeights {
                        Text(r.detail).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    }
                }
            }
        }
        .padding(14)
        .background(Palette.record.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.record.opacity(0.35), lineWidth: 1))
    }

    private func recordPill(_ record: WorkoutShareData.Line, extra: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill").foregroundStyle(Palette.record)
            Text(record.name + (showsWeights ? " · \(record.detail)" : ""))
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if extra > 0 {
                Text("+\(extra)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.record)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Palette.record.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.record.opacity(0.35), lineWidth: 1))
    }

    private func exercisesBlock(limit: Int) -> some View {
        let shown = Array(data.exercises.prefix(limit))
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, line in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text("\(line.sets) \(line.sets == 1 ? "set" : "sets")")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    if showsWeights {
                        Text(line.detail)
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.text.opacity(0.9))
                    }
                }
                .padding(.vertical, 9)
                if i < shown.count - 1 { Divider().overlay(Palette.line) }
            }
            if data.exercises.count > limit {
                Text("+\(data.exercises.count - limit) more")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Palette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }

    /// Small front/back body with the top muscle groups beside it.
    private var bodyRow: some View {
        HStack(alignment: .center, spacing: 18) {
            BodyMapView(intensity: BodyMapView.intensity(from: data.muscles), showsLabels: false)
                .frame(width: 128, height: 118)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(data.muscles.prefix(4)) { m in
                    HStack(spacing: 6) {
                        Text(m.muscle.title).font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 4)
                        Text("\(m.percent)%")
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
            Text("Logged with \(AppInfo.name)")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Palette.textSecondary)
    }

    private var glow: some View {
        ZStack {
            Palette.background
            Circle()
                .fill(Palette.accent.opacity(0.55))
                .frame(width: style.size.width * 1.1)
                .blur(radius: 90)
                .offset(x: -style.size.width * 0.45, y: -style.size.height * 0.45)
            Circle()
                .fill(Palette.success.opacity(0.18))
                .frame(width: style.size.width * 0.9)
                .blur(radius: 90)
                .offset(x: style.size.width * 0.5, y: style.size.height * 0.45)
        }
        .clipped()
    }
}

extension WorkoutShareData {
    static let preview = WorkoutShareData(
        title: "Push day", date: .now, duration: 58 * 60 + 12, volumeKg: 12_480, sets: 18, reps: 152,
        exercises: [
            .init(name: "Bench press", detail: "45 kg × 8", sets: 3),
            .init(name: "Incline dumbbell press", detail: "22 kg × 10", sets: 3),
            .init(name: "Overhead press", detail: "35 kg × 8", sets: 3),
            .init(name: "Cable fly", detail: "15 kg × 12", sets: 3),
            .init(name: "Triceps pushdown", detail: "25 kg × 12", sets: 3),
        ],
        records: [.init(name: "Bench press", detail: "est. 1RM 57 kg")],
        muscles: [.init(muscle: .chest, sets: 9, percent: 50), .init(muscle: .shoulders, sets: 6, percent: 33),
                  .init(muscle: .arms, sets: 3, percent: 17)],
        unit: .kg
    )
}

#Preview("Share cards") {
    ScrollView {
        VStack(spacing: 20) {
            ForEach(ShareStyle.allCases) {
                WorkoutShareCard(data: .preview, style: $0).clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
    .background(Color.gray)
}
