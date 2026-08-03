#!/usr/bin/env bash
# End-to-end apply/destroy of the Azure example with bootstrapped networking.
# Applies, smoke-checks, then destroys everything (cleanup runs even on failure).
#
# Required in env:
#   az CLI, ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
#   MONGODB_ATLAS_CLIENT_ID, MONGODB_ATLAS_CLIENT_SECRET, TF_VAR_atlas_org_id
# Optional:
#   RUN_ID (default: current timestamp), ATLAS_AZURE_APP_ID (non-production Atlas environments),
#   MONGODB_ATLAS_BASE_URL,
#   SKIP_DESTROY=true to keep resources after the run (for debugging; prints manual
#   destroy commands instead of running them)
#
# If the Atlas Azure app's service principal already exists in the tenant (shared tenants),
# it is reused (BYO mode) so terraform never creates/deletes it.
set -euo pipefail

RUN_ID="${RUN_ID:-$(date +%s)}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP="$ROOT/e2e/network-bootstrap/azure"
EXAMPLE="$ROOT/azure/atlas-azure-module-complete"

export TF_VAR_atlas_project_name="ci-azure-$RUN_ID"
export TF_VAR_atlas_cluster_name="ci-azure-$RUN_ID"
export TF_VAR_azure_subscription_id="$ARM_SUBSCRIPTION_ID"
# The validation VM is intentionally out of scope for the E2E: scripted access
# requires an SSH key + Bastion Standard (extra cost); Serial Console is
# manual-only. Tracked as a follow-up.
export TF_VAR_enable_validation_vm=false

app_id="${ATLAS_AZURE_APP_ID:-9f2deb0d-be22-4524-a403-df531868bac0}" # production Atlas app fallback
if [[ -n "${ATLAS_AZURE_APP_ID:-}" ]]; then
  export TF_VAR_atlas_azure_app_id="$ATLAS_AZURE_APP_ID"
fi

az login --service-principal -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" \
  --tenant "$ARM_TENANT_ID" --only-show-errors --output none
if sp_id=$(az ad sp show --id "$app_id" --query id -o tsv --only-show-errors 2>/dev/null); then
  echo "--- Existing service principal found for app $app_id ($sp_id) — using BYO mode"
  export TF_VAR_atlas_azure_service_principal_id="$sp_id"
else
  echo "--- No existing service principal for app $app_id — module will create one"
fi

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

resource_group_name=$(terraform output -raw resource_group_name)
subnet_id=$(terraform output -raw subnet_id)
azure_location=$(terraform output -raw azure_location)
export TF_VAR_azure_resource_group_name="$resource_group_name"
TF_VAR_regions=$(jq -nc --arg subnet "$subnet_id" --arg loc "$azure_location" \
  '[{name: "US_EAST_2", azure_location: $loc, subnet_id: $subnet}]')
export TF_VAR_regions

echo "--- Applying example ($EXAMPLE)"
cd "$EXAMPLE"
terraform init -input=false
terraform apply -auto-approve -input=false

cluster_id=$(terraform output -raw cluster_id)
test -n "$cluster_id"
echo "--- Smoke check passed: cluster_id=$cluster_id"
echo "--- Azure E2E apply succeeded (run $RUN_ID)"
