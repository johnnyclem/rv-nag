import Foundation
import ReviewNaggerCore

/// User-configurable settings, read live so changes apply without a relaunch.
enum Settings {
    private static let defaults = UserDefaults.standard

    static var githubUsername: String? {
        get { defaults.string(forKey: "githubUsername") }
        set { defaults.set(newValue, forKey: "githubUsername") }
    }

    static var gitlabUsername: String? {
        get { defaults.string(forKey: "gitlabUsername") }
        set { defaults.set(newValue, forKey: "gitlabUsername") }
    }

    static var webhookSecret: String? {
        get { defaults.string(forKey: "webhookSecret") }
        set { defaults.set(newValue, forKey: "webhookSecret") }
    }

    static var port: UInt {
        get {
            let value = defaults.integer(forKey: "port")
            return value > 0 ? UInt(value) : 8080
        }
        set { defaults.set(Int(newValue), forKey: "port") }
    }

    static var webhook: WebhookSettings {
        WebhookSettings(githubUsername: githubUsername, gitlabUsername: gitlabUsername, secret: webhookSecret)
    }
}
