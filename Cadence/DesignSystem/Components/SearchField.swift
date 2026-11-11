//  SearchField.swift
//  Inline search field from the Exercises and AddExercise boards.

import SwiftUI

struct SearchField: View {
    @Binding var text: String
    var prompt: String = "Search exercises"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.textTertiary)
                .accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Palette.textTertiary))
                .font(.cadBody)
                .foregroundStyle(Palette.text)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: Size.minTouch, height: Size.minTouch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .frame(minHeight: Size.minTouch)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
    }
}

#Preview("Search") {
    @Previewable @State var empty = ""
    @Previewable @State var filled = "bench"
    VStack(spacing: Space.sm) {
        SearchField(text: $empty)
        SearchField(text: $filled)
    }
    .previewSurface()
}
