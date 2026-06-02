#!/bin/bash

# Jira authentication resolution library.
#
# Provides resolve_jira_auth() which determines the auth method by priority:
#   1. Static Bearer token  (JIRA_OAUTH_TOKEN)
#   2. Dynamic OAuth 2.0 exchange (JIRA_CLIENT_ID + JIRA_CLIENT_SECRET)
#   3. Basic auth fallback  (JIRA_USERNAME + JIRA_PASSWORD)
#
# After a successful call, the following variables are exported:
#   JIRA_AUTH_HEADER       – full "Authorization: ..." header value
#   JIRA_EFFECTIVE_BASE_URL – base URL to use for all Jira REST calls
#                             (may differ from JIRA_BASE_URL when using dynamic OAuth)
#
# Callers must export the relevant input variables before sourcing/calling:
#   JIRA_OAUTH_TOKEN, JIRA_CLIENT_ID, JIRA_CLIENT_SECRET,
#   JIRA_USERNAME, JIRA_PASSWORD, JIRA_BASE_URL

function resolve_jira_auth() {
    local oauthToken="${JIRA_OAUTH_TOKEN:-}"
    local clientId="${JIRA_CLIENT_ID:-}"
    local clientSecret="${JIRA_CLIENT_SECRET:-}"
    local username="${JIRA_USERNAME:-}"
    local password="${JIRA_PASSWORD:-}"
    local baseUrl="${JIRA_BASE_URL:-}"

    # Priority 1: Static Bearer token
    if [[ -n "$oauthToken" ]]; then
        echo "[INFO] Jira auth: using static OAuth Bearer token"
        export JIRA_AUTH_HEADER="Authorization: Bearer $oauthToken"
        export JIRA_EFFECTIVE_BASE_URL="$baseUrl"
        return 0
    fi

    # Priority 2: Dynamic OAuth 2.0 client-credentials token exchange
    if [[ -n "$clientId" && -n "$clientSecret" ]]; then
        echo "[INFO] Jira auth: performing dynamic OAuth 2.0 token exchange"

        local tokenResponse
        tokenResponse=$(curl -s -X POST \
            "https://auth.atlassian.com/oauth/token" \
            -H "Content-Type: application/json" \
            --data "{\"grant_type\":\"client_credentials\",\"client_id\":\"$clientId\",\"client_secret\":\"$clientSecret\"}")

        if [[ $? -ne 0 ]]; then
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed to request OAuth token from Atlassian"
            return 1
        fi

        local accessToken
        accessToken=$(echo "$tokenResponse" | jq -r '.access_token // empty')
        if [[ -z "$accessToken" ]]; then
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed to extract access_token from OAuth response"
            echo "[DEBUG] Response: $tokenResponse"
            return 1
        fi

        local resourcesResponse
        resourcesResponse=$(curl -s -X GET \
            "https://api.atlassian.com/oauth/token/accessible-resources" \
            -H "Authorization: Bearer $accessToken" \
            -H "Accept: application/json")
        if [[ $? -ne 0 ]]; then
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed to retrieve accessible resources from Atlassian"
            return 1
        fi

        local cloudId
        cloudId=$(echo "$resourcesResponse" | jq -r '.[0].id // empty')
        if [[ -z "$cloudId" ]]; then
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed to extract cloud ID from accessible-resources response"
            echo "[DEBUG] Response: $resourcesResponse"
            return 1
        fi

        export JIRA_AUTH_HEADER="Authorization: Bearer $accessToken"
        export JIRA_EFFECTIVE_BASE_URL="https://api.atlassian.com/ex/jira/$cloudId"
        echo "[INFO] Jira auth: OAuth token acquired. Cloud ID: $cloudId"
        echo "[INFO] Jira effective base URL: $JIRA_EFFECTIVE_BASE_URL"
        return 0
    fi

    # Priority 3: Basic auth fallback
    if [[ -n "$username" && -n "$password" ]]; then
        echo "[INFO] Jira auth: using Basic authentication"
        export JIRA_AUTH_HEADER="Authorization: Basic $(echo -n "$username:$password" | base64 | tr -d '\n')"
        export JIRA_EFFECTIVE_BASE_URL="$baseUrl"
        return 0
    fi

    echo "[ERROR] $BASH_SOURCE (line:$LINENO): No Jira authentication method provided." \
         "Set one of: jira-oauth-token, jira-client-id+jira-client-secret, or jira-username+jira-password"
    return 1
}
