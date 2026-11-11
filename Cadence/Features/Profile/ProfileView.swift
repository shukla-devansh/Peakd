//  ProfileView.swift
//  Board 23: grouped settings. Edits write straight to the UserProfile (SwiftData autosaves).

import SwiftData
import SwiftUI

struct ProfileView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profiles.first(where: { !$0.isDeleted }) {
                    ProfileForm(profile: profile)
                } else {
                    // Only reachable for a moment while "Delete all data" returns to onboarding.
                    Color.clear
                }
            }
            .navigationTitle("Profile")
            .cadScreenBackground()
        }
    }
}

private struct ProfileForm: View {
    @Bindable var profile: UserProfile
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query private var workouts: [Workout]
    @State private var confirmDelete = false

    private var permissions: PermissionsService { appState.permissions }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    GoalScheduleEditView(profile: profile)
                } label: {
                    ProfileRow("Goal and schedule", systemImage: "scope",
                               value: "\(profile.goal.shortTitle) · \(profile.daysPerWeek)/wk")
                }
                NavigationLink {
                    EquipmentEditView(profile: profile)
                } label: {
                    let count = profile.equipmentSet.count
                    ProfileRow("Equipment", systemImage: "dumbbell",
                               value: "\(count) \(count == 1 ? "item" : "items")")
                }
                NavigationLink {
                    UnitsEditView(profile: profile)
                } label: {
                    ProfileRow("Units", systemImage: "scalemass", value: profile.unit.symbol)
                }
            } header: {
                ProfileSectionHeader("Training")
            }
            .listRowBackground(Palette.surface)

            Section {
                NavigationLink {
                    RestEditView(profile: profile)
                } label: {
                    ProfileRow("Default rest", systemImage: "timer", value: RestFormat.clock(profile.defaultRestSeconds))
                }
                Toggle(isOn: $profile.restAlerts) {
                    ProfileRow("Alert when rest ends", systemImage: "bell")
                }
            } header: {
                ProfileSectionHeader("Rest timer")
            }
            .listRowBackground(Palette.surface)

            Section {
                Toggle(isOn: $profile.voiceLogging) {
                    ProfileRow("Voice set logging", systemImage: "mic")
                }
                Toggle(isOn: $profile.aiSuggestions) {
                    ProfileRow("AI plan suggestions", systemImage: "sparkle")
                }
            } header: {
                ProfileSectionHeader("Voice and suggestions")
            } footer: {
                if profile.voiceLogging && permissions.state(.voice) != .granted {
                    Button("Voice logging needs microphone access") {
                        Task { await allow(.voice) }
                    }
                    .font(.cadFootnote)
                    .foregroundStyle(Palette.warning)
                    .frame(minHeight: Size.minTouch)
                    .accessibilityHint("Asks for microphone and speech access")
                }
            }
            .listRowBackground(Palette.surface)

            Section {
                Button {
                    Task { await allow(.health) }
                } label: {
                    ProfileRow("Apple Health", systemImage: "heart",
                               value: label(for: permissions.state(.health), on: "On", off: "Off"),
                               showsChevron: true)
                }
                Button {
                    Task { await allow(.watch) }
                } label: {
                    ProfileRow("Apple Watch", systemImage: "applewatch",
                               value: label(for: permissions.state(.watch), on: "Connected", off: "Not connected"),
                               showsChevron: true)
                }
            } header: {
                ProfileSectionHeader("Apple")
            }
            .listRowBackground(Palette.surface)

            Section {
                HStack {
                    ShareLink(item: CSVExportFile(text: DataStore.csv(for: workouts)),
                              preview: SharePreview("Cadence export.csv")) {
                        Text("Export my data")
                            .font(Font.cadSubhead.weight(.medium))
                            .foregroundStyle(Palette.accentText)
                            .frame(minHeight: Size.minTouch)
                    }
                    Spacer()
                    Button("Delete all data") { confirmDelete = true }
                        .font(Font.cadSubhead.weight(.semibold))
                        .foregroundStyle(Palette.danger)
                        .frame(minHeight: Size.minTouch)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .environment(\.defaultMinListRowHeight, 48)
        .scrollContentBackground(.hidden)
        .tint(Palette.success)
        .foregroundStyle(Palette.text)
        .task { await permissions.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await permissions.refresh() } }
        }
        // Autosave can lag by seconds; save each edit so nothing is lost if the app is killed.
        // The edit pages mutate this same profile, so this one observer covers them too.
        .onChange(of: ProfileSnapshot(profile)) { try? context.save() }
        .confirmationDialog("Delete all data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete all data", role: .destructive, action: deleteAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your workouts, routines, records, custom exercises and settings from this iPhone. It can't be undone.")
        }
    }

    private func label(for state: PermissionState, on: String, off: String) -> String {
        switch state {
        case .granted: on
        case .unavailable: "Not available"
        case .notDetermined, .denied: off
        }
    }

    private func allow(_ kind: PermissionKind) async {
        // Already on: Settings is where it can be turned off. Already refused: Settings is the only way back.
        if permissions.state(kind) == .granted {
            openURL(URL(string: UIApplication.openSettingsURLString)!)
            return
        }
        let prompted = await permissions.request(kind)
        if !prompted {
            openURL(URL(string: UIApplication.openSettingsURLString)!)
        }
    }

    private func deleteAll() {
        do {
            try DataStore.deleteAll(in: context)
            appState.selectedTab = .home
        } catch {
            context.rollback()
        }
    }
}

/// Every user-editable profile value, for change detection.
private struct ProfileSnapshot: Equatable {
    let goal: String, experience: String, days: Int, equipment: [String], unit: String, rest: Int
    let restAlerts: Bool, voice: Bool, ai: Bool

    @MainActor
    init(_ p: UserProfile) {
        goal = p.goalRaw; experience = p.experienceRaw; days = p.daysPerWeek; equipment = p.equipment
        unit = p.unitRaw; rest = p.defaultRestSeconds
        restAlerts = p.restAlerts; voice = p.voiceLogging; ai = p.aiSuggestions
    }
}

/// Uppercase section label, as on the board (the system header style is title case on iOS 26).
private struct ProfileSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        SectionLabel(title)
            .padding(.leading, Space.xxs)
    }
}

/// Icon tile + label + optional trailing value, as on the Profile board.
struct ProfileRow: View {
    let title: String
    let systemImage: String
    var value: String?
    /// For button rows that look like links (NavigationLink draws its own chevron).
    var showsChevron = false

    init(_ title: String, systemImage: String, value: String? = nil, showsChevron: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.showsChevron = showsChevron
    }

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.accentText)
                .frame(width: 30, height: 30)
                .background(Palette.elevated, in: RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.cadBody)
                .foregroundStyle(Palette.text)
                .layoutPriority(1)
            Spacer(minLength: Space.xs)
            if let value {
                Text(value)
                    .font(.cadBody)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Size.minTouch)
        .padding(.vertical, -2)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Profile") {
    ProfileView()
        .environment(AppState())
        .modelContainer(PreviewData.container())
        .preferredColorScheme(.dark)
}
