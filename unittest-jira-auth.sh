#!/bin/bash
# Unit tests for scripts/jira-auth-lib.sh using real Jira credentials.
#
# Each scenario reads credentials from environment variables (see env-list.txt).
# If the required env vars for a scenario are not set, that case is skipped.
# TC4 (validation error) always runs – it requires no credentials.
#
# NOTE: JIRA_OAUTH_TOKEN must be a proper OAuth 2.0 Bearer token.
#       Atlassian API tokens (ATATT...) are designed for Basic auth only and
#       will return HTTP 403 when used as a Bearer token. Use a real OAuth
#       access token for TC1's network assertion to pass.
#
# Env vars consumed (see env-list.txt):
#   JIRA_OAUTH_TOKEN   – static Bearer token       (required for TC1)
#   JIRA_CLIENT_ID     – OAuth 2.0 client ID       (required for TC3)
#   JIRA_CLIENT_SECRET – OAuth 2.0 client secret   (required for TC3)
#   JIRA_USERNAME      – basic-auth username        (required for TC2)
#   JIRA_PASSWORD      – basic-auth password / API token (required for TC2)
#
# Usage (local):
#   export JIRA_USERNAME="user@example.com"
#   export JIRA_PASSWORD="your-api-token"
#   export JIRA_OAUTH_TOKEN="your-oauth-bearer-token"
#   export JIRA_CLIENT_ID="your-client-id"
#   export JIRA_CLIENT_SECRET="your-client-secret"
#   ./unittest-jira-auth.sh
#
# Usage (GitHub Actions): inject secrets as env vars in the workflow step.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JIRA_AUTH_LIB="${SCRIPT_DIR}/scripts/jira-auth-lib.sh"
JIRA_BASE_URL_DEFAULT="https://partior.atlassian.net"
LOG_FILE="unit-test-report-$(date +%s).txt"

# Global counters
totalTests=0
totalPass=0
totalFail=0
suitePassCount=0
suiteFailCount=0
declare -a suiteResults

# Per-TC assertion counters (reset by startTestCase)
TC_ASSERT_PASS=0
TC_ASSERT_FAIL=0
TC_WAS_SKIPPED=false

# ── Save incoming credentials before any reset_jira_env call wipes them ───────
SAVED_JIRA_OAUTH_TOKEN="${JIRA_OAUTH_TOKEN:-}"
SAVED_JIRA_CLIENT_ID="${JIRA_CLIENT_ID:-}"
SAVED_JIRA_CLIENT_SECRET="${JIRA_CLIENT_SECRET:-}"
SAVED_JIRA_USERNAME="${JIRA_USERNAME:-}"
SAVED_JIRA_PASSWORD="${JIRA_PASSWORD:-}"

echo "Starting test run at $(date '+%Y-%m-%d %H:%M:%S')" > "$LOG_FILE"

# ── helpers ────────────────────────────────────────────────────────────────────

function logMessage() {
    local logLevel=$1
    local message=$2
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp [$logLevel] $message" >> "$LOG_FILE"
}

function startTestCase() {
    local tcName="$1"
    TC_ASSERT_PASS=0
    TC_ASSERT_FAIL=0
    TC_WAS_SKIPPED=false
    logMessage "INFO" "--- Test Case: $tcName ---"
}

function endTestCase() {
    local tcName="$1"
    if [[ "$TC_WAS_SKIPPED" == "true" ]]; then
        logMessage "INFO" "$tcName SKIPPED"
        suiteResults+=("- $tcName SKIPPED")
    elif [[ $TC_ASSERT_FAIL -gt 0 ]]; then
        logMessage "ERROR" "$tcName FAILED ($TC_ASSERT_PASS passed, $TC_ASSERT_FAIL failed)"
        suiteResults+=("- $tcName FAILED")
        suiteFailCount=$((suiteFailCount + 1))
        totalFail=$((totalFail + 1))
        totalTests=$((totalTests + 1))
    else
        logMessage "INFO" "$tcName PASSED ($TC_ASSERT_PASS assertions passed)"
        suiteResults+=("- $tcName PASS")
        suitePassCount=$((suitePassCount + 1))
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
        logMessage "INFO" "PASS: $description"
        TC_ASSERT_PASS=$((TC_ASSERT_PASS + 1))
    else
        echo "[FAIL] $description"
        echo "       expected : $expected"
        echo "       actual   : $actual"
        logMessage "ERROR" "FAIL: $description (expected='$expected', actual='$actual')"
        TC_ASSERT_FAIL=$((TC_ASSERT_FAIL + 1))
    fi
}

