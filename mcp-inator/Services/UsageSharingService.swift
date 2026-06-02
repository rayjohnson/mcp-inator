import Foundation

// MARK: - UsageReport

struct UsageReport: Codable {
    let schemaVersion: String
    let serverKeys: [String]

    init(serverKeys: [String]) {
        self.schemaVersion = "1"
        self.serverKeys = serverKeys
    }
}

// MARK: - SanitizedServerEntry

struct SanitizedServerEntry: Identifiable {
    let id: UUID
    let serverKey: String
    let command: String
    let sanitizedArgs: [String]
    let envVarKeys: [String]
    var isExcluded: Bool
}

// MARK: - UsageSharingService

@MainActor
final class UsageSharingService {
    static let shared = UsageSharingService()

    private let session: URLSession
    private let maxRetries = 3

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Payload Building

    func buildEntries(servers: [MCPServerConfig]) -> [SanitizedServerEntry] {
        let excluded = Set(SharingPreferences.excludedKeys)
        return servers.compactMap { server in
            guard !server.isPrivate else { return nil }
            return SanitizedServerEntry(
                id: server.uuid,
                serverKey: server.serverKey,
                command: basename(server.command),
                sanitizedArgs: server.args.map { sanitizeArg($0) },
                envVarKeys: server.envVars.map(\.key),
                isExcluded: excluded.contains(server.serverKey)
            )
        }
    }

    func buildPayload(entries: [SanitizedServerEntry]) -> UsageReport? {
        let keys = entries.filter { !$0.isExcluded }.map(\.serverKey)
        return UsageReport(serverKeys: keys)
    }

    // MARK: - Submission

    func submit(report: UsageReport) async throws {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                try await postReport(report)
                return
            } catch let err as URLError where isRetryable(err) {
                lastError = err
                if attempt < maxRetries - 1 {
                    let delay = pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch let httpErr as HTTPError where httpErr.statusCode >= 500 {
                lastError = httpErr
                if attempt < maxRetries - 1 {
                    let delay = pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch {
                throw error
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    // MARK: - Retry Queue

    func queueForRetry(_ report: UsageReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        SharingPreferences.pendingReport = data
        SharingPreferences.pendingRetryCount = maxRetries
    }

    func clearPending() {
        SharingPreferences.pendingReport = nil
        SharingPreferences.pendingRetryCount = 0
    }

    func flushPendingIfNeeded() async {
        guard let data = SharingPreferences.pendingReport,
              let report = try? JSONDecoder().decode(UsageReport.self, from: data) else {
            return
        }

        let remaining = SharingPreferences.pendingRetryCount
        guard remaining > 0 else {
            clearPending()
            return
        }

        SharingPreferences.pendingRetryCount = remaining - 1
        do {
            try await postReport(report)
            clearPending()
        } catch {
            if SharingPreferences.pendingRetryCount == 0 {
                clearPending()
            }
        }
    }

    // MARK: - Private

    private func postReport(_ report: UsageReport) async throws {
        var request = URLRequest(url: TelemetryConfig.serviceURL.appendingPathComponent("report"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(TelemetryConfig.bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(report)
        request.timeoutInterval = 10

        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 500 {
            throw HTTPError(statusCode: http.statusCode)
        }
    }

    private func basename(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        return (path as NSString).lastPathComponent
    }

    private func sanitizeArg(_ arg: String) -> String {
        let isPath = arg.hasPrefix("/") || arg.hasPrefix("~")
        return isPath ? "<path>" : arg
    }

    private func isRetryable(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost:
            return true
        default:
            return false
        }
    }
}

// MARK: - HTTPError

struct HTTPError: Error {
    let statusCode: Int
}
