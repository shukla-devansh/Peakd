//  ListRowCard.swift
//  Row card used by Recent workouts, History and the exercise lists: icon tile, title, subtitle, chevron.
//  Use it as the label of a NavigationLink or Button.

import SwiftUI

struct IconTile: View {
    let systemImage: String
    var side: CGFloat = 40
    var fill: Color = Palette.elevated

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: side * 0.5, weight: .regular))
            .foregroundStyle(Palette.accentText)
            .frame(width: side, height: side)
            .background(fill, in: RoundedRectangle(cornerRadius: side >= 48 ? Radius.row : 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct ListRowCard<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Space.sm) {
            if let systemImage {
                IconTile(systemImage: systemImage)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.cadHeadline)
                    .foregroundStyle(Palette.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.cadFootnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
    }
}

extension ListRowCard where Trailing == RowChevron {
    init(title: String, subtitle: String? = nil, systemImage: String? = nil) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage) { RowChevron() }
    }
}

struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.textTertiary)
            .accessibilityHidden(true)
    }
}

#Preview("List rows") {
    VStack(spacing: Space.rowGap) {
        ListRowCard(title: "Pull day", subtitle: "Monday · 52 min · 9,860 kg", systemImage: "dumbbell")
        ListRowCard(title: "Bench press", subtitle: "Chest · Barbell") {
            Text("45 kg × 8")
                .font(.cadSubhead)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
        }
        ListRowCard(title: "Incline dumbbell press", subtitle: "Next · 3 sets · 0 done")
    }
    .previewSurface()
}
