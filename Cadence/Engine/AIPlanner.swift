//  AIPlanner.swift
//  Phase 7: Foundation Models rewords the rule-based plan. It never makes the plan.
//
//  - The Planner and OverloadEngine choose the routine, sets, reps and weights.
//  - PlanFacts turns that plan into plain text: the only thing the model sees.
//  - The model returns a @Generable PlanWording (explanation + home line).
//  - PlanWordingValidator rejects any wording with a number that isn't in the facts, or that is
//    empty or too long. Rejected or unavailable → the Planner's template text is shown.
//
//  Works without Apple Intelligence: when SystemLanguageModel isn't available nothing is
//  generated and every screen keeps the template text.

import CryptoKit
import Foundation
import FoundationModels
import Observation

// MARK: - Facts

struct PlanFacts: Sendable, Equatable {
    /// What the model is told, one fact per line.
    let text: String
    /// Every number that appears in `text` (digits or words), plus 1 ("one set fewer").
    let allowedNumbers: Set<Double>
    /// Stable cache key: same facts, same wording.
    let key: String

    init(text: String) {
        self.text = text
        allowedNumbers = Set(PlanWordingValidator.numbers(in: text)).union([1])
        key = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func make(plan: SessionPlan, fatigue: FatigueReport?, digests: [WorkoutDigest],
                     unit: WeightUnit, now: Date = .now, calendar: Calendar = .current) -> PlanFacts {
        var lines: [String] = []
        lines.append("Next routine: \(plan.routineName)")

        let recent = digests.filter { $0.date <= now }.sorted { $0.date > $1.date }
        if let last = recent.first {
            let day = Planner.relativeDay(last.date, now: now, calendar: calendar)
            let muscles = Planner.list(Planner.topMuscles(last.muscleSets))
            lines.append("Last session: \(last.displayName), \(day)" + (muscles.isEmpty ? "" : ", mostly \(muscles)"))
            lines.append("Same routine as last session: \(last.displayName == plan.routineName ? "yes" : "no")")
        } else {
            lines.append("Last session: none, this is the first")
        }
        let focus = Planner.focusMuscles(plan.exercises)
        if !focus.isEmpty { lines.append("This routine trains: \(focus)") }

        if let fatigue {
            lines.append("Fatigue: \(fatigue.band.title.lowercased()), \(fatigue.score) of 100")
            let raised = fatigue.factors.filter { $0.status == .elevated }.map { $0.label.lowercased() }
            if !raised.isEmpty { lines.append("Raising fatigue: \(raised.joined(separator: "; "))") }
        } else {
            lines.append("Fatigue: not enough data yet")
        }
        lines.append("Sets: \(plan.lightened ? "one set fewer per exercise than the routine" : "as in the routine")")
        if plan.offerRestDay { lines.append("A rest day is offered instead") }

        lines.append("Exercises:")
        for e in plan.exercises {
            var line = "- \(e.name): \(e.targetText)"
            if let kg = e.weightKg { line += " at \(WeightFormatter.string(kg: kg, in: unit))" }
            switch e.suggestion?.change {
            case .increase(let kg)?: line += "; weight goes up \(WeightFormatter.string(kg: kg, in: unit))"
            case .same?: line += "; same weight, aim for more reps"
            case .decrease(let percent)?: line += "; weight comes down \(percent)%"
            case .addRep?: line += "; one more rep than last time"
            case nil: line += "; no history yet"
            }
            if let reason = e.suggestion?.reason { line += " (\(reason))" }
            lines.append(line)
        }
        return PlanFacts(text: lines.joined(separator: "\n"))
    }
}

// MARK: - Wording

struct PlanWording: Sendable, Equatable, Codable {
    var explanation: String
    var homeReason: String
}

@Generable
struct GeneratedPlanWording {
    @Guide(description: "Why this routine is next and how fatigue shaped the sets. One or two plain sentences, under 220 characters, speaking to the user as you.")
    var explanation: String

    @Guide(description: "One short sentence for the home screen card saying why this workout suits today. Under 90 characters.")
    var homeReason: String
}

enum PlanWordingValidator {
    static let maxExplanation = 320
    static let maxHomeReason = 140

