import Foundation
import System
import MCP

actor ConnectionTester {

    func test(config: MCPServerConfig) async -> ConnectionTestResult {
        guard config.transportType == .stdio, !config.command.isEmpty else {
            return .launchError(detail: "Connection test is only supported for stdio servers")
        }

        // MARK: Launch process

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
        // Use /usr/bin/env so bare command names are resolved against PATH.
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

        // MARK: MCP handshake with timeout

        let start = Date()

        let stdinFD  = FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor)
        let stdoutFD = FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor)
        let transport = StdioTransport(input: stdoutFD, output: stdinFD)
        let client = Client(name: "mcp-inator-tester", version: "1")

        let result: ConnectionTestResult = await withTaskGroup(of: ConnectionTestResult.self) { group in
            group.addTask {
                do {
                    try await client.connect(transport: transport)
                    let elapsed = Date().timeIntervalSince(start)
                    return .success(elapsedSeconds: elapsed)
                } catch {
                    // Distinguish: process still running → protocol error; exited → launch error
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
            group.addTask {
                try? await Task.sleep(for: .seconds(15))
                return .timeout
            }
            let first = await group.next()!
            group.cancelAll()
            return first
        }

        // MARK: Cleanup

        await client.disconnect()
        if process.isRunning { process.terminate() }

        return result
    }

    // MARK: - Helpers

    nonisolated private func readStderr(stderrPipe: Pipe) -> String {
        let data = stderrPipe.fileHandleForReading.availableData
        let text = String(data: data, encoding: .utf8) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(200))
    }
}
