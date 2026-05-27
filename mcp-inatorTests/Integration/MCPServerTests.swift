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

    private func responses(from all: [[String: Any]]) -> [[String: Any]] {
        all.filter { $0["id"] != nil }
    }

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
                    "protocolVersion": "2025-11-25",
                    "capabilities": [:],
                    "clientInfo": ["name": "test", "version": "1.0"]
                ]
            ],
            ["jsonrpc": "2.0", "method": "notifications/initialized"]
        ]
    }

    // MARK: - Wire Protocol

    func testInitializeHandshake() throws {
        let msgs = makeInitSeq()
        let all = try runServer(messages: msgs)
        let resp = try XCTUnwrap(responses(from: all).first)
        let result = try XCTUnwrap(resp["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-11-25")
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
        let toolsResp = try response(id: 2, from: all)
        let result = try XCTUnwrap(toolsResp["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("list_servers"), "Expected list_servers, got \(names)")
        XCTAssertTrue(names.contains("add_server"))
        XCTAssertTrue(names.contains("remove_server"))
        XCTAssertTrue(names.contains("enable_server"))
        XCTAssertTrue(names.contains("disable_server"))
        XCTAssertTrue(names.contains("list_agents"))
        XCTAssertTrue(names.contains("list_catalog"))
        XCTAssertEqual(names.count, 7)
    }

    // MARK: - End-to-End Tool Round-Trip

    func testAddAndListServer() throws {
        // Use separate invocations so add and list are never concurrent.

        // Invocation 1: add
        let addMsgs = makeInitSeq() + [
            [
                "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                "params": ["name": "add_server", "arguments": ["name": "Test Server", "command": "npx", "args": ["-y", "test-mcp"]]]
            ] as [String: Any]
        ]
        let addAll = try runServer(messages: addMsgs)
        let addResult = try XCTUnwrap((try response(id: 2, from: addAll))["result"] as? [String: Any])
        let addText = try XCTUnwrap((addResult["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(addText.contains("Added"), "Expected 'Added', got: \(addText)")
        XCTAssertNil(addResult["isError"])

        // Invocation 2: list to confirm presence
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
        XCTAssertTrue(keys.contains("test-server"), "Expected test-server in \(keys)")

        // Invocation 3: cleanup
        let removeMsgs = makeInitSeq() + [
            [
                "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                "params": ["name": "remove_server", "arguments": ["server_name": "test-server"]]
            ] as [String: Any]
        ]
        _ = try runServer(messages: removeMsgs)
    }

    // MARK: - Error Guards (spot-checks of built-in protections)

    func testCannotRemoveBuiltIn() throws {
        let msgs = makeInitSeq() + [
            [
                "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                "params": ["name": "remove_server", "arguments": ["server_name": "mcp-inator"]]
            ]
        ]
        let all = try runServer(messages: msgs)
        let result = try XCTUnwrap((try response(id: 2, from: all))["result"] as? [String: Any])
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
        let result = try XCTUnwrap((try response(id: 2, from: all))["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        let text = (result["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        XCTAssertTrue(text.contains("app-managed"), "Expected 'app-managed' error, got: \(text)")
    }

    func testEnableServer_serverNotFound() throws {
        let msgs = makeInitSeq() + [
            [
                "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                "params": ["name": "enable_server", "arguments": ["server_name": "nonexistent", "agent": "claude_code"]]
            ]
        ]
        let all = try runServer(messages: msgs)
        let result = try XCTUnwrap((try response(id: 2, from: all))["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        let text = (result["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        XCTAssertTrue(text.contains("not found"), "Expected 'not found' error, got: \(text)")
    }
}
