//  TrendChart.swift
//  The line + soft area + dots chart from the Progress (08) and ExerciseDetail (10) boards.
//  The last point is larger and labelled. Callers pass the VoiceOver summary (boards' aria-label).

import Charts
import SwiftUI

struct TrendPoint: Equatable {
    let date: Date
    let value: Double
}

struct TrendChart: View {
    let points: [TrendPoint]
    /// Value labels on the points ("45"); the last point is always labelled.
    var label: (Double) -> String
    /// Axis date format.
    var dateFormat: Date.FormatStyle = .dateTime.month(.abbreviated).day()
    /// Label every point (few points) or only the last.
    var labelsAllPoints = false
    /// Volume starts at 0; weights zoom in on their range.
    var includesZero = true
    let accessibilitySummary: String

    /// At most six date labels, always including the last point.
    private var axisIndices: [Int] {
        guard !points.isEmpty else { return [] }
        let step = max(1, Int((Double(points.count) / 6).rounded(.up)))
        var result = Array(stride(from: points.count - 1, through: 0, by: -step))
        result.reverse()
        return result
    }

    var body: some View {
        let last = points.count - 1
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                AreaMark(x: .value("Point", i), y: .value("Value", p.value))
                    .foregroundStyle(Palette.accentText.opacity(0.16))
                LineMark(x: .value("Point", i), y: .value("Value", p.value))
                    .foregroundStyle(Palette.accentText)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Point", i), y: .value("Value", p.value))
                    .foregroundStyle(Palette.accentText)
                    .symbolSize(i == last ? 80 : 44)
                    .annotation(position: .top, spacing: 4) {
                        if labelsAllPoints || i == last {
                            Text(label(p.value))
                                .font(Font.cadLabel.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.text)
                        }
                    }
            }
        }
        // Evenly spaced points (as on the boards), with room so the end labels aren't clipped.
        .chartXScale(domain: -0.6...(Double(max(last, 0)) + 0.8))
        .chartYScale(domain: .automatic(includesZero: includesZero))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Palette.line)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(label(v)).font(.system(size: 10)).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: axisIndices) { value in
                AxisValueLabel {
                    if let i = value.as(Int.self), points.indices.contains(i) {
                        Text(points[i].date, format: dateFormat)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
        .frame(height: 140)
        .padding(.top, Space.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }
}

#Preview("Trend chart") {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    TrendChart(
        points: [38.2, 41.5, 39.8, 44.3, 46.1, 48.7].enumerated().map {
            TrendPoint(date: start.addingTimeInterval(Double($0.offset) * 7 * 86_400), value: $0.element * 1000)
        },
        label: { ($0 / 1000).formatted(.number.precision(.fractionLength(0...1))) + "k" },
        accessibilitySummary: "Weekly volume rose"
    )
    .cadCard()
    .previewSurface()
}
