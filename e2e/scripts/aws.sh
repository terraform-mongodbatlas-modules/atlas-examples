#!/usr/bin/env bash
# End-to-end apply/destroy of the AWS example with bootstrapped networking.
# Applies, smoke-checks, then destroys everything (cleanup runs even on failure).
#
# Required in env:
#   AWS credentials (via aws-actions/configure-aws-credentials in CI, or any local AWS auth)
#   MONGODB_ATLAS_CLIENT_ID, MONGODB_ATLAS_CLIENT_SECRET, TF_VAR_atlas_org_id
# Optional:
#   RUN_ID (default: current timestamp), AWS_E2E_REGION (default: us-east-2),
#   MONGODB_ATLAS_BASE_URL (non-production Atlas environments),
#   SKIP_DESTROY=true to keep resources after the run (for debugging; prints manual
#   destroy commands instead of running them)
set -euo pipefail

RUN_ID="${RUN_ID:-$(date +%s)}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP="$ROOT/e2e/network-bootstrap/aws"
EXAMPLE="$ROOT/aws/atlas-aws-module-complete"

export TF_VAR_atlas_project_name="ci-aws-$RUN_ID"
export TF_VAR_atlas_cluster_name="ci-aws-$RUN_ID"
export TF_VAR_aws_region="${AWS_E2E_REGION:-us-east-2}"
# The validation VM is intentionally out of scope for the E2E: verifying it
# meaningfully requires extra networking (public subnet/NAT) and SSM access.
export TF_VAR_enable_validation_vm=false
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

vpc_id=$(terraform output -raw vpc_id)
subnet_ids=$(terraform output -json private_subnet_ids | jq -c .)
atlas_region=$(echo "$TF_VAR_aws_region" | tr 'a-z' 'A-Z' | tr '-' '_')
TF_VAR_regions=$(jq -nc --arg vpc "$vpc_id" --argjson subs "$subnet_ids" --arg name "$atlas_region" \
  '[{name: $name, vpc_id: $vpc, subnet_ids: $subs}]')
export TF_VAR_regions

echo "--- Applying example ($EXAMPLE)"
cd "$EXAMPLE"
terraform init -input=false
terraform apply -auto-approve -input=false

cluster_id=$(terraform output -raw cluster_id)
test -n "$cluster_id"
echo "--- Smoke check passed: cluster_id=$cluster_id"
echo "--- AWS E2E apply succeeded (run $RUN_ID)"
