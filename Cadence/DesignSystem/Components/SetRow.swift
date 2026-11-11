//  SetRow.swift
//  Set table from the Active board: header + rows in three states.
//  done = success tint + green check · active = elevated + accent border · pending = transparent + grey outline.

import SwiftUI

enum SetRowState: Equatable, Sendable {
    case done, active, pending
}

/// Base column widths from the board, scaled with Dynamic Type by each view.
private enum SetColumns {
    static let set: CGFloat = 32
    static let weight: CGFloat = 64
    static let reps: CGFloat = 56
    static let check: CGFloat = 44
}

struct SetTableHeader: View {
    let unit: WeightUnit
    var showsWeight = true

    @ScaledMetric(relativeTo: .caption) private var setWidth = SetColumns.set
    @ScaledMetric(relativeTo: .caption) private var weightWidth = SetColumns.weight
    @ScaledMetric(relativeTo: .caption) private var repsWidth = SetColumns.reps

    var body: some View {
        HStack(spacing: Space.xs) {
            Text("Set").frame(width: setWidth, alignment: .leading)
            Text("Previous").frame(maxWidth: .infinity, alignment: .leading)
            if showsWeight {
                Text(unit.symbol).frame(width: weightWidth)
            }
            Text("Reps").frame(width: repsWidth)
            Color.clear.frame(width: SetColumns.check, height: 1)
        }
        .textCase(.uppercase)
        .font(.cadCaption)
        .tracking(0.5)
        .foregroundStyle(Palette.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 6)
        .accessibilityHidden(true) // Each row's fields carry full labels.
    }
}

struct SetRow: View {
    let number: Int
    /// Last session's same set, e.g. "40 × 10", or "–".
    let previous: String
    @Binding var weight: String
    @Binding var reps: String
    let state: SetRowState
    let unit: WeightUnit
    var showsWeight = true
    let onToggleComplete: () -> Void

    @ScaledMetric(relativeTo: .headline) private var setWidth = SetColumns.set
    @ScaledMetric(relativeTo: .headline) private var weightWidth = SetColumns.weight
    @ScaledMetric(relativeTo: .headline) private var repsWidth = SetColumns.reps
    @ScaledMetric(relativeTo: .headline) private var fieldHeight: CGFloat = 36
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.xs) {
            Text(number, format: .number)
                .font(.cadHeadline)
                .frame(width: setWidth, alignment: .leading)
                .accessibilityLabel("Set \(number)")

            Text(previous)
                .font(.cadSubhead)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel(previous == "–" ? "No previous set" : "Previous \(previous)")

            if showsWeight {
                field(text: $weight, keyboard: .decimalPad, width: weightWidth)
                    .accessibilityLabel("Set \(number) weight in \(unit.spokenName)")
            }
            field(text: $reps, keyboard: .numberPad, width: repsWidth)
                .accessibilityLabel("Set \(number) repetitions")

            checkButton
        }
        .monospacedDigit()
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 6)
        .frame(minHeight: Size.setRowHeight)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .strokeBorder(state == .active ? Palette.accent : .clear, lineWidth: 1)
        )
        .animation(reduceMotion ? nil : Motion.standard, value: state)
        .sensoryFeedback(.impact(weight: .light), trigger: state) { _, new in new == .done }
    }

    private func field(text: Binding<String>, keyboard: UIKeyboardType, width: CGFloat) -> some View {
        TextField("", text: text, prompt: Text("–").foregroundStyle(Palette.textTertiary))
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.cadHeadline)
            .frame(width: width, height: fieldHeight)
            .background(fieldBackground, in: RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
    }

    private var checkButton: some View {
        Button(action: onToggleComplete) {
            Group {
                if state == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Palette.background)
                        .frame(width: 28, height: 28)
                        .background(Palette.success, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(state == .active ? Palette.outline : Palette.lineStrong, lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                }
            }
            .frame(width: SetColumns.check, height: SetColumns.check)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mark set \(number) complete")
        .accessibilityValue(state == .done ? "Done" : "Not done")
    }

    private var rowBackground: Color {
        switch state {
        case .done:    Palette.successTint
        case .active:  Palette.elevated
        case .pending: .clear
        }
    }

    private var fieldBackground: Color {
        switch state {
        case .done:    .clear
        case .active:  Palette.line
        case .pending: Palette.elevated
        }
    }
}

#Preview("Set table") {
    @Previewable @State var rows: [(w: String, r: String, s: SetRowState)] = [
        ("42.5", "10", .done), ("42.5", "10", .done), ("42.5", "", .active), ("", "", .pending),
    ]
    let previous = ["40 × 10", "40 × 10", "40 × 10", "40 × 9"]

    VStack(spacing: 2) {
        SetTableHeader(unit: .kg)
        ForEach(rows.indices, id: \.self) { i in
            SetRow(
                number: i + 1,
                previous: previous[i],
                weight: $rows[i].w,
                reps: $rows[i].r,
                state: rows[i].s,
                unit: .kg
            ) {
                rows[i].s = rows[i].s == .done ? .active : .done
            }
        }
    }
    .padding(Space.sm)
    .cadCard(padding: 0)
    .previewSurface()
}
