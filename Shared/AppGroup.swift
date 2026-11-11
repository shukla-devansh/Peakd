//  AppGroup.swift
//  Shared by the iOS app and the widget extension.

import Foundation

enum AppGroup {
    /// `group.$(BUNDLE_ID_PREFIX).cadence`, read from the `CadenceAppGroup` Info.plist key
    /// (see Config/*-Info.plist). Change `BUNDLE_ID_PREFIX` in the project's build settings,
    /// not here. `nil` in targets that don't use the group (the Watch).
    static var identifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "CadenceAppGroup") as? String
    }

    /// The group container, or `nil` if the entitlement isn't provisioned in this build.
    static var containerURL: URL? {
        guard let identifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
