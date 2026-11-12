//  RestTimerAttributes.swift
//  Shared by the iOS app (starts and updates the activity) and CadenceWidgets (renders it).
//  One activity per workout; each rest updates its content. The content's staleDate is the rest's
//  end, so the widget shows "Rest over" on time even if the app is suspended.

#if os(iOS)
import ActivityKit
import Foundation

struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// The countdown runs toward this date, so it keeps going without updates.
        var endDate: Date
        var totalSeconds: Int
        /// "Bench press set 4"
        var nextTitle: String?
        /// "42.5 × 10"
        var nextValue: String?
        /// Set when the app sees the rest end (or the user skips). The widget also treats a stale
        /// content as over.
        var isOver: Bool
    }

    /// "Push day"
    var workoutName: String
    var workoutStart: Date
}

/// Deep link opened by the Live Activity and Dynamic Island.
enum CadenceLinks {
    static let workout = URL(string: "cadence://workout")!
}
#endif
