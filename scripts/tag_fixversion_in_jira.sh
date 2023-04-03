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

jiraUsername="${1}"
jiraPassword="${2}"
jiraBaseUrl="${3}"
jiraProjectKey="${4}"
newVersion="${5}"
jiraVersionIdentifier="${6}"
versionPrependLabel="${7}"
commitMessageFile="${8}"


echo "[INFO] Jira Base Url: $jiraBaseUrl"
echo "[INFO] Jira Project Key: $jiraProjectKey"
echo "[INFO] New Version: $newVersion"
echo "[INFO] Jira Version Identifier: $jiraVersionIdentifier"
echo "[INFO] Prepend Label: $versionPrependLabel"
echo "[INFO] Commit Message File: $commitMessageFile"


function getJiraProjectId() {
    local responseOutFile=responseOutFile.tmp
    local response=""
    response=$(curl -k -s -u $jiraUsername:$jiraPassword \
                -w "status_code:[%{http_code}]" \
                -X GET \
                -H "Content-Type: application/json" \
                "$jiraBaseUrl/rest/api/latest/project/$jiraProjectKey" -o $responseOutFile)
    if [[ $? -ne 0 ]]; then
        echo "[ACTION_CURL_ERROR] $BASH_SOURCE (line:$LINENO): Error running curl to get the project details."
        echo "[DEBUG] Curl: $jiraBaseUrl/rest/api/latest/project/$jiraProjectKey"
        echo "$response"
        return 1
    fi

    local responseStatus=$(echo $response | awk -F'status_code:' '{print $2}' | awk -F'[][]' '{print $2}')


    if [[ $responseStatus -eq 200 ]]; then
        local jiraProjectId=$(jq '.|.id' < $responseOutFile | tr -d '"' )
        echo "$jiraProjectId"
    else
        echo "[ACTION_RESPONSE_ERROR] $BASH_SOURCE (line:$LINENO): Return code not 200 when querying project details: [$responseStatus]" 
        echo "[ERROR] $(echo $response | jq '.errors | .name')"
		echo "[DEBUG] $(cat $responseOutFile)"
		return 1
    fi
    
}


function tagFixVersionInJira() {
    local jiraIssue="$1"
    local targetVersion="$2"
    local identifierType="$3"
    local prependLabel="$4"
    ## Handle prepend label
    local idenAndPrependLabel=${identifierType}_
    if [[ ! -z "$prependLabel" ]]; then
        idenAndPrependLabel="${identifierType}_${prependLabel}-"
    fi
    local finalTargetVersion="${idenAndPrependLabel}${targetVersion}"

    local response=""
    response=$(curl -k -s -u $jiraUsername:$jiraPassword \
                -w "status_code:[%{http_code}]" \
                -X PUT \
                -H "Content-Type: application/json" \
                -H "Accept: application/json" \
                --data '{"update":{"fixVersions":[{"add":{"name":"'$finalTargetVersion'"}}]}}' \
                "$jiraBaseUrl/rest/api/3/issue/$jiraIssue")
                
    if [[ $? -ne 0 ]]; then
        echo "[ACTION_CURL_ERROR] $BASH_SOURCE (line:$LINENO): Error running curl to update jira issue."
        echo "[DEBUG] Curl: $jiraBaseUrl/rest/api/3/issue/$jiraIssue"
        echo "$response"
        exit 1
    fi
    
    local responseStatus=$(echo $response | awk -F'status_code:' '{print $2}' | awk -F'[][]' '{print $2}')
    #echo "[INFO] responseBody: $responseBody"
    echo "[INFO] Query status code: $responseStatus"

    if [[ $responseStatus -eq 204 ]]; then
        echo "[INFO] Response status $responseStatus"
        echo "[INFO] Version updated: $(echo $response | awk -F'status_code:' '{print $1}' | jq ) "

    else
        echo "[ACTION_RESPONSE_ERROR] $BASH_SOURCE (line:$LINENO): Return code not 204 when updating Jira ticket $jiraIssue: [$responseStatus]" 
        echo "[ERROR] $(echo $response)"
		exit 1
    fi
}

function startTaggingFixVersion() {
    local messageFile="${1}"
    local jiraKey="${2}"
    local targetVersion="${3}"
    local identifierType="${4}"
    local prependLabel="${5}"


    local jiraListFile=jira-list.tmp

    if [[ ! -f "$messageFile" ]]; then
        echo "[INFO] Commit message file not found. Skipping.."
        return 0
    fi

    # Extract Jira ticket IDs using regex and write to file
    cat "${messageFile}" | grep -oP '([A-Z]+-[0-9]+)+' | tr '\n' ',' | sed 's/,$//' > "${jiraListFile}"
    
    # Loop through ticket IDs and do something
    for eachJiraIssue in $(cat "${jiraListFile}" | tr ',' ' '); do
        if [[ "$eachJiraIssue" =~ ^$jiraKey-[0-9]+ ]]; then
            echo "Processing Jira ticket ${eachJiraIssue}"
            tagFixVersionInJira "$eachJiraIssue" "$targetVersion" "$identifierType" "$prependLabel"
        else
            echo "[INFO] [$eachJiraIssue] not matching Jira key [$jiraKey]. Skipping.."
            continue
        fi
    done
}

jiraProjectId=$(getJiraProjectId)
if [[ $? -ne 0 ]]; then
	echo "[ERROR] $BASH_SOURCE (line:$LINENO): Error getting Jira Project ID"
	echo "[DEBUG] echo $jiraProjectId"
	exit 1
fi

startTaggingFixVersion "$commitMessageFile" "$jiraProjectKey" "$newVersion" "$jiraVersionIdentifier" "$versionPrependLabel"
echo "[INFO] Jira issue update done!"

