import Foundation
import Logging
import MCP

// MARK: - MCPServerRunner

struct MCPServerRunner {

    /// Called from main.swift (@MainActor context). Starts the MCP server and
    /// spins the main run loop until stdin closes and all pending handlers finish.
    static func start() {
        // Task{} inherits @MainActor from the caller (main.swift),
        // so runAsync() runs on the main actor. RunLoop.main.run() keeps
        // the process alive and drives the Swift Concurrency main-actor scheduler.
        Task {
            do {
                try await runAsync()
            } catch {
                fputs("mcp-inator server error: \(error)\n", stderr)
            }
            exit(0)
        }
        RunLoop.main.run()
    }

    // MARK: - Private

    @MainActor
    private static func runAsync() async throws {
        let store = try ConfigStore()
        try store.seedSelfEntry()

        let server = Server(
            name: "mcp-inator",
            version: "0.1.0",
            capabilities: .init(tools: .init())
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: MCPTools.allTools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            await MCPTools.dispatch(store: store, params: params)
        }

        let transport = TerminatingStdioTransport()
        try await server.start(transport: transport)

        // server.start() fires the receive loop in a background task and returns.
        // Wait until stdin closes (transport signals done), then give in-flight
        // handler tasks a moment to finish sending their responses.
        await transport.waitUntilDone()
        try await Task.sleep(for: .milliseconds(150))
    }
}

// MARK: - TerminatingStdioTransport
//
// Wraps StdioTransport and exposes a `waitUntilDone()` method that resolves
// when the receive stream reaches EOF. This lets MCPServerRunner wait until
// all messages have been dispatched before calling exit(0).

private actor TerminatingStdioTransport: Transport {
    private let inner = StdioTransport()
    private var isDone = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    nonisolated var logger: Logger { inner.logger }

    func connect() async throws {
        try await inner.connect()
    }

    func disconnect() async {
        await inner.disconnect()
        finish()
    }

    func send(_ message: Data) async throws {
        try await inner.send(message)
    }

    func receive() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let stream = await inner.receive()
                do {
                    for try await data in stream {
                        continuation.yield(data)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                await self.finish()
            }
        }
    }

    /// Blocks until the receive stream has finished (stdin EOF or disconnect).
    func waitUntilDone() async {
        if isDone { return }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    private func finish() {
        isDone = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters = []
    }
}
