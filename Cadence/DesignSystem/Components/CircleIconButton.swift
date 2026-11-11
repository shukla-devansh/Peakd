//  CircleIconButton.swift
//  44 pt round icon button (Home "Profile and settings") and the 56 pt voice button on Active.

import SwiftUI

struct CircleIconButton: View {
    enum Kind { case plain, primary }

    let systemImage: String
    let accessibilityLabel: String
    var kind: Kind = .plain
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: kind == .primary ? 24 : 19, weight: .medium))
                .foregroundStyle(kind == .primary ? Color.white : Palette.text)
                .frame(width: diameter, height: diameter)
                .background(kind == .primary ? Palette.accent : Palette.surface, in: Circle())
                .overlay { if kind == .plain { Circle().strokeBorder(Palette.line, lineWidth: 1) } }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var diameter: CGFloat { kind == .primary ? 56 : Size.minTouch }
}

#Preview("Icon buttons") {
    HStack(spacing: Space.md) {
        CircleIconButton(systemImage: "person", accessibilityLabel: "Profile and settings") {}
        CircleIconButton(systemImage: "mic", accessibilityLabel: "Log a set by voice", kind: .primary) {}
    }
    .previewSurface()
}
