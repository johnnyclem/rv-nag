import Foundation
import AppKit

class MeetingDetector {
    static let shared = MeetingDetector()
    
    /// Returns true if we believe the user is in a Zoom or Google Meet call.
    /// Zoom: process running + UDP ports (heuristic from community).
    /// Meet: looks for Chrome/Edge/Safari with "Meet" in window title is hard;
    ///       we check for common meeting apps and a simple process check.
    func isInMeeting() -> Bool {
        // Check Zoom
        if isZoomInMeeting() { return true }
        
        // Check for Google Meet app or browser processes (basic)
        let running = NSWorkspace.shared.runningApplications
        // We can't easily check browser tab titles without Accessibility, so Meet is only detected
        // when a dedicated Meet app (e.g. a Chrome PWA) is running. Zoom was handled above.
        if running.contains(where: { $0.localizedName?.lowercased().contains("meet") == true }) {
            return true
        }
        
        return false
    }
    
    private func isZoomInMeeting() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-i", "4UDP"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let zoomLines = output.components(separatedBy: .newlines).filter { $0.lowercased().contains("zoom") }
                // Community heuristic: >1 UDP means likely in meeting
                return zoomLines.count > 1
            }
        } catch {
            // Fallback: just check if Zoom process exists
            let running = NSWorkspace.shared.runningApplications
            return running.contains { $0.bundleIdentifier == "us.zoom.xos" || $0.localizedName == "zoom.us" }
        }
        return false
    }
}
