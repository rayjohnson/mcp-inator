import Foundation

enum ConnectionTestResult {
    case success(elapsedSeconds: Double, toolCount: Int)
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
        case .success(let t, let n):
            let toolStr = n == 1 ? "1 tool" : "\(n) tools"
            return String(format: "Connected in %.1fs · %@", t, toolStr)
        case .authRequired:
            return "Server reached · auth required (OAuth not testable)"
        case .launchError(let d):    return "Could not start: \(d)"
        case .protocolError(let d):  return "No MCP response: \(d)"
        case .timeout:               return "No response after 15 s"
        }
    }
}
