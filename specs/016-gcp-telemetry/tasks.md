# Tasks: GCP Telemetry Backend

**Input**: Design documents from `specs/016-gcp-telemetry/`

**Feature**: Replace Cloudflare Worker plan (#39/#40/#47) with a Go Cloud Run service + Firestore for anonymous usage telemetry. Includes full app-side consent/sharing UI (#40), CI/CD via GitHub Actions + WIF, and update to `refresh.py` (#38) to read counts from Firestore instead of GitHub.

**Key architectural decisions**:
- Go (`net/http`) for the Cloud Run service — cold start < 100ms
- Firestore `FieldValue.increment()` for atomic per-server counts — no transactions needed
- Static bearer token for endpoint auth — avoids Moov org policy `allUsers` IAM block
- WIF for both `mcp-inator` and `mcp-catalog` repos — no long-lived credential files
- `mcp-catalog/scripts/refresh.py` reads from Firestore — eliminates `usage.json` GitHub DB pattern

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to

---

## Phase 1: Setup

**Purpose**: Create file scaffolding and the one-time GCP infrastructure script before any story work begins.

- [x] T001 Create `backend/` directory with `go.mod` (module `github.com/rayjohnson/mcp-inator/backend`, Go 1.22) and declare dependencies: `cloud.google.com/go/firestore`, `google.golang.org/api`; run `go mod tidy` to generate `go.sum`
- [x] T002 [P] Create `backend/Dockerfile`: multi-stage build — `golang:1.22-alpine` builder compiles `main.go` to `/app/server`, final `gcr.io/distroless/static` image runs `/app/server` on `PORT` env var (default 8080)
- [x] T003 [P] Create `scripts/setup-gcp.sh` with the complete one-time GCP infrastructure setup from `specs/016-gcp-telemetry/plan.md` (enable APIs, create Firestore DB, Artifact Registry repo, WIF pool + provider, deploy SA, catalog reader SA, WIF bindings for both repos); make executable and run `shellcheck scripts/setup-gcp.sh`

**Checkpoint**: `go mod tidy` succeeds, `docker build backend/` succeeds, `shellcheck` passes on `setup-gcp.sh`.

---

## Phase 2: Foundational (Blocking Prerequisite)

**Purpose**: Provision GCP infrastructure and set GitHub secrets/variables before any story can be deployed or tested end-to-end. This is a one-time manual step.

- [ ] T004 Run `scripts/setup-gcp.sh` from the project root to provision GCP infrastructure; capture the printed `TELEMETRY_BEARER_TOKEN` value; add it as a GitHub Actions **secret** (`TELEMETRY_BEARER_TOKEN`) in `rayjohnson/mcp-inator` repo settings; add the five printed values as GitHub Actions **variables** (not secrets): `GCP_PROJECT`, `GCP_REGION`, `GCP_WIF_PROVIDER`, `GCP_DEPLOY_SA`, `GCP_CATALOG_SA`; add `GCP_CATALOG_SA` and `GCP_WIF_PROVIDER` as variables in `rayjohnson/mcp-catalog` repo settings as well

**Checkpoint**: Firestore database, Artifact Registry repo, and WIF pool visible in GCP Console for `ray-johnson-mcp-inator`. GitHub repo variables set in both repos.

---

## Phase 3: User Story 1 — Backend Service + Firestore (Priority: P1) 🎯 MVP

**Goal**: The Cloud Run service is deployed, accepts `POST /report`, atomically increments Firestore counts, and returns correct responses. No client IP is logged.

**Independent Test**: Use quickstart.md Scenario 1 — `curl POST /report` with two server keys, verify `{"status":"ok","accepted":2}`, verify Firestore `server_usage/github-mcp` count = 1, then send again and verify count = 2. Test 400 for invalid schemaVersion.

- [x] T005 [US1] Implement `backend/main.go` HTTP handler for `POST /report`: read `Authorization` header and reject with 401 if bearer token doesn't match `TELEMETRY_BEARER_TOKEN` env var; enforce 64KB body size limit (413); parse JSON body into struct with `schemaVersion` string and `serverKeys` []string; reject with 400 if `schemaVersion != "1"` or body is malformed; skip keys that are empty or > 256 chars; for each valid key call Firestore `FieldValue.Increment(1)` on `server_usage/{key}.count` and set `lastSeenAt`; use `MergeAll` so `firstSeenAt` is only set on document creation; return `{"status":"ok","accepted":N}`; never log `r.RemoteAddr` or any IP-bearing header
- [x] T006 [US1] Add `main_test.go` in `backend/` with table-driven unit tests covering: valid report returns 200 + correct accepted count; invalid `schemaVersion` returns 400; missing/wrong bearer token returns 401; body > 64KB returns 413; empty `serverKeys` array returns 200 with accepted=0; keys with invalid length are skipped; verify no call to any log function with IP-like strings
- [ ] T007 [US1] First manual deploy to Cloud Run: `gcloud run deploy mcp-inator-telemetry --source backend/ --region us-central1 --project ray-johnson-mcp-inator --set-env-vars TELEMETRY_BEARER_TOKEN=$TELEMETRY_BEARER_TOKEN --no-allow-unauthenticated` (note: using `--no-allow-unauthenticated` avoids org policy issue; the bearer token is the auth mechanism); note the assigned service URL for use in T011

**Checkpoint**: `go test ./...` passes in `backend/`. `curl POST /report` against the deployed URL returns expected responses per quickstart Scenario 1. Firestore counts increment correctly.

---

## Phase 4: User Story 2 — Automated CD on Push (Priority: P2)

**Goal**: Pushing to `main` automatically builds and deploys the backend service via WIF — no manual steps, no stored credentials.

**Independent Test**: Quickstart Scenario 2 — make a trivial backend change, push to `main`, watch `deploy-backend.yml` complete green in GitHub Actions UI, confirm service URL still responds correctly.

- [x] T008 [US2] Create `.github/workflows/deploy-backend.yml`: trigger on `push` to `main` with path filter `backend/**`; job steps: (1) checkout, (2) `google-github-actions/auth@v2` with `workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER }}` and `service_account: ${{ vars.GCP_DEPLOY_SA }}`; (3) `google-github-actions/deploy-cloudrun@v2` with `service: mcp-inator-telemetry`, `region: ${{ vars.GCP_REGION }}`, `project_id: ${{ vars.GCP_PROJECT }}`, `source: ./backend`, `env_vars: TELEMETRY_BEARER_TOKEN=${{ secrets.TELEMETRY_BEARER_TOKEN }}`, `flags: --no-allow-unauthenticated`
- [ ] T009 [US2] Push a trivial backend change (`// deploy test` comment in `main.go`), verify the workflow runs and succeeds; confirm the Cloud Run service URL is unchanged and still accepts reports correctly; revert the comment

**Checkpoint**: Push-to-deploy works end-to-end. The workflow completes in under 5 minutes with no manual steps.

---

## Phase 5: User Story 3 — App Consent + Sharing UI (Priority: P3)

**Goal**: The macOS app gains the full opt-in consent flow, review screen, sharing service, retry logic, Preferences section, and private server toggle — all wired to the Cloud Run URL from T007.

**Independent Test**: Quickstart Scenario 3 — set `firstLaunchDate` to 8+ days ago in UserDefaults, run app with ≥1 enabled server, verify consent prompt appears, review screen shows sanitized entries, submit delivers a report to Cloud Run, Preferences shows opt-in status, withdraw stops future reports.

- [x] T010 [US3] Add `SharingPreferences` enum of UserDefaults keys to a new `mcp-inator/Services/SharingPreferences.swift`: `sharingConsented` (Bool), `sharingConsentShownThisSession` (Bool), `sharingConsentShownAt` (Date?), `pendingReport` (Data?), `sharingExcludedKeys` ([String]); add `TelemetryConfig` struct with `static let serviceURL` set to the Cloud Run URL from T007 and `static let bearerToken` from a build-time constant (value set from `TELEMETRY_BEARER_TOKEN` env or hardcoded for now with a TODO)
- [ ] T011 [US3] Implement `mcp-inator/Services/UsageSharingService.swift`: `buildPayload(servers: [MCPServerConfig], excluded: [String]) -> UsageReport?` — filters out private servers and user-excluded keys, sanitizes command to basename, redacts path args (segments starting with `/` or `~` replaced with `<path>`), includes only env var key names; `submit(report: UsageReport) async throws` — `URLRequest` POST to `TelemetryConfig.serviceURL` with `Authorization: Bearer` header and `Content-Type: application/json`, 3-retry exponential backoff (1s, 2s, 4s) on network errors or 5xx; `queueForRetry(_ report: UsageReport)` — serialize to `SharingPreferences.pendingReport`; `flushPendingIfNeeded() async` — read pending report, attempt submit, clear on success or after 3 launch-retry failures (tracked via a `pendingRetryCount` key)
- [ ] T012 [US3] [P] Implement `mcp-inator/Views/SharingConsentView.swift`: SwiftUI sheet with two buttons — "Review what I'd share" (→ present `SharingReviewView` as a sheet) and "Not now" (sets `sharingConsentShownThisSession = true`, dismisses); shown non-intrusively as a `.sheet` from the main app window
- [ ] T013 [US3] [P] Implement `mcp-inator/Views/SharingReviewView.swift`: displays a `List` of `SanitizedServerEntry` items built by `UsageSharingService.buildPayload`; each row shows `serverKey`, sanitized command, sanitized args, and env var key names; Toggle per row wired to `SharingPreferences.sharingExcludedKeys`; "Submit" button calls `UsageSharingService.submit` then sets `sharingConsented = true` and dismisses; "Cancel" dismisses without submitting
- [ ] T014 [US3] Update `mcp-inator/Views/PreferencesView.swift`: add a "Contributing Usage Data" section (below existing sections); when `sharingConsented == true`, show "You are contributing anonymous usage data" + a "Withdraw participation" button that sets `sharingConsented = false` and calls `UsageSharingService.clearPending()`; when not consented, show a short description of what is shared and a note that they'll be prompted in the app
- [ ] T015 [US3] Wire eligibility check into app lifecycle in `mcp-inator/mcp_inatorApp.swift` (or the appropriate scene entry point): on app becoming active (`onReceive` of `NSApplication.didBecomeActiveNotification`), evaluate: `sharingConsented == false`, `sharingConsentShownThisSession == false`, days since `firstLaunchDate > 7`, enabled server count ≥ 1; if all true, set `sharingConsentShownThisSession = true` and present `SharingConsentView` as a sheet; also call `UsageSharingService.flushPendingIfNeeded()`
- [ ] T016 [US3] Add "Private server" toggle to the server edit/detail view (locate the relevant view in `mcp-inator/Views/`): wire a `Toggle("Private server", isOn: $server.isPrivate)` to the existing `MCPServerConfig.isPrivate` field; add a help text note that private servers are never included in usage reports

**Checkpoint**: App builds and runs. Consent prompt appears after 7+ days. Reports reach Cloud Run. Preferences opt-out works. Private server toggle persists.

---

## Phase 6: User Story 4 — Catalog Pipeline Reads from Firestore (Priority: P4)

**Goal**: The weekly `refresh.py` in `mcp-catalog` reads per-server usage counts from Firestore instead of `usage.json`. `stats.json` reflects real counts. The `usage.json` file pattern is retired.

**Independent Test**: Quickstart Scenario 4 — seed a Firestore count manually, run `refresh.py` locally with ADC, verify `stats.json` shows the seeded count for that server.

- [x] T017 [US4] In `rayjohnson/mcp-catalog` repo: add `google-cloud-firestore>=2.16` to `scripts/requirements.txt`; update `.github/workflows/weekly-refresh.yml` to add a `google-github-actions/auth@v2` step (before the python run step) using `workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER }}` and `service_account: ${{ vars.GCP_CATALOG_SA }}`; add `GCP_WIF_PROVIDER` and `GCP_CATALOG_SA` as GitHub repo variables in the `mcp-catalog` repo settings
- [ ] T018 [US4] Update `mcp-catalog/scripts/refresh.py`: at the top of the main run function, initialize `google.cloud.firestore.Client(project='ray-johnson-mcp-inator')` and read all docs from `server_usage` collection into `usage_counts = {doc.id: doc.to_dict().get('count', 0) for doc in db.collection('server_usage').stream()}`; if Firestore raises an exception, log the error and `sys.exit(1)` (do not write stale counts); replace any `usage.json` file reads with `usage_counts`; when building `stats.json` entries, set `usageCount` from `usage_counts.get(server_key, 0)`; remove any `usage.json` write or commit logic

**Checkpoint**: `refresh.py` runs locally against Firestore with ADC. `stats.json` reflects Firestore counts. No `usage.json` references remain in the script.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [x] T019 Run `make lint` in `mcp-inator` and fix all SwiftLint warnings in the new Swift files (`SharingPreferences.swift`, `UsageSharingService.swift`, `SharingConsentView.swift`, `SharingReviewView.swift`) and the updated files (`PreferencesView.swift`, `mcp_inatorApp.swift`)
- [x] T020 Run `make cover` and verify all tests pass and the coverage threshold is met
- [x] T021 [P] Bump patch version in `VERSION` (e.g. `0.4.11` → `0.4.12`)
- [x] T022 [P] Update `RELEASE_NOTES.md`: add entry for anonymous usage telemetry (opt-in, Cloud Run backend, Firestore storage), deployment automation, and catalog usage counts
- [x] T023 [P] Close GitHub issues in `rayjohnson/mcp-inator`: #39 (Cloudflare Worker — replaced by Cloud Run service), #40 (app-side sharing UI — implemented), #47 (infra decision — resolved: GCP project `ray-johnson-mcp-inator` created)
- [ ] T024 Run all four quickstart.md scenarios end-to-end to confirm the full feature works: backend accepts reports, CD deploys on push, app sends reports, catalog reflects counts

**Checkpoint**: PR ready — lint clean, tests green, coverage above threshold, version bumped, issues closed.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately; T002 and T003 are parallel
- **Foundational (Phase 2)**: Requires Phase 1 complete; T004 is a one-time manual step that blocks end-to-end testing of all stories
- **US1 (Phase 3)**: Requires Phase 2 complete (needs Firestore DB provisioned)
- **US2 (Phase 4)**: Requires Phase 2 complete (needs WIF + Artifact Registry); can run after T007 (first manual deploy establishes the service)
- **US3 (Phase 5)**: Requires T007 complete (needs the Cloud Run URL); T010–T013 can run in parallel; T014–T016 are sequential on T010
- **US4 (Phase 6)**: Requires Phase 2 complete (needs `GCP_CATALOG_SA`); independent of US1–US3
- **Polish (Phase 7)**: Requires all implementation phases complete; T021, T022, T023 are parallel

### Within Each Phase

- T002, T003 in Phase 1 can run in parallel (different files)
- T005, T006 in Phase 3 can run in parallel (handler code and test code)
- T012, T013 in Phase 5 can run in parallel (different view files)
- T017, T018 in Phase 6 can run in parallel (requirements.txt vs refresh.py)
- T021, T022, T023 in Phase 7 can run in parallel

### Parallel Opportunities

```bash
# Phase 1 — run together:
T002: Create backend/Dockerfile
T003: Create scripts/setup-gcp.sh

# Phase 3 — run together:
T005: Implement main.go handler
T006: Write main_test.go

# Phase 5 — run together after T010:
T012: SharingConsentView.swift
T013: SharingReviewView.swift

# Phase 6 — run together:
T017: requirements.txt + weekly-refresh.yml auth step
T018: refresh.py Firestore read

# Phase 7 — run together:
T021: Bump VERSION
T022: Update RELEASE_NOTES.md
T023: Close GitHub issues
```

---

## Implementation Strategy

### MVP (US1 Only — Phases 1–3)

1. Complete Phase 1: Setup (T001–T003)
2. Complete Phase 2: Foundational (T004 — run setup-gcp.sh)
3. Complete Phase 3: US1 (T005–T007)
4. **STOP and VALIDATE**: `go test ./...` passes; `curl POST /report` works against live Cloud Run URL
5. Ship backend — the service is live even without automated CD or app UI

### Full Delivery Order

1. Phase 1 (Setup) → Phase 2 (GCP provisioning)
2. Phase 3 (US1 backend) → Phase 4 (US2 CD) — backend first, then automate it
3. Phase 5 (US3 app) — needs Cloud Run URL from T007
4. Phase 6 (US4 catalog) — independent, can run in parallel with Phase 5
5. Phase 7 (Polish)

---

## Task Summary

| Phase | Tasks | Count |
|-------|-------|-------|
| Phase 1: Setup | T001–T003 | 3 |
| Phase 2: Foundational | T004 | 1 |
| Phase 3: US1 (Backend) | T005–T007 | 3 |
| Phase 4: US2 (CD) | T008–T009 | 2 |
| Phase 5: US3 (App UI) | T010–T016 | 7 |
| Phase 6: US4 (Catalog) | T017–T018 | 2 |
| Phase 7: Polish | T019–T024 | 6 |
| **Total** | | **24** |

**Parallel opportunities**: 10 tasks marked [P]  
**MVP scope**: Phases 1–3 (7 tasks) — backend live, no app UI yet
