#!/usr/bin/env bash
# Deletes stale Atlas projects created by this repo's E2E runs (e.g. when a
# runner is killed before e2e/scripts/<cloud>.sh trap cleanup runs). Modeled on
# the terraform-provider-mongodbatlas cleanup-test-env workflow: only projects
# named atlas-examples-e2e-* older than the grace period are touched, so
# in-flight runs are never affected, and failed deletions are simply retried on
# the next run.
#
# Required in env:
#   curl, jq
#   MONGODB_ATLAS_CLIENT_ID, MONGODB_ATLAS_CLIENT_SECRET (service account with
#   ORG_OWNER), MONGODB_ATLAS_ORG_ID
# Optional:
#   MONGODB_ATLAS_BASE_URL (default: https://cloud.mongodb.com),
#   PROJECT_PREFIX (default: atlas-examples-e2e-),
#   GRACE_PERIOD_HOURS (default: 24),
#   DRY_RUN=true to only list matching projects without deleting them
set -euo pipefail

BASE_URL="${MONGODB_ATLAS_BASE_URL:-https://cloud.mongodb.com}"
BASE_URL="${BASE_URL%/}" # tolerate a trailing slash
PREFIX="${PROJECT_PREFIX:-atlas-examples-e2e-}"
GRACE_HOURS="${GRACE_PERIOD_HOURS:-24}"
DRY_RUN="${DRY_RUN:-false}"

: "${MONGODB_ATLAS_CLIENT_ID:?set MONGODB_ATLAS_CLIENT_ID}"
: "${MONGODB_ATLAS_CLIENT_SECRET:?set MONGODB_ATLAS_CLIENT_SECRET}"
: "${MONGODB_ATLAS_ORG_ID:?set MONGODB_ATLAS_ORG_ID}"

token=$(curl -sfS -u "$MONGODB_ATLAS_CLIENT_ID:$MONGODB_ATLAS_CLIENT_SECRET" \
  -X POST "$BASE_URL/api/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" | jq -r '.access_token // empty')
: "${token:?failed to obtain an Atlas access token (check client ID/secret and base URL)}"

api() { # api <method> <path>
  curl -sfS -X "$1" "$BASE_URL/api/atlas/v2$2" \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.atlas.2023-01-01+json"
}

cutoff=$(( $(date +%s) - GRACE_HOURS * 3600 ))
echo "--- Scanning org $MONGODB_ATLAS_ORG_ID for projects matching '$PREFIX*' older than ${GRACE_HOURS}h"

candidates="[]"
page=1
while :; do
  resp=$(api GET "/groups?orgId=$MONGODB_ATLAS_ORG_ID&pageNum=$page&itemsPerPage=500")
  if [[ -z "$resp" ]]; then
    echo "--- ERROR: empty response from the Atlas API (GET /groups)" >&2
    exit 1
  fi
  batch=$(jq --arg prefix "$PREFIX" --argjson cutoff "$cutoff" \
    '[.results[] | select(.name | startswith($prefix)) | select((.created | fromdateiso8601) < $cutoff) | {id, name, created}]' \
    <<< "$resp")
  candidates=$(jq -n --argjson a "$candidates" --argjson b "$batch" '$a + $b')
  total=$(jq '.totalCount // 0' <<< "$resp")
  if (( page * 500 >= total )); then
    break
  fi
  page=$((page + 1))
done

count=$(jq length <<< "$candidates")
echo "--- Found $count stale project(s):"
jq -r '.[] | "    \(.name) (created \(.created))"' <<< "$candidates"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "--- DRY_RUN=true: nothing deleted"
  exit 0
fi

failed=0
while read -r id name; do
  if api DELETE "/groups/$id" > /dev/null; then
    echo "--- Deleted $name"
  else
    echo "--- WARNING: failed to delete $name (will retry on next run)"
    failed=$((failed + 1))
  fi
done < <(jq -r '.[] | "\(.id) \(.name)"' <<< "$candidates")

echo "--- Cleanup done: $((count - failed)) deleted, $failed failed"