    /// Numbers in the text, as digits ("42.5", "10%") or words ("four", "two and a half").
    static func numbers(in text: String) -> [Double] {
        VoiceSetParser.tokenize(text).compactMap {
            if case .number(let n) = $0 { return n }
            return nil
        }
    }

    /// Trims whitespace and quotes, folds line breaks, drops exclamation marks.
    static func clean(_ w: PlanWording) -> PlanWording {
        func tidy(_ s: String) -> String {
            var t = s.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "!", with: ".")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”")))
            while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
            while t.contains("..") { t = t.replacingOccurrences(of: "..", with: ".") }
            return t
        }
        return PlanWording(explanation: tidy(w.explanation), homeReason: tidy(w.homeReason))
    }

    static func isValid(_ w: PlanWording, facts: PlanFacts) -> Bool {
        guard !w.explanation.isEmpty, !w.homeReason.isEmpty,
              w.explanation.count <= maxExplanation, w.homeReason.count <= maxHomeReason else { return false }
        let used = numbers(in: w.explanation) + numbers(in: w.homeReason)
        return used.allSatisfy { n in facts.allowedNumbers.contains { abs($0 - n) < 0.001 } }
    }
}

// MARK: - Generators

protocol PlanWordingGenerator: Sendable {
    var isAvailable: Bool { get }
    func generate(facts: PlanFacts) async throws -> PlanWording
}

/// The on-device model (Apple Intelligence).
struct FoundationModelsWordingGenerator: PlanWordingGenerator {
    static let instructions = """
        You write the short "Why this plan" text in a strength-training app. \
        The app has already chosen the routine, sets, reps and weights; you only explain them. \
        Use only the facts you are given. Never state a number, weight, rep count or percentage \
        that is not in the facts, and prefer no numbers at all. Do not mention exercises or \
        routines that are not in the facts. No medical advice, no emojis, no exclamation marks. \
        Calm, plain and specific, speaking to the user as you.
        """

    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func generate(facts: PlanFacts) async throws -> PlanWording {
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: "Facts:\n\(facts.text)",
            generating: GeneratedPlanWording.self,
            options: GenerationOptions(temperature: 0.2)
        )
        return PlanWording(explanation: response.content.explanation, homeReason: response.content.homeReason)
    }
}

// MARK: - Service

@Observable
@MainActor
final class AIPlanner {
    private(set) var cache: [String: PlanWording] = [:]
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []
    private var order: [String] = []

    private let generator: any PlanWordingGenerator
    private let defaults: UserDefaults?
    private static let storeKey = "aiPlanWording.v1"
    private static let maxEntries = 30

    init(generator: any PlanWordingGenerator = FoundationModelsWordingGenerator(), defaults: UserDefaults? = .standard) {
        self.generator = generator
        self.defaults = defaults
        load()
    }

    var isAvailable: Bool { generator.isAvailable }

    /// The model's wording for these facts, if it has been generated and passed the checks.
    func wording(for facts: PlanFacts) -> PlanWording? { cache[facts.key] }

    /// Generates wording once per set of facts. Tries twice; if both fail the checks, the
    /// template text stays for this plan.
    func prepare(_ facts: PlanFacts) async {
        let key = facts.key
        guard cache[key] == nil, !inFlight.contains(key), !failed.contains(key), generator.isAvailable else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        for _ in 0..<2 {
            guard let raw = try? await generator.generate(facts: facts) else { break }
            let wording = PlanWordingValidator.clean(raw)
            if PlanWordingValidator.isValid(wording, facts: facts) {
                store(wording, for: key)
                return
            }
        }
        failed.insert(key)
    }

    private func store(_ wording: PlanWording, for key: String) {
        cache[key] = wording
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > Self.maxEntries { cache[order.removeFirst()] = nil }
        if let data = try? JSONEncoder().encode(Stored(order: order, cache: cache)) {
            defaults?.set(data, forKey: Self.storeKey)
        }
    }

    private func load() {
        guard let data = defaults?.data(forKey: Self.storeKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        cache = stored.cache
        order = stored.order
    }

    private struct Stored: Codable {
        var order: [String]
        var cache: [String: PlanWording]
    }
}
