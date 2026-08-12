#!/usr/bin/env bash
# Debug ecs_apps: CloudFront, ALB target health, ECS tasks, ECR image, HTTP probes, logs.
#
# Usage:
#   scripts/aws_health_check.sh [app_key]
#
# Environment:
#   AWS_PROFILE  AWS CLI profile (default: ai)

set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-ai}"

root="$(cd "$(dirname "$0")/.." && pwd)"
lz_dir="${root}/01_lz"
filter_app="${1:-}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: ${1} is required" >&2
    exit 1
  }
}

require terraform
require jq
require aws
require curl

if ! terraform -chdir="${lz_dir}" output -json ecs_apps >/dev/null 2>&1; then
  echo "error: run terraform -chdir=01_lz apply first" >&2
  exit 1
fi

ecs_apps="$(terraform -chdir="${lz_dir}" output -json ecs_apps)"
http_edges="$(terraform -chdir="${lz_dir}" output -json aws | jq '.http_edges')"
ecr_repos="$(terraform -chdir="${lz_dir}" output -json ecr_repositories)"

if [ -n "${filter_app}" ] && ! echo "${ecs_apps}" | jq -e --arg k "${filter_app}" 'has($k)' >/dev/null; then
  echo "error: ecs_apps has no key '${filter_app}'" >&2
  exit 1
fi

app_keys="$(echo "${ecs_apps}" | jq -r 'keys[]')"
if [ -z "${app_keys}" ]; then
  echo "No ecs_apps configured in 01_lz."
  exit 0
fi

section() {
  echo
  echo "== $1 =="
}

find_http_edge() {
  local alb_dns="$1"
  echo "${http_edges}" | jq -r --arg alb "${alb_dns}" '
    to_entries[]
    | select(.value.alb_dns_name == $alb)
    | .key
  ' | head -1
}

