import AppKit
import UserNotifications
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar app, no dock icon
        
        UNUserNotificationCenter.current().delegate = self
        
        setupStatusItem()
        WebhookServer.shared.start()
        
        // Handle notification actions
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "REVIEW", actions: [
                UNNotificationAction(identifier: "OPEN", title: "Open", options: .foreground),
                UNNotificationAction(identifier: "ACK", title: "Dismiss", options: [])
            ], intentIdentifiers: [], options: [])
        ])
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "Review Nagger")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Pending: \(EscalationManager.shared.pendingCount)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Simulate New PR", action: #selector(simulatePR), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Clear All", action: #selector(clearAll), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Set GitHub Username...", action: #selector(setUsername), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Set Webhook Secret...", action: #selector(setSecret), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc func simulatePR() {
        let item = ReviewItem(
            id: "demo/repo#\(Int.random(in: 1...999))",
            title: "Fix the thing that was broken",
            url: URL(string: "https://github.com")!,
            repo: "demo/repo",
            prNumber: 42,
            createdAt: Date(),
            lastEscalatedAt: Date(),
            level: .gentleNudge
        )
        EscalationManager.shared.add(item)
        updateMenu()
    }
    
    @objc func clearAll() {
        for item in EscalationManager.shared.pendingItems {
            EscalationManager.shared.acknowledge(item.id)
        }
        OverlayManager.shared.clearAll()
        updateMenu()
    }
    
    @objc func setUsername() {
        let alert = NSAlert()
        alert.messageText = "GitHub Username"
        alert.informativeText = "Only trigger on review requests for this user (leave blank for any)."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = UserDefaults.standard.string(forKey: "githubUsername") ?? ""
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            UserDefaults.standard.set(input.stringValue.isEmpty ? nil : input.stringValue, forKey: "githubUsername")
        }
    }
    
    @objc func setSecret() {
        let alert = NSAlert()
        alert.messageText = "Webhook Secret"
        alert.informativeText = "Optional. If set, GitHub signatures will be verified."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = UserDefaults.standard.string(forKey: "webhookSecret") ?? ""
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            UserDefaults.standard.set(input.stringValue.isEmpty ? nil : input.stringValue, forKey: "webhookSecret")
        }
    }
    
    private func updateMenu() {
        if let item = statusItem.menu?.item(at: 0) {
            item.title = "Pending: \(EscalationManager.shared.pendingCount)"
        }
    }
    
    // MARK: - Notification Delegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        if response.actionIdentifier == "OPEN" || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            if let urlString = response.notification.request.content.userInfo["url"] as? String,
               let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
            EscalationManager.shared.acknowledge(id)
        } else if response.actionIdentifier == "ACK" {
            EscalationManager.shared.acknowledge(id)
        }
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

// Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
