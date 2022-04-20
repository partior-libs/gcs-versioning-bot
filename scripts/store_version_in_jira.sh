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

artifactoryBaseUrl=$1
artifactoryTargetDevRepo=$2
artifactoryTargetRelRepo=$3
artifactoryTargetGroup=$4
artifactoryTargetArtifactName=$5
artifactoryUsername=$6
artifactoryPassword=$7
jiraUsername=$8
jiraPassword=$9
jiraBaseUrl=${10}
jiraProjectKey=${11}
newVersion=${12}
versionIdentifier=${13}


echo "[INFO] Artifatory Base Url: $artifactoryBaseUrl"
echo "[INFO] Artifactory Target Dev Repo: $artifactoryTargetDevRepo"
echo "[INFO] Artifactory Target Rel Repo: $artifactoryTargetRelRepo"
echo "[INFO] Artifactory Target Group: $artifactoryTargetGroup"
echo "[INFO] Artifactory Target Artifact Name: $artifactoryTargetArtifactName"
echo "[INFO] Jira Base Url: $jiraBaseUrl"
echo "[INFO] Jira Project Key: $jiraProjectKey"
echo "[INFO] New Version: $newVersion"
echo "[INFO] Version Identifier: $versionIdentifier"

versionListFile=versionlist.tmp
projectDetails=tempfile.tmp


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

function createArtifactNextVersionInJira() {
    local newVersion=$1
    local identifierType=$2
    local jiraProjectId=$3
    local startDate=$(date '+%Y-%m-%d')
    local releaseDate=$(date '+%Y-%m-%d' -d "$startDate+14 days")
    local buildUrl=${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}
    local response=""
    response=$(curl -k -s -u $jiraUsername:$jiraPassword \
                -w "status_code:[%{http_code}]" \
                -X POST \
                -H "Content-Type: application/json" \
                --data '{"projectId" : "'$jiraProjectId'","name" : "'$identifierType$newVersion'","startDate" : "'$startDate'","releaseDate" : "'$releaseDate'","description" : "'$buildUrl'"}' \
                "$jiraBaseUrl/rest/api/2/version")
                
    if [[ $? -ne 0 ]]; then
        echo "[ACTION_CURL_ERROR] $BASH_SOURCE (line:$LINENO): Error running curl to post the next version."
        echo "[DEBUG] Curl: $jiraBaseUrl/rest/api/latest/project/$jiraProjectKey"
        echo "$response"
        exit 1
    fi
    
    local responseStatus=$(echo $response | awk -F'status_code:' '{print $2}' | awk -F'[][]' '{print $2}')
    #echo "[INFO] responseBody: $responseBody"
    echo "[INFO] Query status code: $responseStatus"

    if [[ $responseStatus -eq 201 ]]; then
        echo "[INFO] Response status $responseStatus"
        echo "[INFO] Version created: $(echo $response | jq '.') "

    else
        echo "[ACTION_RESPONSE_ERROR] $BASH_SOURCE (line:$LINENO): Return code not 201 when creating new version in jira: [$responseStatus]" 
        echo "[ERROR] $(echo $response | jq '.errors | .name') "
		exit 1
    fi
}

jiraProjectId=$(getJiraProjectId)
if [[ $? -ne 0 ]]; then
	echo "[ERROR] $BASH_SOURCE (line:$LINENO): Error getting Jira Project ID"
	echo "[DEBUG] echo $jiraProjectId"
	exit 1
fi
createArtifactNextVersionInJira "$newVersion" "$versionIdentifier" "$jiraProjectId"





