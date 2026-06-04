# Anonymous Install & Daily-Active Ping — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fire a one-time first-launch ping and a once-per-calendar-day active ping to the existing Cloud Run backend, storing aggregate counts in Firestore — no opt-in, no PII.

**Architecture:** New `PingService` (Swift) reads two UserDefaults flags to gate when pings fire; it POSTs to a new `/ping` endpoint on the existing Cloud Run backend. The backend validates the request and writes to two new Firestore collections: `app_installs/{appVersion}` and `daily_active/{YYYY-MM-DD}`. Both paths reuse the existing bearer token and create-or-increment Firestore pattern.

**Tech Stack:** Swift 6 / SwiftUI (client), Go 1.x / net/http / Firestore SDK (backend), UserDefaults (client state), XcodeGen (project file regeneration via `make cover`).

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `mcp-inator/Services/PingService.swift` | `PingPreferences` enum, `PingReport` Codable struct, `PingService` class |
| Create | `mcp-inatorTests/TestHelpers/MockURLProtocol.swift` | Captures HTTP requests in tests |
| Create | `mcp-inatorTests/Unit/PingServiceTests.swift` | Tests for gating logic and request formation |
| Modify | `mcp-inator/App/mcp_inatorApp.swift` | Call `PingService.shared.firePingsIfNeeded()` on app activation |
| Modify | `backend/main.go` | `pinger` interface, `firestoreStore` methods, `handlePing` handler, route, `server.ping` field |
| Modify | `backend/main_test.go` | `mockPinger`, `newTestServerWithPing`, `postPing`, `decodePing`, `TestHandlePing*` |
| Modify | `VERSION` | 0.5.3 → 0.5.4 |
| Modify | `RELEASE_NOTES.md` | Prepend entry |

---

## Task 1: `PingService` — client-side Swift implementation (TDD)

**Files:**
- Create: `mcp-inatorTests/TestHelpers/MockURLProtocol.swift`
- Create: `mcp-inator/Services/PingService.swift`
- Create: `mcp-inatorTests/Unit/PingServiceTests.swift`

- [ ] **Step 1: Create `MockURLProtocol.swift`**

Create `mcp-inatorTests/TestHelpers/MockURLProtocol.swift`:

```swift
import Foundation

final class MockURLProtocol: URLProtocol {
    static var requests: [URLRequest] = []
    static var responseStatusCode = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,  // swiftlint:disable:this force_unwrapping
            statusCode: MockURLProtocol.responseStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!  // swiftlint:disable:this force_unwrapping
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
```

- [ ] **Step 2: Write failing `PingServiceTests.swift`**

Create `mcp-inatorTests/Unit/PingServiceTests.swift`:

```swift
import XCTest
@testable import mcp_inator

@MainActor
final class PingServiceTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.requests = []
        MockURLProtocol.responseStatusCode = 200
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        UserDefaults.standard.removeObject(forKey: "pingHasLaunched")
        UserDefaults.standard.removeObject(forKey: "pingLastActiveDate")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "pingHasLaunched")
        UserDefaults.standard.removeObject(forKey: "pingLastActiveDate")
        super.tearDown()
    }

    // MARK: - PingPreferences

    func testPingPreferences_hasLaunched_defaultsFalse() {
        XCTAssertFalse(PingPreferences.hasLaunched)
    }

    func testPingPreferences_lastActiveDate_defaultsEmpty() {
        XCTAssertEqual(PingPreferences.lastActiveDate, "")
    }

    // MARK: - First-launch gate

    func testFirstLaunch_setsHasLaunchedTrue() async {
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        XCTAssertTrue(PingPreferences.hasLaunched)
    }

    func testFirstLaunch_sendsFirstLaunchPing() async {
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        let events = capturedEvents()
        XCTAssertTrue(events.contains("first_launch"), "expected first_launch in \(events)")
    }

    func testFirstLaunch_doesNotFireWhenAlreadyLaunched() async {
        PingPreferences.hasLaunched = true
        PingPreferences.lastActiveDate = todayString()  // suppress daily ping too
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        let events = capturedEvents()
        XCTAssertFalse(events.contains("first_launch"))
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    // MARK: - Daily-active gate

    func testDailyActive_firesWhenNoPreviousDate() async {
        PingPreferences.hasLaunched = true
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        let events = capturedEvents()
        XCTAssertTrue(events.contains("daily_active"), "expected daily_active in \(events)")
    }

    func testDailyActive_updatesLastActiveDateToToday() async {
        PingPreferences.hasLaunched = true
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        XCTAssertEqual(PingPreferences.lastActiveDate, todayString())
    }

    func testDailyActive_doesNotFireWhenAlreadyFiredToday() async {
        PingPreferences.hasLaunched = true
        PingPreferences.lastActiveDate = todayString()
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testDailyActive_firesAfterDayChange() async {
        PingPreferences.hasLaunched = true
        PingPreferences.lastActiveDate = "2020-01-01"
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        let events = capturedEvents()
        XCTAssertTrue(events.contains("daily_active"), "expected daily_active in \(events)")
    }

    // MARK: - Request formation

    func testPingReport_containsSchemaVersionOne() async {
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        let reports = capturedReports()
        XCTAssertTrue(reports.allSatisfy { $0.schemaVersion == "1" })
    }

    func testPingReport_appVersionIsNotEmpty() async {
        let service = PingService(session: session)
        await service.firePingsIfNeeded()
        let reports = capturedReports()
        XCTAssertFalse(reports.isEmpty)
        XCTAssertTrue(reports.allSatisfy { !$0.appVersion.isEmpty })
    }

    // MARK: - Helpers

    private func capturedEvents() -> [String] {
        capturedReports().map(\.event)
    }

    private func capturedReports() -> [PingReport] {
        MockURLProtocol.requests
            .compactMap(\.httpBody)
            .compactMap { try? JSONDecoder().decode(PingReport.self, from: $0) }
    }

    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
```

- [ ] **Step 3: Run tests — verify they FAIL**

```bash
cd /path/to/mcp-inator
make cover
```

Expected: compilation errors — `PingPreferences`, `PingService`, `PingReport` not yet defined.

- [ ] **Step 4: Create `PingService.swift`**

Create `mcp-inator/Services/PingService.swift`:

```swift
import Foundation

// MARK: - PingPreferences

enum PingPreferences {
    static var hasLaunched: Bool {
        get { UserDefaults.standard.bool(forKey: "pingHasLaunched") }
        set { UserDefaults.standard.set(newValue, forKey: "pingHasLaunched") }
    }

    static var lastActiveDate: String {
        get { UserDefaults.standard.string(forKey: "pingLastActiveDate") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "pingLastActiveDate") }
    }
}

// MARK: - PingReport

struct PingReport: Codable {
    let schemaVersion: String
    let event: String
    let appVersion: String

    init(event: String) {
        self.schemaVersion = "1"
        self.event = event
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}

// MARK: - PingService

@MainActor
final class PingService {
    static let shared = PingService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func firePingsIfNeeded() async {
        var events: [String] = []

        if !PingPreferences.hasLaunched {
            PingPreferences.hasLaunched = true
            events.append("first_launch")
        }

        let today = todayString()
        if PingPreferences.lastActiveDate != today {
            PingPreferences.lastActiveDate = today
            events.append("daily_active")
        }

        await withTaskGroup(of: Void.self) { group in
            for event in events {
                group.addTask { await self.firePing(event: event) }
            }
        }
    }

    private func firePing(event: String) async {
        let report = PingReport(event: event)
        guard let body = try? JSONEncoder().encode(report) else { return }
        var request = URLRequest(
            url: TelemetryConfig.serviceURL.appendingPathComponent("ping"),
            timeoutInterval: 10
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(TelemetryConfig.bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        _ = try? await session.data(for: request)
    }

    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
```

