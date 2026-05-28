# Quickstart Test Scenarios: MCP Server Connection Test

## Prerequisites

- mcp-inator built and running
- At least one stdio MCP server configured (e.g. `npx -y @modelcontextprotocol/server-filesystem /tmp`)

---

## Scenario 1: Successful connection

1. Open a server entry in the library (e.g. "Filesystem")
2. Press **Test Connection**
3. **Expected**: Button shows a spinner while testing; within ~5 seconds a green checkmark appears with "Connected in X.Xs"

---

## Scenario 2: Bad command / missing binary

1. Add a new server with command `nonexistent-binary-xyz`
2. Press **Test Connection**
3. **Expected**: Red indicator appears with a message like "Could not launch: launch path not accessible"

---

## Scenario 3: Timeout

1. Add a server with command `cat` (reads stdin forever, never sends MCP output)
2. Press **Test Connection**
3. **Expected**: After ~15 seconds a red indicator shows "Server did not respond within 15 seconds"

---

## Scenario 4: No side effects

1. Note the current agent assignments for a server
2. Press **Test Connection** (any outcome)
3. Navigate to the agent view
4. **Expected**: All assignments are unchanged

---

## Scenario 5: Button disabled during test

1. Press **Test Connection** on any server
2. While the spinner is visible, observe the button
3. **Expected**: Button is disabled (not clickable) until the test completes

---

## Scenario 6: HTTP server — no test button

1. Open an HTTP/SSE server entry
2. **Expected**: No "Test Connection" button is visible (stdio-only feature)