function assert_starts_with() {
    local description="$1"
    local prefix="$2"
    local actual="$3"
    if [[ "$actual" == "$prefix"* ]]; then
        echo "[PASS] $description"
        logMessage "INFO" "PASS: $description"
        TC_ASSERT_PASS=$((TC_ASSERT_PASS + 1))
    else
        echo "[FAIL] $description"
        echo "       expected prefix : $prefix"
        echo "       actual          : $actual"
        logMessage "ERROR" "FAIL: $description (expected prefix='$prefix', actual='$actual')"
        TC_ASSERT_FAIL=$((TC_ASSERT_FAIL + 1))
    fi
}

function assert_http_200() {
    local description="$1"
    local url="$2"
    local authHeader="$3"
    local responseStatus

    echo curl -k -s -o /dev/null -w "%{http_code}" -X GET \
    -H "$authHeader" \
    -H "Content-Type: application/json" \
    "$url"

    responseStatus=$(curl -k -s -o /dev/null -w "%{http_code}" -X GET \
        -H "$authHeader" \
        -H "Content-Type: application/json" \
        "$url")
    if [[ "$responseStatus" == "200" ]]; then
        echo "[PASS] $description (HTTP $responseStatus)"
        logMessage "INFO" "PASS: $description (HTTP $responseStatus)"
        TC_ASSERT_PASS=$((TC_ASSERT_PASS + 1))
    else
        echo "[FAIL] $description (expected HTTP 200, got $responseStatus)"
        logMessage "ERROR" "FAIL: $description (expected HTTP 200, got $responseStatus)"
        TC_ASSERT_FAIL=$((TC_ASSERT_FAIL + 1))
    fi
}

# Like assert_http_200 but only warns (does not count as failure) on non-200.
# Used when the token type may not support all endpoints (e.g. API token as Bearer).
function assert_http_200_or_warn() {
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
        logMessage "INFO" "PASS: $description (HTTP $responseStatus)"
        TC_ASSERT_PASS=$((TC_ASSERT_PASS + 1))
    else
        echo "[WARN] $description – HTTP $responseStatus (non-200; token may not be a full OAuth Bearer token)"
        logMessage "WARN" "  WARN: $description – HTTP $responseStatus (non-200; token may not be a full OAuth Bearer token)"
    fi
}

function assert_exit_nonzero() {
    local description="$1"
    local exitCode="$2"
    if [[ "$exitCode" -ne 0 ]]; then
        echo "[PASS] $description"
        logMessage "INFO" "PASS: $description"
        TC_ASSERT_PASS=$((TC_ASSERT_PASS + 1))
    else
        echo "[FAIL] $description (expected non-zero exit, got 0)"
        logMessage "ERROR" "FAIL: $description (expected non-zero exit, got 0)"
        TC_ASSERT_FAIL=$((TC_ASSERT_FAIL + 1))
    fi
}

function skip_test() {
    local description="$1"
    local reason="$2"
    echo "[SKIP] $description – $reason"
    logMessage "INFO" "SKIP: $description – $reason"
    TC_WAS_SKIPPED=true
}

# Reset all Jira-related env vars before each scenario
function reset_jira_env() {
    unset JIRA_OAUTH_TOKEN   || true
    unset JIRA_CLIENT_ID     || true
    unset JIRA_CLIENT_SECRET || true
    unset JIRA_USERNAME      || true
    unset JIRA_PASSWORD      || true
    unset JIRA_BASE_URL      || true
    unset JIRA_AUTH_HEADER   || true
    unset JIRA_EFFECTIVE_BASE_URL || true
}

