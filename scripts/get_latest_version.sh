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

## ANTZ TEMPORARY
# source ./test-files/mock-base-variables.sh

artifactoryBaseUrl=$1
artifactoryTargetDevRepo=$2
artifactoryTargetRelRepo=$3
artifactoryTargetGroup=$4
artifactoryTargetArtifactName=$5
sourceBranchName=$6
artifactoryUsername=$7
artifactoryPassword=$8


echo "[INFO] Branch name: $sourceBranchName"
echo "[INFO] Artifactory username: $artifactoryUsername"
echo "[INFO] Artifactory Base URL: $artifactoryBaseUrl"
echo "[INFO] Artifactory Dev Repo: $artifactoryTargetDevRepo"
echo "[INFO] Artifactory Release Repo: $artifactoryTargetRelRepo"
echo "[INFO] Target artifact group: $artifactoryTargetGroup"
echo "[INFO] Target artifact name: $artifactoryTargetArtifactName"


function storeLatestVersionIntoFile() {
    local inputList=$1
    local identifierType=$2
    local targetSaveFile=$3

    if [[ ! -f "$inputList" ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Artifact list file not found: [$inputList]"
        exit 1
    fi
    if [[ "$identifierType" == "$REL_SCOPE" ]]; then
        echo $(cat $inputList | grep -E "version" | grep -v -E "\-" | head -1 | cut -d"\"" -f4) > $targetSaveFile
    else
        echo $(cat $inputList | grep -E "version" | grep -E "\-$identifierType\." | head -1 | cut -d"\"" -f4) > $targetSaveFile
    fi

    ## If still empty, reset value

    if [[ $(cat $targetSaveFile | wc -l) -eq 0 ]]; then
        echo "[INFO] Reseting $targetSaveFile..."
        if [[ "$identifierType" == "$REL_SCOPE" ]]; then
            echo "0.0.1" > $targetSaveFile
        else
            echo "0.0.1-$identifierType.0" > $targetSaveFile
        fi

    fi

}

function getArtifactLastVersion() {
    local targetRepo=$1
    local versionOutputFile=$2
    echo "[INFO] Getting latest versions for RC, DEV and Release..."

    rm -f $versionStoreFilename
    local response=""
    response=$(curl -k -s -u $artifactoryUsername:$artifactoryPassword \
        -w "status_code:[%{http_code}]" \
        -X GET \
        "$artifactoryBaseUrl/api/search/versions?a=${artifactoryTargetArtifactName}&g=${artifactoryTargetGroup}&repos=${targetRepo}" -o $versionOutputFile)
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
    echo "$(cat $versionOutputFile)"


    if [[ $responseStatus -ne 200 ]]; then
        if (cat $versionOutputFile | grep -q "Unable to find artifact versions");then
            local resetVersion="0.0.1-${DEV_V_IDENTIFIER}.0"

            echo "[INFO] Unable to find last version. Resetting to: $resetVersion"
            echo "\"version\" : \"$resetVersion\"" > $versionOutputFile
        else
            echo "[ACTION_RESPONSE_ERROR] $BASH_SOURCE (line:$LINENO): Return code not 200 when querying latest version: [$responseStatus]" 
            echo " $(cat $versionOutputFile)" 
            exit 1
        fi
    fi

    # fi


}

versionListFile=versionlist.tmp
## Get all the last 1000 versions and store into file
#Create empty file first
touch $ARTIFACT_LAST_DEV_VERSION_FILE
touch $ARTIFACT_LAST_RC_VERSION_FILE
touch $ARTIFACT_LAST_REL_VERSION_FILE
getArtifactLastVersion "$artifactoryTargetDevRepo,$artifactoryTargetRelRepo" "$versionListFile"
## Store respective version type into file
storeLatestVersionIntoFile "$versionListFile" "$DEV_V_IDENTIFIER" "$ARTIFACT_LAST_DEV_VERSION_FILE"
storeLatestVersionIntoFile "$versionListFile" "$RC_V_IDENTIFIER" "$ARTIFACT_LAST_RC_VERSION_FILE"
storeLatestVersionIntoFile "$versionListFile" "$REL_SCOPE" "$ARTIFACT_LAST_REL_VERSION_FILE"
cat $versionListFile
rm -f $versionListFile