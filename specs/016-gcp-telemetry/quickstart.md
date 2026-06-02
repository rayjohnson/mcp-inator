# Quickstart: GCP Telemetry Backend

End-to-end integration test scenarios. Run these after each phase to verify the feature is working.

## Scenario 1 — Backend Service (after US1)

**Prerequisites**: Cloud Run service deployed, Firestore database created.

```bash
SERVICE_URL="https://$(gcloud run services describe mcp-inator-telemetry \
  --region=us-central1 --project=ray-johnson-mcp-inator \
  --format='value(status.url)' | sed 's|https://||')"

# Send a valid report
curl -s -X POST "$SERVICE_URL/report" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TELEMETRY_BEARER_TOKEN" \
  -d '{"schemaVersion":"1","serverKeys":["github-mcp","filesystem"]}'
# Expected: {"status":"ok","accepted":2}

# Verify counts in Firestore
gcloud firestore documents get \
  "projects/ray-johnson-mcp-inator/databases/(default)/documents/server_usage/github-mcp"
# Expected: count field = 1

# Send a second report to verify increment
curl -s -X POST "$SERVICE_URL/report" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TELEMETRY_BEARER_TOKEN" \
  -d '{"schemaVersion":"1","serverKeys":["github-mcp"]}'
# Expected: count for github-mcp is now 2

# Test invalid schemaVersion
curl -s -X POST "$SERVICE_URL/report" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TELEMETRY_BEARER_TOKEN" \
  -d '{"schemaVersion":"99","serverKeys":["github-mcp"]}'
# Expected: HTTP 400, {"status":"error","message":"missing or invalid schemaVersion"}
```

## Scenario 2 — CI/CD Pipeline (after US2)

1. Make a trivial change to `backend/main.go` (add/remove a comment)
2. Push to `main`
3. Watch the `deploy-backend.yml` action in GitHub Actions UI
4. Verify it completes green with no manual steps
5. Confirm the service URL still responds correctly with the report endpoint

## Scenario 3 — App Sends Reports (after US3)

1. Build the app in Xcode (Debug configuration)
2. In Simulator or on device: clear UserDefaults for the sharing keys (or set `firstLaunchDate` to 8+ days ago)
3. Launch the app with at least one enabled server
4. Bring the app to the foreground — the consent prompt should appear
5. Tap "Review what I'd share" — verify the review screen shows correct sanitized fields
6. Submit — verify in Cloud Run logs that a report was received and accepted
7. Open Preferences → verify "Contributing Usage Data" section shows opted-in status
8. Tap "Withdraw participation" — verify no further reports are sent

## Scenario 4 — Catalog Pipeline Reads Counts (after US4)

```bash
cd mcp-catalog/

# Seed a count manually (or use results from Scenario 1)
# Run refresh locally with GOOGLE_APPLICATION_CREDENTIALS or WIF
python scripts/refresh.py --dry-run 2>&1 | grep "usage"
# Expected: output shows usage counts for github-mcp and filesystem

# Verify stats.json
python scripts/refresh.py
git diff stats.json
# Expected: usageCount fields updated for servers with Firestore data
```
