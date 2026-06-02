# Research: GCP Telemetry Backend

## Service Language

**Decision**: Go (`net/http` stdlib + `cloud.google.com/go/firestore`)

**Rationale**: Go cold starts on Cloud Run are consistently under 100ms vs 300–500ms for Python+Flask. For a low-traffic telemetry endpoint that will go cold frequently, this matters. The Go Firestore client is mature. A single-endpoint HTTP handler is ~50 lines in `net/http` — no framework needed.

**Alternatives considered**: Python+Flask is simpler to write but cold start penalty is real. FastAPI is marginally better than Flask but still slower than Go.

---

## Workload Identity Federation (GitHub Actions → GCP)

**Decision**: WIF for both `mcp-inator` and `mcp-catalog` repos using the same identity pool. Store WIF provider resource name and service account email as plain GitHub **repository variables** (not secrets — they are resource identifiers, not credentials).

**Rationale**: No long-lived credential files. The WIF provider name and SA email are logged in CI output anyway — storing them as variables keeps them readable in the Actions UI. For `mcp-catalog`, add a second attribute condition `attribute.repository == "rayjohnson/mcp-catalog"` in the same pool, bound to a read-only SA.

**Minimum IAM grants**:
- Deploy SA (`github-actions-deployer`): `roles/run.developer`, `roles/artifactregistry.writer`, `roles/iam.workloadIdentityUser`
- Catalog SA (`github-catalog-reader`): `roles/datastore.viewer`, `roles/iam.workloadIdentityUser`

**Alternatives considered**: Service account JSON key in GitHub Secrets — simpler initial setup but creates long-lived credentials requiring manual rotation.

---

## Firestore Data Model

**Decision**: Collection `server_usage`, one document per server ID, `FieldValue.increment(1)` for atomic counter updates.

**Rationale**: `FieldValue.increment()` is a server-side atomic operation — avoids read-modify-write races without transaction overhead. No extra RPC, no contention.

**Document structure**:
```
server_usage/{serverKey}
  count:         int64   (atomically incremented)
  firstSeenAt:   timestamp
  lastSeenAt:    timestamp
```

**Alternatives considered**: Transactions add a read RPC and contention risk — unnecessary when you don't need to read before writing. Append-only event log is fine for auditing but makes aggregation expensive.

---

## Public Endpoint vs. Org Policy Constraint

**Decision**: Default to a static bearer token in the `Authorization` header rather than `--allow-unauthenticated`. The token is the same for all app users (not per-user auth) and is embedded in the macOS app binary.

**Rationale**: The project lives under the Moov GCP org (`organizations/513355466794`). The org policy `constraints/iam.allowedPolicyMemberTypes` on Google Workspace orgs typically blocks adding `allUsers` to IAM policies, which is what `--allow-unauthenticated` does under the hood. Rather than requiring Jeff Braucher / Moov infra to grant a policy exception, a static bearer token sidesteps the issue entirely. For anonymous telemetry, the token provides only lightweight "is this our app" protection — which is appropriate.

**Token storage**: Generated once, stored as a GitHub Actions secret (`TELEMETRY_BEARER_TOKEN`), injected into the Cloud Run service as an environment variable via Secret Manager. The same value is committed as a Swift constant (not a user-facing secret — it's anonymous telemetry, not auth).

**Alternatives considered**: `--allow-unauthenticated` works if Jeff exempts the project from the org policy — can revisit if token approach becomes annoying. Cloud Endpoints/API Gateway as a proxy — overkill for one endpoint.

---

## refresh.py Firestore Integration

**Decision**: Add `google-cloud-firestore` to `mcp-catalog`'s `requirements.txt`. Read all documents from `server_usage` collection at the start of the refresh run; use the resulting dict to populate `usageCount` fields in `stats.json`.

**Rationale**: Trivial to implement (~10 lines). The WIF auth for the `mcp-catalog` GitHub Actions workflow handles credential passing identically to the `mcp-inator` deploy workflow.

**Alternatives considered**: REST API calls to Firestore directly — more code, no benefit. Exporting Firestore to GCS on a schedule — unnecessary complexity.
