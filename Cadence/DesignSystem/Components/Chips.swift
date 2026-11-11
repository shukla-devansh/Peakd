//  Chips.swift
//  FilterChip ("Chest" / "Back"), StatusChip (AI suggestion, new record) and TagPill ("+2.5 kg", "Same").

import SwiftUI

/// Pill filter chip. Selected = accent fill. The 36 pt pill sits in a 44 pt touch target.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(isSelected ? Font.cadSubhead.weight(.semibold) : Font.cadSubhead.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : Palette.textSecondary)
                .padding(.horizontal, Space.md)
                .frame(minHeight: Size.chipHeight)
                .background(isSelected ? Palette.accent : Palette.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Palette.accent : Palette.line, lineWidth: 1))
                .frame(minHeight: Size.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Icon + text chip. `.ai` marks every suggestion (sparkle, accent); `.record` marks PRs (trophy, gold).
struct StatusChip: View {
    enum Kind {
        case ai, record

        var systemImage: String {
            switch self {
            case .ai:     "sparkle"
            case .record: "trophy"
            }
        }

        var tone: StatusTone {
            switch self {
            case .ai:     .accent
            case .record: .record
            }
        }
    }

    let text: String
    let kind: Kind
    /// 32 pt standalone, 28 pt inside cards.
    var compact = false

    init(_ text: String, kind: Kind, compact: Bool = false) {
        self.text = text
        self.kind = kind
        self.compact = compact
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: kind.systemImage)
                .accessibilityHidden(true)
        }
        .labelStyle(ChipLabelStyle())
        .font(Font.cadFootnote.weight(.semibold))
        .foregroundStyle(kind.tone.foreground)
        .padding(.leading, compact ? Space.xs : 10)
        .padding(.trailing, Space.sm)
        .padding(.vertical, Space.xxs)
        .frame(minHeight: compact ? 28 : 32)
        .background(kind.tone.background, in: Capsule())
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title
        }
    }
}

/// Small tag next to a planned weight ("+2.5 kg", "Same"). Always text, so colour is never the only signal.
struct TagPill: View {
    let text: String
    var tone: StatusTone = .neutral

    var body: some View {
        Text(text)
            .font(Font.cadLabel.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, Space.xs)
            .frame(minHeight: 22)
            .background(tone.background, in: Capsule())
    }
}

#Preview("Chips") {
    VStack(alignment: .leading, spacing: Space.sm) {
        HStack(spacing: Space.xs) {
            FilterChip(title: "Chest", isSelected: true) {}
            FilterChip(title: "Back", isSelected: false) {}
            FilterChip(title: "Legs", isSelected: false) {}
        }
        HStack(spacing: Space.xs) {
            StatusChip("Try 42.5 kg", kind: .ai)
            StatusChip("New record", kind: .record)
        }
        StatusChip("Try 42.5 kg × 8–10 · you hit 10 reps last time", kind: .ai, compact: true)
        StatusChip("Suggested for today", kind: .ai, compact: true)
        HStack(spacing: Space.xs) {
            TagPill(text: "+2.5 kg", tone: .success)
            TagPill(text: "Same")
            TagPill(text: "−5%", tone: .warning)
        }
    }
    .previewSurface()
}
