package main

import (
	"context"
	"encoding/json"
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

type server struct {
	store       storer
	bearerToken string
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
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /report", srv.handleReport)

	log.Printf("listening on :%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatal(err)
	}
}
