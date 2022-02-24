#!/bin/bash -e

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

artifactName=$1
branchName=$(echo $2 | cut -d"/" -f1)
shortHash=$(echo $3)

lastDevVersion=$(cat $ARTIFACT_LAST_DEV_VERSION_FILE)
lastRelVersion=$(cat $ARTIFACT_LAST_REL_VERSION_FILE)

echo "[INFO] Start generating package version..."
echo "[INFO] Artifact Name: $artifactName"
echo "[INFO] Source branch: $branchName"
echo "[INFO] Last Dev version in Artifactory: $lastDevVersion"
echo "[INFO] Last Rel version in Artifactory: $lastRelVersion"

## Ensure dev and rel version are in sync
function versionCompareLessOrEqual() {
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}

currentDevSemanticVersion=$(echo $lastDevVersion | awk -F'-dev' '{print $1}')
currentRelSemanticVersion=$(echo $lastRelVersion | awk -F'-rc' '{print $1}')

versionCompareLessOrEqual $currentRelSemanticVersion $currentDevSemanticVersion $ && VERSION_VALID=$(echo "checked") || VERSION_VALID=$(echo "no")

echo "[INFO] Version validation: [$VERSION_VALID]"
if [[ "" == "no" ]]; then
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed version validation. Release/PROD version should not be ahead of Dev/RC version"
    exit 1
fi

## Start incrementing
export nextVersion=NIL
if [[ "$branchName" == "feature" ]] || [[ "$branchName" == "develop" ]] || [[ "$branchName" == "bugfix" ]]; then
    echo "[INFO] Development branch..."
    if [[ "$lastDevVersion" == *"-dev-"* ]]; then  ## For backward compatible
        currentSemanticVersion=$(echo $lastDevVersion | awk -F'-dev-' '{print $1}')
        nextDevNumber=$(( $(echo $lastDevVersion | awk -F'-dev-' '{print $2}') + 1 ))
    elif [[ "$lastDevVersion" == *"-dev"* ]]; then
        currentSemanticVersion=$(echo $lastDevVersion | awk -F'-dev' '{print $1}')
        nextDevNumber=$(( $(echo $lastDevVersion | awk -F'-dev' '{print $2}') + 1 ))
    else
        currentSemanticVersion=$(echo $lastDevVersion | awk -F'-dev' '{print $1}')
        nextDevNumber=1
    fi
    nextVersion=$currentSemanticVersion-dev$nextDevNumber
elif [[ "$branchName" == "release" ]] || [[ "$branchName" == "hotfix" ]]; then
    echo "[INFO] Release candidate branch..."
    if [[ "$lastDevVersion" == *"-rc-"* ]]; then  ## For backward compatible
        currentSemanticVersion=$(echo $lastDevVersion | awk -F'-rc-' '{print $1}')
        nextRcNumber=$(( $(echo $lastDevVersion | awk -F'-rc-' '{print $2}') + 1 ))
    elif [[ "$lastDevVersion" == *"-rc"* ]]; then
        currentSemanticVersion=$(echo $lastDevVersion | awk -F'-rc' '{print $1}')
        nextRcNumber=$(( $(echo $lastDevVersion | awk -F'-rc' '{print $2}') + 1 ))
    fi
    nextVersion=$currentSemanticVersion-rc$nextRcNumber

elif [[ "$branchName" == "main" ]] || [[ "$branchName" == "master" ]]; then
    echo "[INFO] PROD branch..."
    currentSemanticVersion=$(echo $lastRelVersion | cut -d"." -f1-2)
    nextVersion=$(( $(echo $lastRelVersion | cut -d"." -f3 | cut -d"-" -f1) + 1 ))
else
    echo "[ERROR] Unknown branch [$branchName]. Unable to auto increment."
    exit 1
fi

echo "[INFO] nextVersion = $nextVersion"
echo $artifactName-$nextVersion > $ARTIFACT_NEXT_VERSION_FILE


