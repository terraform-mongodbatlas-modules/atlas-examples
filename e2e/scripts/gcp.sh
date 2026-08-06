#!/usr/bin/env bash
# End-to-end apply/destroy of the GCP example with bootstrapped networking.
# Applies, smoke-checks, then destroys everything (cleanup runs even on failure).
#
# Required in env:
#   GCP credentials (via google-github-actions/auth in CI, or gcloud application-default
#   credentials locally), GCP_PROJECT_ID
#   MONGODB_ATLAS_CLIENT_ID, MONGODB_ATLAS_CLIENT_SECRET, MONGODB_ATLAS_ORG_ID
# Optional:
#   RUN_ID (default: current timestamp), GCP_E2E_REGION (default: us-central1),
#   MONGODB_ATLAS_BASE_URL (non-production Atlas environments),
#   SKIP_DESTROY=true to keep resources after the run (for debugging; the per-run
#   tfvars files are kept and working manual destroy commands are printed)
set -euo pipefail

RUN_ID="${RUN_ID:-$(date +%s)}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP="$ROOT/e2e/network-bootstrap/gcp"
EXAMPLE="$ROOT/gcp/atlas-gcp-module-complete"

: "${GCP_PROJECT_ID:?set GCP_PROJECT_ID}"
: "${MONGODB_ATLAS_ORG_ID:?set MONGODB_ATLAS_ORG_ID}"

GCP_REGION="${GCP_E2E_REGION:-us-central1}"
# Effective inputs are persisted in per-run tfvars files (gitignored) so applies,
# destroys, and any manual cleanup all use exactly the same values.
BOOTSTRAP_TFVARS="$BOOTSTRAP/e2e-$RUN_ID.tfvars.json"
EXAMPLE_TFVARS="$EXAMPLE/e2e-$RUN_ID.tfvars.json"

jq -n --arg suffix "$RUN_ID" --arg region "$GCP_REGION" --arg project "$GCP_PROJECT_ID" \
  '{name_suffix: $suffix, gcp_region: $region, gcp_project_id: $project}' > "$BOOTSTRAP_TFVARS"

cleanup() {
  if [[ "${SKIP_DESTROY:-false}" == "true" ]]; then
    echo "--- SKIP_DESTROY=true: leaving resources in place (run $RUN_ID)."
    echo "    Effective inputs are persisted in:"
    echo "      $EXAMPLE_TFVARS"
    echo "      $BOOTSTRAP_TFVARS"
    echo "    With Atlas + GCP credentials in the environment, destroy manually when done:"
    echo "    (cd $EXAMPLE && terraform init -input=false && terraform destroy -auto-approve -input=false -var-file=$EXAMPLE_TFVARS)"
    echo "    (cd $BOOTSTRAP && terraform init -input=false && terraform destroy -auto-approve -input=false -var-file=$BOOTSTRAP_TFVARS)"
    return
  fi
  echo "--- Cleanup: destroying example and networking (run $RUN_ID)"
  failed=0
  if [[ -f "$EXAMPLE_TFVARS" ]]; then
    (cd "$EXAMPLE" && terraform init -input=false && terraform destroy -auto-approve -input=false -var-file="$EXAMPLE_TFVARS") || failed=1
  fi
  (cd "$BOOTSTRAP" && terraform init -input=false && terraform destroy -auto-approve -input=false -var-file="$BOOTSTRAP_TFVARS") || failed=1
  if [[ $failed -eq 0 ]]; then
    rm -f "$EXAMPLE_TFVARS" "$BOOTSTRAP_TFVARS"
  else
    echo "--- WARNING: destroy incomplete; tfvars files kept for manual retry"
  fi
}
trap cleanup EXIT

echo "--- Applying networking ($BOOTSTRAP)"
cd "$BOOTSTRAP"
terraform init -input=false
terraform apply -auto-approve -input=false -var-file="$BOOTSTRAP_TFVARS"

# Single region (GCP format) for both the bootstrap subnetwork and Atlas cluster
# placement — the example normalizes it internally. The bootstrap provides a
# ready-made value for the example's regions variable.
# backup_export: ephemeral run — allow bucket deletion with exports, and set an
# explicit bucket name attributable to this repo in the shared GCP project.
# Cluster names use a short prefix: Atlas validates an internal prefix derived
# from the first 23 chars (CLUSTER_NAME_PREFIX_INVALID when char 23 is a
# hyphen). Attribution comes from the containing project name.
jq -n \
  --arg org "$MONGODB_ATLAS_ORG_ID" \
  --arg name "atlas-examples-e2e-gcp-$RUN_ID" \
  --arg cluster "atlas-ex-e2e-gcp-$RUN_ID" \
  --arg project "$GCP_PROJECT_ID" \
  --arg region "$GCP_REGION" \
  --arg bucket "atlas-examples-e2e-backup-$RUN_ID" \
  --argjson regions "$(terraform output -json regions)" \
  '{
    atlas_org_id: $org,
    atlas_project_name: $name,
    atlas_cluster_name: $cluster,
    gcp_project_id: $project,
    gcp_region: $region,
    backup_export_force_destroy: true,
    backup_export_bucket_name: $bucket,
    regions: $regions
  }' > "$EXAMPLE_TFVARS"

echo "--- Applying example ($EXAMPLE)"
cd "$EXAMPLE"
terraform init -input=false
terraform apply -auto-approve -input=false -var-file="$EXAMPLE_TFVARS"

cluster_id=$(terraform output -raw cluster_id)
test -n "$cluster_id"
echo "--- Smoke check passed: cluster_id=$cluster_id"
echo "--- GCP E2E apply succeeded (run $RUN_ID)"
