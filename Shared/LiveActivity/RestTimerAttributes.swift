//  RestTimerAttributes.swift
//  Shared by the iOS app (starts the activity) and CadenceWidgets (renders it). Phase 4 fills in behaviour.

#if os(iOS)
import ActivityKit
import Foundation

struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// The timer counts toward this date, so it survives backgrounding.
        var endDate: Date
        var totalSeconds: Int
        /// "Bench press · set 4"
        var upNext: String
        var isOver: Bool
    }

    /// "Push day"
    var workoutName: String
    /// "Bench press"
    var exerciseName: String
}
#endif
