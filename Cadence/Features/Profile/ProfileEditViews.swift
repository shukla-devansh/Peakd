//  ProfileEditViews.swift
//  Pages behind Profile's link rows. They reuse the onboarding forms so both stay identical.

import SwiftUI

struct GoalScheduleEditView: View {
    @Bindable var profile: UserProfile

    var body: some View {
        ScrollView {
            GoalScheduleForm(goal: $profile.goal, experience: $profile.experience, daysPerWeek: $profile.daysPerWeek)
                .padding(Space.screenMargin)
        }
        .cadScreenBackground()
        .navigationTitle("Goal and schedule")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EquipmentEditView: View {
    @Bindable var profile: UserProfile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("We only suggest exercises you have the equipment for.")
                    .font(.cadSubhead)
                    .foregroundStyle(Palette.textSecondary)
                EquipmentForm(selection: $profile.equipmentSet)
            }
            .padding(Space.screenMargin)
        }
        .cadScreenBackground()
        .navigationTitle("Equipment")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct UnitsEditView: View {
    @Bindable var profile: UserProfile

    var body: some View {
        List {
            Picker("Weight unit", selection: $profile.unit) {
                ForEach(WeightUnit.allCases) { unit in
                    Text(unit.symbol).tag(unit)
                }
            }
            .pickerStyle(.inline)
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .tint(Palette.accentText)
        .cadScreenBackground()
        .navigationTitle("Units")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RestEditView: View {
    @Bindable var profile: UserProfile

    var body: some View {
        ScrollView {
            HStack {
                RestStepperLabel()
                Spacer(minLength: Space.xs)
                RestStepper(restSeconds: $profile.defaultRestSeconds)
            }
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 14)
            .padding(.vertical, Space.xs)
            .frame(minHeight: 56)
            .cadCard(padding: 0)
            .padding(Space.screenMargin)
        }
        .cadScreenBackground()
        .navigationTitle("Default rest")
        .navigationBarTitleDisplayMode(.inline)
    }
}
