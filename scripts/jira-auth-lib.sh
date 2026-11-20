#!/bin/bash

# Jira authentication resolution library.
#
# Usage: resolve_jira_auth <jiraUsername> <jiraPassword> <jiraBaseUrl>
#
# Resolves the auth method by priority:
#   1. OAuth 2.0 client credentials from env vars JIRA_CLIENT_ID + JIRA_CLIENT_SECRET
#      (set them with `env:` on the step that calls the action).
#   2. OAuth 2.0 client credentials passed through the existing jira-username /
#      jira-password inputs. A username that is not an email address is treated
#      as an OAuth client ID, so callers can switch to OAuth by changing the
#      secret values only.
#   3. Basic auth with jira-username (email) + jira-password (API token).
#
# For OAuth, the Jira cloud ID is discovered from the accessible-resources API,
# unless the env var JIRA_CLOUD_ID is set.
#
# After a successful call, the following variables are exported:
#   JIRA_AUTH_HEADER        – full "Authorization: ..." header value
#   JIRA_EFFECTIVE_BASE_URL – base URL to use for all Jira REST calls
#                             (https://api.atlassian.com/ex/jira/<cloudId> for OAuth)

ATLASSIAN_OAUTH_TOKEN_URL="https://auth.atlassian.com/oauth/token"
ATLASSIAN_ACCESSIBLE_RESOURCES_URL="https://api.atlassian.com/oauth/token/accessible-resources"
ATLASSIAN_JIRA_API_BASE_URL="https://api.atlassian.com/ex/jira"

# Hide a sensitive value from GitHub Actions logs.
function _jira_auth_mask() {
    if [[ "${GITHUB_ACTIONS:-}" == "true" && -n "$1" ]]; then
        echo "::add-mask::$1"
    fi
}

function _jira_auth_oauth() {
    local jiraClientId="$1"
    local jiraClientSecret="$2"

    echo "[INFO] Jira auth: performing OAuth 2.0 client credentials token exchange"

    local requestBody tokenResponse accessToken
    requestBody=$(jq -n --arg id "$jiraClientId" --arg secret "$jiraClientSecret" \
        '{grant_type: "client_credentials", client_id: $id, client_secret: $secret}')

    if ! tokenResponse=$(curl -s -X POST "$ATLASSIAN_OAUTH_TOKEN_URL" \
            -H "Content-Type: application/json" \
            --data "$requestBody"); then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed to request OAuth token from Atlassian"
        return 1
    fi

    accessToken=$(echo "$tokenResponse" | jq -r '.access_token // empty' 2>/dev/null)
    if [[ -z "$accessToken" ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed to get access_token from OAuth response:" \
             "$(echo "$tokenResponse" | jq -r '.error_description // .error // "unknown error"' 2>/dev/null)"
        return 1
    fi
    _jira_auth_mask "$accessToken"

    local cloudId="${JIRA_CLOUD_ID:-}"
    if [[ -n "$cloudId" ]]; then
        echo "[INFO] Jira auth: using cloud ID from JIRA_CLOUD_ID"
    else
        local resourcesResponse
        if ! resourcesResponse=$(curl -s -X GET "$ATLASSIAN_ACCESSIBLE_RESOURCES_URL" \
                -H "Authorization: Bearer $accessToken" \
                -H "Accept: application/json"); then
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed to retrieve accessible resources from Atlassian"
            return 1
        fi
        cloudId=$(echo "$resourcesResponse" | jq -r '.[0].id // empty' 2>/dev/null)
        if [[ -z "$cloudId" ]]; then
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed to discover Jira cloud ID from accessible-resources response"
            return 1
        fi
        echo "[INFO] Jira auth: discovered cloud ID: $cloudId"
    fi

    export JIRA_AUTH_HEADER="Authorization: Bearer $accessToken"
    export JIRA_EFFECTIVE_BASE_URL="$ATLASSIAN_JIRA_API_BASE_URL/$cloudId"
    echo "[INFO] Jira effective base URL: $JIRA_EFFECTIVE_BASE_URL"
    return 0
}

function resolve_jira_auth() {
    local jiraUsername="${1}"
    local jiraPassword="${2}"
    local jiraBaseUrl="${3}"

    unset JIRA_AUTH_HEADER JIRA_EFFECTIVE_BASE_URL

    # Priority 1: OAuth client credentials from env vars
    if [[ -n "${JIRA_CLIENT_ID:-}" && -n "${JIRA_CLIENT_SECRET:-}" ]]; then
        echo "[INFO] Jira auth: using OAuth client credentials from JIRA_CLIENT_ID/JIRA_CLIENT_SECRET"
        _jira_auth_oauth "$JIRA_CLIENT_ID" "$JIRA_CLIENT_SECRET"
        return $?
    fi

    if [[ -n "$jiraUsername" && -n "$jiraPassword" ]]; then
        # Priority 2: OAuth client credentials via jira-username/jira-password
        if [[ "$jiraUsername" != *@* ]]; then
            echo "[INFO] Jira auth: jira-username is not an email, using it as OAuth client ID"
            _jira_auth_oauth "$jiraUsername" "$jiraPassword"
            return $?
        fi

        # Priority 3: Basic auth
        echo "[INFO] Jira auth: using Basic authentication"
        local basicToken
        basicToken=$(echo -n "$jiraUsername:$jiraPassword" | base64 | tr -d '\n')
        _jira_auth_mask "$basicToken"
        export JIRA_AUTH_HEADER="Authorization: Basic $basicToken"
        export JIRA_EFFECTIVE_BASE_URL="$jiraBaseUrl"
        return 0
    fi

    echo "[ERROR] $BASH_SOURCE (line:$LINENO): No Jira authentication method provided." \
         "Set env vars JIRA_CLIENT_ID + JIRA_CLIENT_SECRET, or inputs jira-username + jira-password"
    return 1
}
