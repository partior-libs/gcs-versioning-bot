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
artifactoryTargetRepo=$2
artifactoryTargetDevRepo=$3
artifactoryTargetRelRepo=$4
artifactoryTargetGroup=$5
artifactoryTargetArtifactName=$6
sourceBranchName=$7
initialVersion=$8
artifactoryUsername=$9
artifactoryPassword=${10}
jfrogToken=${11}
jiraUsername=${12}
jiraPassword=${13}
jiraBaseUrl=${14}
jiraProjectKeyList=${15}
jiraEnabler=${16}
jiraVersionIdentifier=${17}
artifactType=${18:-default}
prependVersionLabel=${19}
excludeVersionName=${20:-latest}


echo "[INFO] Branch name: $sourceBranchName"
echo "[INFO] Artifactory username: $artifactoryUsername"
echo "[INFO] Artifactory Base URL: $artifactoryBaseUrl"
echo "[INFO] Artifactory Repo: $artifactoryTargetRepo"
echo "[INFO] Artifactory Dev Repo: $artifactoryTargetDevRepo"
echo "[INFO] Artifactory Release Repo: $artifactoryTargetRelRepo"
echo "[INFO] Target artifact group: $artifactoryTargetGroup"
echo "[INFO] Target artifact name: $artifactoryTargetArtifactName"
echo "[INFO] Initial version if empty: $initialVersion"
echo "[INFO] Jira Base URL: $jiraBaseUrl" 
echo "[INFO] Jira Project Keys: $jiraProjectKeyList"
echo "[INFO] Jira Enabler: $jiraEnabler"
echo "[INFO] Jira Version Identifier: $jiraVersionIdentifier"
echo "[INFO] Artifact Type: $artifactType"
echo "[INFO] Prepend Version: $prependVersionLabel"
echo "[INFO] Exclude Version: $excludeVersionName"



