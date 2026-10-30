import Foundation
import GCDWebServer
import ReviewNaggerCore

class WebhookServer {
    static let shared = WebhookServer()
    private let server = GCDWebServer()
    private var handlersInstalled = false

    var isRunning: Bool { server.isRunning }
    private(set) var lastError: String?

    func start(port: UInt = Settings.port) {
        installHandlersIfNeeded()
        guard !server.isRunning else { return }
        do {
            // Localhost only: ngrok/cloudflared/smee tunnels all forward to localhost, and binding
            // all interfaces would let anyone on the LAN inject fake PRs.
            try server.start(options: [
                GCDWebServerOption_Port: port,
                GCDWebServerOption_BindToLocalhost: true
            ])
            lastError = nil
            print("Webhook server started on port \(port)")
        } catch {
            lastError = "\(error.localizedDescription)"
            print("Failed to start server: \(error)")
        }
    }

    func restart(port: UInt = Settings.port) {
        if server.isRunning { server.stop() }
        start(port: port)
    }

    private func installHandlersIfNeeded() {
        guard !handlersInstalled else { return }
        handlersInstalled = true

        server.addHandler(forMethod: "POST", path: "/webhook", request: GCDWebServerDataRequest.self) { request, completion in
            guard let dataRequest = request as? GCDWebServerDataRequest else {
                completion(GCDWebServerResponse(statusCode: 400))
                return
            }

            var headers: [String: String] = [:]
            for (key, value) in request.headers {
                headers[key.lowercased()] = value
            }

            // Settings are read per request so menu changes apply immediately.
            let parser = WebhookParser(settings: Settings.webhook)
            guard parser.isAuthorized(headers: headers, body: dataRequest.data) else {
                completion(GCDWebServerResponse(statusCode: 401))
                return
            }

            switch parser.parse(headers: headers, body: dataRequest.data) {
            case .needsReview(let item):
                DispatchQueue.main.async { EscalationManager.shared.add(item) }
            case .resolved(let id):
                DispatchQueue.main.async { EscalationManager.shared.acknowledge(id) }
            case .ignored:
                break
            }
            completion(GCDWebServerDataResponse(text: "OK"))
        }

        server.addHandler(forMethod: "GET", path: "/health", request: GCDWebServerRequest.self) { _, completion in
            completion(GCDWebServerDataResponse(text: "ReviewNagger is alive"))
        }
    }
}
