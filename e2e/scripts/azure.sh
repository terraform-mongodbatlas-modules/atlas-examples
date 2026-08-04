#!/usr/bin/env bash
# End-to-end apply/destroy of the Azure example with bootstrapped networking.
# Applies, smoke-checks, then destroys everything (cleanup runs even on failure).
#
# Required in env:
#   az CLI authenticated — either an existing az login session, or ARM_CLIENT_ID,
#   ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID for service-principal login
#   MONGODB_ATLAS_CLIENT_ID, MONGODB_ATLAS_CLIENT_SECRET, MONGODB_ATLAS_ORG_ID
# Optional:
#   RUN_ID (default: current timestamp), ATLAS_AZURE_APP_ID (non-production Atlas environments),
#   MONGODB_ATLAS_BASE_URL,
#   SKIP_DESTROY=true to keep resources after the run (for debugging; the per-run
#   tfvars files are kept and working manual destroy commands are printed)
#
# If the Atlas Azure app's service principal already exists in the tenant (shared tenants),
# it is reused (BYO mode) so terraform never creates/deletes it.
set -euo pipefail

RUN_ID="${RUN_ID:-$(date +%s)}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP="$ROOT/e2e/network-bootstrap/azure"
EXAMPLE="$ROOT/azure/atlas-azure-module-complete"

: "${MONGODB_ATLAS_ORG_ID:?set MONGODB_ATLAS_ORG_ID}"

# Effective inputs are persisted in per-run tfvars files (gitignored) so applies,
# destroys, and any manual cleanup all use exactly the same values.
BOOTSTRAP_TFVARS="$BOOTSTRAP/e2e-$RUN_ID.tfvars.json"
EXAMPLE_TFVARS="$EXAMPLE/e2e-$RUN_ID.tfvars.json"

if [[ -n "${ARM_CLIENT_ID:-}" ]]; then
  : "${ARM_CLIENT_SECRET:?set ARM_CLIENT_SECRET}" "${ARM_TENANT_ID:?set ARM_TENANT_ID}" "${ARM_SUBSCRIPTION_ID:?set ARM_SUBSCRIPTION_ID}"
  az login --service-principal -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" \
    --tenant "$ARM_TENANT_ID" --only-show-errors --output none
  subscription_id="$ARM_SUBSCRIPTION_ID"
else
  echo "--- ARM_* not set: using the current az CLI session"
  subscription_id=$(az account show --query id -o tsv --only-show-errors)
fi

app_id="${ATLAS_AZURE_APP_ID:-9f2deb0d-be22-4524-a403-df531868bac0}" # production Atlas app fallback
extra_vars="{}"
if [[ -n "${ATLAS_AZURE_APP_ID:-}" ]]; then
  extra_vars=$(jq -n --arg id "$ATLAS_AZURE_APP_ID" '{atlas_azure_app_id: $id}')
fi
if sp_id=$(az ad sp show --id "$app_id" --query id -o tsv --only-show-errors 2>/dev/null); then
  echo "--- Existing service principal found for app $app_id ($sp_id) — using BYO mode"
  extra_vars=$(jq --arg id "$sp_id" '. + {atlas_azure_service_principal_id: $id}' <<< "$extra_vars")
else
  echo "--- No existing service principal for app $app_id — module will create one"
fi

jq -n --arg suffix "$RUN_ID" '{name_suffix: $suffix}' > "$BOOTSTRAP_TFVARS"

cleanup() {
  if [[ "${SKIP_DESTROY:-false}" == "true" ]]; then
    echo "--- SKIP_DESTROY=true: leaving resources in place (run $RUN_ID)."
    echo "    Effective inputs are persisted in:"
    echo "      $EXAMPLE_TFVARS"
    echo "      $BOOTSTRAP_TFVARS"
    echo "    With Atlas + Azure credentials in the environment, destroy manually when done:"
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

# The bootstrap provides a ready-made value for the example's regions variable.
# The validation VM is intentionally out of scope for the E2E: scripted access
# requires an SSH key + Bastion Standard (extra cost); Serial Console is
# manual-only.
# Cluster names use a short prefix: Atlas validates an internal prefix derived
# from the first 23 chars (CLUSTER_NAME_PREFIX_INVALID when char 23 is a
# hyphen). Attribution comes from the containing project name.
jq -n \
  --arg org "$MONGODB_ATLAS_ORG_ID" \
  --arg name "atlas-examples-e2e-azure-$RUN_ID" \
  --arg cluster "atlas-ex-e2e-azure-$RUN_ID" \
  --arg sub "$subscription_id" \
  --arg rg "$(terraform output -raw resource_group_name)" \
  --argjson regions "$(terraform output -json regions)" \
  --argjson extra "$extra_vars" \
  '{
    atlas_org_id: $org,
    atlas_project_name: $name,
    atlas_cluster_name: $cluster,
    azure_subscription_id: $sub,
    enable_validation_vm: false,
    azure_resource_group_name: $rg,
    regions: $regions
  } + $extra' > "$EXAMPLE_TFVARS"

echo "--- Applying example ($EXAMPLE)"
cd "$EXAMPLE"
terraform init -input=false
terraform apply -auto-approve -input=false -var-file="$EXAMPLE_TFVARS"

cluster_id=$(terraform output -raw cluster_id)
test -n "$cluster_id"
echo "--- Smoke check passed: cluster_id=$cluster_id"
echo "--- Azure E2E apply succeeded (run $RUN_ID)"
