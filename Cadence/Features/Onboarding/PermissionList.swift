//  PermissionList.swift
//  The four permission rows (Permissions board). "Allow" shows the system prompt;
//  if the user already said no, it opens Settings, the only place they can change it.

import SwiftUI

struct PermissionList: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var showNoWatch = false

    private var permissions: PermissionsService { appState.permissions }

    var body: some View {
        VStack(spacing: Space.xs) {
            ForEach(PermissionKind.allCases) { kind in
                PermissionRow(kind: kind, state: permissions.state(kind)) {
                    Task { await allow(kind) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Permissions")
        .task { await permissions.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await permissions.refresh() } }
        }
        .alert("No Apple Watch found", isPresented: $showNoWatch) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Pair an Apple Watch with this iPhone in the Watch app, then try again.")
        }
    }

    private func allow(_ kind: PermissionKind) async {
        let prompted = await permissions.request(kind)
        if !prompted {
            openURL(URL(string: UIApplication.openSettingsURLString)!)
        } else if kind == .watch {
            // Activation is quick; give it a moment before reporting that nothing is paired.
            try? await Task.sleep(for: .seconds(1))
            if !permissions.watch.isConnected { showNoWatch = true }
        }
    }
}

struct PermissionRow: View {
    let kind: PermissionKind
    let state: PermissionState
    let onAllow: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            IconTile(systemImage: kind.systemImage)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(.cadHeadline)
                    .foregroundStyle(Palette.text)
                Text(kind.reason)
                    .font(.cadFootnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            trailing
        }
        .padding(.vertical, Space.sm)
        .padding(.horizontal, 14)
        .frame(minHeight: 76)
        .cadCard(padding: 0)
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .granted:
            Label("On", systemImage: "checkmark")
                .labelStyle(OnChipLabelStyle())
                .font(Font.cadFootnote.weight(.bold))
                .foregroundStyle(Palette.success)
                .padding(.leading, Space.xs)
                .padding(.trailing, 10)
                .frame(minHeight: Size.chipHeight)
                .background(Palette.successTint, in: Capsule())
                .accessibilityLabel("\(kind.title) on")
        case .unavailable:
            Text("Not available")
                .font(.cadFootnote)
                .foregroundStyle(Palette.textTertiary)
                .multilineTextAlignment(.trailing)
        case .notDetermined, .denied:
            Button("Allow", action: onAllow)
                .buttonStyle(.cad(.tinted, size: .small, fullWidth: false))
                .accessibilityLabel("Allow \(kind.title)")
        }
    }
}

private struct OnChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.xxs) {
            configuration.icon.font(.system(size: 12, weight: .heavy))
            configuration.title
        }
    }
}

#Preview("Permission rows") {
    VStack(spacing: Space.xs) {
        PermissionRow(kind: .voice, state: .notDetermined) {}
        PermissionRow(kind: .health, state: .denied) {}
        PermissionRow(kind: .notifications, state: .granted) {}
        PermissionRow(kind: .watch, state: .unavailable) {}
    }
    .previewSurface()
}
