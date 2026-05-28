# Feature Specification: MCP Server Connection Test

**Feature Branch**: `008-mcp-connection-test`

**Created**: 2026-05-28

**Status**: Draft

**Input**: User description: "Connection test button for MCP servers — allow users to verify that a configured MCP server is reachable and responding before enabling it in an agent. Show connection status (success, timeout, error) inline in the server detail view."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Test a Server Before Adding It to an Agent (Priority: P1)

A user has added or edited an MCP server in their library and wants to confirm it works before enabling it in any agent. They press a "Test Connection" button on the server detail view and see an inline result — a success indicator with response time on success, or a clear error message describing what went wrong.

**Why this priority**: This is the core ask. Users currently have no feedback loop — a broken server silently fails inside the agent. Being able to validate before assigning saves debugging time.

**Independent Test**: Open a server's detail view, press "Test Connection", and verify the correct status is shown without enabling the server in any agent.

**Acceptance Scenarios**:

1. **Given** a server with a valid, running command, **When** the user presses "Test Connection", **Then** a success indicator appears within 10 seconds showing the server responded.
2. **Given** a server with an invalid command or wrong path, **When** the user presses "Test Connection", **Then** an error message appears explaining the server could not be started.
3. **Given** a server whose process starts but never responds, **When** the user presses "Test Connection", **Then** a timeout message appears after no longer than 15 seconds.
4. **Given** a test is in progress, **When** the user looks at the button, **Then** a loading indicator is visible and the button is disabled to prevent duplicate tests.

---

### User Story 2 - Distinguish Between Startup Failure and Protocol Failure (Priority: P2)

A user is debugging a misconfigured server and wants to understand whether the problem is that the process won't start at all, or whether it starts but doesn't speak the expected protocol. The error message shown in the detail view makes this distinction clear.

**Why this priority**: Generic "failed" errors are unhelpful. Knowing whether the binary is missing vs. the server speaks the wrong protocol dramatically shortens debugging time.

**Independent Test**: Configure one server with a non-existent binary and another that starts but produces no valid output; verify each shows a distinct, meaningful error message.

**Acceptance Scenarios**:

1. **Given** a server whose executable does not exist, **When** the user tests it, **Then** the error message indicates the program could not be found or launched.
2. **Given** a server that launches but exits immediately with a non-zero code, **When** the user tests it, **Then** the error message includes the exit code or any stderr output.
3. **Given** a server that starts but sends no valid response within the timeout, **Then** the message distinguishes "timed out waiting for response" from a launch failure.

---

### Edge Cases

- What happens when a test is in progress and the user navigates away from the detail view?
- How does the system handle a server that requires environment variables not present in the app's environment?
- What if the user closes the app while a test is running?
- Can the user cancel an in-progress test?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The server detail view MUST include a "Test Connection" button.
- **FR-002**: Pressing "Test Connection" MUST attempt to start the server process and perform a minimal handshake to confirm it responds.
- **FR-003**: The test MUST complete (succeed, fail, or time out) within 15 seconds.
- **FR-004**: On success, the view MUST display a success indicator and the elapsed response time.
- **FR-005**: On failure, the view MUST display a human-readable error message that distinguishes launch failure from protocol/timeout failure.
- **FR-006**: While a test is in progress, the "Test Connection" button MUST be disabled and show a loading state.
- **FR-007**: The last test result MUST remain visible in the detail view after the test completes; it does not need to persist across app restarts.
- **FR-008**: Running a connection test MUST NOT modify any stored configuration or agent assignments.
- **FR-009**: The test MUST use any environment variables or arguments already configured on the server entry.

### Key Entities

- **Connection Test Result**: Outcome of a single test run — status (success / launch-error / timeout / protocol-error), optional elapsed time, optional error detail, timestamp.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A passing connection test completes and displays a result in under 10 seconds for a responsive local server.
- **SC-002**: A failing test always terminates and shows an error within 15 seconds — the UI never hangs indefinitely.
- **SC-003**: Error messages are specific enough that a user can identify the root cause (missing binary, wrong path, timeout) without opening a terminal.
- **SC-004**: Running a connection test leaves all agent assignments and stored configurations unchanged.

## Assumptions

- Connection testing applies to stdio-based MCP servers (the only server type currently supported in mcp-inator).
- The test is on-demand only — there is no automatic background polling or scheduled testing.
- Test results are ephemeral; they are shown in the current session but not persisted to disk.
- Servers that require interactive authentication flows are out of scope; a clear message should indicate the test is not supported for those.
- The test runs using the environment variables already stored in the server's configuration.
