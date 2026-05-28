import Foundation
import System
import MCP

actor ConnectionTester {

    func test(config: MCPServerConfig) async -> ConnectionTestResult {
        switch config.transportType {
        case .stdio:
            return await testStdio(config: config)
        case .http, .sse:
            return await testHTTP(config: config)
        }
    }

    // MARK: - stdio

    private func testStdio(config: MCPServerConfig) async -> ConnectionTestResult {
        guard !config.command.isEmpty else {
            return .launchError(detail: "No command specified")
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        var env = ProcessInfo.processInfo.environment
        // GUI apps don't get the user's full shell PATH. Prepend common locations
        // so bare commands like `uvx`, `npx`, `node` resolve correctly.
        let extraPaths = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin"
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        for ev in config.envVars where !ev.value.isEmpty {
            env[ev.key] = ev.value
        }

        let process = Process()
        if config.command.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: config.command)
            process.arguments = config.args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [config.command] + config.args
        }
        process.environment = env
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .launchError(detail: error.localizedDescription)
        }

        let start = Date()
        let stdinFD  = FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor)
        let stdoutFD = FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor)
        let transport = StdioTransport(input: stdoutFD, output: stdinFD)
        let client = Client(name: "mcp-inator-tester", version: "1")

        let result = await race(timeout: 15, onTimeout: { if process.isRunning { process.terminate() } }) {
            do {
                try await client.connect(transport: transport)
                let elapsed = Date().timeIntervalSince(start)
                let toolCount = (try? await client.listTools().tools.count) ?? 0
                return .success(elapsedSeconds: elapsed, toolCount: toolCount)
            } catch {
                if process.isRunning {
                    return .protocolError(detail: error.localizedDescription)
                }
                let stderr = self.readStderr(stderrPipe: stderrPipe)
                let code = process.terminationStatus
                let detail = stderr.isEmpty
                    ? "Exited with code \(code)"
                    : "Exited with code \(code): \(stderr)"
                return .launchError(detail: detail)
            }
        }

        await client.disconnect()
        if process.isRunning { process.terminate() }
        return result
    }

    // MARK: - HTTP / SSE

    private func testHTTP(config: MCPServerConfig) async -> ConnectionTestResult {
        let trimmedURL = config.url.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmedURL),
              url.scheme == "http" || url.scheme == "https" else {
            return .launchError(detail: "Invalid URL")
        }

        // Inject configured headers (API keys etc.) into every request.
        let headers = config.envVars.filter { !$0.value.isEmpty }
        let requestModifier: @Sendable (URLRequest) -> URLRequest = { request in
            var req = request
            for header in headers {
                req.setValue(header.value, forHTTPHeaderField: header.key)
            }
            return req
        }

        let transport = HTTPClientTransport(
            endpoint: url,
            streaming: false,
            requestModifier: requestModifier
        )
        let client = Client(name: "mcp-inator-tester", version: "1")
        let start = Date()

        let result = await race(timeout: 15, onTimeout: nil) {
            do {
                try await client.connect(transport: transport)
                let elapsed = Date().timeIntervalSince(start)
                let toolCount = (try? await client.listTools().tools.count) ?? 0
                return .success(elapsedSeconds: elapsed, toolCount: toolCount)
            } catch {
                let msg = error.localizedDescription
                if msg.contains("Authentication required") || msg.contains("Access forbidden") {
                    return .authRequired
                }
                return .protocolError(detail: msg)
            }
        }

        await client.disconnect()
        return result
    }

    // MARK: - Race helper

    /// Runs `work` and a timeout concurrently; the first to finish wins.
    /// `onTimeout` is called (on the timeout path) before returning `.timeout`,
    /// allowing callers to kill processes that don't respect cooperative cancellation.
    private func race(
        timeout seconds: Int,
        onTimeout: (@Sendable () -> Void)?,
        work: @escaping @Sendable () async -> ConnectionTestResult
    ) async -> ConnectionTestResult {
        // withTaskGroup implicitly joins all child tasks after its body returns,
        // so we use withCheckedContinuation + OnceSender to return as soon as
        // either task wins without waiting for the other.
        await withCheckedContinuation { (cont: CheckedContinuation<ConnectionTestResult, Never>) in
            let sender = OnceSender(cont)
            Task { await sender.send(await work()) }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                onTimeout?()
                await sender.send(.timeout)
            }
        }
    }

    // MARK: - Helpers

    nonisolated private func readStderr(stderrPipe: Pipe) -> String {
        let data = stderrPipe.fileHandleForReading.availableData
        let text = String(data: data, encoding: .utf8) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(200))
    }
}

// Ensures withCheckedContinuation is resumed exactly once even when two
// concurrent Tasks both try to deliver a result.
private actor OnceSender {
    private var sent = false
    private let continuation: CheckedContinuation<ConnectionTestResult, Never>

    init(_ continuation: CheckedContinuation<ConnectionTestResult, Never>) {
        self.continuation = continuation
    }

    func send(_ result: ConnectionTestResult) {
        guard !sent else { return }
        sent = true
        continuation.resume(returning: result)
    }
}
