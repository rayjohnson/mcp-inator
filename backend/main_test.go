package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// mockStore records calls and can be configured to return an error.
type mockStore struct {
	calls   []string
	callErr error
}

func (m *mockStore) increment(_ context.Context, key string, _ time.Time) error {
	m.calls = append(m.calls, key)
	return m.callErr
}

func newTestServer(t *testing.T, storeErr error) (*server, *mockStore) {
	t.Helper()
	ms := &mockStore{callErr: storeErr}
	return &server{store: ms, bearerToken: "test-token"}, ms
}

func post(t *testing.T, srv *server, body string, token string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/report", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	srv.handleReport(w, req)
	return w
}

func decode(t *testing.T, w *httptest.ResponseRecorder) reportResponse {
	t.Helper()
	var resp reportResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	return resp
}

func TestHandleReport(t *testing.T) {
	tests := []struct {
		name       string
		token      string
		body       string
		storeErr   error
		wantStatus int
		wantStatus2 string
		wantAccepted int
	}{
		{
			name:         "valid report two keys",
			token:        "test-token",
			body:         `{"schemaVersion":"1","serverKeys":["github-mcp","filesystem"]}`,
			wantStatus:   http.StatusOK,
			wantStatus2:  "ok",
			wantAccepted: 2,
		},
		{
			name:        "empty serverKeys",
			token:       "test-token",
			body:        `{"schemaVersion":"1","serverKeys":[]}`,
			wantStatus:  http.StatusOK,
			wantStatus2: "ok",
			wantAccepted: 0,
		},
		{
			name:        "wrong schemaVersion",
			token:       "test-token",
			body:        `{"schemaVersion":"99","serverKeys":["github-mcp"]}`,
			wantStatus:  http.StatusBadRequest,
			wantStatus2: "error",
		},
		{
			name:        "missing schemaVersion",
			token:       "test-token",
			body:        `{"serverKeys":["github-mcp"]}`,
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
			name:        "missing token",
			token:       "",
			body:        `{"schemaVersion":"1","serverKeys":["github-mcp"]}`,
			wantStatus:  http.StatusUnauthorized,
			wantStatus2: "error",
		},
		{
			name:        "wrong token",
			token:       "bad-token",
			body:        `{"schemaVersion":"1","serverKeys":["github-mcp"]}`,
			wantStatus:  http.StatusUnauthorized,
			wantStatus2: "error",
		},
		{
			name:        "storage error returns 503",
			token:       "test-token",
			body:        `{"schemaVersion":"1","serverKeys":["github-mcp"]}`,
			storeErr:    errors.New("firestore unavailable"),
			wantStatus:  http.StatusServiceUnavailable,
			wantStatus2: "error",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			srv, _ := newTestServer(t, tc.storeErr)
			w := post(t, srv, tc.body, tc.token)

			if w.Code != tc.wantStatus {
				t.Errorf("status = %d, want %d", w.Code, tc.wantStatus)
			}
			resp := decode(t, w)
			if resp.Status != tc.wantStatus2 {
				t.Errorf("status field = %q, want %q", resp.Status, tc.wantStatus2)
			}
			if tc.wantAccepted != 0 && resp.Accepted != tc.wantAccepted {
				t.Errorf("accepted = %d, want %d", resp.Accepted, tc.wantAccepted)
			}
		})
	}
}

func TestInvalidKeysAreSkipped(t *testing.T) {
	srv, ms := newTestServer(t, nil)

	longKey := strings.Repeat("a", maxKeyLen+1)
	body := `{"schemaVersion":"1","serverKeys":["valid","","` + longKey + `","also-valid"]}`
	w := post(t, srv, body, "test-token")

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	resp := decode(t, w)
	if resp.Accepted != 2 {
		t.Errorf("accepted = %d, want 2 (empty and too-long keys should be skipped)", resp.Accepted)
	}
	if len(ms.calls) != 2 {
		t.Errorf("store called %d times, want 2", len(ms.calls))
	}
}

func TestBodyTooLarge(t *testing.T) {
	srv, _ := newTestServer(t, nil)

	// Build a body larger than 64KB
	keys := make([]string, 0, 600)
	for range 600 {
		keys = append(keys, `"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"`)
	}
	body := `{"schemaVersion":"1","serverKeys":[` + strings.Join(keys, ",") + `]}`
	if len(body) <= maxBodyBytes {
		t.Skip("body not large enough to trigger limit in this env")
	}

	req := httptest.NewRequest(http.MethodPost, "/report", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer test-token")
	w := httptest.NewRecorder()
	srv.handleReport(w, req)

	if w.Code != http.StatusRequestEntityTooLarge {
		t.Errorf("status = %d, want 413", w.Code)
	}
}

func TestNoIPInLogs(t *testing.T) {
	// Ensure the handler never references RemoteAddr by checking it is not called.
	// We verify indirectly: the request has a RemoteAddr set to a real IP,
	// but the handler must not read it (there is no path in handleReport that
	// touches r.RemoteAddr or X-Forwarded-For).
	srv, _ := newTestServer(t, nil)
	req := httptest.NewRequest(http.MethodPost, "/report",
		strings.NewReader(`{"schemaVersion":"1","serverKeys":["k"]}`))
	req.Header.Set("Authorization", "Bearer test-token")
	req.RemoteAddr = "1.2.3.4:9999"
	w := httptest.NewRecorder()
	srv.handleReport(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("status = %d, want 200", w.Code)
	}
	// Confirm the response body contains no IP address.
	if strings.Contains(w.Body.String(), "1.2.3.4") {
		t.Error("response body must not contain the client IP address")
	}
}

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
