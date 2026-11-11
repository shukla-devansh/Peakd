//  WatchSyncService.swift
//  Phase 2: session activation and pairing status (Permissions + Profile).
//  Phase 9 adds set-log and timer messages both ways.

import Observation
import WatchConnectivity

@Observable
@MainActor
final class WatchSyncService: NSObject {
    private(set) var isActivated = false
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false

    var isSupported: Bool { WCSession.isSupported() }
    /// "Connected" on Profile, "On" on Permissions.
    var isConnected: Bool { isPaired && isWatchAppInstalled }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState == .activated {
            update(activated: true, paired: session.isPaired, installed: session.isWatchAppInstalled)
        } else {
            session.activate()
        }
    }

    private func update(activated: Bool, paired: Bool, installed: Bool) {
        isActivated = activated
        isPaired = paired
        isWatchAppInstalled = installed
    }
}

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        let activated = state == .activated
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor in self.update(activated: activated, paired: paired, installed: installed) }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor in self.update(activated: true, paired: paired, installed: installed) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The user switched watches: reactivate for the new one.
        session.activate()
    }
}
