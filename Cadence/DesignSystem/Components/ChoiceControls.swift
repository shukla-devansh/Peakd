//  ChoiceControls.swift
//  CheckboxCardToggleStyle: equipment grid on the Equipment board.
//  NumberChoiceRow: "Days per week" buttons on the Onboarding board.

import SwiftUI

struct CheckboxCardToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.isOn
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? Palette.accent : .clear)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(.white)
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Palette.outline, lineWidth: 1.5)
                    }
                }
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

                configuration.label
                    .font(Font.cadSubhead.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .frame(minHeight: 52)
            .frame(maxHeight: .infinity) // fill the Grid row so neighbours match
            .background(isOn ? Palette.calloutFill : Palette.surface,
                        in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .strokeBorder(isOn ? Palette.accentText : Palette.line, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
            .animation(reduceMotion ? nil : Motion.quick, value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

extension ToggleStyle where Self == CheckboxCardToggleStyle {
    static var checkboxCard: CheckboxCardToggleStyle { CheckboxCardToggleStyle() }
}

/// Equal-width number buttons; one is selected.
struct NumberChoiceRow: View {
    let options: [Int]
    @Binding var selection: Int
    /// For VoiceOver: "4 days".
    var spokenLabel: (Int) -> String = { "\($0)" }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(option, format: .number)
                        .font(.cadHeadline)
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color.white : Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: Size.compactButton)
                        .background(isSelected ? Palette.accent : Palette.surface,
                                    in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                                .strokeBorder(isSelected ? Palette.accent : Palette.line, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(spokenLabel(option))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .animation(reduceMotion ? nil : Motion.quick, value: selection)
    }
}

#Preview("Choice controls") {
    @Previewable @State var barbell = true
    @Previewable @State var bands = false
    @Previewable @State var days = 4
    VStack(spacing: Space.md) {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.xs), GridItem(.flexible())], spacing: Space.xs) {
            Toggle("Barbell", isOn: $barbell).toggleStyle(.checkboxCard)
            Toggle("Resistance bands", isOn: $bands).toggleStyle(.checkboxCard)
        }
        NumberChoiceRow(options: UserProfile.daysOptions, selection: $days) { "\($0) days" }
    }
    .previewSurface()
}
