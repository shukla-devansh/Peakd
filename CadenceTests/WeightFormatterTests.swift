import Foundation
import Testing
@testable import Cadence

@Suite("WeightFormatter")
struct WeightFormatterTests {
    let en = Locale(identifier: "en_US")

    @Test("kg display rounds to 0.25 kg")
    func kgRounding() {
        #expect(WeightFormatter.displayValue(kg: 42.5, in: .kg) == 42.5)
        #expect(WeightFormatter.displayValue(kg: 42.6, in: .kg) == 42.5)
        #expect(WeightFormatter.displayValue(kg: 42.63, in: .kg) == 42.75)
    }

    @Test("lb display converts with 2.20462 and rounds to 0.5 lb")
    func lbConversion() {
        // 100 kg = 220.462 lb → 220.5
        #expect(WeightFormatter.displayValue(kg: 100, in: .lb) == 220.5)
        // 20 kg = 44.09 lb → 44
        #expect(WeightFormatter.displayValue(kg: 20, in: .lb) == 44)
    }

    @Test("lb input round-trips to the same display value")
    func lbRoundTrip() {
        for lb in stride(from: 5.0, through: 500, by: 2.5) {
            let kg = WeightFormatter.kilograms(from: lb, in: .lb)
            #expect(WeightFormatter.displayValue(kg: kg, in: .lb) == lb)
        }
    }

    @Test("Strings drop trailing zeros and add the unit")
    func strings() {
        #expect(WeightFormatter.string(kg: 42.5, in: .kg, locale: en) == "42.5 kg")
        #expect(WeightFormatter.string(kg: 45, in: .kg, locale: en) == "45 kg")
        #expect(WeightFormatter.number(kg: 12_480, in: .kg, locale: en) == "12,480")
        #expect(WeightFormatter.spoken(kg: 45, in: .kg, locale: en) == "45 kilograms")
    }

    @Test("Previous-column set string")
    func setString() {
        #expect(WeightFormatter.setString(kg: 40, reps: 10, in: .kg, locale: en) == "40 × 10")
        #expect(WeightFormatter.setString(kg: nil, reps: 12, in: .kg, locale: en) == "12")
        #expect(WeightFormatter.setString(kg: nil, reps: nil, in: .kg, locale: en) == "–")
    }

    @Test("Parses typed input in either decimal style")
    func parse() {
        #expect(WeightFormatter.parse("42.5", in: .kg, locale: en) == 42.5)
        #expect(WeightFormatter.parse("42,5", in: .kg, locale: Locale(identifier: "de_DE")) == 42.5)
        #expect(WeightFormatter.parse("", in: .kg, locale: en) == nil)
        #expect(WeightFormatter.parse("abc", in: .kg, locale: en) == nil)
        #expect(WeightFormatter.parse("-5", in: .kg, locale: en) == nil)
        let kg = WeightFormatter.parse("100", in: .lb, locale: en) ?? 0
        #expect(abs(kg - 45.3592) < 0.001)
    }
}
