//  SectionHeader.swift
//  SectionLabel: uppercase form legend ("MAIN GOAL"). SectionHeader: list title with an optional link ("Recent · See all").

import SwiftUI

struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(Font.cadFootnote.weight(.semibold))
            .tracking(1)
            .foregroundStyle(Palette.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.cadHeadline)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.xs)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Font.cadSubhead.weight(.medium))
                    .foregroundStyle(Palette.accentText)
                    .frame(minHeight: Size.minTouch)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
            }
        }
        .frame(minHeight: Size.minTouch)
    }
}

#Preview("Section headers") {
    VStack(alignment: .leading, spacing: Space.md) {
        SectionLabel("Main goal")
        SectionHeader("Recent", actionTitle: "See all") {}
        SectionHeader("Volume by exercise")
    }
    .previewSurface()
}
