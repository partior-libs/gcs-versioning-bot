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

jiraProjectId=$1

cat $ARTIFACT_NEXT_VERSION_FILE
echo $ARTIFACT_NEXT_VERSION_FILE > newversions.tmp
createArtifactNextVersionInJira "newversions.tmp" "$DEV_V_IDENTIFIER"
createArtifactNextVersionInJira "newversions.tmp" "$RC_V_IDENTIFIER"
createArtifactNextVersionInJira "newversions.tmp" "$$REL_SCOPE"


function createArtifactNextVersionInJira() {
local newVersionsFile=$1
local identifierType=$2
local versionName=$(cat $newVersionsFile | grep $identifierType)
if [[ ! -f "$newVersionsFile" ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Artifact list file not found: [$newVersionsFile]"

        exit 1
    fi
	
	response=$(curl -k -s -u $jiraUsername:$jiraPassword \
				-w "status_code:[%{http_code}]" \
				-X POST \
				-H "Content-Type: application/json" \
				--data '{"projectId" : $jiraProjectId,"name" : "$versionName","startDate" : null,"releaseDate" : null,"description" : ""}'
				"$jiraBaseUrl/rest/api/2/version")
				
	if [[ $? -ne 0 ]]; then
        echo "[ACTION_CURL_ERROR] $BASH_SOURCE (line:$LINENO): Error running curl to post the next version."
        echo "[DEBUG] Curl: $jiraBaseUrl/rest/api/latest/project/$jiraProjectKey"
        exit 1
fi

