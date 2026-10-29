import Foundation

enum EscalationLevel: Int, Codable, CaseIterable {
    case gentleNudge = 0      // Soft notification
    case brighter = 1         // More vivid notification / small alert
    case screenWindows = 2    // Notification windows on every screen
    case orangeOverlay = 3    // 15% orange overlay + windows
    case fullscreen = 4       // Fullscreen takeover (skipped if in meeting)
    
    var description: String {
        switch self {
        case .gentleNudge: return "Gentle Nudge"
        case .brighter: return "Brighter Alert"
        case .screenWindows: return "Screen Windows"
        case .orangeOverlay: return "Orange Overlay"
        case .fullscreen: return "Fullscreen"
        }
    }
    
    var intervalMinutes: Int {
        // All steps after the first are 25 minutes
        return self == .gentleNudge ? 0 : 25
    }
}

struct ReviewItem: Codable, Identifiable {
    let id: String           // Unique: "repo#number" or URL
    let title: String
    let url: URL
    let repo: String
    let prNumber: Int?
    let createdAt: Date
    var lastEscalatedAt: Date
    var level: EscalationLevel
    var acknowledged: Bool = false
    var snoozedUntil: Date?
    
    var isDueForEscalation: Bool {
        guard !acknowledged else { return false }
        if let snooze = snoozedUntil, Date() < snooze { return false }
        
        let nextLevel = EscalationLevel(rawValue: level.rawValue + 1)
        guard nextLevel != nil else { return false }
        
        let minutes = nextLevel?.intervalMinutes ?? 25
        let due = lastEscalatedAt.addingTimeInterval(TimeInterval(minutes * 60))
        return Date() >= due
    }
}
