# Feature Specification: GCP Telemetry Backend

**Feature Branch**: `016-gcp-telemetry`

**Created**: 2026-06-01

**Status**: Draft

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Usage Reports Received and Stored (Priority: P1)

The macOS app sends an anonymous usage report to a hosted endpoint when a user opts in to usage sharing. The endpoint accepts the report, validates it, increments per-server usage counts in persistent storage, and returns a success response — all without recording any personally identifiable information.

**Why this priority**: This is the core backend. All other user stories depend on this being deployed and working.

**Independent Test**: Deploy the service. Send a `POST /report` with a valid payload containing two server keys. Verify a `{"status":"ok","accepted":2}` response in under 500ms. Verify per-server counts incremented in storage. Verify no client IP is stored.

**Acceptance Scenarios**:

1. **Given** the service is running, **When** the app POSTs a valid usage report with N server keys, **Then** the service returns `{"status":"ok","accepted":N}` and each server's count is atomically incremented in persistent storage.
2. **Given** a report containing an unknown server key, **When** the service processes it, **Then** the key is accepted and its count is incremented (unknown servers are tracked, not rejected).
3. **Given** a report with a missing or incompatible `schemaVersion`, **When** the service receives it, **Then** it returns HTTP 400 with a descriptive message and no counts are modified.
4. **Given** any valid or invalid request, **Then** no client IP address appears in logs or storage.

---

### User Story 2 — Automated Deployment on Code Push (Priority: P2)

A developer pushes a change to the telemetry service on the `main` branch. Without any manual steps, the updated service is built and deployed — replacing the running version within a few minutes.

**Why this priority**: Manual deployment is error-prone. Automated CI/CD is required for any service that will evolve over time.

**Independent Test**: Modify the service code, push to `main`, observe the pipeline complete without manual intervention. Verify the service URL reflects the updated version.

**Acceptance Scenarios**:

1. **Given** a push to `main`, **When** the pipeline runs, **Then** the new version is deployed with no manually stored credential files and no human steps.
2. **Given** a build failure, **Then** the pipeline fails visibly and the previously deployed version remains live.
3. **Given** a successful deployment, **Then** the service is accessible at the same URL within 5 minutes of the push.

---

### User Story 3 — App Opts In and Sends Usage Reports (Priority: P3)

A user is prompted — once, non-intrusively — to share anonymous usage data. They can review exactly what would be sent before agreeing. If they agree, the app periodically sends sanitized reports to the cloud endpoint. They can opt out at any time from Preferences.

**Why this priority**: Depends on US1 (the endpoint must exist). This is the full app-side implementation — the data collection doesn't happen without it.

**Independent Test**: Run the app after 7+ days since first launch with at least one enabled server. Verify the consent prompt appears. Review the sharing review screen. Submit. Verify a report arrives at the Cloud Run service. Open Preferences and verify opt-out works.

**Acceptance Scenarios**:

1. **Given** the app has been running for 7+ days with at least one enabled server and consent has not been shown this session, **When** it comes to the foreground, **Then** a non-intrusive consent prompt is shown with options to review or dismiss.
2. **Given** the consent prompt, **When** the user taps "Review what I'd share", **Then** a review screen shows each server's sanitized fields (key, command, sanitized args, env var key names only — no values) with a per-server exclude toggle.
3. **Given** the review screen, **When** the user submits, **Then** a sanitized report is POSTed to the cloud endpoint with only opted-in servers included.
4. **Given** a user has opted in, **When** they open Preferences, **Then** a "Contributing Usage Data" section shows their status and an opt-out button that stops future submissions.
5. **Given** the endpoint is temporarily unreachable, **When** the app tries to send, **Then** it retries up to 3 times with exponential backoff, then queues the report for the next launch.
6. **Given** a server is marked as private, **When** a report is built, **Then** that server is excluded from the payload regardless of consent state.
7. **Given** the user taps "Not now" on the consent prompt, **Then** the prompt is dismissed and not shown again in the same session; it may appear in a future session.

---

### User Story 4 — Catalog Pipeline Reads Usage Counts from Storage (Priority: P4)

The weekly catalog refresh job reads per-server usage counts from persistent cloud storage (not from a file in the GitHub repo) and folds them into the catalog's stats. The catalog then surfaces "used by N users" counts to app users.

**Why this priority**: Closes the loop — usage data collected in US3 needs to reach the catalog to be useful. Also eliminates the previous design of using GitHub as a makeshift database.

**Independent Test**: Seed a few server counts in Firestore manually. Run the refresh script locally. Verify `stats.json` in the mcp-catalog repo reflects the seeded counts for those servers.

**Acceptance Scenarios**:

1. **Given** usage counts exist in persistent storage, **When** the weekly refresh job runs, **Then** per-server counts are read and written into `stats.json` in the mcp-catalog repo.
2. **Given** a server has zero reports, **When** the refresh job runs, **Then** its usage count in `stats.json` is 0 or absent (not stale from a previous run).
3. **Given** the refresh job cannot reach persistent storage, **Then** it logs a clear error and exits non-zero rather than writing stale or empty counts.

