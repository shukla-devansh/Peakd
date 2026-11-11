//  StatusTone.swift
//  Foreground/background pairs for status content. Always pair with an icon or a word.

import SwiftUI

enum StatusTone: Sendable {
    case success, warning, danger, record, accent, neutral

    var foreground: Color {
        switch self {
        case .success: Palette.success
        case .warning: Palette.warning
        case .danger:  Palette.danger
        case .record:  Palette.record
        case .accent:  Palette.accentText
        case .neutral: Palette.textSecondary
        }
    }

    var background: Color {
        switch self {
        case .success: Palette.successTint
        case .warning: Palette.warningTint
        case .danger:  Palette.dangerTint
        case .record:  Palette.recordTint
        case .accent:  Palette.accentTint
        case .neutral: Palette.elevated
        }
    }
}

extension FatigueBand {
    var tone: StatusTone {
        switch self {
        case .low:      .success
        case .moderate: .warning
        case .high:     .danger
        }
    }
}
