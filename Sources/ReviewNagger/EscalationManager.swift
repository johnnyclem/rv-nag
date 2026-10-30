import Foundation
import UserNotifications
import AppKit
import ReviewNaggerCore

extension Notification.Name {
    /// Posted on the main thread whenever the pending list changes.
    static let pendingItemsChanged = Notification.Name("ReviewNaggerPendingItemsChanged")
}

class EscalationManager {
    static let shared = EscalationManager()

    private var items: [ReviewItem] = []
    private var timer: Timer?

    /// UNUserNotificationCenter raises an exception when the process isn't inside an app bundle
    /// (e.g. a bare `swift run`), so notifications are skipped there. See scripts/bundle.sh.
    private let notificationsAvailable = Bundle.main.bundleIdentifier != nil

    private init() {
        items = Persistence.shared.load()
        startTimer()
        requestNotificationPermission()
    }

    func add(_ item: ReviewItem) {
        // Webhooks get redelivered (and "opened" is followed by "review_requested"); keep the
        // existing item so its escalation progress isn't reset.
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
        persist()
        escalate(item.id, to: .gentleNudge)
    }

    /// Stops nagging about an item: the user handled it, or it was closed/merged/unassigned.
    func acknowledge(_ id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        persist()
        removeNotifications(for: id)
        OverlayManager.shared.clear(for: id)
        showMostUrgentOverlay()
        publishChange()
    }

    func snooze(_ id: String, minutes: Int) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].snoozedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        items[idx].lastEscalatedAt = Date()
        persist()
        OverlayManager.shared.clear(for: id)
        showMostUrgentOverlay()
        publishChange()
    }

    func clearAll() {
        for item in items { acknowledge(item.id) }
    }

    /// Re-shows overlays for items that were already at an overlay level (app relaunch).
    func restoreOverlays() {
        showMostUrgentOverlay()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkEscalations()
        }
    }

    private func checkEscalations() {
        for item in items where item.isDueForEscalation() {
            if let next = EscalationLevel(rawValue: item.level.rawValue + 1) {
                escalate(item.id, to: next)
            }
        }
    }

    private func escalate(_ id: String, to level: EscalationLevel) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].level = level
        items[idx].lastEscalatedAt = Date()
        persist()

        let item = items[idx]

        switch level {
        case .gentleNudge:
            sendNotification(for: item, title: "Gentle nudge", body: "A PR needs your eyes: \(item.title)", sound: true)
        case .brighter:
            sendNotification(for: item, title: "Still waiting...", body: "\(item.title) is getting lonely", sound: true, timeSensitive: true)
        case .screenWindows, .orangeOverlay, .fullscreen:
            OverlayManager.shared.present(for: item, level: level)
            // Also send a notification as backup
            sendNotification(for: item, title: "Attention Required", body: item.title, sound: true)
        }
        publishChange()
    }

    /// Only one overlay set is shown at a time: the most escalated item that isn't snoozed.
    private func showMostUrgentOverlay() {
        guard OverlayManager.shared.presentedItemID == nil else { return }
        let candidates = items.filter { $0.level.rawValue >= EscalationLevel.screenWindows.rawValue && !$0.isSnoozed() }
        if let top = candidates.max(by: { $0.level.rawValue < $1.level.rawValue }) {
            OverlayManager.shared.present(for: top, level: top.level)
        }
    }

    private func sendNotification(for item: ReviewItem, title: String, body: String, sound: Bool = false, timeSensitive: Bool = false) {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["url": item.url.absoluteString, "id": item.id]
        content.categoryIdentifier = "REVIEW"   // category is registered once in AppDelegate
        if sound { content.sound = .default }
        if timeSensitive { content.interruptionLevel = .timeSensitive }

        let request = UNNotificationRequest(identifier: item.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func removeNotifications(for id: String) {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    private func requestNotificationPermission() {
        guard notificationsAvailable else {
            print("Not running from an app bundle; system notifications disabled (use scripts/bundle.sh).")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func persist() {
        Persistence.shared.save(items)
    }

    private func publishChange() {
        NotificationCenter.default.post(name: .pendingItemsChanged, object: nil)
    }

    var pendingCount: Int { items.count }
    var pendingItems: [ReviewItem] { items.sorted { $0.createdAt < $1.createdAt } }
}
