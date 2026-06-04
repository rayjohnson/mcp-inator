import Foundation

// MARK: - PingPreferences

enum PingPreferences {
    static var hasLaunched: Bool {
        get { UserDefaults.standard.bool(forKey: "pingHasLaunched") }
        set { UserDefaults.standard.set(newValue, forKey: "pingHasLaunched") }
    }

    static var lastActiveDate: String {
        get { UserDefaults.standard.string(forKey: "pingLastActiveDate") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "pingLastActiveDate") }
    }
}

// MARK: - PingReport

struct PingReport: Codable {
    let schemaVersion: String
    let event: String
    let appVersion: String

    init(event: String) {
        self.schemaVersion = "1"
        self.event = event
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}

// MARK: - PingService

@MainActor
final class PingService {
    static let shared = PingService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func firePingsIfNeeded() async {
        var events: [String] = []

        if !PingPreferences.hasLaunched {
            PingPreferences.hasLaunched = true
            events.append("first_launch")
        }

        let today = todayString()
        if PingPreferences.lastActiveDate != today {
            PingPreferences.lastActiveDate = today
            events.append("daily_active")
        }

        await withTaskGroup(of: Void.self) { group in
            for event in events {
                group.addTask { await self.firePing(event: event) }
            }
        }
    }

    private func firePing(event: String) async {
        let report = PingReport(event: event)
        guard let body = try? JSONEncoder().encode(report) else { return }
        var request = URLRequest(
            url: TelemetryConfig.serviceURL.appendingPathComponent("ping"),
            timeoutInterval: 10
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(TelemetryConfig.bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        _ = try? await session.data(for: request)
    }

    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
