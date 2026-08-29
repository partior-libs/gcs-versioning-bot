#!/bin/bash
# Unit tests for scripts/jira-auth-lib.sh
#
# Validates all three auth resolution paths: static Bearer token, dynamic
# OAuth 2.0 token exchange, and Basic auth fallback.
#
# Env vars consumed:
#   JIRA_OAUTH_TOKEN   – static Bearer token       (required for TC1, TC5)
#   JIRA_CLIENT_ID     – OAuth 2.0 client ID       (required for TC3)
#   JIRA_CLIENT_SECRET – OAuth 2.0 client secret   (required for TC3)
#   JIRA_USERNAME      – Basic auth username        (required for TC2, TC5)
#   JIRA_API_TOKEN     – Jira API token             (required for TC2, TC5)
#   JIRA_PASSWORD      – alias for JIRA_API_TOKEN   (backward compat)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JIRA_AUTH_LIB="${SCRIPT_DIR}/scripts/jira-auth-lib.sh"
JIRA_BASE_URL_DEFAULT="https://partior.atlassian.net"
LOG_FILE="${SCRIPT_DIR}/unit-test-report-$(date +%s).txt"

# ── Load auth library once ────────────────────────────────────────────────────
if [[ ! -f "$JIRA_AUTH_LIB" ]]; then
    echo "[ERROR] Auth library not found: $JIRA_AUTH_LIB"
    exit 1
fi
# shellcheck source=scripts/jira-auth-lib.sh
source "$JIRA_AUTH_LIB"

# ── Read credentials from env vars once at startup ───────────────────────────
# JIRA_API_TOKEN takes precedence over the legacy JIRA_PASSWORD alias.
INPUT_OAUTH_TOKEN="${JIRA_OAUTH_TOKEN:-}"
INPUT_CLIENT_ID="${JIRA_CLIENT_ID:-}"
INPUT_CLIENT_SECRET="${JIRA_CLIENT_SECRET:-}"
INPUT_USERNAME="${JIRA_USERNAME:-}"
INPUT_API_TOKEN="${JIRA_API_TOKEN:-${JIRA_PASSWORD:-}}"
INPUT_BASE_URL="${JIRA_BASE_URL:-$JIRA_BASE_URL_DEFAULT}"

# ── Counters ──────────────────────────────────────────────────────────────────
totalTests=0
totalPass=0
totalFail=0
totalSkip=0
declare -a suiteResults

# Per-TC assertion counters (reset by startTestCase)
TC_ASSERT_PASS=0
TC_ASSERT_FAIL=0
TC_WAS_SKIPPED=false

echo "Starting test run at $(date '+%Y-%m-%d %H:%M:%S')" | tee "$LOG_FILE"

# ── Helper functions ──────────────────────────────────────────────────────────

function log() {
    local level="$1"; shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" >> "$LOG_FILE"
}

# Clears only the output variables exported by resolve_jira_auth so each test
# case starts from a known clean state.
function reset_output_vars() {
    unset JIRA_AUTH_HEADER        || true
    unset JIRA_EFFECTIVE_BASE_URL || true
}

function startTestCase() {
    local tcName="$1"
    TC_ASSERT_PASS=0
    TC_ASSERT_FAIL=0
    TC_WAS_SKIPPED=false
    reset_output_vars
    log "INFO" "--- Test Case: $tcName ---"
}

function endTestCase() {
    local tcName="$1"
    if [[ "$TC_WAS_SKIPPED" == "true" ]]; then
        log "INFO" "$tcName SKIPPED"
        suiteResults+=("[SKIP] $tcName")
        totalSkip=$((totalSkip + 1))
    elif [[ $TC_ASSERT_FAIL -gt 0 ]]; then
        log "ERROR" "$tcName FAILED ($TC_ASSERT_PASS passed, $TC_ASSERT_FAIL failed)"
        suiteResults+=("[FAIL] $tcName")
        totalFail=$((totalFail + 1))
        totalTests=$((totalTests + 1))
    else
        log "INFO" "$tcName PASSED ($TC_ASSERT_PASS assertions passed)"
        suiteResults+=("[PASS] $tcName")
        totalPass=$((totalPass + 1))
        totalTests=$((totalTests + 1))
    fi
}

function assert_equals() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "[PASS] $description"
        log "INFO" "PASS: $description"
        TC_ASSERT_PASS=$((TC_ASSERT_PASS + 1))
    else
        echo "[FAIL] $description"
        echo "         expected : $expected"
        echo "         actual   : $actual"
        log "ERROR" "FAIL: $description (expected='$expected', actual='$actual')"
        TC_ASSERT_FAIL=$((TC_ASSERT_FAIL + 1))
    fi
}