---

### Edge Cases

- What if two app instances send reports for the same server key simultaneously? Storage must support atomic increments — no count loss under concurrent writes.
- What if the request body exceeds a reasonable maximum size? Reject with 413 without attempting to parse.
- What if persistent storage is temporarily unavailable when the service receives a report? Return 503 so the app retries; do not return 200 falsely.
- What if a server key contains unexpected characters or is extremely long? Validate and reject with 400.
- What if the deployment pipeline credentials are misconfigured? The build must fail loudly, not silently deploy with wrong permissions.
- What if the weekly refresh job runs while a large batch of reports is being written? Counts may be slightly behind by one batch — this is acceptable; exact real-time accuracy is not required.

## Requirements *(mandatory)*

### Functional Requirements

**Backend service:**

- **FR-001**: The service MUST accept `POST /report` requests containing a `schemaVersion` field and a list of server keys.
- **FR-002**: The service MUST atomically increment a per-server usage count for each server key in the report.
- **FR-003**: The service MUST return `{"status":"ok","accepted":N}` where N is the count of server keys processed.
- **FR-004**: The service MUST return HTTP 400 for requests with a missing or incompatible `schemaVersion`.
- **FR-005**: The service MUST NOT log, store, or forward client IP addresses under any circumstances.
- **FR-006**: The service MUST be publicly accessible without authentication.
- **FR-007**: The service MUST respond within 500ms at p95 under expected load.

**Deployment pipeline:**

- **FR-008**: The deployment pipeline MUST build and deploy the service automatically on every push to `main` with no manual steps.
- **FR-009**: The pipeline MUST authenticate to the cloud provider using short-lived, automatically rotated credentials — no long-lived credential files stored in GitHub.
- **FR-010**: The infrastructure setup steps MUST be documented as runnable commands reproducible from scratch.

**App-side (issue #40):**

- **FR-011**: The app MUST show a non-intrusive consent prompt once per session when the user has had the app for 7+ days and has at least one enabled server, and has not previously opted in or permanently dismissed.
- **FR-012**: The consent prompt MUST offer a "Review what I'd share" path that shows per-server sanitized fields before any data is sent.
- **FR-013**: The review screen MUST allow the user to exclude individual servers before submitting.
- **FR-014**: The app MUST sanitize report payloads: server key and command are included; args are included with path segments redacted; env var keys are included but values are never sent.
- **FR-015**: Servers marked as private MUST be excluded from all report payloads regardless of user consent state.
- **FR-016**: The app MUST retry failed submissions up to 3 times with exponential backoff, then queue for the next launch.
- **FR-017**: After 3 launch-retry failures the pending report MUST be dropped silently.
- **FR-018**: Preferences MUST include a "Contributing Usage Data" section with current opt-in status and an opt-out action.
- **FR-019**: The app MUST send reports to the Cloud Run service URL.

**Catalog pipeline (issue #38 update):**

- **FR-020**: The weekly refresh script MUST read per-server usage counts from persistent cloud storage (not from a file in the GitHub repository).
- **FR-021**: The refresh script MUST write the counts into `stats.json` in the mcp-catalog repo, making them available to the app as "used by N users."

### Key Entities

- **UsageReport**: Payload sent by the app. Contains `schemaVersion` (string) and `serverKeys` (list of strings). No user identity, IP, or device info.
- **ServerUsageCount**: Persistent record of report appearances per server key. Incremented atomically; never decremented.
- **SanitizedServerEntry**: What the review screen and report payload show per server: key, command name, sanitized args (paths redacted), env var key names only.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The service accepts and processes a valid usage report in under 500ms at p95.
- **SC-002**: Per-server counts are correct after 100 concurrent reports naming the same server key — no count lost due to race conditions.
- **SC-003**: A push to `main` results in a live deployment within 5 minutes, with zero manual steps.
- **SC-004**: Zero client IP addresses appear in service logs or storage after processing 1,000 reports.
- **SC-005**: A user who opts in sees their server usage counts reflected in the catalog within one weekly refresh cycle.
- **SC-006**: 100% of servers marked private are absent from all submitted report payloads.

## Assumptions

- The GCP project `ray-johnson-mcp-inator` already exists with billing enabled; setup begins from this baseline.
- Persistent cloud storage is the single source of truth for usage counts — no `usage.json` file in the GitHub repo is used or maintained.
- `schemaVersion` in reports is a string; `"1"` is the only supported version. Any other value is rejected with 400.
- Unknown server keys (not in the catalog) are accepted and counted — they will appear in `stats.json` and the app will ignore counts for servers it doesn't know about.
- The weekly refresh job (#38) is updated as part of this feature to read from cloud storage instead of `usage.json`.
- `MCPServerConfig.isPrivate` and its migration already exist in the codebase.
- GitHub Actions is already in use in this repository; the CD workflow is additive.
- A single geographic region is sufficient for v1; multi-region is out of scope.
- The default cloud-assigned service URL is acceptable for v1; a custom domain is out of scope.
- Budget alerts for the GCP project are handled separately by Moov infra (INFRA-4755).
