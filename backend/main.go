package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	maxBodyBytes   = 64 * 1024
	maxKeyLen      = 256
	schemaVersion1 = "1"
	collection     = "server_usage"
)

type reportRequest struct {
	SchemaVersion string   `json:"schemaVersion"`
	ServerKeys    []string `json:"serverKeys"`
}

type reportResponse struct {
	Status   string `json:"status"`
	Accepted int    `json:"accepted,omitempty"`
	Message  string `json:"message,omitempty"`
}

// storer abstracts Firestore so the handler is testable without a real client.
type storer interface {
	increment(ctx context.Context, key string, now time.Time) error
}

type firestoreStore struct {
	client *firestore.Client
}

func (s *firestoreStore) increment(ctx context.Context, key string, now time.Time) error {
	ref := s.client.Collection(collection).Doc(key)

	// Try to create the document first; on AlreadyExists, update only count+lastSeenAt.
	// This ensures firstSeenAt is only written once without a transaction.
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

// submitRequest mirrors the fields an MCPServerConfig can contribute.
type submitEnvVar struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	IsRequired  bool   `json:"isRequired"`
	IsSensitive bool   `json:"isSensitive"`
}

type submitRequest struct {
	ServerKey     string         `json:"serverKey"`
	DisplayName   string         `json:"displayName"`
	TransportType string         `json:"transportType"`
	Command       string         `json:"command"`
	Args          []string       `json:"args"`
	URL           string         `json:"url"`
	EnvVars       []submitEnvVar `json:"envVars"`
	Notes         string         `json:"notes"`
	SubmitterNote string         `json:"submitterNote"`
}

type submitResponse struct {
	Status   string `json:"status"`
	IssueURL string `json:"issueURL,omitempty"`
	Message  string `json:"message,omitempty"`
}

type server struct {
	store       storer
	bearerToken string
	githubPAT   string
}

func (s *server) handleReport(w http.ResponseWriter, r *http.Request) {
	auth := r.Header.Get("Authorization")
	token, found := strings.CutPrefix(auth, "Bearer ")
	if !found || token != s.bearerToken {
		writeJSON(w, http.StatusUnauthorized, reportResponse{Status: "error", Message: "unauthorized"})
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusRequestEntityTooLarge, reportResponse{Status: "error", Message: "request too large"})
		return
	}

	var req reportRequest
	if err := json.Unmarshal(body, &req); err != nil || req.ServerKeys == nil || req.SchemaVersion != schemaVersion1 {
		writeJSON(w, http.StatusBadRequest, reportResponse{Status: "error", Message: "missing or invalid schemaVersion"})
		return
	}

	ctx := r.Context()
	now := time.Now()
	accepted := 0

	for _, key := range req.ServerKeys {
		if len(key) == 0 || len(key) > maxKeyLen {
			continue
		}
		if err := s.store.increment(ctx, key, now); err != nil {
			writeJSON(w, http.StatusServiceUnavailable, reportResponse{Status: "error", Message: "storage unavailable, please retry"})
			return
		}
		accepted++
	}

	writeJSON(w, http.StatusOK, reportResponse{Status: "ok", Accepted: accepted})
}

func (s *server) handleSubmit(w http.ResponseWriter, r *http.Request) {
	auth := r.Header.Get("Authorization")
	token, found := strings.CutPrefix(auth, "Bearer ")
	if !found || token != s.bearerToken {
		writeJSON(w, http.StatusUnauthorized, submitResponse{Status: "error", Message: "unauthorized"})
		return
	}

	if s.githubPAT == "" {
		writeJSON(w, http.StatusServiceUnavailable, submitResponse{Status: "error", Message: "submissions not available yet"})
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusRequestEntityTooLarge, submitResponse{Status: "error", Message: "request too large"})
		return
	}

	var req submitRequest
	if err := json.Unmarshal(body, &req); err != nil || req.ServerKey == "" {
		writeJSON(w, http.StatusBadRequest, submitResponse{Status: "error", Message: "invalid request"})
		return
	}

	issueURL, err := s.createSubmissionIssue(r.Context(), req)
	if err != nil {
		log.Printf("createSubmissionIssue: %v", err)
		writeJSON(w, http.StatusServiceUnavailable, submitResponse{Status: "error", Message: "failed to create issue"})
		return
	}

	writeJSON(w, http.StatusOK, submitResponse{Status: "ok", IssueURL: issueURL})
}

func (s *server) createSubmissionIssue(ctx context.Context, req submitRequest) (string, error) {
	configJSON, err := json.MarshalIndent(map[string]interface{}{
		"serverKey":     req.ServerKey,
		"displayName":   req.DisplayName,
		"transportType": req.TransportType,
		"command":       req.Command,
		"args":          req.Args,
		"url":           req.URL,
		"envVars":       req.EnvVars,
		"notes":         req.Notes,
	}, "", "  ")
	if err != nil {
		return "", err
	}

	submitterSection := ""
	if strings.TrimSpace(req.SubmitterNote) != "" {
		submitterSection = fmt.Sprintf("**Why I use it**: %s\n\n", req.SubmitterNote)
	}

	issueBody := fmt.Sprintf(`Submitted via mcp-inator.

%s### Structured Config

`+"```json\n%s\n```", submitterSection, string(configJSON))

	title := fmt.Sprintf("[Submission] %s", req.DisplayName)

	payload, err := json.Marshal(map[string]interface{}{
		"title":  title,
		"body":   issueBody,
		"labels": []string{"submission"},
	})
	if err != nil {
		return "", err
	}

	ghReq, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://api.github.com/repos/rayjohnson/mcp-catalog/issues",
		bytes.NewReader(payload),
	)
	if err != nil {
		return "", err
	}
	ghReq.Header.Set("Authorization", "Bearer "+s.githubPAT)
	ghReq.Header.Set("Accept", "application/vnd.github+json")
	ghReq.Header.Set("Content-Type", "application/json")
	ghReq.Header.Set("X-GitHub-Api-Version", "2022-11-28")

	resp, err := http.DefaultClient.Do(ghReq)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		b, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("github API %d: %s", resp.StatusCode, string(b))
	}

	var created struct {
		HTMLURL string `json:"html_url"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&created); err != nil {
		return "", err
	}
	return created.HTMLURL, nil
}

func writeJSON(w http.ResponseWriter, code int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func main() {
	ctx := context.Background()

	projectID := os.Getenv("GCP_PROJECT")
	if projectID == "" {
		projectID = "ray-johnson-mcp-inator"
	}

	token := os.Getenv("TELEMETRY_BEARER_TOKEN")
	if token == "" {
		log.Fatal("TELEMETRY_BEARER_TOKEN env var is required")
	}

	fsClient, err := firestore.NewClient(ctx, projectID)
	if err != nil {
		log.Fatalf("firestore.NewClient: %v", err)
	}
	defer fsClient.Close()

	srv := &server{
		store:       &firestoreStore{client: fsClient},
		bearerToken: token,
		githubPAT:   os.Getenv("GITHUB_PAT"),
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /report", srv.handleReport)
	mux.HandleFunc("POST /submit", srv.handleSubmit)

	log.Printf("listening on :%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatal(err)
	}
}
