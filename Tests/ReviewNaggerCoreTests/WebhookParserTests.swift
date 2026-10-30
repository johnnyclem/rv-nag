import XCTest
import CryptoKit
@testable import ReviewNaggerCore

final class WebhookParserTests: XCTestCase {
    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func githubPayload(
        action: String,
        draft: Bool = false,
        author: String = "alice",
        requestedReviewers: [String] = [],
        requestedReviewer: String? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "action": action,
            "pull_request": [
                "title": "Fix it",
                "html_url": "https://github.com/o/r/pull/7",
                "number": 7,
                "draft": draft,
                "user": ["login": author],
                "requested_reviewers": requestedReviewers.map { ["login": $0] },
            ],
            "repository": ["full_name": "o/r"],
        ]
        if let r = requestedReviewer { payload["requested_reviewer"] = ["login": r] }
        return payload
    }

    private func parser(github: String? = nil, gitlab: String? = nil, secret: String? = nil) -> WebhookParser {
        WebhookParser(settings: WebhookSettings(githubUsername: github, gitlabUsername: gitlab, secret: secret))
    }

    // MARK: GitHub

    func testGitHubOpenedWithoutUsernameNotifies() {
        let out = parser().parse(headers: [:], body: json(githubPayload(action: "opened")))
        guard case .needsReview(let item) = out else { return XCTFail("\(out)") }
        XCTAssertEqual(item.id, "o/r#7")
        XCTAssertEqual(item.title, "Fix it")
    }

    func testGitHubDraftIgnored() {
        let out = parser().parse(headers: [:], body: json(githubPayload(action: "opened", draft: true)))
        XCTAssertEqual(out, .ignored)
    }

    func testGitHubUsernameFilterOnReviewRequested() {
        let me = parser(github: "Bob")
        XCTAssertEqual(me.parse(headers: [:], body: json(githubPayload(action: "review_requested", requestedReviewer: "carol"))), .ignored)
        guard case .needsReview = me.parse(headers: [:], body: json(githubPayload(action: "review_requested", requestedReviewer: "bob"))) else {
            return XCTFail("expected needsReview (case-insensitive match)")
        }
    }

    func testGitHubOpenedWithUsernameRequiresBeingRequested() {
        let me = parser(github: "bob")
        XCTAssertEqual(me.parse(headers: [:], body: json(githubPayload(action: "opened", requestedReviewers: ["carol"]))), .ignored)
        guard case .needsReview = me.parse(headers: [:], body: json(githubPayload(action: "opened", requestedReviewers: ["bob"]))) else {
            return XCTFail("expected needsReview")
        }
    }

    func testGitHubOwnPRIgnored() {
        let out = parser(github: "alice").parse(headers: [:], body: json(githubPayload(action: "opened", requestedReviewers: ["alice"])))
        XCTAssertEqual(out, .ignored)
    }

    func testGitHubClosedResolves() {
        XCTAssertEqual(parser().parse(headers: ["x-github-event": "pull_request"], body: json(githubPayload(action: "closed"))), .resolved(id: "o/r#7"))
    }

    func testGitHubReviewRequestRemovedResolvesOnlyForMe() {
        let me = parser(github: "bob")
        XCTAssertEqual(me.parse(headers: [:], body: json(githubPayload(action: "review_request_removed", requestedReviewer: "bob"))), .resolved(id: "o/r#7"))
        XCTAssertEqual(me.parse(headers: [:], body: json(githubPayload(action: "review_request_removed", requestedReviewer: "carol"))), .ignored)
    }

    func testGitHubSubmittedReviewByMeResolves() {
        var payload = githubPayload(action: "submitted")
        payload["review"] = ["user": ["login": "bob"]]
        XCTAssertEqual(parser(github: "bob").parse(headers: ["x-github-event": "pull_request_review"], body: json(payload)), .resolved(id: "o/r#7"))
        XCTAssertEqual(parser(github: "dave").parse(headers: ["x-github-event": "pull_request_review"], body: json(payload)), .ignored)
    }

    func testPingAndGarbageIgnored() {
        XCTAssertEqual(parser().parse(headers: ["x-github-event": "ping"], body: json(["zen": "Keep it logically awesome."])), .ignored)
        XCTAssertEqual(parser().parse(headers: [:], body: Data("not json".utf8)), .ignored)
    }

    // MARK: GitLab

    private func gitlabPayload(action: String, actor: String = "alice", reviewers: [String] = [], changedReviewers: Bool = false) -> [String: Any] {
        var payload: [String: Any] = [
            "object_kind": "merge_request",
            "user": ["username": actor],
            "project": ["path_with_namespace": "grp/proj"],
            "object_attributes": ["iid": 3, "title": "MR title", "url": "https://gitlab.com/grp/proj/-/merge_requests/3", "action": action],
            "reviewers": reviewers.map { ["username": $0] },
        ]
        if changedReviewers { payload["changes"] = ["reviewers": ["previous": [], "current": []]] }
        return payload
    }

    func testGitLabOpenNotifiesWithBangId() {
        guard case .needsReview(let item) = parser().parse(headers: ["x-gitlab-event": "Merge Request Hook"], body: json(gitlabPayload(action: "open"))) else {
            return XCTFail()
        }
        XCTAssertEqual(item.id, "grp/proj!3")
        XCTAssertEqual(item.prNumber, 3)
    }

    func testGitLabUpdateWithoutReviewerChangeIgnored() {
        XCTAssertEqual(parser().parse(headers: [:], body: json(gitlabPayload(action: "update"))), .ignored)
    }

    func testGitLabUsernameFilter() {
        let me = parser(gitlab: "bob")
        XCTAssertEqual(me.parse(headers: [:], body: json(gitlabPayload(action: "open", reviewers: ["carol"]))), .ignored)
        guard case .needsReview = me.parse(headers: [:], body: json(gitlabPayload(action: "update", reviewers: ["bob"], changedReviewers: true))) else {
            return XCTFail()
        }
        // Removed as reviewer -> resolve.
        XCTAssertEqual(me.parse(headers: [:], body: json(gitlabPayload(action: "update", reviewers: [], changedReviewers: true))), .resolved(id: "grp/proj!3"))
    }

    func testGitLabMergeCloseAndOwnApprovalResolve() {
        XCTAssertEqual(parser().parse(headers: [:], body: json(gitlabPayload(action: "merge"))), .resolved(id: "grp/proj!3"))
        XCTAssertEqual(parser().parse(headers: [:], body: json(gitlabPayload(action: "close"))), .resolved(id: "grp/proj!3"))
        XCTAssertEqual(parser(gitlab: "bob").parse(headers: [:], body: json(gitlabPayload(action: "approved", actor: "bob"))), .resolved(id: "grp/proj!3"))
        XCTAssertEqual(parser(gitlab: "bob").parse(headers: [:], body: json(gitlabPayload(action: "approved", actor: "zed"))), .ignored)
    }

    // MARK: Auth

    func testNoSecretAcceptsEverything() {
        XCTAssertTrue(parser().isAuthorized(headers: [:], body: Data()))
    }

    func testSecretRejectsUnsignedAndBadSignature() {
        let p = parser(secret: "s3cret")
        XCTAssertFalse(p.isAuthorized(headers: [:], body: Data("x".utf8)))
        XCTAssertFalse(p.isAuthorized(headers: ["x-hub-signature-256": "sha256=deadbeef"], body: Data("x".utf8)))
        XCTAssertFalse(p.isAuthorized(headers: ["x-hub-signature-256": "nonsense"], body: Data("x".utf8)))
    }

    func testSecretAcceptsValidGitHubSignatureAndGitLabToken() {
        let body = Data("{\"a\":1}".utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: body, using: SymmetricKey(data: Data("s3cret".utf8)))
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        let p = parser(secret: "s3cret")
        XCTAssertTrue(p.isAuthorized(headers: ["x-hub-signature-256": "sha256=" + hex], body: body))
        XCTAssertTrue(p.isAuthorized(headers: ["x-gitlab-token": "s3cret"], body: body))
        XCTAssertFalse(p.isAuthorized(headers: ["x-gitlab-token": "wrong"], body: body))
    }
}

