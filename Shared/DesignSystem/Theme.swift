//  Theme.swift
//  Cadence — design tokens from the "00 Design language" board.
//  Dark only. 4 pt grid. SF Pro via Dynamic Type text styles.
//  Never use raw hex in views: use these tokens.

import SwiftUI

// MARK: - Color tokens

extension Color {
    /// Builds a color from a 0xRRGGBB literal.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Palette {
    // Surfaces
    static let background = Color(hex: 0x0B0D10)   // Screen background
    static let surface    = Color(hex: 0x14171C)   // Cards, list rows
    static let elevated   = Color(hex: 0x1B1F26)   // Sheets, inputs, pressed rows
    static let line       = Color(hex: 0x262B33)   // Dividers, card borders
    static let lineStrong = Color(hex: 0x3A414D)   // Pending-state outlines, grabber
    static let outline    = Color(hex: 0x5A6472)   // Active-set check box, unselected radio ring
    static let tabBar     = Color(hex: 0x0F1217)   // Only if a custom bar is ever needed

    // Text
    static let text          = Color(hex: 0xF4F6F8) // 17:1 on background
    static let textSecondary = Color(hex: 0xA3ACB9) // 7.8:1 on surface
    static let textTertiary  = Color(hex: 0x8B94A3) // Inactive tab, disabled CTA text

    // Brand
    static let accent     = Color(hex: 0x2B64F0)   // Filled buttons, white text 5.0:1
    static let accentText = Color(hex: 0x7FA6FF)   // Links, active tab, AI tint, 8.1:1

    // Status — always paired with an icon or a word, never colour alone
    static let success = Color(hex: 0x34D399)      // Completed set (check icon)
    static let warning = Color(hex: 0xF5A524)      // Moderate fatigue (label)
    static let danger  = Color(hex: 0xF2545B)      // High fatigue, delete
    static let record  = Color(hex: 0xFFC857)      // Personal records (trophy icon)

    // Tints used behind status content
    static let successTint = success.opacity(0.14)
    static let warningTint = warning.opacity(0.16)
    static let dangerTint  = danger.opacity(0.16)
    static let recordTint  = record.opacity(0.16)
    static let accentTint  = accent.opacity(0.18)

    // AI callout card ("Why this plan") and selected radio card
    static let calloutFill   = accent.opacity(0.12)
    static let calloutBorder = accentText.opacity(0.35)

    // Personal-records card (Summary)
    static let recordCalloutFill   = record.opacity(0.10)
    static let recordCalloutBorder = record.opacity(0.35)
}

// MARK: - Spacing (4 pt grid)

enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat  = 8
    static let sm: CGFloat  = 12
    static let md: CGFloat  = 16   // Screen margin, card padding
    static let lg: CGFloat  = 24
    static let xl: CGFloat  = 32

    static let screenMargin: CGFloat = 16
    static let cardPadding: CGFloat  = 16
    static let rowGap: CGFloat       = 8
}

// MARK: - Shape

enum Radius {
    static let input: CGFloat  = 8
    static let row: CGFloat    = 12
    static let button: CGFloat = 14
    static let card: CGFloat   = 16
    static let sheet: CGFloat  = 24
}

// MARK: - Sizing

enum Size {
    static let minTouch: CGFloat      = 44   // HIG minimum, enforced everywhere
    static let buttonHeight: CGFloat  = 52
    static let compactButton: CGFloat = 48
    static let setRowHeight: CGFloat  = 48
    static let chipHeight: CGFloat    = 36
}

// MARK: - Typography (Dynamic Type styles only, never fixed sizes)

extension Font {
    static let cadLargeTitle = Font.largeTitle.weight(.bold)          // 34 bold
    static let cadScreenTitle = Font.title.weight(.bold)              // 28 bold, Home / onboarding headers
    static let cadTitle      = Font.title2.weight(.bold)              // 22 bold
    static let cadHeadline   = Font.headline                          // 17 semibold
    static let cadBody       = Font.body                              // 17 regular
    static let cadSubhead    = Font.subheadline                       // 15
    static let cadFootnote   = Font.footnote                          // 13
    static let cadCaption    = Font.caption.weight(.semibold)         // 12, uppercase section labels
    static let cadLabel      = Font.caption                           // 12 regular, tile labels, meta lines
    /// Set numbers: "45.0 × 8"
    static let cadSetNumber  = Font.title3.weight(.semibold).monospacedDigit()
    /// Big timers (rest ring, lock screen)
    static let cadTimer      = Font.system(.largeTitle, design: .default).weight(.bold).monospacedDigit()
    /// Display-size timers (rest ring 64 pt, lock screen 40 pt). Pass a @ScaledMetric size so it
    /// still follows Dynamic Type.
    static func cadTimer(size: CGFloat) -> Font {
        .system(size: size, weight: .bold).monospacedDigit()
    }
}

// MARK: - Motion

enum Motion {
    /// 150–300 ms ease-out per the build rules. Respect Reduce Motion at call sites:
    /// `.animation(reduceMotion ? nil : Motion.standard, value: x)`
    static let quick    = Animation.easeOut(duration: 0.15)
    static let standard = Animation.easeOut(duration: 0.22)
    static let slow     = Animation.easeOut(duration: 0.30)
}
