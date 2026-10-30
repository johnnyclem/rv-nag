import AppKit
import UserNotifications
import SwiftUI
import ServiceManagement
import ReviewNaggerCore

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar app, no dock icon

        if Bundle.main.bundleIdentifier != nil {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.setNotificationCategories([
                UNNotificationCategory(identifier: "REVIEW", actions: [
                    UNNotificationAction(identifier: "OPEN", title: "Open PR", options: .foreground),
                    UNNotificationAction(identifier: "ACK", title: "Dismiss", options: [])
                ], intentIdentifiers: [], options: [])
            ])
        }

        setupStatusItem()
        NotificationCenter.default.addObserver(forName: .pendingItemsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.updateStatusIcon()
        }
        updateStatusIcon()

        WebhookServer.shared.start()
        EscalationManager.shared.restoreOverlays()
    }

    // MARK: - Status item & menu

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self   // rebuilt on every open so it never shows stale state
        statusItem.menu = menu
    }

    private func updateStatusIcon() {
        let count = EscalationManager.shared.pendingCount
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: count > 0 ? "bell.badge.fill" : "bell",
                               accessibilityDescription: "Review Nagger")
        button.title = count > 0 ? " \(count)" : ""
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let items = EscalationManager.shared.pendingItems
        menu.addItem(disabled: items.isEmpty ? "No reviews pending" : "Pending reviews: \(items.count)")
        for item in items {
            let label = "\(item.repo)\(item.prNumber.map { item.id.contains("!") ? "!\($0)" : "#\($0)" } ?? "") — \(item.title)"
            let row = NSMenuItem(title: truncated(label, to: 60), action: nil, keyEquivalent: "")
            row.toolTip = "\(item.title)\nLevel: \(item.level.description)\(item.isSnoozed() ? " (snoozed)" : "")"
            let sub = NSMenu()
            sub.addItem(action: "Open", #selector(openItem(_:)), target: self, id: item.id)
            sub.addItem(action: "Snooze 30 min", #selector(snoozeItem(_:)), target: self, id: item.id)
            sub.addItem(action: "Dismiss", #selector(dismissItem(_:)), target: self, id: item.id)
            row.submenu = sub
            menu.addItem(row)
        }
        menu.addItem(.separator())
        menu.addItem(action: "Simulate New PR", #selector(simulatePR), target: self, key: "s")
        if !items.isEmpty {
            menu.addItem(action: "Clear All", #selector(clearAll), target: self)
        }
        menu.addItem(.separator())

        if WebhookServer.shared.isRunning {
            menu.addItem(disabled: "Webhook: http://localhost:\(Settings.port)/webhook")
        } else {
            menu.addItem(disabled: "Webhook server NOT running" + (WebhookServer.shared.lastError.map { " (\($0))" } ?? ""))
        }
        menu.addItem(action: "Set GitHub Username…", #selector(setGitHubUsername), target: self)
        menu.addItem(action: "Set GitLab Username…", #selector(setGitLabUsername), target: self)
        menu.addItem(action: "Set Webhook Secret…", #selector(setSecret), target: self)
        menu.addItem(action: "Set Port…", #selector(setPort), target: self)
        let login = menu.addItem(action: "Launch at Login", #selector(toggleLaunchAtLogin), target: self)
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func truncated(_ s: String, to n: Int) -> String {
        s.count > n ? String(s.prefix(n - 1)) + "…" : s
    }

    // MARK: - Item actions

    private func item(from sender: Any?) -> ReviewItem? {
        guard let id = (sender as? NSMenuItem)?.representedObject as? String else { return nil }
        return EscalationManager.shared.pendingItems.first { $0.id == id }
    }

    @objc func openItem(_ sender: NSMenuItem) {
        guard let item = item(from: sender) else { return }
        NSWorkspace.shared.open(item.url)
        EscalationManager.shared.acknowledge(item.id)
    }

    @objc func snoozeItem(_ sender: NSMenuItem) {
        guard let item = item(from: sender) else { return }
        EscalationManager.shared.snooze(item.id, minutes: 30)
    }

    @objc func dismissItem(_ sender: NSMenuItem) {
        guard let item = item(from: sender) else { return }
        EscalationManager.shared.acknowledge(item.id)
    }

    @objc func simulatePR() {
        let number = Int.random(in: 1...999)
        EscalationManager.shared.add(ReviewItem(
            id: "demo/repo#\(number)",
            title: "Fix the thing that was broken",
            url: URL(string: "https://github.com")!,
            repo: "demo/repo",
            prNumber: number
        ))
    }

    @objc func clearAll() {
        EscalationManager.shared.clearAll()
        OverlayManager.shared.clearAll()
    }

    // MARK: - Settings

    /// Shows a text prompt. Returns nil on Cancel; an empty string means "clear the value".
    private func prompt(title: String, info: String, current: String?) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = current ?? ""
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return input.stringValue.trimmingCharacters(in: .whitespaces)
    }

    @objc func setGitHubUsername() {
        guard let value = prompt(title: "GitHub Username",
                                 info: "Only alert when a review is requested from this user (leave blank for any PR).",
                                 current: Settings.githubUsername) else { return }
        Settings.githubUsername = value.isEmpty ? nil : value
    }

    @objc func setGitLabUsername() {
        guard let value = prompt(title: "GitLab Username",
                                 info: "Only alert when you are added as a reviewer on a merge request (leave blank for any MR).",
                                 current: Settings.gitlabUsername) else { return }
        Settings.gitlabUsername = value.isEmpty ? nil : value
    }

    @objc func setSecret() {
        guard let value = prompt(title: "Webhook Secret",
                                 info: "Optional. If set, deliveries must carry a valid GitHub signature or GitLab token; unsigned requests are rejected.",
                                 current: Settings.webhookSecret) else { return }
        Settings.webhookSecret = value.isEmpty ? nil : value
    }

    @objc func setPort() {
        guard let value = prompt(title: "Webhook Port",
                                 info: "Local port for the webhook server (default 8080). The server restarts when this changes.",
                                 current: String(Settings.port)) else { return }
        guard let port = UInt(value), (1024...65535).contains(port) else {
            NSSound.beep()
            return
        }
        Settings.port = port
        WebhookServer.shared.restart(port: port)
    }

    @objc func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nThis only works when running the bundled app (scripts/bundle.sh)."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
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

private extension NSMenu {
    func addItem(disabled title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }

    @discardableResult
    func addItem(action title: String, _ selector: Selector, target: AnyObject, key: String = "", id: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = target
        item.representedObject = id
        addItem(item)
        return item
    }
}

// Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
