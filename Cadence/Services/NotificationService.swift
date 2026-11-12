//  NotificationService.swift
//  The "Rest over" notification and the Live Activity: the real RestTimerEffects.
//  Also the notification-centre delegate, so tapping the notification reopens the workout.

import ActivityKit
import Foundation
import OSLog
import UserNotifications

@MainActor
final class NotificationService: NSObject, RestTimerEffects {
    static let restOverID = "rest-over"

    /// Set by AppState: reopens the active workout.
    var onOpenWorkout: () -> Void = {}

    private let center = UNUserNotificationCenter.current()
    private var activity: Activity<RestTimerAttributes>?

    override init() {
        super.init()
        center.delegate = self
        // Re-attach to an activity left from before a relaunch.
        activity = Activity<RestTimerAttributes>.activities.first
    }

    // MARK: Notification

    func scheduleRestOverNotification(at date: Date, info: RestInfo) {
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = info.notificationBody
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: Self.restOverID, content: content, trigger: trigger)
        center.add(request) { error in
            if let error { Logger.app.error("Rest notification failed: \(error.localizedDescription)") }
        }
    }

    func cancelRestOverNotification() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.restOverID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.restOverID])
    }

    // MARK: Live Activity

    func showActivity(info: RestInfo, endDate: Date, totalSeconds: Int, isOver: Bool) {
        let state = RestTimerAttributes.ContentState(
            endDate: endDate,
            totalSeconds: totalSeconds,
            nextTitle: info.nextExercise.flatMap { name in info.nextSet.map { "\(name) set \($0)" } },
            nextValue: info.upNextValue,
            isOver: isOver
        )
        let content = ActivityContent(state: state, staleDate: isOver ? nil : endDate)

        if let activity, activity.activityState == .active {
            Task { await activity.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(
                attributes: RestTimerAttributes(workoutName: info.workoutName, workoutStart: info.workoutStart),
                content: content
            )
        } catch {
            Logger.app.error("Live Activity failed: \(error.localizedDescription)")
        }
    }

    func endActivity() {
        let activities = Activity<RestTimerAttributes>.activities
        activity = nil
        for activity in activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run { self.onOpenWorkout() }
    }
}
