//  StatTile.swift
//  "Volume · 12,480 kg · +6% vs last". Read by VoiceOver as one element.

import SwiftUI

struct StatTile: View {
    let label: String
    let value: String
    var detail: String?
    /// `nil` → secondary text. Pass a tone only when the detail also says what it means ("+6% vs last").
    var detailTone: StatusTone?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.cadLabel)
                .foregroundStyle(Palette.textSecondary)
            Text(value)
                .font(.cadTitle)
                .monospacedDigit()
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(detailTone == nil ? .cadFootnote : Font.cadFootnote.weight(.semibold))
                    .foregroundStyle(detailTone?.foreground ?? Palette.textSecondary)
            }
        }
        .cadCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Stat tiles") {
    HStack(spacing: 10) {
        StatTile(label: "Volume", value: "12,480 kg", detail: "+6% vs last", detailTone: .success)
        StatTile(label: "Duration", value: "58:12", detail: "18 sets")
    }
    .previewSurface()
}
