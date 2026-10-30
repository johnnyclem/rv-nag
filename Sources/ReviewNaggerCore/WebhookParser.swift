import Foundation
import CryptoKit

/// What a webhook delivery means for the pending-review list.
public enum WebhookOutcome: Equatable {
    /// A review is being asked of the user.
    case needsReview(ReviewItem)
    /// The review is no longer needed (closed/merged, request removed, user already reviewed).
    case resolved(id: String)
    case ignored
}

public struct WebhookSettings: Equatable {
    public var githubUsername: String?
    public var gitlabUsername: String?
    public var secret: String?

    public init(githubUsername: String? = nil, gitlabUsername: String? = nil, secret: String? = nil) {
        self.githubUsername = githubUsername
        self.gitlabUsername = gitlabUsername
        self.secret = secret
    }
}

/// Authenticates and interprets GitHub (pull_request, pull_request_review) and
/// GitLab (Merge Request Hook) webhook deliveries. Header keys must be lowercased.
public struct WebhookParser {
    public let settings: WebhookSettings

    public init(settings: WebhookSettings) {
        self.settings = settings
    }

    // MARK: - Authentication

    /// With no secret configured every delivery is accepted. With one configured, a delivery
    /// must carry a valid GitHub signature or a matching GitLab token; unsigned requests are rejected.
    public func isAuthorized(headers: [String: String], body: Data) -> Bool {
        guard let secret = settings.secret, !secret.isEmpty else { return true }
        if let signature = headers["x-hub-signature-256"] {
            return Self.verifyGitHubSignature(body: body, signature: signature, secret: secret)
        }
        if let token = headers["x-gitlab-token"] {
            return Self.constantTimeEqual(Array(token.utf8), Array(secret.utf8))
        }
        return false
    }

    public static func verifyGitHubSignature(body: Data, signature: String, secret: String) -> Bool {
        let prefix = "sha256="
        guard signature.hasPrefix(prefix),
              let mac = Self.data(fromHex: String(signature.dropFirst(prefix.count))) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: body, using: SymmetricKey(data: Data(secret.utf8)))
    }

    private static func data(fromHex hex: String) -> Data? {
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    private static func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }

    // MARK: - Parsing

    public func parse(headers: [String: String], body: Data, now: Date = Date()) -> WebhookOutcome {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return .ignored }
        if headers["x-gitlab-event"] != nil || json["object_kind"] != nil {
            return parseGitLab(json, now: now)
        }
        return parseGitHub(json, event: headers["x-github-event"], now: now)
    }

    private func parseGitHub(_ json: [String: Any], event: String?, now: Date) -> WebhookOutcome {
        // Header is absent on hand-made payloads (e.g. the README's curl example), so infer it.
        let kind = event ?? (json["review"] != nil ? "pull_request_review" : "pull_request")
        guard let action = json["action"] as? String,
              let pr = json["pull_request"] as? [String: Any],
              let number = pr["number"] as? Int,
              let repository = json["repository"] as? [String: Any],
              let fullName = repository["full_name"] as? String else { return .ignored }

        let id = "\(fullName)#\(number)"
        let me = settings.githubUsername

        func isMe(_ user: Any?) -> Bool {
            guard let me = me, let login = (user as? [String: Any])?["login"] as? String else { return false }
            return login.caseInsensitiveCompare(me) == .orderedSame
        }

        switch kind {
        case "pull_request_review":
            // The user reviewed it themselves, so stop nagging.
            if action == "submitted", isMe((json["review"] as? [String: Any])?["user"]) {
                return .resolved(id: id)
            }
            return .ignored

        case "pull_request":
            switch action {
            case "closed", "converted_to_draft":
                return .resolved(id: id)
            case "review_request_removed":
                return isMe(json["requested_reviewer"]) ? .resolved(id: id) : .ignored
            case "opened", "reopened", "ready_for_review", "review_requested":
                if pr["draft"] as? Bool == true { return .ignored }
                if me != nil {
                    if isMe(pr["user"]) { return .ignored }
                    let requested: Bool
                    if action == "review_requested" {
                        requested = isMe(json["requested_reviewer"])
                    } else {
                        requested = (pr["requested_reviewers"] as? [Any])?.contains(where: isMe) ?? false
                    }
                    guard requested else { return .ignored }
                }
                guard let title = pr["title"] as? String,
                      let htmlURL = pr["html_url"] as? String,
                      let url = URL(string: htmlURL) else { return .ignored }
                return .needsReview(ReviewItem(id: id, title: title, url: url, repo: fullName,
                                               prNumber: number, createdAt: now, lastEscalatedAt: now))
            default:
                return .ignored
            }

        default:
            return .ignored
        }
    }

    private func parseGitLab(_ json: [String: Any], now: Date) -> WebhookOutcome {
        guard json["object_kind"] as? String == "merge_request",
              let attrs = json["object_attributes"] as? [String: Any],
              let iid = attrs["iid"] as? Int,
              let project = json["project"] as? [String: Any],
              let path = project["path_with_namespace"] as? String else { return .ignored }

        let id = "\(path)!\(iid)"
        let action = attrs["action"] as? String ?? ""
        let me = settings.gitlabUsername

        func same(_ name: String?) -> Bool {
            guard let me = me, let name = name else { return false }
            return name.caseInsensitiveCompare(me) == .orderedSame
        }
        let actor = (json["user"] as? [String: Any])?["username"] as? String
        let reviewers = (json["reviewers"] as? [[String: Any]])?.compactMap { $0["username"] as? String } ?? []
        let reviewersChanged = (json["changes"] as? [String: Any])?["reviewers"] != nil

        switch action {
        case "close", "merge":
            return .resolved(id: id)
        case "approved", "approval":
            return same(actor) ? .resolved(id: id) : .ignored
        case "open", "reopen", "update":
            if attrs["draft"] as? Bool == true || attrs["work_in_progress"] as? Bool == true { return .ignored }
            // Other edits to an MR must not re-trigger; only reviewer changes matter.
            if action == "update" && !reviewersChanged { return .ignored }
            if me != nil {
                if action == "open" && same(actor) { return .ignored }   // actor on "open" is the author
                if !reviewers.contains(where: { same($0) }) {
                    return (action == "update") ? .resolved(id: id) : .ignored   // removed as reviewer
                }
            }
            guard let title = attrs["title"] as? String,
                  let urlString = attrs["url"] as? String,
                  let url = URL(string: urlString) else { return .ignored }
            return .needsReview(ReviewItem(id: id, title: title, url: url, repo: path,
                                           prNumber: iid, createdAt: now, lastEscalatedAt: now))
        default:
            return .ignored
        }
    }
}
