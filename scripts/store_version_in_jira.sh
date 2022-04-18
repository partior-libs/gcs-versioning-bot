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
jiraProjectId=${11}
newVersion=${12}
versionIdentifier=${13}


echo "[INFO] Artifatory Base Url: $artifactoryBaseUrl"
echo "[INFO] Artifactory Target Dev Repo: $artifactoryTargetDevRepo"
echo "[INFO] Artifactory Target Rel Repo: $artifactoryTargetRelRepo"
echo "[INFO] Artifactory Target Group: $artifactoryTargetGroup"
echo "[INFO] Artifactory Target Artifact Name: $artifactoryTargetArtifactName"
echo "[INFO] Artifactory Username: $artifactoryUsername"
echo "[INFO] Artifactory Password: $artifactoryPassword"
echo "[INFO] Jira Username: $jiraUsername"
echo "[INFO] Jira Password: $jiraPassword"
echo "[INFO] Jira Base Url: $jiraBaseUrl"
echo "[INFO] Jira Project ID: $jiraProjectId"
echo "[INFO] New Version: $newVersion"
echo "[INFO] Version Identifier: $versionIdentifier"

versionListFile=versionlist.tmp
    

function createArtifactNextVersionInJira() {
	local newVersion=$1
	local identifierType=$2
	local startDate=$(date '+%Y-%m-%d')
	local releaseDate=$(date '+%Y-%m-%d' -d "$startDate+15 days")
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
        	echo "response status $responseStatus"
        	echo "Version created: $response | jq '.' "

        else
        	echo "[ERROR] $response | jq '.errors | .name' "

        fi
}

if curl --head --silent --fail "$artifactoryBaseUrl/api/search/pattern?pattern=$artifactoryTargetDevRepo:$artifactoryTargetGroup/$artifactoryTargetArtifactName/$artifactoryTargetArtifactName-$newVersion.*" > /dev/null;
 then
  echo "This page exists."
 else
  echo "This page does not exist."
fi
    


