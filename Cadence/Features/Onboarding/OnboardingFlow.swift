//  OnboardingFlow.swift
//  Boards 11–13: Goal → Equipment → Permissions. Shown by RootView while no UserProfile exists.
//  Nothing is saved until "Finish setup" or "Skip setup".

import OSLog
import SwiftData
import SwiftUI

@Observable
@MainActor
final class OnboardingModel {
    enum Step: Int, Comparable {
        case goal = 1, equipment, permissions
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    var step: Step = .goal
    /// Direction of the last move, for the slide transition.
    var movingForward = true

    // Draft values start at the boards' pre-selected state (UserProfile defaults).
    var goal = TrainingGoal.strength
    var experience = Experience.intermediate
    var daysPerWeek = 4
    var equipment = Set(Equipment.defaultSelection)
    var unit = WeightUnit.kg
    var restSeconds = 90

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        movingForward = true
        step = next
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        movingForward = false
        step = previous
    }

    /// Saves the profile and the starter routine. RootView switches to the tabs once the profile exists.
    func finish(in context: ModelContext, useDefaults: Bool = false) {
        let profile = useDefaults ? UserProfile() : UserProfile(
            goal: goal,
            experience: experience,
            daysPerWeek: daysPerWeek,
            equipment: Equipment.selectable.filter(equipment.contains),
            unit: unit,
            defaultRestSeconds: restSeconds
        )
        context.insert(profile)
        do {
            // The library normally seeds at launch; make sure it's there before picking exercises.
            try ExerciseLibrary.seedIfNeeded(in: context)
            try StarterPlan.install(for: profile, in: context)
            try context.save()
        } catch {
            Logger.app.error("Finishing onboarding failed: \(error.localizedDescription)")
        }
    }
}

struct OnboardingFlow: View {
    @State private var model = OnboardingModel()
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch model.step {
            case .goal:
                OnboardingGoalView(model: model) { finish(useDefaults: true) }
            case .equipment:
                OnboardingEquipmentView(model: model)
            case .permissions:
                OnboardingPermissionsView(model: model) { finish(useDefaults: false) }
            }
        }
        .id(model.step)
        .transition(transition)
        .animation(reduceMotion ? nil : Motion.standard, value: model.step)
        .cadScreenBackground()
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: model.movingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: model.movingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func finish(useDefaults: Bool) {
        model.finish(in: context, useDefaults: useDefaults)
    }
}

/// Header, scrolling body and pinned bottom bar shared by the three steps.
struct OnboardingStepLayout<Content: View, Footer: View>: View {
    let step: Int
    let title: String
    let message: String
    /// "Back to goals"; `nil` hides the back button.
    var backLabel: String?
    var onBack: (() -> Void)?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: Space.xs) {
                        if let backLabel, let onBack {
                            Button(action: onBack) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Palette.text)
                                    .frame(width: Size.minTouch, height: Size.minTouch)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, -12)
                            .padding(.vertical, -10)
                            .accessibilityLabel(backLabel)
                        }
                        StepProgressBar(step: step, total: 3)
                    }
                    Text("Step \(step) of 3")
                        .font(.cadFootnote)
                        .foregroundStyle(Palette.textSecondary)
                    Text(title)
                        .font(.cadScreenTitle)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(.cadSubhead)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .cadStatusBarBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Space.xxs) {
                footer()
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xs)
            .background(Palette.background)
        }
    }
}

// MARK: - Step 1 · Goal

struct OnboardingGoalView: View {
    @Bindable var model: OnboardingModel
    let onSkip: () -> Void

    var body: some View {
        OnboardingStepLayout(
            step: 1,
            title: "What are you training for?",
            message: "Your plan suggestions start from this. You can change it any time in Profile."
        ) {
            GoalScheduleForm(goal: $model.goal, experience: $model.experience, daysPerWeek: $model.daysPerWeek)
        } footer: {
            Button("Continue") { model.advance() }
                .buttonStyle(.cadPrimary)
            Button("Skip setup", action: onSkip)
                .font(Font.cadSubhead.weight(.medium))
                .foregroundStyle(Palette.accentText)
                .frame(maxWidth: .infinity, minHeight: Size.minTouch)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
        }
    }
}

// MARK: - Step 2 · Equipment

struct OnboardingEquipmentView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingStepLayout(
            step: 2,
            title: "What can you use?",
            message: "We only suggest exercises you have the equipment for.",
            backLabel: "Back to goals",
            onBack: { model.back() }
        ) {
            VStack(spacing: 20) {
                EquipmentForm(selection: $model.equipment)
                UnitRestCard(unit: $model.unit, restSeconds: $model.restSeconds)
            }
        } footer: {
            Button("Continue") { model.advance() }
                .buttonStyle(.cadPrimary)
        }
    }
}

// MARK: - Step 3 · Permissions

struct OnboardingPermissionsView: View {
    @Bindable var model: OnboardingModel
    let onFinish: () -> Void

    var body: some View {
        OnboardingStepLayout(
            step: 3,
            title: "Turn on what you need",
            message: "Each one is optional. The app works without them, with fewer features.",
            backLabel: "Back to equipment",
            onBack: { model.back() }
        ) {
            VStack(alignment: .leading, spacing: 20) {
                PermissionList()
                Text("Speech is turned into text on your iPhone where supported. Only the numbers you confirm, like weight and reps, are saved.")
                    .font(.cadFootnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            Button("Finish setup", action: onFinish)
                .buttonStyle(.cadPrimary)
        }
    }
}

#Preview("Onboarding") {
    OnboardingFlow()
        .environment(AppState())
        .modelContainer(PreviewData.container(withProfile: false))
        .preferredColorScheme(.dark)
}
