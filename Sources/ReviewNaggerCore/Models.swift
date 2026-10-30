import Foundation

public enum EscalationLevel: Int, Codable, CaseIterable {
    case gentleNudge = 0      // Soft notification
    case brighter = 1         // More vivid notification / small alert
    case screenWindows = 2    // Notification windows on every screen
    case orangeOverlay = 3    // 15% orange overlay + windows
    case fullscreen = 4       // Fullscreen takeover (skipped if in meeting)

    public var description: String {
        switch self {
        case .gentleNudge: return "Gentle Nudge"
        case .brighter: return "Brighter Alert"
        case .screenWindows: return "Screen Windows"
        case .orangeOverlay: return "Orange Overlay"
        case .fullscreen: return "Fullscreen"
        }
    }

    public var intervalMinutes: Int {
        // All steps after the first are 25 minutes
        return self == .gentleNudge ? 0 : 25
    }
}

public struct ReviewItem: Codable, Identifiable, Equatable {
    public let id: String           // Unique: "owner/repo#number" (GitHub) or "group/project!iid" (GitLab)
    public let title: String
    public let url: URL
    public let repo: String
    public let prNumber: Int?
    public let createdAt: Date
    public var lastEscalatedAt: Date
    public var level: EscalationLevel
    public var snoozedUntil: Date?

    public init(
        id: String,
        title: String,
        url: URL,
        repo: String,
        prNumber: Int?,
        createdAt: Date = Date(),
        lastEscalatedAt: Date = Date(),
        level: EscalationLevel = .gentleNudge,
        snoozedUntil: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.repo = repo
        self.prNumber = prNumber
        self.createdAt = createdAt
        self.lastEscalatedAt = lastEscalatedAt
        self.level = level
        self.snoozedUntil = snoozedUntil
    }

    public func isSnoozed(at now: Date = Date()) -> Bool {
        if let snooze = snoozedUntil { return now < snooze }
        return false
    }

    public func isDueForEscalation(at now: Date = Date()) -> Bool {
        if isSnoozed(at: now) { return false }
        guard let next = EscalationLevel(rawValue: level.rawValue + 1) else { return false }
        let due = lastEscalatedAt.addingTimeInterval(TimeInterval(next.intervalMinutes * 60))
        return now >= due
    }
}
