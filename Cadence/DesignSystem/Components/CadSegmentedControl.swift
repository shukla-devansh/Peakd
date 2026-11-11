//  CadSegmentedControl.swift
//  Segmented radio group. `.card` = Experience (surface + border, equal widths);
//  `.inset` = Weight unit (dark well, compact segments).

import SwiftUI

struct CadSegmentedControl<Value: Hashable>: View {
    enum Style { case card, inset }

    let options: [Value]
    @Binding var selection: Value
    var style: Style = .card
    let title: (Value) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ options: [Value], selection: Binding<Value>, style: Style = .card, title: @escaping (Value) -> String) {
        self.options = options
        self._selection = selection
        self.style = style
        self.title = title
    }

    var body: some View {
        HStack(spacing: style == .card ? Space.xxs : 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(Font.cadSubhead.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, Space.sm)
                        .frame(maxWidth: style == .card ? .infinity : nil)
                        .frame(minWidth: 52, minHeight: style == .card ? 40 : 38)
                        .background(isSelected ? Palette.accent : .clear,
                                    in: RoundedRectangle(cornerRadius: style == .card ? 9 : Radius.input, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(style == .card ? Space.xxs : 3)
        .background(style == .card ? Palette.surface : Palette.background,
                    in: RoundedRectangle(cornerRadius: style == .card ? Radius.row : 10, style: .continuous))
        .overlay {
            if style == .card {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            }
        }
        .animation(reduceMotion ? nil : Motion.quick, value: selection)
    }
}

#Preview("Segmented") {
    @Previewable @State var level = Experience.intermediate
    @Previewable @State var unit = WeightUnit.kg
    VStack(alignment: .leading, spacing: Space.lg) {
        CadSegmentedControl(Experience.allCases, selection: $level) { $0.title }
            .accessibilityLabel("Experience")
        HStack {
            Text("Weight unit").font(.cadBody)
            Spacer()
            CadSegmentedControl(WeightUnit.allCases, selection: $unit, style: .inset) { $0.symbol }
        }
        .padding(Space.sm)
        .cadCard(padding: 0)
    }
    .previewSurface()
}
