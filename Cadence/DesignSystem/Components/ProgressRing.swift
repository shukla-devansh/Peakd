//  ProgressRing.swift
//  Ring used by the fatigue card, the fatigue screen and the rest timer.

import SwiftUI

struct ProgressRing: View {
    /// 0...1
    let progress: Double
    var lineWidth: CGFloat = 6
    var tint: Color = Palette.accentText
    var track: Color = Palette.line

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : Motion.slow, value: progress)
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

/// Fatigue score ring: number in the middle, ring in the band colour. `nil` score = "Not enough data".
struct FatigueRing: View {
    let score: Int?
    var diameter: CGFloat = 60
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            ProgressRing(
                progress: Double(score ?? 0) / 100,
                lineWidth: lineWidth,
                tint: score.map { FatigueBand(score: $0).tone.foreground } ?? Palette.line
            )
            Text(score.map(String.init) ?? "–")
                .font(diameter >= 100 ? .cadLargeTitle : .cadTitle)
                .monospacedDigit()
                .foregroundStyle(score == nil ? Palette.textSecondary : Palette.text)
                .minimumScaleFactor(0.5)
                .padding(lineWidth)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let score else { return "Fatigue score, not enough data" }
        return "Fatigue score \(score) of 100, \(FatigueBand(score: score).title)"
    }
}

/// One of the three band tiles on the design board (Low 0–39 · Moderate 40–69 · High 70–100).
struct FatigueBandTile: View {
    let band: FatigueBand

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(band.title)
                .font(Font.cadFootnote.weight(.bold))
                .foregroundStyle(band.tone.foreground)
            Text("\(band.range.lowerBound)–\(band.range.upperBound)")
                .font(.cadLabel)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(band.tone.background, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Rings") {
    VStack(spacing: Space.lg) {
        HStack(spacing: Space.md) {
            FatigueRing(score: 24)
            FatigueRing(score: 62)
            FatigueRing(score: 81)
            FatigueRing(score: nil)
        }
        FatigueRing(score: 62, diameter: 160, lineWidth: 12)
        ProgressRing(progress: 0.6, lineWidth: 9)
            .frame(width: 116, height: 116)
        HStack(spacing: Space.xs) {
            ForEach(FatigueBand.allCases, id: \.self) { FatigueBandTile(band: $0) }
        }
    }
    .previewSurface()
}
