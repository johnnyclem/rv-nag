import AppKit
import SwiftUI
import ReviewNaggerCore

class OverlayManager {
    static let shared = OverlayManager()
    
    private var overlayWindows: [NSWindow] = []
    private var alertWindows: [NSWindow] = []
    
    /// The item the current overlay/windows are about, if any.
    private(set) var presentedItemID: String?
    
    func clearAll() {
        overlayWindows.forEach { $0.orderOut(nil) }
        alertWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
        alertWindows.removeAll()
        presentedItemID = nil
    }
    
    /// Clears the overlay only if it belongs to `id`, so dismissing one PR doesn't hide another's.
    func clear(for id: String) {
        if presentedItemID == id { clearAll() }
    }
    
    func present(for item: ReviewItem, level: EscalationLevel) {
        clearAll()
        presentedItemID = item.id
        
        switch level {
        case .gentleNudge, .brighter:
            // Handled by notifications
            break
        case .screenWindows:
            showAlertWindows(for: item, withOverlay: false)
        case .orangeOverlay:
            showOrangeOverlays()
            showAlertWindows(for: item, withOverlay: true)
        case .fullscreen:
            if MeetingDetector.shared.isInMeeting() {
                // Fallback to orange overlay if in meeting
                showOrangeOverlays()
                showAlertWindows(for: item, withOverlay: true)
            } else {
                showFullscreen(for: item)
            }
        }
    }
    
    private func showOrangeOverlays() {
        for screen in NSScreen.screens {
            let panel = createOverlayPanel(for: screen)
            let view = NSView(frame: screen.frame)
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.15).cgColor
            panel.contentView = view
            panel.ignoresMouseEvents = true
            panel.orderFrontRegardless()
            overlayWindows.append(panel)
        }
    }
    
    private func showAlertWindows(for item: ReviewItem, withOverlay: Bool) {
        for screen in NSScreen.screens {
            let panel = createAlertPanel(for: screen, item: item)
            panel.orderFrontRegardless()
            alertWindows.append(panel)
        }
    }
    
    private func showFullscreen(for item: ReviewItem) {
        for screen in NSScreen.screens {
            let panel = createOverlayPanel(for: screen)
            panel.level = .screenSaver
            panel.ignoresMouseEvents = false
            
            let hosting = NSHostingView(rootView: FullscreenAlertView(item: item, onAction: { action in
                self.handleAction(action, for: item)
            }))
            hosting.frame = screen.frame
            panel.contentView = hosting
            panel.orderFrontRegardless()
            overlayWindows.append(panel)
        }
    }
    
    private func createOverlayPanel(for screen: NSScreen) -> NSPanel {
        let panel = FullScreenPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        return panel
    }
    
    private func createAlertPanel(for screen: NSScreen, item: ReviewItem) -> NSPanel {
        let size = NSSize(width: 420, height: 220)
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "Review Needed"
        panel.isReleasedWhenClosed = false
        
        let hosting = NSHostingView(rootView: AlertWindowView(item: item, onAction: { action in
            self.handleAction(action, for: item)
        }))
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        return panel
    }
    
    private func handleAction(_ action: AlertAction, for item: ReviewItem) {
        switch action {
        case .open:
            NSWorkspace.shared.open(item.url)
            fallthrough
        case .acknowledge:
            EscalationManager.shared.acknowledge(item.id)
        case .snooze:
            EscalationManager.shared.snooze(item.id, minutes: 30)
        }
    }
}

// Subclass to allow covering menu bar and dock
class FullScreenPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

enum AlertAction {
    case open, acknowledge, snooze
}

// MARK: - SwiftUI Views

struct AlertWindowView: View {
    let item: ReviewItem
    let onAction: (AlertAction) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("PR Needs Your Review")
                .font(.headline)
            Text(item.title)
                .font(.title3)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Text(item.repo)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Button("Review Now") { onAction(.open) }
                    .buttonStyle(.borderedProminent)
                Button("Snooze 30m") { onAction(.snooze) }
                Button("Dismiss") { onAction(.acknowledge) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct FullscreenAlertView: View {
    let item: ReviewItem
    let onAction: (AlertAction) -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
            VStack(spacing: 24) {
                Text("YOU HAVE AN UNREVIEWED PR")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                Text(item.title)
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                Text(item.repo)
                    .font(.title2)
                    .foregroundColor(.gray)
                
                HStack(spacing: 20) {
                    Button("Open PR") { onAction(.open) }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                    Button("I've Got It") { onAction(.acknowledge) }
                        .controlSize(.large)
                    Button("Snooze") { onAction(.snooze) }
                        .controlSize(.large)
                }
                .padding(.top, 20)
            }
        }
        .ignoresSafeArea()
    }
}
