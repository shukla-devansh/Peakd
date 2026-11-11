//  OnboardingForms.swift
//  The form bodies of the Onboarding and Equipment boards. Used by onboarding and by Profile's edit pages.

import SwiftUI

/// "Main goal", "Experience", "Days per week".
struct GoalScheduleForm: View {
    @Binding var goal: TrainingGoal
    @Binding var experience: Experience
    @Binding var daysPerWeek: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: Space.xs) {
                SectionLabel("Main goal")
                    .padding(.bottom, Space.xs)
                ForEach(TrainingGoal.allCases) { option in
                    RadioCard(title: option.title, subtitle: option.subtitle, isSelected: goal == option) {
                        goal = option
                    }
                }
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                SectionLabel("Experience")
                    .padding(.bottom, Space.xs)
                CadSegmentedControl(Experience.allCases, selection: $experience) { $0.title }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Experience")
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                SectionLabel("Days per week")
                    .padding(.bottom, Space.xs)
                NumberChoiceRow(options: UserProfile.daysOptions, selection: $daysPerWeek) { "\($0) days" }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Training days per week")
            }
        }
    }
}

/// Equipment checkbox grid.
struct EquipmentForm: View {
    @Binding var selection: Set<Equipment>

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel("Equipment")
                .padding(.bottom, Space.xs)
            // Grid (not LazyVGrid) so both cards in a row share the taller one's height.
            Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                ForEach(Array(stride(from: 0, to: Equipment.selectable.count, by: 2)), id: \.self) { start in
                    GridRow {
                        ForEach(Equipment.selectable[start..<min(start + 2, Equipment.selectable.count)]) { item in
                            toggle(for: item)
                        }
                    }
                }
            }
        }
    }
}

extension EquipmentForm {
    fileprivate func toggle(for item: Equipment) -> some View {
        Toggle(item.setupTitle, isOn: Binding(
            get: { selection.contains(item) },
            set: { isOn in
                if isOn { selection.insert(item) } else { selection.remove(item) }
            }
        ))
        .toggleStyle(.checkboxCard)
    }
}

/// "Weight unit" and "Default rest" card.
struct UnitRestCard: View {
    @Binding var unit: WeightUnit
    @Binding var restSeconds: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Weight unit")
                    .font(.cadBody)
                Spacer(minLength: Space.xs)
                CadSegmentedControl(WeightUnit.allCases, selection: $unit, style: .inset) { $0.symbol }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Weight unit")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)

            Divider().overlay(Palette.line)

            HStack {
                RestStepperLabel()
                Spacer(minLength: Space.xs)
                RestStepper(restSeconds: $restSeconds)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, Space.xs)
            .frame(minHeight: 56)
        }
        .foregroundStyle(Palette.text)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
    }
}

struct RestStepperLabel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Default rest")
                .font(.cadBody)
            Text("Change per exercise later")
                .font(.cadFootnote)
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

/// 30 s – 5 min in 15 s steps.
struct RestStepper: View {
    @Binding var restSeconds: Int

    var body: some View {
        ValueStepper(
            value: $restSeconds,
            range: UserProfile.restRange,
            step: UserProfile.restStep,
            format: RestFormat.clock,
            decrementLabel: "Shorter rest",
            incrementLabel: "Longer rest",
            spokenValue: RestFormat.spoken
        )
    }
}

#Preview("Goal form") {
    @Previewable @State var goal = TrainingGoal.strength
    @Previewable @State var experience = Experience.intermediate
    @Previewable @State var days = 4
    ScrollView {
        GoalScheduleForm(goal: $goal, experience: $experience, daysPerWeek: $days)
            .padding(Space.screenMargin)
    }
    .background(Palette.background)
    .preferredColorScheme(.dark)
}

#Preview("Equipment form") {
    @Previewable @State var gear = Set(Equipment.defaultSelection)
    @Previewable @State var unit = WeightUnit.kg
    @Previewable @State var rest = 90
    ScrollView {
        VStack(spacing: 20) {
            EquipmentForm(selection: $gear)
            UnitRestCard(unit: $unit, restSeconds: $rest)
        }
        .padding(Space.screenMargin)
    }
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
