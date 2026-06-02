import Foundation

enum ConnectionTestResult {
    case success(elapsedSeconds: Double, toolCount: Int?)
    case authRequired                   // server responded 401/403 — reachable but needs auth
    case launchError(detail: String)
    case protocolError(detail: String)
    case timeout

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var isWarning: Bool {
        if case .authRequired = self { return true }
        return false
    }

    var shortLabel: String {
        switch self {
        case .success(let elapsed, let toolCount):
            let toolStr: String
            if let toolCount {
                toolStr = toolCount == 1 ? "1 tool" : "\(toolCount) tools"
            } else {
                toolStr = "reachable"
            }
            return String(format: "Connected in %.1fs · %@", elapsed, toolStr)
        case .authRequired:
            return "Server reached · auth required (OAuth not testable)"
        case .launchError(let detail):    return "Could not start: \(detail)"
        case .protocolError(let detail):  return "No MCP response: \(detail)"
        case .timeout:                    return "No response after 15 s"
        }
    }
}