for app_key in ${app_keys}; do
  if [ -n "${filter_app}" ] && [ "${app_key}" != "${filter_app}" ]; then
    continue
  fi

  app="$(echo "${ecs_apps}" | jq -r --arg k "${app_key}" '.[$k]')"
  name="$(echo "${app}" | jq -r '.name')"
  region="$(echo "${app}" | jq -r '.aws_region')"
  ecr_key="$(echo "${app}" | jq -r '.ecr_key')"
  tfvars_path="$(echo "${app}" | jq -r '.tfvars_path // empty')"
  ecr_url="$(echo "${ecr_repos}" | jq -r --arg k "${ecr_key}" '.[$k]')"

  section "ecs_apps.${app_key} (${name}, ${region})"
  echo "AWS_PROFILE=${AWS_PROFILE}"
  echo "ecr_key=${ecr_key}  repo=${ecr_url}"

  if [ -z "${tfvars_path}" ]; then
    echo "tfvars_path: (none) — apply 02_app_ecs manually or set tfvars_path in 01_lz"
    continue
  fi

  stack_dir="$(cd "${lz_dir}/$(dirname "${tfvars_path}")" && pwd)"
  echo "stack: ${stack_dir#${root}/}"

  if ! terraform -chdir="${stack_dir}" output -json >/dev/null 2>&1; then
    echo "02_app stack not applied yet (no terraform output in ${stack_dir#${root}/})"
    continue
  fi

  stack_out="$(terraform -chdir="${stack_dir}" output -json)"
  cluster="$(echo "${stack_out}" | jq -r '.ecs_cluster_name.value')"
  service="$(echo "${stack_out}" | jq -r '.ecs_service_name.value')"
  log_group="$(echo "${stack_out}" | jq -r '.ecs_log_group_name.value')"
  image_uri="$(echo "${stack_out}" | jq -r '.image_uri.value')"
  alb_dns="$(echo "${stack_out}" | jq -r '.alb_dns_name.value // empty')"
  image_tag="${image_uri##*:}"
  repo_name="${ecr_url##*/}"

  section "ECR image"
  echo "image_uri: ${image_uri}"
  if aws ecr describe-images \
    --repository-name "${repo_name}" \
    --image-ids "imageTag=${image_tag}" \
    --region "${region}" \
    --query 'imageDetails[0].{pushedAt:imagePushedAt,size:imageSizeInBytes,digest:imageDigest}' \
    --output table 2>/dev/null; then
    :
  else
    echo "MISSING: tag ${image_tag} not found in ${repo_name}"
  fi

  section "ECS service ${cluster}/${service}"
  aws ecs describe-services \
    --cluster "${cluster}" \
    --services "${service}" \
    --region "${region}" \
    --query 'services[0].{status:status,running:runningCount,desired:desiredCount,pending:pendingCount,deployments:deployments[*].{status:status,running:runningCount,desired:desiredCount,rollout:rolloutState}}' \
    --output yaml
  echo "recent events:"
  aws ecs describe-services \
    --cluster "${cluster}" \
    --services "${service}" \
    --region "${region}" \
    --query 'services[0].events[0:5].[createdAt,message]' \
    --output table

  section "ECS tasks"
  task_arns="$(aws ecs list-tasks \
    --cluster "${cluster}" \
    --service-name "${service}" \
    --region "${region}" \
    --query 'taskArns' \
    --output text)"
  if [ -z "${task_arns}" ] || [ "${task_arns}" = "None" ]; then
    echo "No running tasks."
  else
    aws ecs describe-tasks \
      --cluster "${cluster}" \
      --tasks ${task_arns} \
      --region "${region}" \
      --query 'tasks[*].{taskArn:taskArn,lastStatus:lastStatus,healthStatus:healthStatus,stopReason:stoppedReason,containers:containers[*].{name:name,lastStatus:lastStatus,reason:reason,exitCode:exitCode}}' \
      --output yaml
  fi

  if [ -z "${alb_dns}" ]; then
    echo
    echo "No alb_dns_name in stack output (ecs_apps.${app_key} may omit routing)."
    continue
  fi

  edge_key="$(find_http_edge "${alb_dns}")"
  https_url="$(echo "${http_edges}" | jq -r --arg k "${edge_key}" '.[$k].https_url // empty')"
  cloudfront_id="$(echo "${http_edges}" | jq -r --arg k "${edge_key}" '.[$k].cloudfront_id // empty')"

  section "ALB target group ${name}"
  tg_arn="$(aws elbv2 describe-target-groups \
    --names "${name}" \
    --region "${region}" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null || true)"
  if [ -z "${tg_arn}" ] || [ "${tg_arn}" = "None" ]; then
    echo "Target group ${name} not found."
  else
    aws elbv2 describe-target-groups \
      --target-group-arns "${tg_arn}" \
      --region "${region}" \
      --query 'TargetGroups[0].{healthCheckPath:HealthCheckPath,matcher:Matcher,port:Port,protocol:Protocol}' \
      --output yaml
    echo "target health:"
    aws elbv2 describe-target-health \
      --target-group-arn "${tg_arn}" \
      --region "${region}" \
      --output table
    healthy="$(aws elbv2 describe-target-health \
      --target-group-arn "${tg_arn}" \
      --region "${region}" \
      --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
      --output text)"
    if [ "${healthy}" = "0" ]; then
      echo
      echo "No healthy targets — ALB/CloudFront return 502/503 until targets pass health checks."
    fi
  fi

  section "HTTP edge ${edge_key:-unknown}"
  if [ -n "${cloudfront_id}" ]; then
    aws cloudfront get-distribution \
      --id "${cloudfront_id}" \
      --query 'Distribution.{status:Status,domain:DomainName,enabled:DistributionConfig.Enabled}' \
      --output yaml
  fi
  echo "https_url: ${https_url}"
  echo "alb_dns_name: ${alb_dns}"
  if [ -n "${https_url}" ]; then
    cf_code="$(curl -sS -o /dev/null -w '%{http_code}' "${https_url}/" || true)"
    echo "curl cloudfront: HTTP ${cf_code}"
  fi
  alb_code="$(curl -sS -o /dev/null -w '%{http_code}' "http://${alb_dns}/" || true)"
  echo "curl alb:        HTTP ${alb_code}"

  section "CloudWatch logs ${log_group}"
  if aws logs tail "${log_group}" --region "${region}" --since 30m --format short 2>/dev/null | tail -15; then
    if aws logs filter-log-events \
      --log-group-name "${log_group}" \
      --region "${region}" \
      --start-time "$(($(date +%s) * 1000 - 1800000))" \
      --filter-pattern "rapid" \
      --limit 1 \
      --query 'events[0].message' \
      --output text 2>/dev/null | grep -q rapid; then
      echo
      echo "hint: logs show Lambda runtime (rapid) — image was built from src/Dockerfile."
      echo "      ECS needs uvicorn on port 8000: just build-push-ecs <repo_url> <tag>"
    fi
  else
    echo "(no recent log events)"
  fi
done
