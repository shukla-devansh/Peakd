//  PreviewSupport.swift
//  Background for component previews. Debug builds only.

#if DEBUG
import SwiftUI

extension View {
    func previewSurface() -> some View {
        self
            .padding(Space.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
            .foregroundStyle(Palette.text)
            .preferredColorScheme(.dark)
    }
}
#endif
