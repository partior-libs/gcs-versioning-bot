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

versionListFile=versionlist.tmp


echo "[INFO] Getting all versions for RC, DEV and Release from Artifactory"
    response=$(curl -k -s -u $artifactoryUsername:$artifactoryPassword \
        -w "status_code:[%{http_code}]" \
        -X GET \
        "$artifactoryBaseUrl/api/search/versions?a=${artifactoryTargetArtifactName}&g=${artifactoryTargetGroup}&repos=${targetRepo}" -o $versionListFile)
    if [[ $? -ne 0 ]]; then
        echo "[ACTION_CURL_ERROR] $BASH_SOURCE (line:$LINENO): Error running curl to get latest version."
        echo "[DEBUG] Curl: $artifactoryBaseUrl/api/search/versions?a=${artifactoryTargetArtifactName}&g=${artifactoryTargetGroup}&repos=${targetRepo}"
        exit 1
    fi
    #echo "[DEBUG] response...[$response]"
    #responseBody=$(echo $response | awk -F'status_code:' '{print $1}')
    responseStatus=$(echo $response | awk -F'status_code:' '{print $2}' | awk -F'[][]' '{print $2}')
    #echo "[INFO] responseBody: $responseBody"
    echo "[INFO] Query status code: $responseStatus"
    echo "[DEBUG] Latest [$versionOutputFile] version:"
    echo "$(cat $versionListFile)"
    
    if [[ $responseStatus -ne 200 ]]; then
        if (cat $versionListFile | grep -q "Unable to find artifact versions"); then
	createArtifactNextVersionInJira "$newVersion" "$versionIdentifier"
	fi
    else
	compareVersionsFromArtifactory "$versionListFile" "$newVersion" 
    fi
    
function compareVersionsFromArtifactory() {
    local versionOutputFile=$1
    local newVersion=$2    
    versions=$( jq  '.results | .[] | .versions' < $versionOutputFile)
    for version in "${versions[@]}"; do
        if [[ $version == $newVersion ]]; then
            echo "[ERROR] New Version already present in Artifactory "
            exit 1
    
	else
	createArtifactNextVersionInJira "$newVersion" "$versionIdentifier"
	fi
    done

}

    

function createArtifactNextVersionInJira() {
local newVersion=$1
local identifierType=$2
	
	response=$(curl -k -s -u $jiraUsername:$jiraPassword \
				-w "status_code:[%{http_code}]" \
				-X POST \
				-H "Content-Type: application/json" \
				--data '{"projectId" : $jiraProjectId,"name" : "$identifierType$newVersion","startDate" : null,"releaseDate" : null,"description" : ""}' \
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