- [ ] **Step 5: Run tests — verify they PASS**

```bash
make cover
```

Expected: all `PingServiceTests` pass; overall coverage ≥ 24%.

- [ ] **Step 6: Run lint and fix any warnings**

```bash
make lint
```

Fix any `swiftlint` warnings before proceeding.

- [ ] **Step 7: Commit**

```bash
git add mcp-inator/Services/PingService.swift \
        mcp-inatorTests/TestHelpers/MockURLProtocol.swift \
        mcp-inatorTests/Unit/PingServiceTests.swift \
        mcp-inator.xcodeproj/project.pbxproj
git commit -m "feat: add PingService for anonymous first-launch and daily-active pings"
```

---

## Task 2: Wire `PingService` into the app

**Files:**
- Modify: `mcp-inator/App/mcp_inatorApp.swift`

- [ ] **Step 1: Add ping call to `checkSharingEligibility`**

In `mcp_inatorApp.swift`, find the `checkSharingEligibility()` method (around line 184). Add the `PingService` Task immediately after the existing `UsageSharingService` flush Task:

```swift
private func checkSharingEligibility() {
    guard !mcp_inatorApp.isRunningTests else { return }
    Task { @MainActor in
        await UsageSharingService.shared.flushPendingIfNeeded()
    }
    Task { @MainActor in                                      // ← add this block
        await PingService.shared.firePingsIfNeeded()
    }
    guard !SharingPreferences.consented,
    // ... rest of method unchanged
```

- [ ] **Step 2: Run `make cover` to verify nothing is broken**

```bash
make cover
```

Expected: all tests still pass, coverage ≥ 24%.

- [ ] **Step 3: Run lint**

```bash
make lint
```

- [ ] **Step 4: Commit**

```bash
git add mcp-inator/App/mcp_inatorApp.swift
git commit -m "feat: fire PingService pings on app activation"
```

---

## Task 3: Backend `/ping` handler (TDD)

**Files:**
- Modify: `backend/main_test.go`
- Modify: `backend/main.go`

- [ ] **Step 1: Add `mockPinger` and test helpers to `main_test.go`**

Append to `backend/main_test.go` (after the last test function):

```go
// MARK: - Ping test helpers

type mockPinger struct {
	installCalls []string
	dailyCalls   []string
	callErr      error
}

func (m *mockPinger) recordInstall(_ context.Context, appVersion string, _ time.Time) error {
	m.installCalls = append(m.installCalls, appVersion)
	return m.callErr
}

func (m *mockPinger) recordDailyActive(_ context.Context, dateStr string, _ time.Time) error {
	m.dailyCalls = append(m.dailyCalls, dateStr)
	return m.callErr
}

func newTestServerWithPing(t *testing.T, pingErr error) (*server, *mockPinger) {
	t.Helper()
	mp := &mockPinger{callErr: pingErr}
	ms := &mockStore{}
	return &server{store: ms, ping: mp, bearerToken: "test-token"}, mp
}

func postPing(t *testing.T, srv *server, body string, token string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/ping", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	srv.handlePing(w, req)
	return w
}

func decodePing(t *testing.T, w *httptest.ResponseRecorder) pingResponse {
	t.Helper()
	var resp pingResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode ping response: %v", err)
	}
	return resp
}
```

- [ ] **Step 2: Add `TestHandlePing` table-driven test and two focused tests to `main_test.go`**

Append after the helpers you just added:

