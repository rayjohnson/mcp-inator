import Foundation

// MARK: - SharingPreferences

enum SharingPreferences {
    // Set once on first launch; used to gate the consent prompt (>7 days).
    static var firstLaunchDate: Date? {
        get { UserDefaults.standard.object(forKey: "sharingFirstLaunchDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "sharingFirstLaunchDate") }
    }

    // True after the user submits from the review screen.
    static var consented: Bool {
        get { UserDefaults.standard.bool(forKey: "sharingConsented") }
        set { UserDefaults.standard.set(newValue, forKey: "sharingConsented") }
    }

    // Cleared on every launch; prevents showing the prompt more than once per session.
    static var shownThisSession: Bool {
        get { UserDefaults.standard.bool(forKey: "sharingConsentShownThisSession") }
        set { UserDefaults.standard.set(newValue, forKey: "sharingConsentShownThisSession") }
    }

    // Timestamp of when the consent prompt was last shown.
    static var consentShownAt: Date? {
        get { UserDefaults.standard.object(forKey: "sharingConsentShownAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "sharingConsentShownAt") }
    }

    // Serialised UsageReport payload to retry on next launch.
    static var pendingReport: Data? {
        get { UserDefaults.standard.data(forKey: "sharingPendingReport") }
        set {
            if let data = newValue {
                UserDefaults.standard.set(data, forKey: "sharingPendingReport")
            } else {
                UserDefaults.standard.removeObject(forKey: "sharingPendingReport")
            }
        }
    }

    // Number of launch-retry attempts remaining for the pending report.
    static var pendingRetryCount: Int {
        get { UserDefaults.standard.integer(forKey: "sharingPendingRetryCount") }
        set { UserDefaults.standard.set(newValue, forKey: "sharingPendingRetryCount") }
    }

    // Server keys the user has permanently excluded from reports.
    static var excludedKeys: [String] {
        get { UserDefaults.standard.stringArray(forKey: "sharingExcludedKeys") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "sharingExcludedKeys") }
    }
}

// MARK: - TelemetryConfig

enum TelemetryConfig {
    // swiftlint:disable:next force_unwrapping
    static let serviceURL = URL(string: "https://mcp-inator-telemetry-128251816185.us-central1.run.app")!
    static let bearerToken = "ff503c3842fd5d6fd6308874ee7f9a4f67ff4ed96d0116b248f94de97fadd873"
}
