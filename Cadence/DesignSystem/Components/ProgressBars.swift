//  ProgressBars.swift
//  LinearProgressBar: rest bar on Active. StepProgressBar: onboarding "Step 1 of 3".

import SwiftUI

struct LinearProgressBar: View {
    /// 0...1
    let progress: Double
    var tint: Color = Palette.accentText

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.line)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 4)
        .animation(reduceMotion ? nil : Motion.standard, value: progress)
        .accessibilityHidden(true)
    }
}

struct StepProgressBar: View {
    /// 1-based
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Palette.accentText : Palette.line)
                    .frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress, step \(step) of \(total)")
    }
}

#Preview("Progress bars") {
    VStack(alignment: .leading, spacing: Space.lg) {
        LinearProgressBar(progress: 0.4)
        VStack(alignment: .leading, spacing: 10) {
            StepProgressBar(step: 1, total: 3)
            Text("Step 1 of 3").font(.cadFootnote).foregroundStyle(Palette.textSecondary)
        }
    }
    .previewSurface()
}