function assert_empty() {
    local description="$1"
    local actual="$2"
    if [[ -z "$actual" ]]; then
        echo "[PASS] $description"
        log "INFO" "PASS: $description"
        TC_ASSERT_PASS=$((TC_ASSERT_PASS + 1))
    else
        echo "[FAIL] $description (expected empty, got: $actual)"
        log "ERROR" "FAIL: $description (expected empty, got='$actual')"
        TC_ASSERT_FAIL=$((TC_ASSERT_FAIL + 1))
    fi
}

function assert_starts_with() {
    local description="$1"
    local prefix="$2"
    local actual="$3"
    if [[ "$actual" == "$prefix"* ]]; then
        echo "[PASS] $description"
        log "INFO" "PASS: $description"
        TC_ASSERT_PASS=$((TC_ASSERT_PASS + 1))
    else
        echo "[FAIL] $description"
        echo "         expected prefix : $prefix"
        echo "         actual          : $actual"
        log "ERROR" "FAIL: $description (expected prefix='$prefix', actual='$actual')"
        TC_ASSERT_FAIL=$((TC_ASSERT_FAIL + 1))
    fi
}

function assert_http_200() {
    local description="$1"
    local url="$2"
    local authHeader="$3"
    local responseStatus
    responseStatus=$(curl -k -s -o /dev/null -w "%{http_code}" -X GET \
        -H "$authHeader" \
        -H "Content-Type: application/json" \
        "$url")
    if [[ "$responseStatus" == "200" ]]; then
        echo "[PASS] $description (HTTP $responseStatus)"
        log "INFO" "PASS: $description (HTTP $responseStatus)"
        TC_ASSERT_PASS=$((TC_ASSERT_PASS + 1))
    else
        echo "[FAIL] $description (expected HTTP 200, got $responseStatus)"
        log "ERROR" "FAIL: $description (expected HTTP 200, got $responseStatus)"
        TC_ASSERT_FAIL=$((TC_ASSERT_FAIL + 1))
    fi
}

function assert_exit_nonzero() {
    local description="$1"
    local exitCode="$2"
    if [[ "$exitCode" -ne 0 ]]; then
        echo "[PASS] $description"
        log "INFO" "PASS: $description"
        TC_ASSERT_PASS=$((TC_ASSERT_PASS + 1))
    else
        echo "[FAIL] $description (expected non-zero exit, got 0)"
        log "ERROR" "FAIL: $description (expected non-zero exit, got 0)"
        TC_ASSERT_FAIL=$((TC_ASSERT_FAIL + 1))
    fi
}

function skip_test() {
    local description="$1"
    local reason="$2"
    echo "[SKIP] $description – $reason"
    log "INFO" "SKIP: $description – $reason"
    TC_WAS_SKIPPED=true
}

function printSummary() {
    local line
    {
        echo ""
        echo "==============================="
        echo "Test Summary"
        echo "==============================="
        for line in "${suiteResults[@]}"; do
            echo "  $line"
        done
        echo ""
        echo "Passed : $totalPass"
        echo "Failed : $totalFail"
        echo "Skipped: $totalSkip"
        echo "Total  : $((totalPass + totalFail + totalSkip))"
        echo "==============================="
    } | tee -a "$LOG_FILE"
}

# ── TC1: Static Bearer token ──────────────────────────────────────────────────
echo ""
echo "=== TC1: Static Bearer token ==="
startTestCase "TC1: Static Bearer token"

if [[ -z "$INPUT_OAUTH_TOKEN" ]]; then
    skip_test "TC1" "JIRA_OAUTH_TOKEN is not set"
else
    resolve_jira_auth \
        "$INPUT_OAUTH_TOKEN" "" "" "" "" "$INPUT_BASE_URL"

    assert_starts_with \
        "JIRA_AUTH_HEADER is a Bearer token" \
        "Authorization: Bearer " \
        "${JIRA_AUTH_HEADER:-}"

    assert_equals \
        "JIRA_EFFECTIVE_BASE_URL is unchanged for static token" \
        "$INPUT_BASE_URL" \
        "${JIRA_EFFECTIVE_BASE_URL:-}"

    assert_http_200 \
        "Jira API responds to static Bearer token" \
        "${JIRA_EFFECTIVE_BASE_URL:-}/rest/api/3/myself" \
        "${JIRA_AUTH_HEADER:-}"
fi

endTestCase "TC1: Static Bearer token"

# ── TC2: Basic auth fallback ──────────────────────────────────────────────────
echo ""
echo "=== TC2: Basic auth fallback ==="
startTestCase "TC2: Basic auth fallback"

