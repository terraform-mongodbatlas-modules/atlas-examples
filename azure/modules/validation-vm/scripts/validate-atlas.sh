#!/bin/bash
# ==========================================================================
# Atlas PrivateLink Validation Script
# ==========================================================================
# Validates Atlas connectivity over PrivateLink:
#   1. MongoDB Connection - mongosh can connect
#   2. CRUD Operations - Insert/read/update/delete
#   3. Cluster Info - Version and topology
#
# Connection string is pre-configured in ~/.atlas-connection
# Run: ./validate-atlas
# Or ./validate-atlas [--strict] [connection-string]
# ==========================================================================

set -uo pipefail

CONFIG_FILE="$HOME/.atlas-connection"
STRICT_MODE=false
CONNECTION_STRING=""

print_usage() {
  echo "Usage: ./validate-atlas [OPTIONS] [connection-string]"
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
        shift
      else
        echo "ERROR: Too many arguments."
        print_usage
        exit 1
      fi
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
# TEST 1: MongoDB Connection
# =========================================================================
print_section "Test 1: MongoDB Connection"

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
# TEST 2: CRUD Operations
# =========================================================================
print_section "Test 2: CRUD Operations"

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