```go
func TestHandlePing(t *testing.T) {
	tests := []struct {
		name        string
		token       string
		body        string
		pingErr     error
		wantStatus  int
		wantStatus2 string
	}{
		{
			name:        "first_launch valid",
			token:       "test-token",
			body:        `{"schemaVersion":"1","event":"first_launch","appVersion":"0.5.3"}`,
			wantStatus:  http.StatusOK,
			wantStatus2: "ok",
		},
		{
			name:        "daily_active valid",
			token:       "test-token",
			body:        `{"schemaVersion":"1","event":"daily_active","appVersion":"0.5.3"}`,
			wantStatus:  http.StatusOK,
			wantStatus2: "ok",
		},
		{
			name:        "missing token",
			token:       "",
			body:        `{"schemaVersion":"1","event":"first_launch","appVersion":"0.5.3"}`,
			wantStatus:  http.StatusUnauthorized,
			wantStatus2: "error",
		},
		{
			name:        "wrong token",
			token:       "bad-token",
			body:        `{"schemaVersion":"1","event":"first_launch","appVersion":"0.5.3"}`,
			wantStatus:  http.StatusUnauthorized,
			wantStatus2: "error",
		},
		{
			name:        "wrong schemaVersion",
			token:       "test-token",
			body:        `{"schemaVersion":"2","event":"first_launch","appVersion":"0.5.3"}`,
			wantStatus:  http.StatusBadRequest,
			wantStatus2: "error",
		},
		{
			name:        "unknown event",
			token:       "test-token",
			body:        `{"schemaVersion":"1","event":"unknown","appVersion":"0.5.3"}`,
			wantStatus:  http.StatusBadRequest,
			wantStatus2: "error",
		},
		{
			name:        "empty appVersion",
			token:       "test-token",
			body:        `{"schemaVersion":"1","event":"first_launch","appVersion":""}`,
			wantStatus:  http.StatusBadRequest,
			wantStatus2: "error",
		},
		{
			name:        "appVersion too long",
			token:       "test-token",
			body:        `{"schemaVersion":"1","event":"first_launch","appVersion":"` + strings.Repeat("a", maxAppVersionLen+1) + `"}`,
			wantStatus:  http.StatusBadRequest,
			wantStatus2: "error",
		},
		{
			name:        "malformed JSON",
			token:       "test-token",
			body:        `not json`,
			wantStatus:  http.StatusBadRequest,
			wantStatus2: "error",
		},
		{
			name:        "storage error returns 503",
			token:       "test-token",
			body:        `{"schemaVersion":"1","event":"first_launch","appVersion":"0.5.3"}`,
			pingErr:     errors.New("firestore unavailable"),
			wantStatus:  http.StatusServiceUnavailable,
			wantStatus2: "error",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			srv, _ := newTestServerWithPing(t, tc.pingErr)
			w := postPing(t, srv, tc.body, tc.token)
			if w.Code != tc.wantStatus {
				t.Errorf("status = %d, want %d", w.Code, tc.wantStatus)
			}
			resp := decodePing(t, w)
			if resp.Status != tc.wantStatus2 {
				t.Errorf("status field = %q, want %q", resp.Status, tc.wantStatus2)
			}
		})
	}
}

func TestHandlePing_firstLaunch_callsRecordInstall(t *testing.T) {
	srv, mp := newTestServerWithPing(t, nil)
	postPing(t, srv, `{"schemaVersion":"1","event":"first_launch","appVersion":"0.5.3"}`, "test-token")
	if len(mp.installCalls) != 1 || mp.installCalls[0] != "0.5.3" {
		t.Errorf("installCalls = %v, want [\"0.5.3\"]", mp.installCalls)
	}
	if len(mp.dailyCalls) != 0 {
		t.Errorf("dailyCalls should be empty, got %v", mp.dailyCalls)
	}
}

func TestHandlePing_dailyActive_callsRecordDailyActive(t *testing.T) {
	srv, mp := newTestServerWithPing(t, nil)
	postPing(t, srv, `{"schemaVersion":"1","event":"daily_active","appVersion":"0.5.3"}`, "test-token")
	if len(mp.dailyCalls) != 1 {
		t.Fatalf("dailyCalls = %v, want one entry", mp.dailyCalls)
	}
	if len(mp.dailyCalls[0]) != 10 || mp.dailyCalls[0][4] != '-' {
		t.Errorf("dailyCalls[0] = %q, want YYYY-MM-DD format", mp.dailyCalls[0])
	}
	if len(mp.installCalls) != 0 {
		t.Errorf("installCalls should be empty, got %v", mp.installCalls)
	}
}

func TestHandlePing_noIPInLogs(t *testing.T) {
	srv, _ := newTestServerWithPing(t, nil)
	req := httptest.NewRequest(http.MethodPost, "/ping",
		strings.NewReader(`{"schemaVersion":"1","event":"first_launch","appVersion":"0.5.3"}`))
	req.Header.Set("Authorization", "Bearer test-token")
	req.RemoteAddr = "1.2.3.4:9999"
	w := httptest.NewRecorder()
	srv.handlePing(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("status = %d, want 200", w.Code)
	}
	if strings.Contains(w.Body.String(), "1.2.3.4") {
		t.Error("response body must not contain the client IP address")
	}
}
```

