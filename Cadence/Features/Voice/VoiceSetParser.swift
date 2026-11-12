//  VoiceSetParser.swift
//  Turns a transcript into weight and reps. Deterministic: no model, no guessing beyond the rules
//  below, and nothing is saved from here (the Voice sheet asks the user to confirm).
//
//  Handles "45 kilos for 8 reps", "45 for 8", "forty five kg eight reps", "same weight 10 reps",
//  "add 2.5 kilos 8 reps", "8 reps" (weight from the current row), "bodyweight 12", pound variants,
//  number words with "and a half" / "point five", and gym shorthand like "one thirty five pounds".

import Foundation

struct VoiceParseContext: Sendable, Equatable {
    /// Unit for numbers said without one.
    var unit: WeightUnit
    /// Weight already in the row being logged (or the set above): used by "same weight",
    /// "add 2.5", and phrases that only give reps.
    var currentWeightKg: Double?
    /// False for reps-only exercises: every number is reps.
    var tracksWeight = true
}

struct VoiceParseResult: Sendable, Equatable {
    enum Field: Sendable, Hashable { case weight, reps }

    var weightKg: Double?
    var reps: Int?
    var isBodyweight = false
    /// Fields the user still has to give (VoiceRetry asks only for these).
    var missing: Set<Field> = []

    var isComplete: Bool { missing.isEmpty }
}

enum VoiceSetParser {
    static let maxReps = 100
    static let maxWeightKg = 1000.0

    static func parse(_ transcript: String, context: VoiceParseContext) -> VoiceParseResult {
        let tokens = tokenize(transcript)
        var result = interpret(tokens, context: context)
        if !context.tracksWeight { result.weightKg = nil; result.isBodyweight = false }
        var missing: Set<VoiceParseResult.Field> = []
        if result.reps == nil { missing.insert(.reps) }
        if context.tracksWeight && result.weightKg == nil { missing.insert(.weight) }
        result.missing = missing
        return result
    }

    // MARK: - Tokens

    enum Token: Equatable, Sendable {
        case number(Double)
        case kg, lb
        case reps
        case bodyweight
        case same
        case add, subtract
        /// "for", "at", "x", "by": joins weight and reps.
        case separator
        /// "times": reps when it ends the phrase, a separator between two numbers.
        case times
        case word(String)
    }

    static func tokenize(_ transcript: String) -> [Token] {
        let words = normalize(transcript)
        var tokens: [Token] = []
        var i = 0
        while i < words.count {
            if let (value, used) = readNumber(words, from: i) {
                tokens.append(.number(value))
                i += used
                continue
            }
            let word = words[i]
            let next = i + 1 < words.count ? words[i + 1] : nil
            switch word {
            case "kg", "kgs", "kilo", "kilos", "kilogram", "kilograms", "kilogrammes", "k":
                tokens.append(.kg)
            case "lb", "lbs", "pound", "pounds":
                tokens.append(.lb)
            case "rep", "reps", "repetition", "repetitions", "wraps", "raps":
                tokens.append(.reps)
            case "times":
                tokens.append(.times)
            case "bodyweight":
                tokens.append(.bodyweight)
            case "body" where next == "weight":
                tokens.append(.bodyweight); i += 1
            case "no" where next == "weight":
                tokens.append(.bodyweight); i += 1
            case "same":
                tokens.append(.same)
            case "add", "added", "plus", "increase", "up":
                tokens.append(.add)
            case "minus", "drop", "less", "subtract", "lower", "down", "remove":
                tokens.append(.subtract)
            case "take" where next == "off":
                tokens.append(.subtract); i += 1
            case "for", "at", "x", "by", "with", "of":
                tokens.append(.separator)
            default:
                tokens.append(.word(word))
            }
            i += 1
        }
        return tokens
    }

