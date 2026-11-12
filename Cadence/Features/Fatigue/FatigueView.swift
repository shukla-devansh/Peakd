//  FatigueView.swift
//  Board 07. Score ring + band, factor list, 14-day line (with a table fallback), suggestion,
//  and the "not medical advice" footnote, which always shows.

import Charts
import SwiftData
import SwiftUI

struct FatigueView: View {
    @Query private var profiles: [UserProfile]
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @Query(filter: #Predicate<Workout> { $0.end != nil }) private var workouts: [Workout]
    @State private var showsTable = false

    private var profile: UserProfile? { profiles.first { !$0.isGone } }

    var body: some View {
        let coach = CoachSnapshot(profile: profile, routines: routines, workouts: workouts)
        let history = FatigueEngine.history(workouts: coach.digests, plannedDaysPerWeek: profile?.daysPerWeek ?? 4)

        ScrollView {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Fatigue")
                    .font(.cadScreenTitle)
                    .accessibilityAddTraits(.isHeader)

                if let report = coach.fatigue {
                    scoreCard(report)
                    factors(report)
                    trend(history)
                    suggestion(report, plan: coach.plan)
                } else {
                    notEnoughData(logged: coach.digests.count)
                }

                Text("A fitness estimate from your training data, not medical advice. If you feel unwell or in pain, rest and speak to a professional.")
                    .font(.cadLabel)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Palette.text)
            .padding(.horizontal, Space.screenMargin)
            .padding(.bottom, Space.lg)
        }
        .cadScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func scoreCard(_ report: FatigueReport) -> some View {
        HStack(spacing: Space.md) {
            ZStack {
                ProgressRing(progress: Double(report.score) / 100, lineWidth: 10, tint: report.band.tone.foreground)
                VStack(spacing: 0) {
                    Text("\(report.score)")
                        .font(Font.cadTitle.weight(.bold))
                        .monospacedDigit()
                    Text("of 100")
                        .font(.cadLabel)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(report.band.title)
                    .font(.cadTitle)
                    .foregroundStyle(report.band.tone.foreground)
                Text("Built from your training load, frequency, performance and recovery signals.")
                    .font(.cadFootnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cadCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fatigue score \(report.score) of 100, \(report.band.title)")
    }

    private func factors(_ report: FatigueReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What is driving it")
                .font(.cadHeadline)
                .padding(.bottom, Space.xxs)
                .accessibilityAddTraits(.isHeader)
            ForEach(report.factors) { factor in
                Divider().overlay(Palette.line)
                HStack(spacing: Space.xs) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(factor.label).font(.cadSubhead)
                        Text(factor.value)
                            .font(.cadFootnote)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: Space.xs)
                    TagPill(text: factor.statusText, tone: factor.status == .elevated ? .warning : .success)
                }
                .frame(minHeight: Size.minTouch)
                .padding(.vertical, Space.xxs)
                .accessibilityElement(children: .combine)
                .accessibilityValue("adds \(factor.points) points")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Space.sm)
        .cadCard(padding: 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What is driving it")
    }

    private func trend(_ history: [(date: Date, score: Int?)]) -> some View {
        let points = history.compactMap { p in p.score.map { (date: p.date, score: $0) } }
        let first = points.first?.score ?? 0, last = points.last?.score ?? 0
        let summary = "Fatigue score over 14 days, \(last >= first ? "rising" : "falling") from \(first) to \(last), "
            + (last >= 70 ? "above" : "below") + " the high threshold of 70"

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 14 days")
                    .font(.cadHeadline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(FatigueEngine.trendText(history))
                    .font(.cadLabel)
                    .foregroundStyle(Palette.textSecondary)
            }
            if showsTable {
                ForEach(points, id: \.date) { point in
                    HStack {
                        Text(point.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        Spacer()
                        Text("\(point.score)").monospacedDigit()
                        Text(FatigueBand(score: point.score).title)
                            .foregroundStyle(FatigueBand(score: point.score).tone.foreground)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .font(.cadFootnote)
                    .accessibilityElement(children: .combine)
                }
            } else {
                Chart {
                    RuleMark(y: .value("High", 70))
                        .foregroundStyle(Palette.danger)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("High 70").font(.cadLabel).foregroundStyle(Palette.textSecondary)
                        }
                    ForEach(points, id: \.date) { point in
                        LineMark(x: .value("Day", point.date), y: .value("Score", point.score))
                            .foregroundStyle(FatigueBand(score: last).tone.foreground)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                    if let end = points.last {
                        PointMark(x: .value("Day", end.date), y: .value("Score", end.score))
                            .foregroundStyle(FatigueBand(score: last).tone.foreground)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 84)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summary)
            }
            Button(showsTable ? "View as chart" : "View as table") { showsTable.toggle() }
                .font(Font.cadFootnote.weight(.semibold))
                .foregroundStyle(Palette.accentText)
                .frame(minHeight: Size.minTouch)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, Space.sm)
        .cadCard(padding: 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Last 14 days")
    }

    @ViewBuilder
    private func suggestion(_ report: FatigueReport, plan: SessionPlan?) -> some View {
        let tone = report.band.tone
        let routine = plan?.routineName ?? "your next session"
        let text: String = switch report.band {
        case .low: "Recovery looks good. Train \(routine) as planned."
        case .moderate: "Keep \(routine) but trim one set from each exercise, or take a rest day before it."
        case .high: "Take a rest day, or do \(routine) with one set less on each exercise."
        }
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(text)
                .font(.cadSubhead)
                .fixedSize(horizontal: false, vertical: true)
            if plan != nil {
                NavigationLink(value: HomeRoute.nextSession(lighten: report.band != .low)) {
                    Text(report.band == .low ? "See next session" : "Lighten next session")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.cad(.elevated, size: .small))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.foreground.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(tone.foreground.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestion")
    }

    private func notEnoughData(logged: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Not enough data")
                .font(Font.cadHeadline.weight(.bold))
            Text("Log 3 workouts to see your score")
                .font(.cadFootnote)
                .foregroundStyle(Palette.textSecondary)
            StepProgressBar(step: min(logged, 3), total: 3, spacing: Space.xxs,
                            accessibilityText: "\(min(logged, 3)) of 3 workouts logged")
        }
        .cadCard()
    }
}