final class ReviewItemTests: XCTestCase {
    private func item(level: EscalationLevel, lastEscalated: Date, snoozedUntil: Date? = nil) -> ReviewItem {
        ReviewItem(id: "o/r#1", title: "t", url: URL(string: "https://x.test")!, repo: "o/r", prNumber: 1,
                   createdAt: lastEscalated, lastEscalatedAt: lastEscalated, level: level, snoozedUntil: snoozedUntil)
    }

    func testDueAfter25Minutes() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let i = item(level: .gentleNudge, lastEscalated: t0)
        XCTAssertFalse(i.isDueForEscalation(at: t0.addingTimeInterval(24 * 60)))
        XCTAssertTrue(i.isDueForEscalation(at: t0.addingTimeInterval(25 * 60)))
    }

    func testFullscreenIsTerminal() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(item(level: .fullscreen, lastEscalated: t0).isDueForEscalation(at: t0.addingTimeInterval(10_000 * 60)))
    }

    func testSnoozeBlocksEscalation() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let i = item(level: .brighter, lastEscalated: t0, snoozedUntil: t0.addingTimeInterval(60 * 60))
        XCTAssertFalse(i.isDueForEscalation(at: t0.addingTimeInterval(30 * 60)))
        XCTAssertTrue(i.isDueForEscalation(at: t0.addingTimeInterval(61 * 60)))
    }
}