    /// Lowercases, splits glued units ("45kg"), and keeps decimal points between digits.
    static func normalize(_ text: String) -> [String] {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: "½", with: " and a half ")
        s = s.replacingOccurrences(of: "×", with: " x ")
        // Decimal comma ("42,5") becomes a point; a thousands comma ("1,000") disappears.
        s = s.replacingOccurrences(of: #"(\d),(\d{3})(?!\d)"#, with: "$1$2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d),(\d)"#, with: "$1.$2", options: .regularExpression)
        // Keep "42.5" but drop sentence punctuation.
        s = s.replacingOccurrences(of: #"(?<!\d)\.|\.(?!\d)"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[^a-z0-9.\s]"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d)([a-z])"#, with: "$1 $2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([a-z])(\d)"#, with: "$1 $2", options: .regularExpression)
        return s.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    // MARK: - Numbers

    private static let ones: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9,
    ]
    private static let teens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fourty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    private static let weightUnits: Set<String> = [
        "kg", "kgs", "kilo", "kilos", "kilogram", "kilograms", "lb", "lbs", "pound", "pounds",
    ]

    private static func digitWord(_ w: String) -> Int? {
        if let n = ones[w] { return n }
        if w.count == 1, let n = Int(w) { return n }
        return nil
    }

    /// Reads one number starting at `start`: digits ("42.5"), words ("forty two point five"),
    /// either followed by "and a half". Returns the value and how many words it used.
    static func readNumber(_ words: [String], from start: Int) -> (Double, Int)? {
        guard start < words.count else { return nil }
        var i = start
        var value: Double

        if let digits = Double(words[i]), words[i].first?.isNumber == true {
            value = digits
            i += 1
        } else if let (wordValue, used) = readNumberWords(words, from: i) {
            value = Double(wordValue)
            i += used
        } else {
            return nil
        }

        // "point five", "point two five", "point 5"
        if i + 1 < words.count, words[i] == "point", value == value.rounded() {
            var fraction = ""
            var j = i + 1
            while j < words.count, let d = digitWord(words[j]) {
                fraction += String(d); j += 1
            }
            if fraction.isEmpty, j < words.count, Int(words[j]) != nil {
                fraction = words[j]; j += 1
            }
            if !fraction.isEmpty, let f = Double("0." + fraction) {
                value += f
                i = j
            }
        }

        // "and a half"
        if i + 2 < words.count, words[i] == "and", words[i + 1] == "a", words[i + 2] == "half" {
            value += 0.5
            i += 3
        }
        return (value, i - start)
    }

    /// "forty five", "one hundred and twenty", "a hundred", "twelve", and gym shorthand
    /// "one thirty five" (= 135) when a weight unit follows.
    private static func readNumberWords(_ words: [String], from start: Int) -> (Int, Int)? {
        var i = start
        // Gym shorthand: one/two/three + tens [+ one] + unit word → hundreds.
        if let h = ones[words[i]], h > 0, i + 1 < words.count, let t = tens[words[i + 1]] ?? teens[words[i + 1]] {
            var j = i + 2
            var n = h * 100 + t
            if tens[words[i + 1]] != nil, j < words.count, let o = ones[words[j]], o > 0 { n += o; j += 1 }
            if j < words.count, weightUnits.contains(words[j]) { return (n, j - start) }
        }

        var total = 0
        var used = false
        if words[i] == "a", i + 1 < words.count, words[i + 1] == "hundred" {
            total = 100; i += 2; used = true
            if i + 1 < words.count, words[i] == "and", tens[words[i + 1]] != nil || teens[words[i + 1]] != nil || ones[words[i + 1]] != nil {
                i += 1
            }
        }
        var last: Kind = used ? .hundred : .none
        enum Kind { case none, one, teen, ten, hundred }

        while i < words.count {
            let w = words[i]
            if let n = ones[w], last == .none || last == .ten || last == .hundred {
                total += n; last = .one
            } else if let n = teens[w], last == .none || last == .hundred {
                total += n; last = .teen
            } else if let n = tens[w], last == .none || last == .hundred {
                total += n; last = .ten
            } else if w == "hundred", last == .one, total % 100 > 0, total < 10 {
                total *= 100; last = .hundred
                // "one hundred and twenty"
                if i + 2 < words.count, words[i + 1] == "and",
                   tens[words[i + 2]] != nil || teens[words[i + 2]] != nil || ones[words[i + 2]] != nil {
                    i += 1
                }
            } else {
                break
            }
            used = true
            i += 1
        }
        return used ? (total, i - start) : nil
    }

    // MARK: - Meaning

    private enum WeightSource {
        case explicit(Double)      // in kg
        case same
        case delta(Double)         // kg, signed
        case bodyweight
    }

    static func interpret(_ tokens: [Token], context: VoiceParseContext) -> VoiceParseResult {
        var consumed = Array(repeating: false, count: tokens.count)
        var weight: WeightSource?
        var reps: Int?

        func kilograms(_ value: Double, unitAt index: Int) -> (Double, Bool) {
            guard index < tokens.count else { return (WeightFormatter.kilograms(from: value, in: context.unit), false) }
            switch tokens[index] {
            case .kg: return (value, true)
            case .lb: return (WeightFormatter.kilograms(from: value, in: .lb), true)
            default: return (WeightFormatter.kilograms(from: value, in: context.unit), false)
            }
        }

        // Pass 1: phrases with a keyword.
        var i = 0
        while i < tokens.count {
            switch tokens[i] {
            case .bodyweight:
                weight = .bodyweight; consumed[i] = true
            case .same:
                if weight == nil { weight = .same }
                consumed[i] = true
            case .add, .subtract:
                let sign: Double = tokens[i] == .add ? 1 : -1
                consumed[i] = true
                var j = i + 1
                if j < tokens.count, tokens[j] == .separator { j += 1 }     // "add by 2.5"
                if j < tokens.count, case .number(let n) = tokens[j], !isRepsNumber(at: j, tokens) {
                    let (kg, hadUnit) = kilograms(n, unitAt: j + 1)
                    weight = .delta(sign * kg)
                    consumed[j] = true
                    if hadUnit { consumed[j + 1] = true }
                    i = hadUnit ? j + 1 : j
                }
            case .number(let n) where !consumed[i]:
                if isRepsNumber(at: i, tokens) {
                    if reps == nil, let r = repsValue(n) { reps = r }
                    consumed[i] = true
                    if i + 1 < tokens.count { consumed[i + 1] = true }
                } else if i + 1 < tokens.count, tokens[i + 1] == .kg || tokens[i + 1] == .lb {
                    let (kg, _) = kilograms(n, unitAt: i + 1)
                    switch weight {
                    case nil, .same?: weight = .explicit(kg)
                    default: break
                    }
                    consumed[i] = true; consumed[i + 1] = true
                }
            default:
                break
            }
            i += 1
        }

        // Pass 2: bare numbers ("45 for 8", "bodyweight 12", "8").
        let bare: [Double] = tokens.indices.compactMap { idx in
            guard !consumed[idx], case .number(let n) = tokens[idx] else { return nil }
            return n
        }
        var remaining = bare[...]
        if !context.tracksWeight {
            if reps == nil, let n = remaining.first { reps = repsValue(n) }
        } else if weight == nil && reps == nil {
            if remaining.count >= 2 {
                weight = .explicit(WeightFormatter.kilograms(from: remaining.removeFirst(), in: context.unit))
                reps = repsValue(remaining.removeFirst())
            } else if let n = remaining.first {
                // A lone number: small whole numbers are reps, anything else is a weight.
                if let r = repsValue(n), r <= 30 { reps = r } else { weight = .explicit(WeightFormatter.kilograms(from: n, in: context.unit)) }
            }
        } else if reps == nil, let n = remaining.first {
            reps = repsValue(n)
        } else if weight == nil, let n = remaining.first {
            weight = .explicit(WeightFormatter.kilograms(from: n, in: context.unit))
        }

        // Resolve the weight.
        var result = VoiceParseResult()
        result.reps = reps
        switch weight {
        case .explicit(let kg): result.weightKg = kg
        case .bodyweight: result.weightKg = 0; result.isBodyweight = true
        case .same: result.weightKg = context.currentWeightKg
        case .delta(let d): result.weightKg = context.currentWeightKg.map { max(0, $0 + d) }
        case nil:
            // "8 reps": the weight already in the row.
            if reps != nil { result.weightKg = context.currentWeightKg }
        }
        if let kg = result.weightKg, !(0...maxWeightKg).contains(kg) { result.weightKg = nil }
        if let kg = result.weightKg { result.weightKg = (kg * 1000).rounded() / 1000 }
        return result
    }

    /// A number followed by "reps", or by "times" at the end of the phrase.
    private static func isRepsNumber(at index: Int, _ tokens: [Token]) -> Bool {
        guard index + 1 < tokens.count else { return false }
        switch tokens[index + 1] {
        case .reps: return true
        case .times:
            let after = index + 2 < tokens.count ? tokens[index + 2] : nil
            if case .number = after { return false }
            return true
        default: return false
        }
    }

    private static func repsValue(_ n: Double) -> Int? {
        guard n == n.rounded(), n >= 1, n <= Double(maxReps) else { return nil }
        return Int(n)
    }
}