- [ ] **Step 3: Run Go tests — verify they FAIL**

```bash
cd backend && go test ./...
```

Expected: compilation error — `pingResponse`, `maxAppVersionLen`, `server.ping`, `server.handlePing` not defined.

- [ ] **Step 4: Add `pinger` interface, constants, and `firestoreStore` methods to `main.go`**

Add these constants after the existing `const` block (around line 21):

```go
const (
	maxBodyBytes      = 64 * 1024
	maxKeyLen         = 256
	maxAppVersionLen  = 32
	schemaVersion1    = "1"
	collection        = "server_usage"
	collectionInstalls    = "app_installs"
	collectionDailyActive = "daily_active"
)
```

**Note:** Replace the existing `const` block entirely — do not duplicate it.

Add the `pinger` interface after the `storer` interface definition:

```go
type pinger interface {
	recordInstall(ctx context.Context, appVersion string, now time.Time) error
	recordDailyActive(ctx context.Context, dateStr string, now time.Time) error
}
```

Add these two methods to `firestoreStore` (after the existing `increment` method):

```go
func (s *firestoreStore) recordInstall(ctx context.Context, appVersion string, now time.Time) error {
	ref := s.client.Collection(collectionInstalls).Doc(appVersion)
	_, err := ref.Create(ctx, map[string]interface{}{
		"count":       1,
		"firstSeenAt": now,
		"lastSeenAt":  now,
	})
	if status.Code(err) == codes.AlreadyExists {
		_, err = ref.Update(ctx, []firestore.Update{
			{Path: "count", Value: firestore.Increment(1)},
			{Path: "lastSeenAt", Value: now},
		})
	}
	return err
}

func (s *firestoreStore) recordDailyActive(ctx context.Context, dateStr string, now time.Time) error {
	ref := s.client.Collection(collectionDailyActive).Doc(dateStr)
	_, err := ref.Create(ctx, map[string]interface{}{
		"count": 1,
		"date":  dateStr,
	})
	if status.Code(err) == codes.AlreadyExists {
		_, err = ref.Update(ctx, []firestore.Update{
			{Path: "count", Value: firestore.Increment(1)},
		})
	}
	return err
}
```

- [ ] **Step 5: Add `pingRequest`, `pingResponse` structs and `ping` field to `server`**

Add after the existing `reportResponse` struct:

```go
type pingRequest struct {
	SchemaVersion string `json:"schemaVersion"`
	Event         string `json:"event"`
	AppVersion    string `json:"appVersion"`
}

type pingResponse struct {
	Status  string `json:"status"`
	Message string `json:"message,omitempty"`
}
```

Update the `server` struct to add the `ping` field:

```go
type server struct {
	store       storer
	ping        pinger
	bearerToken string
	githubPAT   string
}
```

- [ ] **Step 6: Add `handlePing` method to `server`**

