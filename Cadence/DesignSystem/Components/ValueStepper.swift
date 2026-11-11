//  ValueStepper.swift
//  − value + control from the Equipment board ("Default rest"). VoiceOver reads − , value, + in order.

import SwiftUI

struct ValueStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    let format: (Int) -> String
    /// "Shorter rest"
    let decrementLabel: String
    /// "Longer rest"
    let incrementLabel: String
    /// Spoken value, e.g. "1 minute 30 seconds". Defaults to `format`.
    var spokenValue: ((Int) -> String)?

    var body: some View {
        HStack(spacing: Space.sm) {
            stepButton("minus", label: decrementLabel, enabled: value > range.lowerBound) { adjust(-step) }
            Text(format(value))
                .font(.cadHeadline)
                .monospacedDigit()
                .frame(minWidth: 52)
                .accessibilityLabel((spokenValue ?? format)(value))
            stepButton("plus", label: incrementLabel, enabled: value < range.upperBound) { adjust(step) }
        }
        .accessibilityElement(children: .contain)
    }

    private func adjust(_ delta: Int) {
        value = min(max(value + delta, range.lowerBound), range.upperBound)
    }

    private func stepButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(enabled ? Palette.text : Palette.textTertiary)
                .frame(width: Size.minTouch, height: Size.minTouch)
                .background(Palette.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// "1:30" for rest durations.
enum RestFormat {
    static func clock(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    static func spoken(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }
}

#Preview("Stepper") {
    @Previewable @State var rest = 90
    HStack {
        VStack(alignment: .leading) {
            Text("Default rest").font(.cadBody)
            Text("Change per exercise later").font(.cadFootnote).foregroundStyle(Palette.textSecondary)
        }
        Spacer()
        ValueStepper(
            value: $rest,
            range: UserProfile.restRange,
            step: UserProfile.restStep,
            format: RestFormat.clock,
            decrementLabel: "Shorter rest",
            incrementLabel: "Longer rest",
            spokenValue: RestFormat.spoken
        )
    }
    .cadCard()
    .previewSurface()
}
