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
initialVersion=$7
artifactoryUsername=$8
artifactoryPassword=$9
jiraUsername=${10}
jiraPassword=${11}
jiraBaseUrl=${12}
jiraProjectKey=${13}
jiraEnabler=${14}



echo "[INFO] Branch name: $sourceBranchName"
echo "[INFO] Artifactory username: $artifactoryUsername"
echo "[INFO] Artifactory Base URL: $artifactoryBaseUrl"
echo "[INFO] Artifactory Dev Repo: $artifactoryTargetDevRepo"
echo "[INFO] Artifactory Release Repo: $artifactoryTargetRelRepo"
echo "[INFO] Target artifact group: $artifactoryTargetGroup"
echo "[INFO] Target artifact name: $artifactoryTargetArtifactName"
echo "[INFO] Initial version if empty: $initialVersion"
echo "[INFO] Jira Base URL: $jiraBaseUrl" 
echo "[INFO] Jira Project Key: $jiraProjectKey"
echo "[INFO] Jira Enabler: $jiraEnabler"


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
    local updatedContent=$(cat $targetSaveFile | head -1 | xargs)
    if [[ -z "$updatedContent" ]]; then
        echo "[INFO] Resetting $targetSaveFile..."
        if [[ "$identifierType" == "$REL_SCOPE" ]]; then
            echo "$initialVersion" > $targetSaveFile
        else
            echo "$initialVersion-$identifierType.0" > $targetSaveFile
        fi

    fi

}

function getArtifactLastVersion() {
    if [[ $jiraEnabler == true ]]; then
        getLatestVersionFromJira "$versionListFile" "$finalVersionsListFile"
        
    else
    
        getLastestVersionFromArtifactory "$artifactoryTargetDevRepo,$artifactoryTargetRelRepo" "$versionListFile"
    fi
}

function getLastestVersionFromArtifactory() {
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
            local resetVersion="$initialVersion-${DEV_V_IDENTIFIER}.0"

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

function getLatestVersionFromJira() {
local versionOutputFile=$1
local finalVersionsFile=$2
local response=""
local version=""


response=$(curl -k -s -u $jiraUsername:$jiraPassword \
				-w "status_code:[%{http_code}]" \
				-X GET \
				"$jiraBaseUrl/rest/api/latest/project/$jiraProjectKey" -o $versionOutputFile)

if [[ $? -ne 0 ]]; then
        echo "[ACTION_CURL_ERROR] $BASH_SOURCE (line:$LINENO): Error running curl to get latest version."
        echo "[DEBUG] Curl: $jiraBaseUrl/rest/api/latest/project/$jiraProjectKey"
        exit 1
fi

local responseStatus=$(echo $response | awk -F'status_code:' '{print $2}' | awk -F'[][]' '{print $2}')
    #echo "[INFO] responseBody: $responseBody"
    echo "[INFO] Query status code: $responseStatus"
	
if [[ $responseStatus -eq 200 ]]; then
	echo "response status $responseStatus"

	   versions=$( jq '.versions | .[] | select(.archived==false) | select(.name|test("^su.")) | .name' < $versionOutputFile)
	for version in ${versions[@]}; do 
			echo $version;	
	done
	
else
	echo "Error fetching version details"
	exit 1
fi

getlatestversion "$versions" "$DEV_V_IDENTIFIER"
getlatestversion "$versions" "$RC_V_IDENTIFIER"
echo "${finalVersionsList[*]}" >$finalVersionsFile
echo "$(cat $finalVersionsFile)"
}

finalVersionsList=()
finalVersionsListFile=finalversionlist.tmp
function getlatestversion() {
    local versionList=$1
    local identifier=$2
    local value=""
    local eachValue=""
    IFS=$'\n' sorted=($(sort -V -r <<<"${versions[*]}"))
    value=$(for elements in ${sorted[@]}; do  echo "$elements"; done | grep $identifier | head -1 | tr -d '"'| cut -d'-' -f 1 --complement)
    finalVersionsList+=("$value")
    #for eachValue in ${finalVersionsList[@]}; do
    #echo $eachValue
    #done
}




function checkInitialReleaseVersion() {
    local initialVersion=$1

    ## In case not set in yaml
    if [[ -z "$initialVersion" ]]; then
        echo "[WARNING] $BASH_SOURCE (line:$LINENO): Initial version is empty. Resetting to 0.0.1."
        initialVersion=0.0.1
    fi

    if [[ "$initialVersion" == *"-"* ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Incorrect initial version format. Should not contain hyphen: [$initialVersion]"
        exit 1
    fi

    if [[ ! $initialVersion =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Incorrect initial version format. Not in the required semantic format (ie: 1.0.0): [$initialVersion]"
        exit 1
    fi

}

checkInitialReleaseVersion "$initialVersion"
versionListFile=versionlist.tmp
## Get all the last 1000 versions and store into file
#Create empty file first
touch $ARTIFACT_LAST_DEV_VERSION_FILE
touch $ARTIFACT_LAST_RC_VERSION_FILE
touch $ARTIFACT_LAST_REL_VERSION_FILE
## getArtifactLastVersion "$artifactoryTargetDevRepo,$artifactoryTargetRelRepo" "$versionListFile"
getArtifactLastVersion
## Store respective version type into file
storeLatestVersionIntoFile "$versionListFile" "$DEV_V_IDENTIFIER" "$ARTIFACT_LAST_DEV_VERSION_FILE"
storeLatestVersionIntoFile "$versionListFile" "$RC_V_IDENTIFIER" "$ARTIFACT_LAST_RC_VERSION_FILE"
storeLatestVersionIntoFile "$versionListFile" "$REL_SCOPE" "$ARTIFACT_LAST_REL_VERSION_FILE"
cat $versionListFile
rm -f $versionListFile