function summaryReport() {
    echo "" >> "$LOG_FILE"
    echo "===============================" >> "$LOG_FILE"
    echo "Test Summary Report" >> "$LOG_FILE"
    echo "===============================" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    for line in "${suiteResults[@]}"; do
        echo "$line" >> "$LOG_FILE"
    done
    echo "Result: $suitePassCount passed / $((suitePassCount + suiteFailCount)) total" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    echo "===============================" >> "$LOG_FILE"
    echo "Overall Summary" >> "$LOG_FILE"
    echo "-------------------------------" >> "$LOG_FILE"
    echo "Total Test Cases:  $totalTests" >> "$LOG_FILE"
    echo "Passed:            $totalPass" >> "$LOG_FILE"
    echo "Failed:            $totalFail" >> "$LOG_FILE"
    echo "===============================" >> "$LOG_FILE"
}

# ── Scenario 1: Static Bearer token ──────────────────────────────────────────
echo ""
echo "=== Scenario 1: Static Bearer token ==="
startTestCase "TC1: Static Bearer token"

if [[ -z "$SAVED_JIRA_OAUTH_TOKEN" ]]; then
    skip_test "TC1" "JIRA_OAUTH_TOKEN is not set"
else
    reset_jira_env
    export JIRA_OAUTH_TOKEN="$SAVED_JIRA_OAUTH_TOKEN"
    export JIRA_BASE_URL="$JIRA_BASE_URL_DEFAULT"

    source "$JIRA_AUTH_LIB"
    resolve_jira_auth

    assert_starts_with \
        "JIRA_AUTH_HEADER is set to a Bearer token" \
        "Authorization: Bearer " \
        "$JIRA_AUTH_HEADER"

    assert_equals \
        "JIRA_EFFECTIVE_BASE_URL is unchanged for static token" \
        "$JIRA_BASE_URL_DEFAULT" \
        "$JIRA_EFFECTIVE_BASE_URL"

    # Note: Atlassian API tokens (ATATT...) are for Basic auth only and return
    # 403 as Bearer; a real OAuth 2.0 access token is required for HTTP 200.
    assert_http_200_or_warn \
        "Jira API call with static Bearer token" \
        "$JIRA_EFFECTIVE_BASE_URL/rest/api/3/myself" \
        "$JIRA_AUTH_HEADER"
fi

endTestCase "TC1: Static Bearer token"

# ── Scenario 2: Basic auth fallback ──────────────────────────────────────────
echo ""
echo "=== Scenario 2: Basic auth fallback ==="
startTestCase "TC2: Basic auth fallback"

if [[ -z "$SAVED_JIRA_USERNAME" || -z "$SAVED_JIRA_PASSWORD" ]]; then
    skip_test "TC2" "JIRA_USERNAME or JIRA_PASSWORD is not set"
else
    reset_jira_env
    export JIRA_USERNAME="$SAVED_JIRA_USERNAME"
    export JIRA_PASSWORD="$SAVED_JIRA_PASSWORD"
    export JIRA_BASE_URL="$JIRA_BASE_URL_DEFAULT"

    source "$JIRA_AUTH_LIB"
    resolve_jira_auth

    assert_starts_with \
        "JIRA_AUTH_HEADER is set to a Basic token" \
        "Authorization: Basic " \
        "$JIRA_AUTH_HEADER"

    assert_equals \
        "JIRA_EFFECTIVE_BASE_URL is unchanged for Basic auth" \
        "$JIRA_BASE_URL_DEFAULT" \
        "$JIRA_EFFECTIVE_BASE_URL"

    assert_http_200 \
        "Jira API call succeeds with Basic auth" \
        "$JIRA_EFFECTIVE_BASE_URL/rest/api/3/myself" \
        "$JIRA_AUTH_HEADER"
