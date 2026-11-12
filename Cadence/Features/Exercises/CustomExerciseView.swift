//  CustomExerciseView.swift
//  Board 22. The name doubles as a voice alias. Pushed inside a NavigationStack.

import SwiftData
import SwiftUI

struct CustomExerciseView: View {
    var initialName = ""
    var onSave: (Exercise) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query private var allExercises: [Exercise]

    @State private var name = ""
    @State private var muscle = MuscleGroup.shoulders
    @State private var tracking = TrackingType.weightReps
    @State private var equipment = Equipment.barbell
    @State private var secondary: [String] = []
    @State private var restSeconds = 90
    @State private var notes = ""
    @State private var didLoad = false

    /// "Also works" choices, lower case as stored.
    static let secondaryOptions = ["chest", "back", "shoulders", "front delts", "rear delts", "biceps", "triceps",
                                   "forearms", "traps", "upper back", "lower back", "core", "obliques",
                                   "glutes", "quads", "hamstrings", "calves", "hip flexors"]

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var isDuplicate: Bool {
        allExercises.contains { !$0.isGone && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }
    }
    private var canSave: Bool { !trimmedName.isEmpty && !isDuplicate }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Name")
                    TextField("", text: $name, prompt: Text("Exercise name").foregroundStyle(Palette.textTertiary))
                        .font(.cadBody)
                        .textInputAutocapitalization(.sentences)
                        .padding(.horizontal, 14)
                        .frame(minHeight: Size.compactButton)
                        .background(Palette.elevated, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                            .strokeBorder(Palette.line, lineWidth: 1))
                        .accessibilityLabel("Name")
                    Text(isDuplicate ? "An exercise with this name already exists." : "Voice logging will recognise this name too.")
                        .font(.cadLabel)
                        .foregroundStyle(isDuplicate ? Palette.warning : Palette.textSecondary)
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    fieldLabel("Main muscle group")
                    FlowLayout {
                        ForEach(MuscleGroup.allCases) { option in
                            FilterChip(title: option.title, isSelected: muscle == option) { muscle = option }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Main muscle group")
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    fieldLabel("How you track it")
                    CadSegmentedControl(TrackingType.allCases, selection: $tracking) { $0.title }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Tracking type")
                }

                VStack(spacing: 0) {
                    NavigationLink {
                        EquipmentPickerView(selection: $equipment)
                    } label: {
                        LinkRow(title: "Equipment", value: equipment.title)
                    }
                    Divider().overlay(Palette.line)
                    NavigationLink {
                        SecondaryMusclesView(options: Self.secondaryOptions, selection: $secondary)
                    } label: {
                        LinkRow(title: "Also works",
                                value: secondary.isEmpty ? "None" : secondary.map(\.capitalized).joined(separator: ", "))
                    }
                    Divider().overlay(Palette.line)
                    HStack {
                        Text("Default rest").font(.cadBody)
                        Spacer(minLength: Space.xs)
                        RestStepper(restSeconds: $restSeconds)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .frame(minHeight: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.text)
                .cadCard(padding: 0)

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Notes (optional)")
                    TextField("", text: $notes, prompt: Text("Setup cues, grip, seat height").foregroundStyle(Palette.textTertiary),
                              axis: .vertical)
                        .lineLimit(3...6)
                        .font(.cadBody)
                        .padding(.horizontal, 14)
                        .padding(.vertical, Space.sm)
                        .background(Palette.elevated, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                            .strokeBorder(Palette.line, lineWidth: 1))
                        .accessibilityLabel("Notes")
                }
            }
            .foregroundStyle(Palette.text)
            .padding(Space.screenMargin)
        }
        .scrollDismissesKeyboard(.interactively)
        .cadScreenBackground()
        .navigationTitle("New exercise")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            name = initialName
            restSeconds = profiles.first(where: { !$0.isGone })?.defaultRestSeconds ?? 90
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.cadFootnote)
            .foregroundStyle(Palette.textSecondary)
    }

    private func save() {
        let exercise = Exercise(
            name: trimmedName,
            primaryMuscle: muscle,
            secondaryMuscles: secondary,
            equipment: equipment,
            trackingType: tracking,
            defaultRestSeconds: restSeconds,
            isCustom: true,
            aliases: [trimmedName.lowercased()],
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(exercise)
        try? context.save()
        onSave(exercise)
        dismiss()
    }
}

/// Label + grey value + chevron, for NavigationLink rows inside cards.
struct LinkRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: Space.xs) {
            Text(title)
                .font(.cadBody)
                .foregroundStyle(Palette.text)
                .layoutPriority(1)
            Spacer(minLength: Space.xs)
            Text(value)
                .font(.cadBody)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct EquipmentPickerView: View {
    @Binding var selection: Equipment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(Equipment.allCases) { item in
                Button {
                    selection = item
                    dismiss()
                } label: {
                    HStack {
                        Text(item.title).foregroundStyle(Palette.text)
                        Spacer()
                        if item == selection {
                            Image(systemName: "checkmark").foregroundStyle(Palette.accentText)
                        }
                    }
                    .frame(minHeight: Size.minTouch)
                }
                .accessibilityAddTraits(item == selection ? [.isSelected] : [])
                .listRowBackground(Palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .cadScreenBackground()
        .navigationTitle("Equipment")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SecondaryMusclesView: View {
    let options: [String]
    @Binding var selection: [String]

    var body: some View {
        List {
            ForEach(options, id: \.self) { option in
                let isOn = selection.contains(option)
                Button {
                    if isOn { selection.removeAll { $0 == option } } else { selection.append(option) }
                } label: {
                    HStack {
                        Text(option.capitalized).foregroundStyle(Palette.text)
                        Spacer()
                        if isOn {
                            Image(systemName: "checkmark").foregroundStyle(Palette.accentText)
                        }
                    }
                    .frame(minHeight: Size.minTouch)
                }
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
                .listRowBackground(Palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .cadScreenBackground()
        .navigationTitle("Also works")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("New exercise") {
    NavigationStack {
        CustomExerciseView(initialName: "Landmine press")
    }
    .modelContainer(PreviewData.container())
    .preferredColorScheme(.dark)
}
