#!/usr/bin/env bash
# End-to-end apply/destroy of the GCP example with bootstrapped networking.
# Applies, smoke-checks, then destroys everything (cleanup runs even on failure).
#
# Required in env:
#   GCP credentials (via google-github-actions/auth in CI, or gcloud application-default
#   credentials locally), GCP_PROJECT_ID
#   MONGODB_ATLAS_CLIENT_ID, MONGODB_ATLAS_CLIENT_SECRET, TF_VAR_atlas_org_id
# Optional:
#   RUN_ID (default: current timestamp), GCP_E2E_REGION (default: us-central1),
#   MONGODB_ATLAS_BASE_URL (non-production Atlas environments),
#   SKIP_DESTROY=true to keep resources after the run (for debugging; prints manual
#   destroy commands instead of running them)
set -euo pipefail

RUN_ID="${RUN_ID:-$(date +%s)}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP="$ROOT/e2e/network-bootstrap/gcp"
EXAMPLE="$ROOT/gcp/atlas-gcp-module-complete"

: "${GCP_PROJECT_ID:?set GCP_PROJECT_ID}"
export TF_VAR_gcp_project_id="$GCP_PROJECT_ID"
export TF_VAR_atlas_project_name="ci-gcp-$RUN_ID"
export TF_VAR_atlas_cluster_name="ci-gcp-$RUN_ID"
# Single region (GCP format) for both the bootstrap subnetwork and Atlas cluster
# placement — the example normalizes it internally.
export TF_VAR_gcp_region="${GCP_E2E_REGION:-us-central1}"
export TF_VAR_backup_export_force_destroy=true # ephemeral run: allow bucket deletion with exports

cleanup() {
  if [[ "${SKIP_DESTROY:-false}" == "true" ]]; then
    echo "--- SKIP_DESTROY=true: leaving resources in place (run $RUN_ID). Destroy manually when done:"
    echo "    (cd $EXAMPLE && terraform destroy -auto-approve -input=false)"
    echo "    (cd $BOOTSTRAP && terraform destroy -auto-approve -input=false -var=\"name_suffix=$RUN_ID\")"
    return
  fi
  echo "--- Cleanup: destroying example and networking (run $RUN_ID)"
  (cd "$EXAMPLE" && terraform init -input=false && terraform destroy -auto-approve -input=false) || true
  (cd "$BOOTSTRAP" && terraform init -input=false && terraform destroy -auto-approve -input=false -var="name_suffix=$RUN_ID") || true
}
trap cleanup EXIT

echo "--- Applying networking ($BOOTSTRAP)"
cd "$BOOTSTRAP"
terraform init -input=false
terraform apply -auto-approve -input=false -var="name_suffix=$RUN_ID"

subnetwork=$(terraform output -raw subnetwork_self_link)
TF_VAR_regions=$(jq -nc --arg subnet "$subnetwork" --arg region "$TF_VAR_gcp_region" \
  '[{name: $region, subnetwork: $subnet}]')
export TF_VAR_regions

echo "--- Applying example ($EXAMPLE)"
cd "$EXAMPLE"
terraform init -input=false
terraform apply -auto-approve -input=false

cluster_id=$(terraform output -raw cluster_id)
test -n "$cluster_id"
echo "--- Smoke check passed: cluster_id=$cluster_id"
echo "--- GCP E2E apply succeeded (run $RUN_ID)"
