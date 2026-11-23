//  AppInfo.swift
//  The app's display name, from APP_DISPLAY_NAME in Config/Branding.xcconfig.
//  Rename the app there: Home Screen name, permission prompts, share cards and export files follow.

import Foundation

enum AppInfo {
    static let name: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Peakd"
}
