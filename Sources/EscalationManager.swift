import Foundation
import UserNotifications
import AppKit

class EscalationManager {
    static let shared = EscalationManager()
    
    private var items: [ReviewItem] = []
    private var timer: Timer?
    
    private init() {
        items = Persistence.shared.load()
        startTimer()
        requestNotificationPermission()
    }
    
    func add(_ item: ReviewItem) {
        // Deduplicate by id
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        } else {
            items.append(item)
        }
        persist()
        escalate(item.id, to: .gentleNudge)
    }
    
    func acknowledge(_ id: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].acknowledged = true
            items[idx].level = .gentleNudge // reset visual
        }
        persist()
        OverlayManager.shared.clearAll()
        removeNotifications(for: id)
    }
    
    func snooze(_ id: String, minutes: Int) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].snoozedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
            items[idx].lastEscalatedAt = Date()
        }
        persist()
        OverlayManager.shared.clearAll()
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkEscalations()
        }
    }
    
    private func checkEscalations() {
        for item in items where item.isDueForEscalation {
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
            sendNotification(for: item, title: "Still waiting...", body: "\(item.title) is getting lonely", sound: true, critical: true)
        case .screenWindows, .orangeOverlay, .fullscreen:
            OverlayManager.shared.present(for: item, level: level)
            // Also send a notification as backup
            sendNotification(for: item, title: "Attention Required", body: item.title, sound: true)
        }
    }
    
    private func sendNotification(for item: ReviewItem, title: String, body: String, sound: Bool = false, critical: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["url": item.url.absoluteString, "id": item.id]
        if sound { content.sound = .default }
        if critical {
            content.interruptionLevel = .timeSensitive
        }
        
        // Add actions
        let openAction = UNNotificationAction(identifier: "OPEN", title: "Open PR", options: [.foreground])
        let ackAction = UNNotificationAction(identifier: "ACK", title: "Dismiss", options: [])
        let category = UNNotificationCategory(identifier: "REVIEW", actions: [openAction, ackAction], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        content.categoryIdentifier = "REVIEW"
        
        let request = UNNotificationRequest(identifier: item.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    private func removeNotifications(for id: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    
    private func persist() {
        Persistence.shared.save(items)
    }
    
    var pendingCount: Int { items.filter { !$0.acknowledged }.count }
    var pendingItems: [ReviewItem] { items.filter { !$0.acknowledged } }
}
