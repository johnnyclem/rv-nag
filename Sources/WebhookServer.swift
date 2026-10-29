import Foundation
import GCDWebServer
import CommonCrypto

class WebhookServer {
    static let shared = WebhookServer()
    private let server = GCDWebServer()
    private var secret: String? = UserDefaults.standard.string(forKey: "webhookSecret")
    private var githubUsername: String? = UserDefaults.standard.string(forKey: "githubUsername")
    
    func start(port: UInt = 8080) {
        server.addHandler(forMethod: "POST", path: "/webhook", request: GCDWebServerDataRequest.self) { [weak self] request, completion in
            guard let self = self,
                  let dataRequest = request as? GCDWebServerDataRequest else {
                completion(GCDWebServerResponse(statusCode: 400))
                return
            }
            
            // Optional signature verification
            if let secret = self.secret,
               let signature = request.headers["X-Hub-Signature-256"] as? String,
               !self.verifySignature(body: dataRequest.data, signature: signature, secret: secret) {
                completion(GCDWebServerResponse(statusCode: 401))
                return
            }
            
            if let item = self.parseGitHubWebhook(data: dataRequest.data) {
                DispatchQueue.main.async {
                    EscalationManager.shared.add(item)
                }
                completion(GCDWebServerDataResponse(text: "OK"))
            } else {
                completion(GCDWebServerResponse(statusCode: 200)) // ignore other events
            }
        }
        
        server.addHandler(forMethod: "GET", path: "/health", request: GCDWebServerRequest.self) { _, completion in
            completion(GCDWebServerDataResponse(text: "ReviewNagger is alive"))
        }
        
        do {
            try server.start(options: [
                GCDWebServerOption_Port: port,
                GCDWebServerOption_BindToLocalhost: false, // listen on all interfaces
                GCDWebServerOption_AutomaticallySuspendInBackground: false
            ])
            print("Webhook server started on port \(port)")
        } catch {
            print("Failed to start server: \(error)")
        }
    }
    
    private func verifySignature(body: Data, signature: String, secret: String) -> Bool {
        // GitHub uses sha256=hex
        guard signature.hasPrefix("sha256=") else { return false }
        let expected = "sha256=" + body.hmacSHA256(key: secret)
        return signature == expected
    }
    
    private func parseGitHubWebhook(data: Data) -> ReviewItem? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["action"] as? String else { return nil }
        
        // We care about pull_request events
        guard let pr = json["pull_request"] as? [String: Any],
              let title = pr["title"] as? String,
              let htmlURL = pr["html_url"] as? String,
              let url = URL(string: htmlURL),
              let number = pr["number"] as? Int,
              let repoDict = json["repository"] as? [String: Any],
              let fullName = repoDict["full_name"] as? String else {
            return nil
        }
        
        let relevantActions = ["opened", "review_requested", "ready_for_review", "reopened"]
        guard relevantActions.contains(event) else { return nil }
        
        // Optional: only if the user is requested as reviewer
        if let username = githubUsername,
           let reviewers = pr["requested_reviewers"] as? [[String: Any]] {
            let isRequested = reviewers.contains { ($0["login"] as? String) == username }
            if !isRequested && event == "review_requested" { return nil }
        }
        
        let id = "\(fullName)#\(number)"
        return ReviewItem(
            id: id,
            title: title,
            url: url,
            repo: fullName,
            prNumber: number,
            createdAt: Date(),
            lastEscalatedAt: Date(),
            level: .gentleNudge
        )
    }
}

// Simple HMAC helper
extension Data {
    func hmacSHA256(key: String) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withCString { keyPtr in
            self.withUnsafeBytes { bodyPtr in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), keyPtr, key.count, bodyPtr.baseAddress, self.count, &digest)
            }
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
