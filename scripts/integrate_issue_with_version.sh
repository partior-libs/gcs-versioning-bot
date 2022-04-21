#!/bin/bash +e

## Reading action's global setting
if [[ ! -z $BASH_SOURCE ]]; then
    ACTION_BASE_DIR=$(dirname $BASH_SOURCE)
    source $(find $ACTION_BASE_DIR/.. -type f | grep general.ini)
elif [[ $(find . -type f -name general.ini | wc -l) > 0 ]]; then
    source $(find . -type f | grep general.ini)
elif [[ $(find .. -type f -name general.ini | wc -l) > 0 ]]; then
    source $(find .. -type f | grep general.ini)
else
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to find and source general.ini"
    exit 1
fi

jiraUsername=$1
jiraPassword=$2
jiraBaseUrl=$3
deltaMessage=$4
projectKey=$5
newVersion=$6

echo "[INFO] Jira base URL: $jiraBaseUrl"
echo "[INFO] Consolidated commit message: $deltaMessage"
echo "[INFO] Jira project key: $projectKey"
echo "[INFO] New version: $newVersion"

# Extract all issue keys from consolidated commit message 
function extractIssueKey() {
    deltaMessage=$1
    projectKey=$2
    for word in $deltaMessage; do
        issueKeys+=("$(echo $word | grep -i "$projectKey" | cut -d "-" --complement -f 3 | tr 'a-z' 'A-Z')")  # Grep and Convert all keys to uppercase
    done
    issueKeys=($(echo "${issueKeys[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))  # Store only distinct keys 
    echo ${issueKeys[@]} 
}

function updateIssueWithVersion() {
    local newVersion=$1
    local jiraBaseUrl=$2
    local response=""
    for issueKey in ${issueKeys[@]}; do
        response=$(curl -k -s -u $jiraUsername:$jiraPassword \
                -w "status_code:[%{http_code}]" \
                -X PUT \
                -H "Content-Type: application/json" \
                --data '{"update" : { "fixVersions":[{ "add": { "name": "'$newVersion'" }}]}}' \
                "https://$jiraBaseUrl/rest/api/2/issue/$issueKey")
                
    if [[ $? -ne 0 ]]; then
        echo "[ACTION_CURL_ERROR] $BASH_SOURCE (line:$LINENO): Error running curl to post the next version."
        echo "[DEBUG] Curl: https://$jiraBaseUrl/rest/api/2/issue/$issueKey"
        echo "$response"
        exit 1
    fi
    
    local responseStatus=$(echo $response | awk -F'status_code:' '{print $2}' | awk -F'[][]' '{print $2}')
    #echo "[INFO] responseBody: $responseBody"
    echo "[INFO] Query status code: $responseStatus"

    if [[ $responseStatus -eq 204 ]]; then
        echo "[INFO] Response status $responseStatus"
        echo "[INFO] Issue update with fix version "

    else
        echo "[ACTION_RESPONSE_ERROR] $BASH_SOURCE (line:$LINENO): Return code not 204 when updating issue with new version in jira: [$responseStatus]" 
        echo "[ERROR] $(echo $response) "
		exit 1
    fi
}

}
local issueKeys=()
extractIssueKey "$deltaMessage" "$projectKey"
updateIssueWithVersion "$newVersion" "$jiraBaseUrl"
