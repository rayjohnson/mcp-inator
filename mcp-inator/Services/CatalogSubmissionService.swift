import Foundation

struct CatalogSubmissionService {
    struct SubmitEnvVar: Encodable {
        let name: String
        let description: String
        let isRequired: Bool
        let isSensitive: Bool
    }

    struct SubmitRequest: Encodable {
        let serverKey: String
        let displayName: String
        let transportType: String
        let command: String
        let args: [String]
        let url: String
        let envVars: [SubmitEnvVar]
        let notes: String
        let submitterNote: String
    }

    struct SubmitResponse: Decodable {
        let status: String
        let issueURL: String?
        let message: String?
    }

    enum SubmitError: Error, LocalizedError {
        case notAvailable
        case serverError(String)
        case network(Error)

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Catalog submissions are not available yet. Try again later."
            case .serverError(let msg):
                return msg
            case .network(let err):
                return err.localizedDescription
            }
        }
    }

    static func submit(_ config: MCPServerConfig, submitterNote: String) async throws -> URL {
        let envVars = config.envVars.map {
            SubmitEnvVar(
                name: $0.key,
                description: "",
                isRequired: !$0.value.isEmpty,
                isSensitive: $0.isSensitive
            )
        }

        let req = SubmitRequest(
            serverKey: config.serverKey,
            displayName: config.displayName,
            transportType: config.transportType.rawValue,
            command: config.command,
            args: config.args,
            url: config.url,
            envVars: envVars,
            notes: config.notes,
            submitterNote: submitterNote
        )

        var urlRequest = URLRequest(url: TelemetryConfig.serviceURL.appendingPathComponent("submit"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(TelemetryConfig.bearerToken)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(req)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw SubmitError.network(error)
        }

        let decoded = try JSONDecoder().decode(SubmitResponse.self, from: data)

        if let http = response as? HTTPURLResponse, http.statusCode == 503 {
            throw SubmitError.notAvailable
        }

        guard decoded.status == "ok", let issueURLString = decoded.issueURL,
              let issueURL = URL(string: issueURLString) else {
            throw SubmitError.serverError(decoded.message ?? "Submission failed")
        }

        return issueURL
    }
}
