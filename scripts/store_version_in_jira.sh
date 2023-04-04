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

jiraUsername="${1}"
jiraPassword="${2}"
jiraBaseUrl="${3}"
jiraPojectKeyList="${4}"
newVersion="${5}"
jiraVersionIdentifier="${6}"
versionPrependLabel="${7}"


echo "[INFO] Jira Base Url: $jiraBaseUrl"
echo "[INFO] Jira Project Keys: $jiraPojectKeyList"
echo "[INFO] New Version: $newVersion"
echo "[INFO] Jira Version Identifier: $jiraVersionIdentifier"
echo "[INFO] Prepend Label: $versionPrependLabel"

versionListFile=versionlist.tmp
projectDetails=tempfile.tmp


function getJiraProjectId() {
    local jiraProjectKey="$1"
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
    local newVersion="$1"
    local jiraVersionIdentifier="$2"
    local jiraProjectId="$3"
    local versionPrependLabel="$4"
    local jiraProjectKey="$5"

    ## Handle prepend label
    local finalPrepend=${jiraVersionIdentifier}_
    if [[ ! -z "$versionPrependLabel" ]]; then
        finalPrepend="${jiraVersionIdentifier}_${versionPrependLabel}-"
    fi

    local startDate=$(date '+%Y-%m-%d')
    local releaseDate=$(date '+%Y-%m-%d' -d "$startDate+14 days")
    local buildUrl=${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}
    local response=""
    response=$(curl -k -s -u $jiraUsername:$jiraPassword \
                -w "status_code:[%{http_code}]" \
                -X POST \
                -H "Content-Type: application/json" \
                --data '{"projectId" : "'$jiraProjectId'","name" : "'${finalPrepend}${newVersion}'","startDate" : "'$startDate'","releaseDate" : "'$releaseDate'","description" : "'$buildUrl'"}' \
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
        echo "[INFO] Version created: $(echo $response | awk -F'status_code:' '{print $1}' | jq '.') "
    else
        echo "[ACTION_RESPONSE_ERROR] $BASH_SOURCE (line:$LINENO): Return code not 201 when creating new version in jira: [$responseStatus]" 
        echo "[ERROR] $(echo $response | awk -F'status_code:' '{print $1}' | jq '.errors | .name') "
		exit 1
    fi
}

function updateJiraVersion() {
    local jiraVersionId="$1"
    local releaseVersionFlag="$2"
    local archiveVersionFlag="$3"

    local releaseDate=$(date '+%Y-%m-%d')
    local buildUrl=${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}
    local response=""
    response=$(curl -k -s -u $jiraUsername:$jiraPassword \
                -w "status_code:[%{http_code}]" \
                -X PUT \
                -H "Content-Type: application/json" \
                -H "Accept: application/json" \
                --data '{"archived" : '$archiveVersionFlag',"released" : '$releaseVersionFlag',"releaseDate" : "'$releaseDate'"}' \
                "$jiraBaseUrl/rest/api/3/version/$jiraVersionId")
                
    if [[ $? -ne 0 ]]; then
        echo "[ACTION_CURL_ERROR] $BASH_SOURCE (line:$LINENO): Error running curl to post the next version."
        echo "[DEBUG] Curl: $jiraBaseUrl/rest/api/latest/project/$jiraProjectKey"
        echo "$response"
        exit 1
    fi
    
    local responseStatus=$(echo $response | awk -F'status_code:' '{print $2}' | awk -F'[][]' '{print $2}')
    #echo "[INFO] responseBody: $responseBody"
    echo "[INFO] Query status code: $responseStatus"

    if [[ $responseStatus -eq 200 ]]; then
        echo "[INFO] Response status $responseStatus"
        echo "[INFO] Version updated: $(echo $response | awk -F'status_code:' '{print $1}' | jq ) "

    else
        echo "[ACTION_RESPONSE_ERROR] $BASH_SOURCE (line:$LINENO): Return code not 200 when updating version in jira: [$responseStatus]" 
        echo "[ERROR] $(echo $response)"
		exit 1
    fi
}

function getUnreleasedVersionsFromJira() {
    local versionOutputFile="$1"
    local identifierType="$2"
    local prependLabel="$3"
    local jiraProjectKey="$4"
    local response=""
    local version=""
    local tempVariable=""
    ## Handle prepend label
    local idenAndPrependLabel=${identifierType}_
    if [[ ! -z "$prependLabel" ]]; then
        idenAndPrependLabel="${identifierType}_${prependLabel}-"
    fi
    ## reset output file
    touch $versionOutputFile
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
            echo "[INFO] No version found. Skipping.."
            ## So downstream processing will know it's empty
            touch $versionOutputFile
            return 0
        else
            ## Store all versions in the same format as artifactory list
            echo "[INFO] idenAndPrependLabel=$idenAndPrependLabel"
            versions=$( jq -r --arg identifierType "$idenAndPrependLabel" '.[] | select(.archived==false) | select(.released==false) | select(.name|startswith($identifierType)) | [.name,.id] | join(",")' < $versionOutputFile)
            rm -f $versionOutputFile
            for eachVersionLine in ${versions[@]}; do 
                local eachVersion=$(echo $eachVersionLine | cut -d"," -f1)
                local versionId=$(echo $eachVersionLine | cut -d"," -f2)
                local trimVersion=$(echo $eachVersion | awk -F "${idenAndPrependLabel}" '{print $2}')
                echo "[DEBUG] Adding $trimVersion,$versionId..."
                echo "$trimVersion,$versionId" >> $versionOutputFile
            done
            ## If empty after filter
            if [[ ! -f "$versionOutputFile" ]]; then
                echo "[INFO] No version found after filtered. Skipping.."
                ## So downstream processing will know it's empty
                touch $versionOutputFile
                return 0
            fi
        fi

    else
        echo "[ACTION_RESPONSE_ERROR] $BASH_SOURCE (line:$LINENO): Return code not 200 when querying version list: [$responseStatus]" 
        echo "[Error] Error fetching version list from Jira"
        exit 1
    fi

    echo "[DEBUG] Latest [$versionOutputFile] version:"
    echo "$(cat $versionOutputFile)"
    
}

function startArchiveJiraVersions() {
    local currentVersion="$1"
    local identifierType="$2"
    local prependLabel="$3"
    local jiraProjectKey="$4"

    local versionFileList=jiraVersions.list
    rm -f $versionFileList
    getUnreleasedVersionsFromJira "$versionFileList" "$identifierType" "$prependLabel" "$jiraProjectKey"
    if [[ ! -f "$versionFileList" ]]; then
        echo "[WARNING] Version file not found"
        return 0
    fi
    echo "[DEBUG] versionFileList [$versionFileList]:"
    cat $versionFileList

    for eachVersionLine in $(cat $versionFileList)
    do
        local eachVersion=$(echo $eachVersionLine | cut -d"," -f1)
        local versionId=$(echo $eachVersionLine | cut -d"," -f2)
        if (isReleaseVersion $eachVersion); then
            echo "[INFO] [$eachVersion] is a released version. Updating status to released..."
            updateJiraVersion "$versionId" "true" "false"
        else
            if (versionIsGreaterThanCurrent "$currentVersion" "$eachVersion"); then
                echo "[INFO] $currentVersion is greater or equal than $eachVersion. Start archiving..."
                updateJiraVersion "$versionId" "false" "true"
            fi
        fi
    done
}

function versionIsGreaterThanCurrent() {

    local currentVersion="$1"
    local comparedVersion="$(echo $2 | grep -E -o [0-9]+\.[0-9]+\.[0-9]+)"

    if [[ $currentVersion > $comparedVersion ]] || [[ $currentVersion == $comparedVersion ]]; then
        return 0
    else
        return 1
    fi

}

function isReleaseVersion() {
    local versionInput="$1"
    # Check if version is in the format "X.Y.Z". Also need to cater prepend format "PREPEND-LABEL-X.Y.Z"
    if [[ "$versionInput" =~ ^.*[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}


for eachJiraProjectKey in $(echo "${jiraPojectKeyList}" | tr ',' ' '); do
    jiraProjectId=$(getJiraProjectId $eachJiraProjectKey)
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Error getting Jira Project ID for $eachJiraProjectKey"
        echo "[DEBUG] echo $jiraProjectId"
        exit 1
    fi
    createArtifactNextVersionInJira "$newVersion" "$jiraVersionIdentifier" "$jiraProjectId" "$versionPrependLabel" "$eachJiraProjectKey"

    if (isReleaseVersion $newVersion); then
        echo "[INFO] Detected fixed release version. Processing the versions..."
        startArchiveJiraVersions "$newVersion" "$jiraVersionIdentifier" "$versionPrependLabel" "$eachJiraProjectKey"
    else
        echo "[INFO] $newVersion is not a released version. Skip archiving..."
    fi
done







