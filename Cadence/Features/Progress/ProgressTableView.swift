//  ProgressTableView.swift
//  Board 20: the same data as the Progress charts, as tables, with Export CSV.

import SwiftData
import SwiftUI

struct ProgressTableView: View {
    let range: ProgressRange

    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<Workout> { $0.end != nil }) private var workouts: [Workout]

    private var unit: WeightUnit { profiles.first { !$0.isGone }?.unit ?? .kg }

    private var summary: ProgressSummary {
        ProgressStats.summary(range: range, workouts: TrainingHistory.digests(from: workouts))
    }

    var body: some View {
        let s = summary
        let rows = Array(s.buckets.reversed())
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(range.bucket.chartTitle)
                        .font(.cadScreenTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text("Same data as the chart · \(Self.span(range))")
                        .font(.cadSubhead)
                        .foregroundStyle(Palette.textSecondary)
                }

                TableCard(caption: "\(range.bucket.chartTitle) in \(unit.spokenName), sessions and change from the \(Self.unitName(range)) before") {
                    TableRow(cells: [range.bucket.columnTitle, unit.symbol, "Sessions", "Change"], isHeader: true)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, b in
                        TableRow(cells: [
                            Self.bucketLabel(b.start, range: range),
                            WeightFormatter.displayValue(kg: b.volumeKg, in: unit).formatted(.number.precision(.fractionLength(0))),
                            "\(b.sessions)",
                            ProgressStats.changeText(b.change),
                        ], tones: [nil, nil, Palette.textSecondary, Self.tone(b.change)],
                           showsDivider: i < rows.count - 1)
                    }
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Sets by muscle group")
                        .font(.cadHeadline)
                        .accessibilityAddTraits(.isHeader)
                    TableCard(caption: "Share of working sets by muscle group, \(range.periodText)") {
                        TableRow(cells: ["Muscle", "Share of sets"], isHeader: true)
                        ForEach(Array(s.muscles.enumerated()), id: \.element.id) { i, m in
                            TableRow(cells: [m.muscle.title, "\(m.percent)%"], showsDivider: i < s.muscles.count - 1)
                        }
                        if s.muscles.isEmpty {
                            TableRow(cells: ["No sets in this period", ""], showsDivider: false)
                        }
                    }
                }

                ShareLink(item: CSVExportFile(text: Self.csv(s, unit: unit), filename: "\(AppInfo.name) progress.csv"),
                          preview: SharePreview("\(AppInfo.name) progress.csv")) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.cad(.elevated, size: .compact))
            }
            .foregroundStyle(Palette.text)
            .padding(.horizontal, Space.screenMargin)
            .padding(.bottom, Space.lg)
        }
        .cadScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    static func span(_ range: ProgressRange) -> String {
        "last \(range.bucketCount) \(unitName(range))s"
    }

    static func unitName(_ range: ProgressRange) -> String {
        switch range.bucket {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        }
    }

    static func bucketLabel(_ date: Date, range: ProgressRange) -> String {
        switch range.bucket {
        case .day: date.formatted(.dateTime.weekday(.abbreviated).day())
        case .week: date.formatted(.dateTime.day().month(.abbreviated))
        case .month: date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        }
    }

    /// Up = green, down = amber; the text carries the ▲/▼ too.
    static func tone(_ change: Int?) -> Color {
        guard let change else { return Palette.textSecondary }
        return change >= 0 ? Palette.success : Palette.warning
    }

    static func csv(_ s: ProgressSummary, unit: WeightUnit) -> String {
        var lines = ["period_start,volume_\(unit.symbol),sessions,change_percent"]
        for b in s.buckets {
            let volume = WeightFormatter.displayValue(kg: b.volumeKg, in: unit).rounded()
            lines.append("\(b.start.formatted(.iso8601.year().month().day())),\(Int(volume)),\(b.sessions),\(b.change.map(String.init) ?? "")")
        }
        lines.append("")
        lines.append("muscle,sets,share_percent")
        for m in s.muscles { lines.append("\(m.muscle.title),\(m.sets),\(m.percent)") }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Card-styled table with a VoiceOver caption.
private struct TableCard<Content: View>: View {
    let caption: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(caption)
    }
}

/// First column left-aligned, the rest right-aligned.
private struct TableRow: View {
    let cells: [String]
    var tones: [Color?] = []
    var isHeader = false
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.xs) {
                ForEach(cells.indices, id: \.self) { i in
                    Text(isHeader ? cells[i].uppercased() : cells[i])
                        .font(isHeader ? Font.cadCaption : (i == 0 ? Font.cadSubhead.weight(.medium) : Font.cadSubhead.weight(.semibold)))
                        .tracking(isHeader ? 0.5 : 0)
                        .monospacedDigit()
                        .foregroundStyle(isHeader ? Palette.textSecondary : (i < tones.count ? tones[i] : nil) ?? Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: isHeader ? 40 : 48)
            if showsDivider { Divider().overlay(Palette.line) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHeader ? .isHeader : [])
    }
}
