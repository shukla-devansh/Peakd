//  CadButtonStyle.swift
//  Buttons from the design language board:
//  primary (accent fill), secondary (surface + border), destructive (red text), tinted (Skip), neutral (−15 / +15).

import SwiftUI

struct CadButtonStyle: ButtonStyle {
    enum Kind {
        /// "Start workout"
        case primary
        /// "Add exercise"
        case secondary
        /// "Edit plan" inside a card: elevated fill so it reads against the surface
        case elevated
        /// "Cancel workout"
        case destructive
        /// "Skip" on the rest bar
        case tinted
        /// "−15" / "+15"
        case neutral
    }

    enum Height {
        /// 52 pt, headline. Full-width CTAs.
        case regular
        /// 48 pt, headline. CTAs inside cards.
        case compact
        /// 44 pt, subheadline. Inline controls.
        case small

        var minHeight: CGFloat {
            switch self {
            case .regular: Size.buttonHeight
            case .compact: Size.compactButton
            case .small:   Size.minTouch
            }
        }
    }

    var kind: Kind
    var size: Height = .regular
    /// Stretch to the available width (default for CTAs).
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        CadButtonBody(configuration: configuration, kind: kind, size: size, fullWidth: fullWidth)
    }
}

private struct CadButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: CadButtonStyle.Kind
    let size: CadButtonStyle.Height
    let fullWidth: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(size == .small ? Font.cadSubhead.weight(.semibold) : .cadHeadline)
            .foregroundStyle(foreground)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, size == .small ? Space.sm : Space.md)
            .padding(.vertical, Space.xs)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: size.minHeight)
            .background(background, in: shape)
            .overlay { if hasBorder { shape.strokeBorder(Palette.line, lineWidth: 1) } }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size == .small ? Radius.row : Radius.button, style: .continuous)
    }

    private var hasBorder: Bool {
        kind == .secondary || kind == .neutral || kind == .elevated
    }

    private var foreground: Color {
        guard isEnabled else { return Palette.textTertiary }
        switch kind {
        case .primary:     return .white
        case .secondary:   return Palette.text
        case .elevated:    return Palette.text
        case .destructive: return Palette.danger
        case .tinted:      return Palette.accentText
        case .neutral:     return Palette.text
        }
    }

    private var background: Color {
        switch kind {
        case .primary:     return isEnabled ? Palette.accent : Palette.elevated
        case .secondary:   return Palette.surface
        case .elevated:    return Palette.elevated
        case .destructive: return .clear
        case .tinted:      return Palette.accent.opacity(0.2)
        case .neutral:     return Palette.elevated
        }
    }
}

extension ButtonStyle where Self == CadButtonStyle {
    static var cadPrimary: CadButtonStyle { CadButtonStyle(kind: .primary) }
    static var cadSecondary: CadButtonStyle { CadButtonStyle(kind: .secondary) }
    static var cadDestructive: CadButtonStyle { CadButtonStyle(kind: .destructive, size: .small) }
    static func cad(_ kind: CadButtonStyle.Kind, size: CadButtonStyle.Height = .regular, fullWidth: Bool = true) -> CadButtonStyle {
        CadButtonStyle(kind: kind, size: size, fullWidth: fullWidth)
    }
}

#Preview("Buttons") {
    VStack(spacing: Space.xs) {
        Button("Start workout") {}.buttonStyle(.cadPrimary)
        Button("Add exercise") {}.buttonStyle(.cadSecondary)
        Button("Cancel workout") {}.buttonStyle(.cadDestructive)
        Button("Save set") {}.buttonStyle(.cadPrimary).disabled(true)
        HStack(spacing: Space.xs) {
            Button("Start workout") {}.buttonStyle(.cad(.primary, size: .compact))
            Button("Edit plan") {}.buttonStyle(.cad(.elevated, size: .compact, fullWidth: false))
        }
        HStack(spacing: 6) {
            Button("−15") {}.buttonStyle(.cad(.neutral, size: .small, fullWidth: false))
            Button("+15") {}.buttonStyle(.cad(.neutral, size: .small, fullWidth: false))
            Button("Skip") {}.buttonStyle(.cad(.tinted, size: .small, fullWidth: false))
        }
    }
    .previewSurface()
}
