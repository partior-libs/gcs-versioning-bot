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

cat $ARTIFACT_NEXT_VERSION_FILE
echo $ARTIFACT_NEXT_VERSION_FILE > newversions.tmp

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
    local responseStatus=$(echo $response | awk -F'status_code:' '{print $2}' | awk -F'[][]' '{print $2}')
    #echo "[INFO] responseBody: $responseBody"
    echo "[INFO] Query status code: $responseStatus"
    echo "[DEBUG] Latest [$versionOutputFile] version:"
    echo "$(cat $versionListFile)"
    
    if [[ $responseStatus -ne 200 ]]; then
        if (cat $versionOutputFile | grep -q "Unable to find artifact versions");then
	createArtifactNextVersionInJira "$newVersionsList" "$DEV_V_IDENTIFIER"
        createArtifactNextVersionInJira "$newVersionsList" "$RC_V_IDENTIFIER"
        createArtifactNextVersionInJira "$newVersionsList" "$$REL_SCOPE"
	
	else
	compareVersionsFromArtifactory  "$versionListFile" "$newVersionsList" "$DEV_V_IDENTIFIER"
	compareVersionsFromArtifactory  "$versionListFile" "$newVersionsList" "$RC_V_IDENTIFIER"
	compareVersionsFromArtifactory  "$versionListFile" "$newVersionsList" "$REL_SCOPE"
	

function compareVersionsFromArtifactory() {
    local versionOutputFile=$1
    local newVersionsFile=$2
    local identifier=$3
    
    versions=$( jq  '.results | .[] | .versions' < $versionOutputFile)
    local newVersion=$(cat $newVersionsFile | grep $identifier)
    for version in "${array[@]}"; do
        if [[ $version == "$newVersion" ]]; then
            echo "[ERROR] New Version already present in Artifactory "
            break
    
	else
	createArtifactNextVersionInJira "$newVersionsFile" "$identifier"
    done

}
            
}

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
	echo "$response"
        exit 1
fi
}



newVersionsList=newversions.tmp
versionListFile=versionlist.tmp

