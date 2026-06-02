#!/usr/bin/env bash
# One-time GCP infrastructure setup for mcp-inator telemetry backend.
# Run this once from the repo root after creating the GCP project.
# Captures output at the end — save the printed values to GitHub secrets/variables.

set -euo pipefail

PROJECT="ray-johnson-mcp-inator"
REGION="us-central1"
GITHUB_REPO="rayjohnson/mcp-inator"
CATALOG_REPO="rayjohnson/mcp-catalog"

echo "==> Enabling required GCP APIs..."
gcloud services enable \
  run.googleapis.com \
  firestore.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  --project="${PROJECT}"

echo "==> Waiting 30s for API enablement to propagate..."
sleep 30

echo "==> Creating Firestore database (native mode)..."
if gcloud firestore databases describe --project="${PROJECT}" &>/dev/null; then
  echo "    Firestore database already exists, skipping."
else
  gcloud firestore databases create \
    --location="${REGION}" \
    --project="${PROJECT}"
fi

echo "==> Creating Artifact Registry repository..."
if gcloud artifacts repositories describe mcp-inator \
  --location="${REGION}" --project="${PROJECT}" &>/dev/null; then
  echo "    Artifact Registry repo already exists, skipping."
else
  gcloud artifacts repositories create mcp-inator \
    --repository-format=docker \
    --location="${REGION}" \
    --project="${PROJECT}"
fi

echo "==> Creating Workload Identity Pool..."
if gcloud iam workload-identity-pools describe github-pool \
  --location=global --project="${PROJECT}" &>/dev/null; then
  echo "    WIF pool already exists, skipping."
else
  gcloud iam workload-identity-pools create github-pool \
    --location=global \
    --project="${PROJECT}"
fi

echo "==> Creating Workload Identity Provider..."
if gcloud iam workload-identity-pools providers describe github-provider \
  --location=global \
  --workload-identity-pool=github-pool \
  --project="${PROJECT}" &>/dev/null; then
  echo "    WIF provider already exists, skipping."
else
  gcloud iam workload-identity-pools providers create-oidc github-provider \
    --location=global \
    --workload-identity-pool=github-pool \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --project="${PROJECT}"
fi

echo "==> Creating deploy service account (mcp-inator repo)..."
if gcloud iam service-accounts describe \
  "github-actions-deployer@${PROJECT}.iam.gserviceaccount.com" \
  --project="${PROJECT}" &>/dev/null; then
  echo "    Service account already exists, skipping creation."
else
  gcloud iam service-accounts create github-actions-deployer \
    --project="${PROJECT}"
fi

echo "==> Granting Cloud Run developer role to deploy SA..."
gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="serviceAccount:github-actions-deployer@${PROJECT}.iam.gserviceaccount.com" \
  --role="roles/run.developer" \
  --condition=None

echo "==> Granting Artifact Registry writer role to deploy SA..."
gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="serviceAccount:github-actions-deployer@${PROJECT}.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer" \
  --condition=None

echo "==> Resolving project number..."
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT}" --format='value(projectNumber)')

echo "==> Binding deploy SA to WIF for mcp-inator repo..."
gcloud iam service-accounts add-iam-policy-binding \
  "github-actions-deployer@${PROJECT}.iam.gserviceaccount.com" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/${GITHUB_REPO}" \
  --role="roles/iam.workloadIdentityUser" \
  --project="${PROJECT}"

echo "==> Creating catalog reader service account (mcp-catalog repo)..."
if gcloud iam service-accounts describe \
  "github-catalog-reader@${PROJECT}.iam.gserviceaccount.com" \
  --project="${PROJECT}" &>/dev/null; then
  echo "    Service account already exists, skipping creation."
else
  gcloud iam service-accounts create github-catalog-reader \
    --project="${PROJECT}"
fi

echo "==> Granting Firestore viewer role to catalog reader SA..."
gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="serviceAccount:github-catalog-reader@${PROJECT}.iam.gserviceaccount.com" \
  --role="roles/datastore.viewer" \
  --condition=None

echo "==> Binding catalog reader SA to WIF for mcp-catalog repo..."
gcloud iam service-accounts add-iam-policy-binding \
  "github-catalog-reader@${PROJECT}.iam.gserviceaccount.com" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/${CATALOG_REPO}" \
  --role="roles/iam.workloadIdentityUser" \
  --project="${PROJECT}"

echo "==> Generating bearer token..."
BEARER_TOKEN=$(openssl rand -hex 32)

WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
DEPLOY_SA="github-actions-deployer@${PROJECT}.iam.gserviceaccount.com"
CATALOG_SA="github-catalog-reader@${PROJECT}.iam.gserviceaccount.com"

echo ""
echo "============================================================"
echo "Setup complete. Add the following to GitHub:"
echo "============================================================"
echo ""
echo "--- GitHub Actions SECRET (rayjohnson/mcp-inator) ---"
echo "  TELEMETRY_BEARER_TOKEN=${BEARER_TOKEN}"
echo ""
echo "--- GitHub Actions VARIABLES (rayjohnson/mcp-inator AND rayjohnson/mcp-catalog) ---"
echo "  GCP_PROJECT=${PROJECT}"
echo "  GCP_REGION=${REGION}"
echo "  GCP_WIF_PROVIDER=${WIF_PROVIDER}"
echo "  GCP_DEPLOY_SA=${DEPLOY_SA}"
echo "  GCP_CATALOG_SA=${CATALOG_SA}"
echo ""
echo "NOTE: TELEMETRY_BEARER_TOKEN is shown only once. Save it now."
