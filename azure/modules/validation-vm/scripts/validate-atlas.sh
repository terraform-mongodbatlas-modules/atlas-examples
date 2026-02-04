#!/bin/bash
# ==========================================================================
# Atlas PrivateLink Validation Script
# ==========================================================================
# Validates Atlas connectivity over PrivateLink:
#   1. DNS Resolution - Targets resolve to private IPs
#   2. MongoDB Connection - mongosh can connect
#   3. CRUD Operations - Insert/read/update/delete
#   4. Backup (optional) - Requires Atlas API keys
#   5. Cluster Info - Version and topology
#
# Connection string is pre-configured in ~/.atlas-connection
# Run: ./validate-atlas
# Or ./validate-atlas [--strict] [connection-string]
# ==========================================================================

set -uo pipefail

CONFIG_FILE="$HOME/.atlas-connection"
ATLAS_CONFIG_FILE="$HOME/.atlas-config"
STRICT_MODE=false
CONNECTION_STRING=""
PUBLIC_URI=""

print_usage() {
  echo "Usage: ./validate-atlas [OPTIONS] [connection-string] [public-connection-string]"
  echo ""
  echo "Connection string is read from ~/.atlas-connection by default."
  echo "Override by providing a connection string as an argument."
  echo ""
  echo "Options:"
  echo "  --strict  Exit immediately on first failure (for CI/CD)"
  echo "  --help    Show this help message"
  echo ""
  echo "Examples:"
  echo "  ./validate-atlas                     # Uses pre-configured connection string"
  echo "  ./validate-atlas --strict            # Strict mode with pre-configured string"
  echo "  ./validate-atlas 'mongodb+srv://...' # Override with custom connection string"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --strict) STRICT_MODE=true; shift ;;
    --help|-h) print_usage; exit 0 ;;
    -*)
      echo "Unknown option: $1"
      print_usage
      exit 1
      ;;
    *)
      if [ -z "$CONNECTION_STRING" ]; then
        CONNECTION_STRING="$1"
      else
        PUBLIC_URI="$1"
      fi
      shift
      ;;
  esac
done

# Load connection string from config file if not provided
if [ -z "$CONNECTION_STRING" ]; then
  if [ -f "$CONFIG_FILE" ]; then
    CONNECTION_STRING=$(cat "$CONFIG_FILE" | tr -d '\n')
    if [ -z "$CONNECTION_STRING" ]; then
      echo "ERROR: Config file $CONFIG_FILE is empty."
      exit 1
    fi
  else
    echo "ERROR: No connection string provided and $CONFIG_FILE not found."
    echo ""
    print_usage
    exit 1
  fi
fi

# Prerequisites Check
# Verify required tools are installed (cloud-init may still be running)
check_prerequisites() {
  local missing=false
  
  if ! command -v mongosh &> /dev/null; then
    echo "ERROR: mongosh is not installed."
    missing=true
  fi
  
  if ! command -v dig &> /dev/null; then
    echo "ERROR: dig (dnsutils) is not installed."
    missing=true
  fi
  
  if [ "$missing" = true ]; then
    echo ""
    echo "Cloud-init may still be running. Check status with:"
    echo "  cloud-init status"
    echo "  tail -f /var/log/cloud-init-validation.log"
    echo ""
    echo "Wait for cloud-init to complete and try again."
    exit 1
  fi
}

check_prerequisites

PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0
TEST_RESULTS=""

print_header() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║  $1"
  echo "╚══════════════════════════════════════════════════════════════════════╝"
  echo ""
}

print_section() {
  echo ""
  echo "── $1 ──────────────────────────────────────────────"
  echo ""
}

record_pass() {
  PASSED_TESTS=$((PASSED_TESTS + 1))
  TEST_RESULTS="${TEST_RESULTS}✓ $1\n"
  echo "  ✓ $1"
}

record_fail() {
  FAILED_TESTS=$((FAILED_TESTS + 1))
  TEST_RESULTS="${TEST_RESULTS}✗ $1\n"
  echo "  ✗ $1"
  if [ "$STRICT_MODE" = true ]; then
    echo ""
    echo "STRICT MODE: Exiting on first failure"
    print_final_summary
    exit 1
  fi
}

record_skip() {
  SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
  TEST_RESULTS="${TEST_RESULTS}○ $1 (skipped)\n"
  echo "  ○ $1 (skipped)"
}

