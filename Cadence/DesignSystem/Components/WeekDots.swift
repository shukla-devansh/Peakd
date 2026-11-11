//  WeekDots.swift
//  "This week" dots on Home: trained = filled, today = accent ring, other days = grey ring.

import SwiftUI

struct WeekDay: Identifiable, Sendable {
    enum Status: Sendable { case trained, today, notYet }

    let id: Int
    /// "M"
    let letter: String
    /// "Monday"
    let name: String
    let status: Status

    /// Monday-first week containing `date`, with trained weekdays taken from `trainedDates`.
    static func week(containing date: Date = .now, trainedDates: [Date], calendar: Calendar = .current) -> [WeekDay] {
        var calendar = calendar
        calendar.firstWeekday = 2
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let trained = trainedDates.contains { calendar.isDate($0, inSameDayAs: day) }
            let status: Status = calendar.isDate(day, inSameDayAs: date) && !trained ? .today
                : (trained ? .trained : .notYet)
            let symbolIndex = calendar.component(.weekday, from: day) - 1
            return WeekDay(
                id: offset,
                letter: calendar.veryShortStandaloneWeekdaySymbols[symbolIndex],
                name: calendar.standaloneWeekdaySymbols[symbolIndex],
                status: status
            )
        }
    }
}

struct WeekDots: View {
    let days: [WeekDay]

    var body: some View {
        HStack {
            ForEach(days) { day in
                VStack(spacing: Space.xxs) {
                    dot(for: day.status)
                    Text(day.letter)
                        .font(.cadLabel)
                        .foregroundStyle(Palette.textSecondary)
                }
                if day.id != days.last?.id { Spacer(minLength: 0) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(days))
    }

    @ViewBuilder
    private func dot(for status: WeekDay.Status) -> some View {
        switch status {
        case .trained:
            Circle().fill(Palette.accent).frame(width: 16, height: 16)
        case .today:
            Circle().strokeBorder(Palette.accentText, lineWidth: 2).frame(width: 16, height: 16)
        case .notYet:
            Circle().strokeBorder(Palette.lineStrong, lineWidth: 1.5).frame(width: 16, height: 16)
        }
    }

    /// "Trained Monday and Tuesday. Today is Wednesday."
    static func summary(_ days: [WeekDay]) -> String {
        let trained = days.filter { $0.status == .trained }.map(\.name)
        var parts: [String] = []
        parts.append(trained.isEmpty
            ? "No workouts yet this week."
            : "Trained \(trained.formatted(.list(type: .and))).")
        if let today = days.first(where: { $0.status == .today }) {
            parts.append("Today is \(today.name).")
        }
        return parts.joined(separator: " ")
    }
}

#Preview("Week dots") {
    let calendar = Calendar(identifier: .gregorian)
    let wednesday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11))!
    let trained = [-2, -1].compactMap { calendar.date(byAdding: .day, value: $0, to: wednesday) }
    VStack(spacing: Space.lg) {
        WeekDots(days: WeekDay.week(containing: wednesday, trainedDates: trained, calendar: calendar))
        WeekDots(days: WeekDay.week(containing: wednesday, trainedDates: [], calendar: calendar))
    }
    .cadCard(padding: 14)
    .previewSurface()
}