if [[ -z "$INPUT_USERNAME" || -z "$INPUT_API_TOKEN" ]]; then
    skip_test "TC2" "JIRA_USERNAME or JIRA_API_TOKEN is not set"
else
    resolve_jira_auth \
        "" "" "" "$INPUT_USERNAME" "$INPUT_API_TOKEN" "$JIRA_BASE_URL_DEFAULT"

    assert_starts_with \
        "JIRA_AUTH_HEADER is a Basic token" \
        "Authorization: Basic " \
        "${JIRA_AUTH_HEADER:-}"

    assert_equals \
        "JIRA_EFFECTIVE_BASE_URL is unchanged for Basic auth" \
        "$JIRA_BASE_URL_DEFAULT" \
        "${JIRA_EFFECTIVE_BASE_URL:-}"

    assert_http_200 \
        "Jira API responds to Basic auth" \
        "${JIRA_EFFECTIVE_BASE_URL:-}/rest/api/3/myself" \
        "${JIRA_AUTH_HEADER:-}"
fi

endTestCase "TC2: Basic auth fallback"

# ── TC3: Dynamic OAuth 2.0 token exchange ────────────────────────────────────
echo ""
echo "=== TC3: Dynamic OAuth 2.0 token exchange ==="
startTestCase "TC3: Dynamic OAuth 2.0 token exchange"

if [[ -z "$INPUT_CLIENT_ID" || -z "$INPUT_CLIENT_SECRET" ]]; then
    skip_test "TC3" "JIRA_CLIENT_ID or JIRA_CLIENT_SECRET is not set"
else
    resolve_jira_auth \
        "" "$INPUT_CLIENT_ID" "$INPUT_CLIENT_SECRET" "" "" "$JIRA_BASE_URL_DEFAULT"

    assert_starts_with \
        "JIRA_AUTH_HEADER is a dynamic Bearer token" \
        "Authorization: Bearer " \
        "${JIRA_AUTH_HEADER:-}"

    assert_starts_with \
        "JIRA_EFFECTIVE_BASE_URL points to api.atlassian.com/ex/jira" \
        "https://api.atlassian.com/ex/jira/" \
        "${JIRA_EFFECTIVE_BASE_URL:-}"

    assert_http_200 \
        "Jira API responds to dynamic OAuth Bearer token" \
        "${JIRA_EFFECTIVE_BASE_URL:-}/rest/api/3/myself" \
        "${JIRA_AUTH_HEADER:-}"
fi

endTestCase "TC3: Dynamic OAuth 2.0 token exchange"

# ── TC4: Validation error – no credentials (always runs) ─────────────────────
echo ""
echo "=== TC4: Validation error – no credentials ==="
startTestCase "TC4: Validation error – no credentials"

set +e
resolve_jira_auth "" "" "" "" "" ""
TC4_EXIT=$?
set -e

assert_exit_nonzero \
    "resolve_jira_auth exits non-zero when no auth credentials are provided" \
    "$TC4_EXIT"  

assert_empty \
    "JIRA_AUTH_HEADER is not set after auth failure" \
    "${JIRA_AUTH_HEADER:-}"

assert_empty \
    "JIRA_EFFECTIVE_BASE_URL is not set after auth failure" \
    "${JIRA_EFFECTIVE_BASE_URL:-}"

endTestCase "TC4: Validation error – no credentials"

# ── TC5: Priority – static token takes precedence over basic auth ─────────────
echo ""
echo "=== TC5: Priority – static token takes precedence over basic auth ==="
startTestCase "TC5: Priority – static token over basic auth"

if [[ -z "$INPUT_OAUTH_TOKEN" || -z "$INPUT_USERNAME" || -z "$INPUT_API_TOKEN" ]]; then
    skip_test "TC5" "JIRA_OAUTH_TOKEN, JIRA_USERNAME, and JIRA_API_TOKEN are all required"
else
    resolve_jira_auth \
        "$INPUT_OAUTH_TOKEN" "" "" "$INPUT_USERNAME" "$INPUT_API_TOKEN" "$INPUT_BASE_URL"

    assert_equals \
        "Static Bearer token wins over Basic credentials" \
        "Authorization: Bearer $INPUT_OAUTH_TOKEN" \
        "${JIRA_AUTH_HEADER:-}"
fi

endTestCase "TC5: Priority – static token over basic auth"

# ── Summary ───────────────────────────────────────────────────────────────────
log "INFO" "Test execution completed"
printSummary

echo ""
echo "Report saved to: $LOG_FILE"

if [[ $totalFail -gt 0 ]]; then
    exit 1
fi
exit 0
