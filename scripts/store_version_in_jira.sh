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
	local projectDetailsFile=$1
	local response=""
	response=$(curl -k -s -u $jiraUsername:$jiraPassword \
				-w "status_code:[%{http_code}]" \
				-X GET \
				-H "Content-Type: application/json" \
				"$jiraBaseUrl/rest/api/latest/project/$jiraProjectKey" -o $projectDetailsFile)
	if [[ $? -ne 0 ]]; then
		echo "[ACTION_CURL_ERROR] $BASH_SOURCE (line:$LINENO): Error running curl to get the project details."
		echo "[DEBUG] Curl: $jiraBaseUrl/rest/api/latest/project/$jiraProjectKey"
		echo "$response"
		exit 1
	fi
	
        local responseStatus=$(echo $response | awk -F'status_code:' '{print $2}' | awk -F'[][]' '{print $2}')
        #echo "[INFO] responseBody: $responseBody"
        echo "[INFO] Query status code: $responseStatus"

        if [[ $responseStatus -eq 200 ]]; then
        	echo "[INFO] Response status $responseStatus"
        	local jiraProjectId=$(jq '.|.id' < $projectDetailsFile | tr -d '"' )
		echo "Project Id::: $jiraProjectId"
		createArtifactNextVersionInJira "newVersion" "versionIdentifier" "jiraProjectId"

        else
		echo "[ACTION_RESPONSE_ERROR] $BASH_SOURCE (line:$LINENO): Return code not 200 when querying project details: [$responseStatus]" 
        	echo "[ERROR] $(echo $response | jq '.errors | .name') "

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
	echo"[INFO] Inside function"
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

        fi
}


echo "[INFO] Checking if the new version is present in the Artifactory"
response=$(curl -k -s -u $artifactoryUsername:$artifactoryPassword \
    -w "status_code:[%{http_code}]" \
    -X GET \
    "$artifactoryBaseUrl/api/search/pattern?pattern=$artifactoryTargetDevRepo:$artifactoryTargetGroup/$artifactoryTargetArtifactName/$artifactoryTargetArtifactName-$newVersion.*" -o $versionListFile)
if [[ $? -ne 0 ]]; then
	echo "[ACTION_CURL_ERROR] $BASH_SOURCE (line:$LINENO): Error running curl to get latest version."
        echo "[DEBUG] Curl: $artifactoryBaseUrl/api/search/pattern?pattern=$artifactoryTargetDevRepo:$artifactoryTargetGroup/$artifactoryTargetArtifactName/$artifactoryTargetArtifactName-$newVersion.*"
        exit 1
fi
#echo "[DEBUG] response...[$response]"
#responseBody=$(echo $response | awk -F'status_code:' '{print $1}')
responseStatus=$(echo $response | awk -F'status_code:' '{print $2}' | awk -F'[][]' '{print $2}')
#echo "[INFO] responseBody: $responseBody"
echo "[INFO] Query status code: $responseStatus"
echo "[DEBUG] Latest [$versionListFile] version:"
echo "$(cat $versionListFile)"
    
if [[ $responseStatus -eq 200 ]]; then
	if (($(jq '.files | length' < $versionListFile) == 0)); then
		getJiraProjectId "$projectDetails"
	else
		echo "[ACTION_CURL_ERROR] $BASH_SOURCE (line:$LINENO): New Version already present in Artifactory "
		echo "[ERROR] $response"
		exit 1
	fi
else
	echo "[ACTION_CURL_ERROR] $BASH_SOURCE (line:$LINENO): Response status not equal to 200"
	echo "[ERROR] $response"
	exit 1
fi



