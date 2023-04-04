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

newVersion="$1"
commitMessageFile="$2"


function isReleaseVersion() {
    local versionInput="$1"
    # Check if version is in the format "X.Y.Z". Also need to cater prepend format "PREPEND-LABEL-X.Y.Z"
    if [[ "$versionInput" =~ ^.*[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

if (isReleaseVersion $newVersion); then
    echo "[INFO] Detected fixed release version. Trying to get commit message between tags..."
    lastVersion="v$ARTIFACT_LAST_REL_VERSION_FILE"

    commitMessage=$(git log  --pretty=format:"%s" HEAD ${lastVersion}..v${newVersion})
    if [[ $? -ne 0 ]]; then
        echo "[ACTION_CURL_WARNING] $BASH_SOURCE (line:$LINENO): Unable to get commit message between ${lastVersion}..v${newVersion}"
        echo "[DEBUG] $(echo $commitMessage)"
        exit 0
    else
        echo "[INFO] Extracting new delta commit message between ${lastVersion}..v${newVersion}"
        echo "$commitMessage" > $commitMessageFile
        echo $commitMessage
    fi
else
    echo "[INFO] $newVersion is not a released version. Skip retrieving commit message delta..."
fi