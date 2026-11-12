//  WeightFormatter.swift
//  The one formatter every weight goes through (DESIGN_SPEC "Units").
//  Storage is kg. Display rounds to 0.25 kg or 0.5 lb.

import Foundation

enum WeightFormatter {
    static let poundsPerKilogram = 2.20462

    /// Rounding step for display and input in each unit.
    static func step(for unit: WeightUnit) -> Double {
        unit == .kg ? 0.25 : 0.5
    }

    /// Stored kg → value shown in `unit`, rounded to that unit's step.
    static func displayValue(kg: Double, in unit: WeightUnit) -> Double {
        let raw = unit == .kg ? kg : kg * poundsPerKilogram
        return round(raw, to: step(for: unit))
    }

    /// Value typed in `unit` → kg for storage. Not rounded, so a lb entry round-trips exactly.
    static func kilograms(from value: Double, in unit: WeightUnit) -> Double {
        unit == .kg ? value : value / poundsPerKilogram
    }

    /// "42.5", "45", "1,250" (no unit). Drops trailing zeros.
    static func number(kg: Double, in unit: WeightUnit, locale: Locale = .current) -> String {
        format(displayValue(kg: kg, in: unit), locale: locale)
    }

    /// "42.5 kg", "95 lb".
    static func string(kg: Double, in unit: WeightUnit, locale: Locale = .current) -> String {
        "\(number(kg: kg, in: unit, locale: locale)) \(unit.symbol)"
    }

    /// "40 × 10" (Previous column). "–" when there is no set to show.
    static func setString(kg: Double?, reps: Int?, in unit: WeightUnit, locale: Locale = .current) -> String {
        guard let reps else { return "–" }
        guard let kg else { return "\(reps)" }
        return "\(number(kg: kg, in: unit, locale: locale)) × \(reps)"
    }

    /// For VoiceOver: "42.5 kilograms".
    static func spoken(kg: Double, in unit: WeightUnit, locale: Locale = .current) -> String {
        "\(number(kg: kg, in: unit, locale: locale)) \(unit.spokenName)"
    }

    /// Parses user input in `unit` ("42,5" or "42.5") to kg. `nil` if not a positive number.
    static func parse(_ text: String, in unit: WeightUnit, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let value = (try? Double(trimmed, format: .number.locale(locale)))
            ?? Double(trimmed.replacingOccurrences(of: ",", with: "."))
        guard let value, value >= 0 else { return nil }
        return kilograms(from: value, in: unit)
    }

    /// Text for an editable weight field: no grouping separators, so it parses back cleanly.
    static func fieldString(kg: Double?, in unit: WeightUnit, locale: Locale = .current) -> String {
        guard let kg else { return "" }
        return displayValue(kg: kg, in: unit)
            .formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(locale))
    }

    /// Workout volume, whole units: "12,480 kg". `compact` gives "178.4k kg" for month totals.
    static func volume(kg: Double, in unit: WeightUnit, compact: Bool = false, locale: Locale = .current) -> String {
        let value = (unit == .kg ? kg : kg * poundsPerKilogram).rounded()
        let number = compact && value >= 10_000
            ? (value / 1000).formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + "k"
            : value.formatted(.number.precision(.fractionLength(0)).locale(locale))
        return "\(number) \(unit.symbol)"
    }

    // MARK: Helpers

    static func round(_ value: Double, to step: Double) -> Double {
        (value / step).rounded() * step
    }

    private static func format(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }
}
