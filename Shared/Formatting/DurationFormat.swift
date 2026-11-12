//  DurationFormat.swift
//  Elapsed-time strings: "42:18", "1:02:05", "58 min".

import Foundation

enum DurationFormat {
    /// "42:18", or "1:02:05" past an hour.
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "58 min" (rounded to the nearest minute, at least 1).
    static func minutes(_ interval: TimeInterval) -> String {
        "\(max(1, Int((interval / 60).rounded()))) min"
    }

    /// For VoiceOver: "58 minutes 12 seconds".
    static func spoken(_ interval: TimeInterval) -> String {
        Duration.seconds(max(0, Int(interval))).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}
