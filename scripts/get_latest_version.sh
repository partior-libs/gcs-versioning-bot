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
artifactType=$6
sourceBranchName=$7
artifactoryUsername=$8
artifactoryPassword=$9


echo "[INFO] Branch name: $sourceBranchName"
echo "[INFO] Artifactory username: $artifactoryUsername"
echo "[INFO] Artifactory Base URL: $artifactoryBaseUrl"
echo "[INFO] Artifactory Dev Repo: $artifactoryTargetDevRepo"
echo "[INFO] Artifactory Release Repo: $artifactoryTargetRelRepo"
echo "[INFO] Target artifact group: $artifactoryTargetGroup"
echo "[INFO] Target artifact name: $artifactoryTargetArtifactName"

function checkArtifactLastVersion() {
    local targetRepo=$1
    local versionStoreFilename=$2
    local versionLabel=$3
    local mockType=$4
    echo "[INFO] Getting latest $versionLabel version..."

    rm -f $versionStoreFilename
    local response=""
    if [[ "$MOCK_ENABLED" == "true" ]]; then  ## This is purely for providing mock data during local development
        if [[ ! -f $MOCK_FILE ]]; then
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate mock file: [$MOCK_FILE]"
            exit 1
        fi
        if [[ "$mockType" == "$DEV_SCOPE" ]]; then
            response=$(cat $MOCK_FILE | grep -E "^${MOCK_DEV_VERSION_KEYNAME}=" | cut -d"=" -f1 --complement)
            if [[ "$response" == "" ]]; then
                response=1.0.0-dev.1
            fi
        elif [[ "$mockType" == "$RC_SCOPE" ]]; then

            response=$(cat $MOCK_FILE | grep -E "^${MOCK_REL_VERSION_KEYNAME}=" | cut -d"=" -f1 --complement)
            if [[ "$response" == "" ]]; then
                response=1.0.0-rc.1
            fi
        else
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unsupported mock type: [$mockType]"
            exit 1
        fi
        echo $response > $versionStoreFilename
    else
        response=$(curl -k -s -u $artifactoryUsername:$artifactoryPassword \
            -w "status_code:[%{http_code}]" \
            -X GET \
            "$artifactoryBaseUrl/api/search/latestVersion?a=${artifactoryTargetArtifactName}&g=${artifactoryTargetGroup}&repos=${targetRepo}" -o $versionStoreFilename)
        if [[ $? -ne 0 ]]; then
            echo "[ACTION_CURL_ERROR] $BASH_SOURCE (line:$LINENO): Error running curl to get latest version."
            echo "[DEBUG] Curl: $artifactoryBaseUrl/api/search/latestVersion?a=${artifactoryTargetArtifactName}&g=${artifactoryTargetGroup}&repos=${targetRepo}"
            exit 1
        fi
            #echo "[DEBUG] response...[$response]"
        #responseBody=$(echo $response | awk -F'status_code:' '{print $1}')
        local responseStatus=$(echo $response | awk -F'status_code:' '{print $2}' | awk -F'[][]' '{print $2}')
        #echo "[INFO] responseBody: $responseBody"
        echo "[INFO] Query status code: $responseStatus"
        echo "[INFO] Latest [$versionLabel] version: $(cat $versionStoreFilename)"


        if [[ $responseStatus -ne 200 ]]; then
            if (cat $versionStoreFilename | grep -q "Unable to find artifact versions");then
                resetVersion="1.0.0"
                echo "[INFO] Unable to find last version. Resetting to: $resetVersion"
                echo $resetVersion > $versionStoreFilename
            else
                echo "[ACTION_RESPONSE_ERROR] $BASH_SOURCE (line:$LINENO): Return code not 200 when querying latest version: [$responseStatus]" 
                echo " $(cat $versionStoreFilename)" 
                exit 1
            fi
            
        fi
    fi


}

## Validate supported artifact type first. It must be handled in packaging_xxx.sh files
if [[ "$artifactType" == "tgz" ]]; then
    echo "[INFO] Supported artifact type: [$artifactType]"
else
    echo "[ERROR] Unsupported artifact type: [$artifactType]"
    exit 1
fi


checkArtifactLastVersion "$artifactoryTargetDevRepo" "$ARTIFACT_LAST_DEV_VERSION_FILE" "Dev/RC" "$DEV_SCOPE"
checkArtifactLastVersion "$artifactoryTargetRelRepo" "$ARTIFACT_LAST_REL_VERSION_FILE" "Release" "$RC_SCOPE"

# echo [DEBUG] yeah
# ./scripts/generate_package_version.sh "$artifactoryTargetArtifactName" "$sourceBranchName" "MAJOR" "TAG" "MSGTAG" "test-files/app-version.cfg"

