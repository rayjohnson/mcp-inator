import XCTest
@testable import mcp_inator

final class MCPServerTests: XCTestCase {

    // MARK: - Helpers

    private var binaryURL: URL {
        // Hosted tests nest the xctest bundle inside the app:
        // .../Debug/mcp-inator.app/Contents/PlugIns/mcp-inatorTests.xctest
        // Walk up three components to reach the app bundle, then find the binary.
        let testBundleURL = Bundle(for: type(of: self)).bundleURL
        let appBundleURL = testBundleURL
            .deletingLastPathComponent()  // PlugIns/
            .deletingLastPathComponent()  // Contents/
            .deletingLastPathComponent()  // mcp-inator.app/
        return appBundleURL.appendingPathComponent("Contents/MacOS/mcp-inator")
    }

    /// Sends messages to `mcp-inator --mcp-server`, closes stdin, waits for exit, returns parsed responses.
    private func runServer(messages: [[String: Any]]) throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: binaryURL.path) else {
            throw XCTSkip("mcp-inator binary not found at \(binaryURL.path) — build the app target first")
        }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["--mcp-server"]

        let stdin  = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput  = stdin
        process.standardOutput = stdout
        process.standardError  = stderr

        try process.run()

        // Write all messages then close stdin
        for msg in messages {
            let data = try JSONSerialization.data(withJSONObject: msg)
            stdin.fileHandleForWriting.write(data + "\n".data(using: .utf8)!)
        }
        stdin.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let lines = outputData.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        return try lines.map { line in
            let obj = try JSONSerialization.jsonObject(with: line)
            return obj as? [String: Any] ?? [:]
        }
    }

    /// Returns only responses that have an `id` field (not notifications).
    private func responses(from all: [[String: Any]]) -> [[String: Any]] {
        all.filter { $0["id"] != nil }
    }

    /// Finds the response with the given numeric id. Responses may arrive out of order.
    private func response(id: Int, from all: [[String: Any]]) throws -> [String: Any] {
        try XCTUnwrap(all.first { ($0["id"] as? Int) == id })
    }

    private func makeInitSeq(id: Int = 1) -> [[String: Any]] {
        [
            [
                "jsonrpc": "2.0",
                "id": id,
                "method": "initialize",
                "params": [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [:],
                    "clientInfo": ["name": "test", "version": "1.0"]
                ]
            ],
            ["jsonrpc": "2.0", "method": "notifications/initialized"]
        ]
    }

    // MARK: - Tests

    func testInitializeHandshake() throws {
        let msgs = makeInitSeq()
        let all = try runServer(messages: msgs)
        let resp = try XCTUnwrap(responses(from: all).first)
        let result = try XCTUnwrap(resp["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2024-11-05")
        let serverInfo = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(serverInfo["name"] as? String, "mcp-inator")
        let caps = try XCTUnwrap(result["capabilities"] as? [String: Any])
        XCTAssertNotNil(caps["tools"])
    }

    func testToolsList() throws {
        let msgs = makeInitSeq() + [
            ["jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": [:]]
        ]
        let all = try runServer(messages: msgs)
        let toolsResp = try XCTUnwrap(responses(from: all).last)
        let result = try XCTUnwrap(toolsResp["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("list_servers"), "Expected list_servers, got \(names)")
        XCTAssertTrue(names.contains("add_server"))
        XCTAssertTrue(names.contains("remove_server"))
        XCTAssertTrue(names.contains("enable_server"))
        XCTAssertTrue(names.contains("disable_server"))
        XCTAssertTrue(names.contains("list_agents"))
        XCTAssertEqual(names.count, 6)
    }

    func testAddAndListServer() throws {
        let msgs = makeInitSeq() + [
            [
                "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                "params": [
                    "name": "add_server",
                    "arguments": ["name": "Test Server", "command": "npx", "args": ["-y", "test-mcp"]]
                ]
            ],
            [
                "jsonrpc": "2.0", "id": 3, "method": "tools/call",
                "params": ["name": "list_servers", "arguments": [:]]
            ],
            // Remove the server we just added so tests are idempotent
            [
                "jsonrpc": "2.0", "id": 4, "method": "tools/call",
                "params": ["name": "remove_server", "arguments": ["server_name": "test-server"]]
            ]
        ]
        let all = try runServer(messages: msgs)

        // Responses may arrive out of order — look up by id
        let addResult = try XCTUnwrap((try response(id: 2, from: all))["result"] as? [String: Any])
        let addText = try XCTUnwrap((addResult["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(addText.contains("Added"), "Expected 'Added', got: \(addText)")
        XCTAssertNil(addResult["isError"])

        let listResult = try XCTUnwrap((try response(id: 3, from: all))["result"] as? [String: Any])
        let listText = try XCTUnwrap((listResult["content"] as? [[String: Any]])?.first?["text"] as? String)
        let servers = try XCTUnwrap(
            JSONSerialization.jsonObject(with: listText.data(using: .utf8)!) as? [[String: Any]]
        )
        let keys = servers.compactMap { $0["serverKey"] as? String }
        XCTAssertTrue(keys.contains("test-server"), "Expected test-server in \(keys)")
    }

    func testRemoveServer() throws {
        // Use separate invocations to avoid concurrency ordering issues: add first,
        // then remove, then list in separate process runs so ordering is deterministic.

        // Invocation 1: add the server
        let addMsgs = makeInitSeq() + [
            [
                "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                "params": ["name": "add_server", "arguments": ["name": "Removable", "command": "echo"]]
            ] as [String: Any]
        ]
        let addAll = try runServer(messages: addMsgs)
        let addResult = try XCTUnwrap((try response(id: 2, from: addAll))["result"] as? [String: Any])
        let addText = (addResult["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        let addOK = addText.contains("Added") || addText.contains("already exists")
        XCTAssertTrue(addOK, "Unexpected add result: \(addText)")

        // Invocation 2: remove it (single operation — no ordering race)
        let removeMsgs = makeInitSeq() + [
            [
                "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                "params": ["name": "remove_server", "arguments": ["server_name": "removable"]]
            ] as [String: Any]
        ]
        let removeAll = try runServer(messages: removeMsgs)
        let removeResult = try XCTUnwrap((try response(id: 2, from: removeAll))["result"] as? [String: Any])
        XCTAssertNil(removeResult["isError"], "remove_server failed: \(removeResult)")

        // Invocation 3: list to confirm it's gone
        let listMsgs = makeInitSeq() + [
            [
                "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                "params": ["name": "list_servers", "arguments": [:]]
            ] as [String: Any]
        ]
        let listAll = try runServer(messages: listMsgs)
        let listResult = try XCTUnwrap((try response(id: 2, from: listAll))["result"] as? [String: Any])
        let listText = try XCTUnwrap((listResult["content"] as? [[String: Any]])?.first?["text"] as? String)
        let servers = try XCTUnwrap(
            JSONSerialization.jsonObject(with: listText.data(using: .utf8)!) as? [[String: Any]]
        )
        let keys = servers.compactMap { $0["serverKey"] as? String }
        XCTAssertFalse(keys.contains("removable"), "removable should be gone from \(keys)")
    }

    func testCannotRemoveBuiltIn() throws {
        let msgs = makeInitSeq() + [
            [
                "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                "params": ["name": "remove_server", "arguments": ["server_name": "mcp-inator"]]
            ]
        ]
        let all = try runServer(messages: msgs)
        let reps = responses(from: all)
        let result = try XCTUnwrap(reps.last?["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        let text = (result["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        XCTAssertTrue(text.contains("built-in"), "Expected 'built-in' error, got: \(text)")
    }

    func testAppManagedAgentError() throws {
        let msgs = makeInitSeq() + [
            [
                "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                "params": [
                    "name": "enable_server",
                    "arguments": ["server_name": "mcp-inator", "agent": "gemini_desktop"]
                ]
            ]
        ]
        let all = try runServer(messages: msgs)
        let reps = responses(from: all)
        let result = try XCTUnwrap(reps.last?["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        let text = (result["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        XCTAssertTrue(text.contains("app-managed"), "Expected 'app-managed' error, got: \(text)")
    }

    func testEnableDisableServer() throws {
        // The MCP server process doesn't run agent discovery, so agents are only present
        // if the GUI app has previously discovered them. This test verifies the enable/disable
        // pathway returns a coherent result (either success or "agent not found").
        let msgs = makeInitSeq() + [
            [
                "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                "params": ["name": "add_server", "arguments": ["name": "E2E Test", "command": "echo"]]
            ],
            [
                "jsonrpc": "2.0", "id": 3, "method": "tools/call",
                "params": ["name": "enable_server", "arguments": ["server_name": "e2e-test", "agent": "claude_code"]]
            ],
            [
                "jsonrpc": "2.0", "id": 4, "method": "tools/call",
                "params": ["name": "disable_server", "arguments": ["server_name": "e2e-test", "agent": "claude_code"]]
            ],
            // Cleanup: remove the test server so this test is idempotent
            [
                "jsonrpc": "2.0", "id": 5, "method": "tools/call",
                "params": ["name": "remove_server", "arguments": ["server_name": "e2e-test"]]
            ]
        ]
        let all = try runServer(messages: msgs)

        let enableResult = try XCTUnwrap((try response(id: 3, from: all))["result"] as? [String: Any])
        let enableText = (enableResult["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        // Either success or "agent not found" (no discovery in server mode) — both are valid
        let isKnownOutcome = enableText.contains("Enabled") || enableText.contains("not found")
        XCTAssertTrue(isKnownOutcome, "Unexpected enable result: \(enableText)")
    }

    func testListAgents() throws {
        let msgs = makeInitSeq() + [
            [
                "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                "params": ["name": "list_agents", "arguments": [:]]
            ]
        ]
        let all = try runServer(messages: msgs)
        let reps = responses(from: all)
        let result = try XCTUnwrap(reps.last?["result"] as? [String: Any])
        XCTAssertNil(result["isError"])
        let text = try XCTUnwrap(
            (result["content"] as? [[String: Any]])?.first?["text"] as? String
        )
        // Result must be a valid JSON array (may be empty if no agents discovered in test environment)
        let agents = try XCTUnwrap(
            JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [[String: Any]]
        )
        // Each entry must have the expected shape if present
        for agent in agents {
            XCTAssertNotNil(agent["agentType"])
            XCTAssertNotNil(agent["displayName"])
            XCTAssertNotNil(agent["configPath"])
        }
    }
}