function storeLatestVersionIntoFile() {
    local inputList=$1
    local identifierType=$2
    local targetSaveFile=$3

    if [[ ! -f "$inputList" ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Artifact list file not found: [$inputList]"
        exit 1
    fi
    if [[ "$identifierType" == "$REL_SCOPE" ]]; then
        echo $(cat $inputList | grep -E "version" | grep -v -E "\-" | cut -d"\"" -f4 | sort -rV | head -1) > $targetSaveFile
    else
        echo $(cat $inputList | grep -E "version" | grep -E "\-$identifierType\." | cut -d"\"" -f4 | sort -rV | head -1) > $targetSaveFile
    fi
    ## If still empty, reset value
    local updatedContent=$(cat $targetSaveFile | head -1 | xargs)
    if [[ -z "$updatedContent" ]]; then
        echo "[INFO] Resetting $targetSaveFile..."
        local tmpPreRelVersion=$initialVersion
        ## Pick the release version from pre-release files if already generated.
        if [[ -f "$ARTIFACT_LAST_RC_VERSION_FILE" ]] && [[ "$ARTIFACT_LAST_RC_VERSION_FILE" != "$targetSaveFile" ]]; then
            tmpPreRelVersion=$(cat $ARTIFACT_LAST_RC_VERSION_FILE | cut -d"-" -f1)
        elif [[ -f "$ARTIFACT_LAST_DEV_VERSION_FILE" ]] && [[ "$ARTIFACT_LAST_DEV_VERSION_FILE" != "$targetSaveFile" ]]; then
            tmpPreRelVersion=$(cat $ARTIFACT_LAST_DEV_VERSION_FILE | cut -d"-" -f1)
        fi
        ## Adjust the version if returned version is invalid
        if [[ -z "$tmpPreRelVersion" ]]; then
            if [[ -f "$ARTIFACT_LAST_REL_VERSION_FILE" ]] && [[ ! -z $(cat $ARTIFACT_LAST_REL_VERSION_FILE) ]]; then
                tmpPreRelVersion=$(cat $ARTIFACT_LAST_REL_VERSION_FILE | xargs)
                local tmpRelMajorMinorVersion=$(echo $tmpPreRelVersion | cut -d"." -f1-2)
                local tmpRelPatchVersion=$(echo $tmpPreRelVersion | cut -d"." -f3)
                local tmpNewRelPatchVersion=$(( tmpRelPatchVersion + 1))
                tmpPreRelVersion=${tmpRelMajorMinorVersion}.${tmpNewRelPatchVersion}
            else
                tmpPreRelVersion=$initialVersion
            fi
            
        fi
        ## Decrement the patch version if pre-release patch version is greater than 0
        local tmpRelMajorMinorVersion=$(echo $tmpPreRelVersion | cut -d"." -f1-2)
        local tmpRelPatchVersion=$(echo $tmpPreRelVersion | cut -d"." -f3)
        local tmpRelVersion=${tmpRelMajorMinorVersion}.0
        if [[ $(( tmpRelPatchVersion - 1 )) -gt 0 ]]; then
            tmpRelVersion=${tmpRelMajorMinorVersion}.$(( tmpRelPatchVersion - 1))
        fi

        if [[ "$identifierType" == "$REL_SCOPE" ]]; then
            echo "$tmpRelVersion" > $targetSaveFile
        else
            echo "$tmpPreRelVersion-$identifierType.0" > $targetSaveFile
        fi 

    fi
}

function getArtifactLastVersion() {
    local versionListFile="$1"
    local jiraPojectKeyCommaList="$2"

    if [[ "$artifactType" == "docker" ]]; then
        getDockerLatestVersionFromArtifactory "$artifactoryTargetRepo,$artifactoryTargetDevRepo,$artifactoryTargetRelRepo" "$versionListFile"
    else
        getLatestVersionFromArtifactory "$artifactoryTargetRepo,$artifactoryTargetDevRepo,$artifactoryTargetRelRepo" "$versionListFile"
    fi
    
    ## Combine result from Jira if enabled
    if [[ "$jiraEnabler" == "true" ]]; then
        for eachJiraProjectKey in $(echo "${jiraPojectKeyCommaList}" | tr ',' ' '); do
            local tmpVersionFile=versionfile_$(date +%s).tmp
            getLatestVersionFromJira "$tmpVersionFile" "$jiraVersionIdentifier" "$eachJiraProjectKey"
            echo "[DEBUG] List from Jira $eachJiraProjectKey:"
            cat $tmpVersionFile
            ## combine both
            # Ensure newline
            echo "[DEBUG] Combining list with Artifactory"
            echo >> $versionListFile
            cat $tmpVersionFile >> $versionListFile
            cat $versionListFile | sort -u | grep -v "^\n" > $versionListFile.2
            mv $versionListFile.2 $versionListFile
        done
    fi
    
    ## Exclude the excluded version if it's not blank
    if [[ ! -z "$excludeVersionName" ]];
    then
        echo "[DEBUG] Clean up with exclusion"
        cat $versionListFile | grep -v "$excludeVersionName" > $versionListFile.2
        mv $versionListFile.2 $versionListFile
        echo "[DEBUG] List after cleaned up with exclusion"
        cat $versionListFile

    fi

}

function getDockerLatestVersionFromArtifactory() {
    ## Make sure targetRepo list doesnt has space
    local targetRepo=$(echo $1 | sed "s/ //g")
    local versionOutputFile=$2
    local artifactoryDockerTargetArtifactName="${artifactoryTargetArtifactName}"

    ## If artifact group not empty, form the final docker artifact name
    if [[ ! -z "$artifactoryTargetGroup" ]]; then
        artifactoryDockerTargetArtifactName="$(echo $artifactoryTargetGroup | sed "s/\./\//g")/${artifactoryTargetArtifactName}"
    fi
    rm -f $versionOutputFile
    echo "[INFO] Getting latest versions for RC, DEV and Release from Artifactory's Docker Registry..."
    local foundValidVersion=false
    for currentDockerRepo in ${targetRepo//,/ }
    do
        local tmpOutputFile=$versionOutputFile-${currentDockerRepo}
        rm -f $tmpOutputFile
        echo "[INFO] Querying docker registry $currentDockerRepo..."
        local queryPath="-w 'status_code:[%{http_code}]' \
        -X GET \
        '$artifactoryBaseUrl/api/docker/${currentDockerRepo}/v2/${artifactoryDockerTargetArtifactName}/tags/list' -o $tmpOutputFile"


        ## Check which credential to use
        local execQuery="curl -k -s -u $artifactoryUsername:$artifactoryPassword"
        if [[ ! -z "$jfrogToken" ]]; then
            execQuery="jfrog rt curl -k -s"
            queryPath="-w 'status_code:[%{http_code}]' \
                -XGET \
                '/api/docker/${currentDockerRepo}/v2/${artifactoryDockerTargetArtifactName}/tags/list' -o $tmpOutputFile"
        fi

        ## Start querying
        rm -f $versionStoreFilename
        local response=""
        response=$(sh -c "$execQuery $queryPath")
        if [[ $? -ne 0 ]]; then
            echo "[ACTION_CURL_ERROR] $BASH_SOURCE (line:$LINENO): Error running curl to get latest version."
            echo "[DEBUG] Curl: $execQuery $queryPath"
            echo "[DEBUG] $(echo $response)"
            exit 1
        fi
        #echo "[DEBUG] response...[$response]"
        #responseBody=$(echo $response | awk -F'status_code:' '{print $1}')
        local responseStatus=$(echo $response | awk -F'status_code:' '{print $2}' | awk -F'[][]' '{print $2}')
        #echo "[INFO] responseBody: $responseBody"
        echo "[INFO] Query status code: $responseStatus"
        echo "[DEBUG] Latest [$tmpOutputFile] version:"
        echo "$(cat $tmpOutputFile)"

        if [[ $responseStatus -ne 200 ]]; then
            if (cat $tmpOutputFile | grep -q "NAME_UNKNOWN");then
                echo "[INFO] Unable to find last version on registry $currentDockerRepo"
            else
                echo "[ACTION_RESPONSE_ERROR] $BASH_SOURCE (line:$LINENO): Return code not 200 when querying latest version from $currentDockerRepo: [$responseStatus]"
                echo "[DEBUG] $execQuery $queryPath" 
                exit 1
            fi
        else
            foundValidVersion=true
            cat $tmpOutputFile | jq -r ".tags[]" >> $versionOutputFile
        fi

        echo >> $versionOutputFile
        rm -f $tmpOutputFile
    done

    ## Filter out only with matching version prepend label
    filterVersionListWithPrependVersion "$versionOutputFile" "$prependVersionLabel"  "docker"

    ## Reformating final output for next stage processing
    if [[ "$foundValidVersion" == "false" ]]; then
        local resetVersion="$initialVersion-${DEV_V_IDENTIFIER}.0"
        echo "[INFO] Unable to find last version. Resetting to: $resetVersion"
        echo "\"version\" : \"$resetVersion\"" > $versionOutputFile
    else
        ## Store all versions in the same format as artifactory list
        local versions=$(cat $versionOutputFile | grep -v "^$")
        rm -f $versionOutputFile
        for eachVersion in ${versions[@]}; do 
            echo "\"version\" : \"$eachVersion\"" >> $versionOutputFile
        done
    fi
   
}

function getLatestVersionFromArtifactory() {
    local targetRepo=$1
    local versionOutputFile=$2
    echo "[INFO] Getting latest versions for RC, DEV and Release from Artifactory..."

    local queryPath="-w 'status_code:[%{http_code}]' \
        -X GET \
        '$artifactoryBaseUrl/api/search/versions?a=${artifactoryTargetArtifactName}&g=${artifactoryTargetGroup}&repos=${targetRepo}' -o $versionOutputFile"

    ## Check which credential to use
    local execQuery="curl -k -s -u $artifactoryUsername:$artifactoryPassword"
    if [[ ! -z "$jfrogToken" ]]; then
        execQuery="jfrog rt curl -k -s"
        queryPath="-w 'status_code:[%{http_code}]' \
            -XGET \
            '/api/search/versions?a=${artifactoryTargetArtifactName}&g=${artifactoryTargetGroup}&repos=${targetRepo}' -o $versionOutputFile"
    fi

    ## Start querying
    rm -f $versionStoreFilename
    local response=""
    response=$(sh -c "$execQuery $queryPath")
    if [[ $? -ne 0 ]]; then
        echo "[ACTION_CURL_ERROR] $BASH_SOURCE (line:$LINENO): Error running curl to get latest version."
        echo "[DEBUG] Curl: $execQuery $queryPath"
        echo "[DEBUG] $(echo $response)"
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
            echo "[DEBUG] $execQuery $queryPath" 
            exit 1
        fi
    fi

    echo "[INFO] Trimming redundant lines..."
    cat $versionOutputFile | grep "\"version\"" > $versionOutputFile.2
    mv $versionOutputFile.2 $versionOutputFile
      
    ## Filter out only with matching version prepend label
    filterVersionListWithPrependVersion "$versionOutputFile" "$prependVersionLabel"   
}

function getLatestVersionFromJira() {
    local versionOutputFile="$1"
    local identifierType="$2"
    local jiraProjectKey="$3"
    local response=""
    local version=""
    local tempVariable=""

    echo "[INFO] Getting all versions from Jira... "
    response=$(curl -k -s -u $jiraUsername:$jiraPassword \
                    -w "status_code:[%{http_code}]" \
                    -X GET \
                    "$jiraBaseUrl/rest/api/3/project/$jiraProjectKey/versions" -o $versionOutputFile)
    if [[ $? -ne 0 ]]; then
        echo "[ACTION_CURL_ERROR] $BASH_SOURCE (line:$LINENO): Error running curl to get latest version."
        echo "[DEBUG] Curl: $jiraBaseUrl/rest/api/3/project/$jiraProjectKey/versions"
        exit 1
    fi

    local responseStatus=$(echo $response | awk -F'status_code:' '{print $2}' | awk -F'[][]' '{print $2}')
    #echo "[INFO] responseBody: $responseBody"
    echo "[INFO] Query status code: $responseStatus"

    if [[ $responseStatus -eq 200 ]]; then
        echo "[INFO] Response status $responseStatus"
        local versionsLength=$(jq '. | length' < $versionOutputFile)
        if (($versionsLength == 0 )); then
            local resetVersion="$initialVersion-${DEV_V_IDENTIFIER}.0"

            echo "[INFO] Unable to find last version. Resetting to: $resetVersion"
            echo "\"version\" : \"$resetVersion\"" > $versionOutputFile
        else
            ## Store all versions in the same format as artifactory list
            versions=$( jq -r --arg identifierType "$identifierType_" '.[] | select(.archived==false) | select(.name|startswith($identifierType)) | .name' < $versionOutputFile)
            rm -f $versionOutputFile
            for eachVersion in ${versions[@]}; do 
                local trimVersion=$(echo $eachVersion | awk -F "${identifierType}_" '{print $2}')
                echo "\"version\" : \"$trimVersion\"" >> $versionOutputFile
            done
            ## Filter out only with matching version prepend label
            filterVersionListWithPrependVersion "$versionOutputFile" "$prependVersionLabel"
        fi

    else
        echo "[ACTION_RESPONSE_ERROR] $BASH_SOURCE (line:$LINENO): Return code not 200 when querying version list: [$responseStatus]" 
        echo "[Error] Error fetching version list from Jira"
        exit 1
    fi

    echo "[DEBUG] Latest [$versionOutputFile] version:"
    echo "$(cat $versionOutputFile)"
    
}

## Filter out only with matching version prepend label
function filterVersionListWithPrependVersion() {
    local versionOutputFile="$1"
    local inputPrependVersionLabel="$2"
    local isDockerOutput="$3"

    echo "[DEBUG] Filtering following list:"
    cat $versionOutputFile
    echo "[DEBUG] Start filtering..."
    if [[ ! -z "$inputPrependVersionLabel" ]]; then
        echo "[INFO] Filtering version list with version prepend label: $inputPrependVersionLabel"
        if [[ $(cat $versionOutputFile | grep -E "(^|\"|\s)$inputPrependVersionLabel-\<[0-9]+\.[0-9]+\.[0-9]+\>" | wc -l) -eq 0 ]]; then
            local resetVersion="$initialVersion-${DEV_V_IDENTIFIER}.0"
            echo "[INFO] No version found after filtered. Resetting to: $resetVersion"
            echo "\"version\" : \"$resetVersion\"" > $versionOutputFile
            if [[ ! -z "$isDockerOutput" ]]; then
                echo "$resetVersion" > $versionOutputFile
            fi
        else
            cat $versionOutputFile | grep -E "(^|\"|\s)$inputPrependVersionLabel-\<[0-9]+\.[0-9]+\.[0-9]+\>" > $versionOutputFile.tmp
            mv $versionOutputFile.tmp $versionOutputFile
            echo "[INFO] List of versions after filtered"
            cat $versionOutputFile
            # Remove the label
            sed -i "s/$inputPrependVersionLabel-//g" $versionOutputFile
            echo "[INFO] List of semantic versions from filtered"
            cat $versionOutputFile
        fi
    fi
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

#Create empty file first
touch $ARTIFACT_LAST_DEV_VERSION_FILE
touch $ARTIFACT_LAST_RC_VERSION_FILE
touch $ARTIFACT_LAST_REL_VERSION_FILE
## getArtifactLastVersion "$artifactoryTargetDevRepo,$artifactoryTargetRelRepo" "$versionListFile"
getArtifactLastVersion "$versionListFile" "$jiraProjectKeyList"
## Store respective version type into file
storeLatestVersionIntoFile "$versionListFile" "$DEV_V_IDENTIFIER" "$ARTIFACT_LAST_DEV_VERSION_FILE"
storeLatestVersionIntoFile "$versionListFile" "$RC_V_IDENTIFIER" "$ARTIFACT_LAST_RC_VERSION_FILE"
storeLatestVersionIntoFile "$versionListFile" "$REL_SCOPE" "$ARTIFACT_LAST_REL_VERSION_FILE"

cat $versionListFile
rm -f $versionListFile