print_final_summary() {
  echo ""
  echo "═══════════════════════════════════════════════════════════════════════"
  echo "  VALIDATION SUMMARY"
  echo "═══════════════════════════════════════════════════════════════════════"
  echo -e "$TEST_RESULTS"
  if [ "$FAILED_TESTS" -eq 0 ] && [ "$SKIPPED_TESTS" -eq 0 ]; then
    echo "  Result: ALL PASSED"
  elif [ "$FAILED_TESTS" -gt 0 ]; then
    echo "  Result: $FAILED_TESTS failed"
  else
    echo "  Result: $SKIPPED_TESTS skipped"
  fi
  echo "═══════════════════════════════════════════════════════════════════════"
}

print_header "Atlas PrivateLink Validation"

echo "Mode: $([ "$STRICT_MODE" = true ] && echo "STRICT (fail fast)" || echo "PERMISSIVE (run all tests)")"
echo ""

# Detect connection string format
if [[ "$CONNECTION_STRING" =~ ^mongodb\+srv:// ]]; then
  IS_SRV=true
  echo "Format: SRV (mongodb+srv://)"
else
  IS_SRV=false
  echo "Format: Standard (mongodb://)"
fi

# Extract host portion from connection string
if [[ "$CONNECTION_STRING" =~ @([^/?]+) ]]; then
  HOST_PORTION="${BASH_REMATCH[1]}"
else
  HOST_PORTION=$(echo "$CONNECTION_STRING" | sed -n 's|^[a-zA-Z0-9+.-]\+://\([^@/?]*\).*|\1|p')
fi
echo "Host:   $HOST_PORTION"

# =========================================================================
# TEST 1: DNS Resolution
# =========================================================================
print_section "Test 1: DNS Resolution (Private IP Verification)"

echo "Discovering targets..."

# Build list of all targets to validate
if [ "$IS_SRV" = true ]; then
  SRV_RECORDS=$(dig +short SRV "_mongodb._tcp.$HOST_PORTION" 2>/dev/null || true)
  
  if [ -z "$SRV_RECORDS" ]; then
    echo "  WARNING: No SRV records found"
    TARGETS="$HOST_PORTION"
    TARGET_COUNT=1
  else
    # Deduplicate targets (SRV may return same host multiple times via private endpoint)
    TARGETS=$(echo "$SRV_RECORDS" | awk '{print $4}' | sed 's/\.$//' | sort -u)
    TARGET_COUNT=$(echo "$TARGETS" | wc -l | tr -d ' ')
  fi
else
  # Deduplicate standard connection string hosts
  TARGETS=$(echo "$HOST_PORTION" | tr ',' '\n' | sed 's/:[0-9]*$//' | sort -u)
  TARGET_COUNT=$(echo "$TARGETS" | wc -l | tr -d ' ')
fi

echo "  Found $TARGET_COUNT unique target(s)"
echo ""
echo "Resolving each target:"
echo ""

DNS_PASSED=0
DNS_FAILED=0
DNS_FAILED_LIST=""

for TARGET in $TARGETS; do
  IP=$(dig +short "$TARGET" 2>/dev/null | head -1)
  
  if [ -z "$IP" ]; then
    echo "  ✗ $TARGET"
    echo "    → No DNS record (Private DNS zone may not be linked)"
    DNS_FAILED=$((DNS_FAILED + 1))
    DNS_FAILED_LIST="$DNS_FAILED_LIST\n    - $TARGET (no DNS)"
    if [ "$STRICT_MODE" = true ]; then
      echo ""
      echo "STRICT MODE: Exiting on first failure"
      exit 1
    fi
  elif [[ $IP =~ ^10\. ]] || [[ $IP =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || [[ $IP =~ ^192\.168\. ]]; then
    echo "  ✓ $TARGET"
    echo "    → $IP (private)"
    DNS_PASSED=$((DNS_PASSED + 1))
  else
    echo "  ✗ $TARGET"
    echo "    → $IP (PUBLIC IP - not using PrivateLink!)"
    DNS_FAILED=$((DNS_FAILED + 1))
    DNS_FAILED_LIST="$DNS_FAILED_LIST\n    - $TARGET → $IP (public)"
    if [ "$STRICT_MODE" = true ]; then
      echo ""
      echo "STRICT MODE: Exiting on first failure"
      exit 1
    fi
  fi
done

echo ""
echo "DNS Summary: $DNS_PASSED/$TARGET_COUNT passed"

if [ "$DNS_FAILED" -eq 0 ]; then
  record_pass "DNS Resolution: All $TARGET_COUNT targets resolve to private IPs"
else
  record_fail "DNS Resolution: $DNS_FAILED/$TARGET_COUNT targets failed"
  echo -e "  Failed targets:$DNS_FAILED_LIST"
fi

# =========================================================================
# TEST 2: MongoDB Connection
# =========================================================================
print_section "Test 2: MongoDB Connection"

echo "Testing mongosh ping..."

if mongosh "$CONNECTION_STRING" --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
  record_pass "MongoDB Connection: Successfully connected"
else
  record_fail "MongoDB Connection: Failed to connect"
  echo "    Possible causes:"
  echo "    - Invalid credentials"
  echo "    - IP access list blocking connection"
  echo "    - Cluster is paused or unavailable"
fi

# =========================================================================
# TEST 3: CRUD Operations
# =========================================================================
print_section "Test 3: CRUD Operations"

echo "Running insert/read/update/delete test..."
echo ""

CRUD_OUTPUT=$(mongosh "$CONNECTION_STRING" --quiet --eval "
  try {
    db = db.getSiblingDB('validation_test');
    
    // Insert
    db.test.insertOne({_id:'crud_test', ts: new Date(), source: 'validation-vm'});
    print('  INSERT: OK');
    
    // Read
    var doc = db.test.findOne({_id:'crud_test'});
    if (!doc) throw new Error('Document not found');
    print('  READ:   OK');
    
    // Update
    db.test.updateOne({_id:'crud_test'}, {\$set: {updated: true}});
    print('  UPDATE: OK');
    
    // Delete
    db.test.deleteOne({_id:'crud_test'});
    print('  DELETE: OK');
    
    // Cleanup (drop collection instead of database - doesn't require dbAdmin role)
    db.test.drop();
    print('  CLEANUP: OK');
    
    print('__CRUD_SUCCESS__');
  } catch (e) {
    print('  ERROR: ' + e.message);
    print('__CRUD_FAILED__');
  }
" 2>&1) || true

echo "$CRUD_OUTPUT" | grep -v '__CRUD_'

if echo "$CRUD_OUTPUT" | grep -q '__CRUD_SUCCESS__'; then
  record_pass "CRUD Operations: All operations successful"
else
  record_fail "CRUD Operations: One or more operations failed"
fi

# =========================================================================
# TEST 4: Network Isolation (Optional)
# =========================================================================
if [ -n "$PUBLIC_URI" ]; then
  print_section "Test 4: Network Isolation (Public Path Blocked)"
  
  if [[ "$PUBLIC_URI" =~ @([^/?]+) ]]; then
    PUBLIC_HOST="${BASH_REMATCH[1]}"
  else
    PUBLIC_HOST="unknown"
  fi
  
  echo "Testing that public endpoint is NOT reachable: $PUBLIC_HOST"
  echo "(Public path should timeout if network isolation is working)"
  echo ""
  
  if timeout 5 mongosh "$PUBLIC_URI" --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
    record_fail "Network Isolation: Public connection SUCCEEDED (should be blocked!)"
    echo "    WARNING: VM can reach Atlas via public internet"
    echo "    Check NSG rules and routing tables"
  else
    record_pass "Network Isolation: Public connection blocked (as expected)"
  fi
fi

# =========================================================================
# TEST 5: Backup Validation (Optional - requires Atlas API credentials)
# =========================================================================
# Load Atlas config (project ID and cluster name)
ATLAS_PROJECT_ID=""
ATLAS_CLUSTER_NAME=""

if [ -f "$ATLAS_CONFIG_FILE" ]; then
  source "$ATLAS_CONFIG_FILE"
fi

# Check if Atlas CLI credentials are available via environment variables
# Using ${var:-} syntax to handle unset variables with set -u
if [ -n "${MONGODB_ATLAS_PUBLIC_API_KEY:-}" ] && [ -n "${MONGODB_ATLAS_PRIVATE_API_KEY:-}" ]; then
  print_section "Test 5: Backup Validation (Atlas CLI)"
  
  if ! command -v atlas &> /dev/null; then
    record_skip "Backup Validation: Atlas CLI not installed"
  elif [ -z "$ATLAS_PROJECT_ID" ] || [ -z "$ATLAS_CLUSTER_NAME" ]; then
    record_skip "Backup Validation: Project ID or cluster name not configured"
  else
    # Configure Atlas CLI with API keys from environment variables
    atlas config set public_api_key "$MONGODB_ATLAS_PUBLIC_API_KEY" 2>/dev/null || true
    atlas config set private_api_key "$MONGODB_ATLAS_PRIVATE_API_KEY" 2>/dev/null || true
    
    echo "Querying backup snapshots via Atlas CLI..."
    echo "  Project:  $ATLAS_PROJECT_ID"
    echo "  Cluster:  $ATLAS_CLUSTER_NAME"
    echo ""
    
    SNAPSHOT_OUTPUT=$(atlas backups snapshots list "$ATLAS_CLUSTER_NAME" \
      --projectId "$ATLAS_PROJECT_ID" \
      --output json 2>&1) || true
    
    # Check if API call succeeded (valid JSON response with totalCount)
    if echo "$SNAPSHOT_OUTPUT" | grep -q '"totalCount"'; then
      SNAPSHOT_COUNT=$(echo "$SNAPSHOT_OUTPUT" | jq '.totalCount' 2>/dev/null || echo "0")
      
      if [ "$SNAPSHOT_COUNT" -gt 0 ]; then
        record_pass "Backup Validation: Found $SNAPSHOT_COUNT snapshot(s)"
        echo ""
        echo "  Recent snapshots:"
        echo "$SNAPSHOT_OUTPUT" | jq -r '.results[:3][] | "    • \(.createdAt) - \(.snapshotType) - \(.status)"' 2>/dev/null || true
      else
        # No snapshots yet is OK for new clusters - backup API is working
        record_pass "Backup Validation: API working (no snapshots yet - cluster may be new)"
        echo "    First snapshot will be created according to backup schedule."
      fi
    elif echo "$SNAPSHOT_OUTPUT" | grep -qi "unauthorized\|forbidden\|401\|403"; then
      record_fail "Backup Validation: Authentication failed"
      echo "    Check that your API keys have Project Read Only or higher permissions."
    else
      record_fail "Backup Validation: Failed to query snapshots"
      echo "    Error: $SNAPSHOT_OUTPUT"
    fi
    
    # Check backup compliance policy (optional info)
    echo ""
    echo "  Checking backup schedule..."
    SCHEDULE_OUTPUT=$(atlas backups schedule describe "$ATLAS_CLUSTER_NAME" \
      --projectId "$ATLAS_PROJECT_ID" \
      --output json 2>&1) || true
    
    if echo "$SCHEDULE_OUTPUT" | grep -q '"clusterName"'; then
      POLICY_ITEMS=$(echo "$SCHEDULE_OUTPUT" | jq '.policies[0].policyItems | length' 2>/dev/null || echo "0")
      echo "    Backup policies configured: $POLICY_ITEMS"
      
      # Show retention info if available
      HOURLY=$(echo "$SCHEDULE_OUTPUT" | jq -r '.policies[0].policyItems[] | select(.frequencyType=="hourly") | "\(.frequencyInterval)h retention: \(.retentionValue) \(.retentionUnit)"' 2>/dev/null | head -1)
      DAILY=$(echo "$SCHEDULE_OUTPUT" | jq -r '.policies[0].policyItems[] | select(.frequencyType=="daily") | "daily retention: \(.retentionValue) \(.retentionUnit)"' 2>/dev/null | head -1)
      
      [ -n "$HOURLY" ] && echo "    $HOURLY"
      [ -n "$DAILY" ] && echo "    $DAILY"
    fi
  fi
else
  print_section "Test 5: Backup Validation (Skipped)"
  record_skip "Backup Validation: Atlas API keys not provided"
  echo ""
  echo "  To enable, set Atlas API keys:"
  echo "    export MONGODB_ATLAS_PUBLIC_API_KEY=\"key\" MONGODB_ATLAS_PRIVATE_API_KEY=\"secret\""
  echo ""
  echo "  Required permissions: Project Read Only (or higher)"
fi

# =========================================================================
# INFO: Cluster Details
# =========================================================================
print_section "Info: Cluster Details"

mongosh "$CONNECTION_STRING" --quiet --eval "
  var v = db.adminCommand('buildInfo').version;
  var h = db.adminCommand('hello');
  print('  MongoDB: ' + v + ' (' + (h.msg === 'isdbgrid' ? 'Sharded' : 'ReplicaSet') + ')');
" 2>/dev/null || echo "  (Could not retrieve cluster details)"

# =========================================================================
# FINAL SUMMARY
# =========================================================================
print_final_summary

# Exit code
if [ "$FAILED_TESTS" -gt 0 ]; then
  exit 1
else
  exit 0
fi
