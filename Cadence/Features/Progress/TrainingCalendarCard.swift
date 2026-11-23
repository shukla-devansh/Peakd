//  TrainingCalendarCard.swift
//  GitHub-style training calendar for Progress: one square per day for the last 18 weeks,
//  bluer the more volume you lifted that day. VoiceOver gets a summary instead of 126 squares.

import SwiftUI

struct TrainingCalendarCard: View {
    let workouts: [WorkoutDigest]
    let unit: WeightUnit
    var weeks = 18

    @State private var width: CGFloat = 320
    private let gap: CGFloat = 3
    private let labelWidth: CGFloat = 26
    private let monthRow: CGFloat = 16

    static let fills: [Color] = [
        Palette.line,
        Palette.accentText.opacity(0.28),
        Palette.accentText.opacity(0.5),
        Palette.accentText.opacity(0.75),
        Palette.accentText,
    ]

    private var cell: CGFloat {
        let fit = (width - labelWidth - gap - gap * CGFloat(weeks - 1)) / CGFloat(weeks)
        return min(18, max(8, fit.rounded(.down)))
    }

    var body: some View {
        let columns = TrainingCalendar.columns(workouts: workouts, weeks: weeks)
        let active = columns.flatMap { $0 }.filter { $0.workouts > 0 }
        let sessions = active.reduce(0) { $0 + $1.workouts }

        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Training calendar").font(.cadHeadline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("last \(weeks) weeks").font(.cadLabel).foregroundStyle(Palette.textSecondary)
            }

            grid(columns)
                .frame(height: monthRow + 7 * cell + 6 * gap)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .accessibilityHidden(true)

            HStack(spacing: 4) {
                Text("\(sessions) \(sessions == 1 ? "workout" : "workouts") on \(active.count) \(active.count == 1 ? "day" : "days")")
                    .font(.cadLabel)
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Text("Less").font(.cadLabel).foregroundStyle(Palette.textSecondary)
                ForEach(Self.fills.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2.5).fill(Self.fills[i]).frame(width: 11, height: 11)
                }
                Text("More").font(.cadLabel).foregroundStyle(Palette.textSecondary)
            }
            .accessibilityHidden(true)
        }
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 14)
        .padding(.vertical, Space.sm)
        .cadCard(padding: 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary(active: active, sessions: sessions))
    }

    private func grid(_ columns: [[HeatDay]]) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let symbols = calendar.shortWeekdaySymbols
        let firstWeekday = calendar.firstWeekday - 1

        return HStack(alignment: .top, spacing: gap) {
            // Labels on the 2nd, 4th and 6th rows ("Mon, Wed, Fri" when weeks start on Sunday).
            VStack(alignment: .leading, spacing: gap) {
                Color.clear.frame(height: monthRow - gap)
                ForEach(0..<7, id: \.self) { row in
                    Text(row % 2 == 1 ? symbols[(firstWeekday + row) % 7] : "")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: labelWidth, height: cell, alignment: .leading)
                }
            }
            ForEach(columns.indices, id: \.self) { c in
                VStack(spacing: gap) {
                    // Month name above the first column of each month.
                    let first = columns[c].first?.date ?? .now
                    let startsMonth = c > 0 && calendar.component(.month, from: first)
                        != calendar.component(.month, from: columns[c - 1].first?.date ?? .now)
                    Text(startsMonth && c < columns.count - 1 ? first.formatted(.dateTime.month(.abbreviated)) : "")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize()
                        .frame(width: cell, height: monthRow - gap, alignment: .leading)
                    ForEach(columns[c].indices, id: \.self) { r in
                        let day = columns[c][r]
                        RoundedRectangle(cornerRadius: max(2, cell * 0.22), style: .continuous)
                            .fill(day.isFuture ? Color.clear : Self.fills[day.level])
                            .overlay {
                                if day.date == today {
                                    RoundedRectangle(cornerRadius: max(2, cell * 0.22), style: .continuous)
                                        .strokeBorder(Palette.text.opacity(0.8), lineWidth: 1.2)
                                }
                            }
                            .frame(width: cell, height: cell)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// "Training calendar, last 18 weeks. 14 workouts on 12 days. Busiest day Monday 3 November, 4,000 kilograms."
    private func summary(active: [HeatDay], sessions: Int) -> String {
        var text = "Training calendar, last \(weeks) weeks. \(sessions) \(sessions == 1 ? "workout" : "workouts") on \(active.count) \(active.count == 1 ? "day" : "days")."
        if let busiest = active.max(by: { $0.volumeKg < $1.volumeKg }), busiest.volumeKg > 0 {
            let amount = WeightFormatter.displayValue(kg: busiest.volumeKg, in: unit).formatted(.number.precision(.fractionLength(0)))
            text += " Busiest day \(busiest.date.formatted(.dateTime.weekday(.wide).day().month(.wide))), \(amount) \(unit.spokenName)."
        }
        return text
    }
}

#Preview("Training calendar") {
    let now = Date.now
    let workouts = (0..<60).compactMap { i -> WorkoutDigest? in
        guard i % 3 != 1 else { return nil }
        return WorkoutDigest(date: now.addingTimeInterval(-Double(i) * 86_400 * 1.3), routineName: "Push day",
                             volumeKg: Double((i * 37) % 9 + 1) * 900, setCount: 15, setsBelowTarget: 0,
                             exerciseNames: [], muscleSets: [:])
    }
    TrainingCalendarCard(workouts: workouts, unit: .kg)
        .padding()
        .previewSurface()
}