Add after `handleSubmit`:

```go
func (s *server) handlePing(w http.ResponseWriter, r *http.Request) {
	auth := r.Header.Get("Authorization")
	token, found := strings.CutPrefix(auth, "Bearer ")
	if !found || token != s.bearerToken {
		writeJSON(w, http.StatusUnauthorized, pingResponse{Status: "error", Message: "unauthorized"})
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusRequestEntityTooLarge, pingResponse{Status: "error", Message: "request too large"})
		return
	}

	var req pingRequest
	if err := json.Unmarshal(body, &req); err != nil || req.SchemaVersion != schemaVersion1 {
		writeJSON(w, http.StatusBadRequest, pingResponse{Status: "error", Message: "missing or invalid schemaVersion"})
		return
	}

	if req.Event != "first_launch" && req.Event != "daily_active" {
		writeJSON(w, http.StatusBadRequest, pingResponse{Status: "error", Message: "invalid event"})
		return
	}

	if req.AppVersion == "" || len(req.AppVersion) > maxAppVersionLen {
		writeJSON(w, http.StatusBadRequest, pingResponse{Status: "error", Message: "invalid appVersion"})
		return
	}

	ctx := r.Context()
	now := time.Now().UTC()

	var storeErr error
	switch req.Event {
	case "first_launch":
		storeErr = s.ping.recordInstall(ctx, req.AppVersion, now)
	case "daily_active":
		storeErr = s.ping.recordDailyActive(ctx, now.Format("2006-01-02"), now)
	}

	if storeErr != nil {
		writeJSON(w, http.StatusServiceUnavailable, pingResponse{Status: "error", Message: "storage unavailable, please retry"})
		return
	}

	writeJSON(w, http.StatusOK, pingResponse{Status: "ok"})
}
```

- [ ] **Step 7: Register the route and wire `ping` in `main()`**

In `main()`, change:

```go
// Before:
srv := &server{
    store:       &firestoreStore{client: fsClient},
    bearerToken: token,
    githubPAT:   os.Getenv("GITHUB_PAT"),
}
```

to:

```go
// After:
fs := &firestoreStore{client: fsClient}
srv := &server{
    store:       fs,
    ping:        fs,
    bearerToken: token,
    githubPAT:   os.Getenv("GITHUB_PAT"),
}
```

And add the route after `POST /submit`:

```go
mux.HandleFunc("POST /report", srv.handleReport)
mux.HandleFunc("POST /submit", srv.handleSubmit)
mux.HandleFunc("POST /ping", srv.handlePing)
```

- [ ] **Step 8: Run Go tests — verify they PASS**

```bash
cd backend && go test ./...
```

Expected: `ok github.com/rayjohnson/mcp-inator/backend`

- [ ] **Step 9: Commit**

```bash
git add backend/main.go backend/main_test.go
git commit -m "feat: add /ping endpoint for first-launch and daily-active telemetry"
```

---

## Task 4: Version bump and release notes

**Files:**
- Modify: `VERSION`
- Modify: `RELEASE_NOTES.md`

- [ ] **Step 1: Bump `VERSION` to 0.5.4**

Edit `VERSION` — replace `0.5.3` with `0.5.4`.

- [ ] **Step 2: Prepend entry to `RELEASE_NOTES.md`**

Add this as the first line of `RELEASE_NOTES.md`:

```
- Anonymous install and daily-active pings: on first launch the app fires a one-time install ping; once per calendar day it fires a daily-active ping — both POST to the existing Cloud Run backend and store aggregate counts in Firestore (no opt-in required, no PII)
```

- [ ] **Step 3: Run `make cover` and `make lint` one final time**

```bash
make cover && make lint
```

Expected: all tests pass, lint clean.

- [ ] **Step 4: Commit**

```bash
git add VERSION RELEASE_NOTES.md
git commit -m "chore: bump version to 0.5.4; update release notes"
```