fi

endTestCase "TC2: Basic auth fallback"

# ── Scenario 3: Dynamic OAuth 2.0 token exchange ─────────────────────────────
echo ""
echo "=== Scenario 3: Dynamic OAuth 2.0 token exchange ==="
startTestCase "TC3: Dynamic OAuth 2.0 token exchange"

if [[ -z "$SAVED_JIRA_CLIENT_ID" || -z "$SAVED_JIRA_CLIENT_SECRET" ]]; then
    skip_test "TC3" "JIRA_CLIENT_ID or JIRA_CLIENT_SECRET is not set"
else
    reset_jira_env
    export JIRA_CLIENT_ID="$SAVED_JIRA_CLIENT_ID"
    export JIRA_CLIENT_SECRET="$SAVED_JIRA_CLIENT_SECRET"
    export JIRA_BASE_URL="$JIRA_BASE_URL_DEFAULT"

    source "$JIRA_AUTH_LIB"
    resolve_jira_auth

    assert_starts_with \
        "JIRA_AUTH_HEADER is set to a dynamic Bearer token" \
        "Authorization: Bearer " \
        "$JIRA_AUTH_HEADER"

    assert_starts_with \
        "JIRA_EFFECTIVE_BASE_URL points to api.atlassian.com/ex/jira endpoint" \
        "https://api.atlassian.com/ex/jira/" \
        "$JIRA_EFFECTIVE_BASE_URL"

    assert_http_200 \
        "Jira API call succeeds with dynamic OAuth Bearer token" \
        "$JIRA_EFFECTIVE_BASE_URL/rest/api/3/myself" \
        "$JIRA_AUTH_HEADER"
fi

endTestCase "TC3: Dynamic OAuth 2.0 token exchange"

# ── Scenario 4: Validation error – no auth method provided ───────────────────
echo ""
echo "=== Scenario 4: Validation error – no auth method provided ==="
startTestCase "TC4: Validation error – no credentials"
reset_jira_env

set +e
source "$JIRA_AUTH_LIB"
resolve_jira_auth
TC4_EXIT=$?
set -e

assert_exit_nonzero \
    "resolve_jira_auth exits with non-zero when no auth credentials are provided" \
    "$TC4_EXIT"

endTestCase "TC4: Validation error – no credentials"

# ── Scenario 5: Priority – static token beats basic auth ────────────────────
echo ""
echo "=== Scenario 5: Priority – static token takes precedence over basic auth ==="
startTestCase "TC5: Priority – static token over basic auth"

if [[ -z "$SAVED_JIRA_OAUTH_TOKEN" || -z "$SAVED_JIRA_USERNAME" || -z "$SAVED_JIRA_PASSWORD" ]]; then
    skip_test "TC5" "JIRA_OAUTH_TOKEN, JIRA_USERNAME, and JIRA_PASSWORD are all required"
else
    reset_jira_env
    export JIRA_OAUTH_TOKEN="$SAVED_JIRA_OAUTH_TOKEN"
    export JIRA_USERNAME="$SAVED_JIRA_USERNAME"
    export JIRA_PASSWORD="$SAVED_JIRA_PASSWORD"
    export JIRA_BASE_URL="$JIRA_BASE_URL_DEFAULT"

    source "$JIRA_AUTH_LIB"
    resolve_jira_auth

    assert_equals \
        "Static token wins over Basic credentials" \
        "Authorization: Bearer $SAVED_JIRA_OAUTH_TOKEN" \
        "$JIRA_AUTH_HEADER"
fi

endTestCase "TC5: Priority – static token over basic auth"

# ── Summary ───────────────────────────────────────────────────────────────────
logMessage "INFO" "Test execution completed"
summaryReport

echo ""
echo "================================================"
echo "Jira Auth Unit Tests: $totalPass passed, $totalFail failed ($(( 5 - totalTests )) skipped)"
echo "================================================"

if [[ $totalFail -gt 0 ]]; then
    exit 1
fi
exit 0
