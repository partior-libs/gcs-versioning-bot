#!/bin/bash

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

currentBranch=$(echo $1 | cut -d'/' -f1)

## Check if given branch is in the comma delimited list of config branches
function validateBranch(){
    local listString=$1
    local subString=$2
    local listArray=''

    if [[ -z $listString ]] && [[ -z $subString ]]; then
        echo "true"
        return 0
    fi

    IFS=', ' read -r -a listArray <<< "$listString"
    for eachString in "${listArray[@]}";
    do 
        ## Skip empty
        if [[ -z "$eachString" ]]; then
            continue
        fi
        if [[ "$subString" == "$eachString" ]]; then
            echo "true"
            return 0
        fi
    done
    echo "false"
}

specialExcludedBranches="main,master"
configBranchesList=("$MAJOR_V_CONFIG_BRANCHES" "$MINOR_V_CONFIG_BRANCHES" "$PATCH_V_CONFIG_BRANCHES" "$RC_V_CONFIG_BRANCHES" "$DEV_V_CONFIG_BRANCHES" "$BUILD_V_CONFIG_BRANCHES" "$specialExcludedBranches" )

# Initialize an empty variable to store the joined config branches
configBranches=""

# Joining the config branches
for eachConfigBranches in "${configBranchesList[@]}"; do
    configBranches="$configBranches,$eachConfigBranches"
done

if [[ $(validateBranch "${configBranches}" "${BUILD_GH_BRANCH_NAME}") == "true" ]]; then
    echo "[INFO] Branch [${BUILD_GH_BRANCH_NAME}] found in branch configs: $configBranches"
else   
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Branch [${BUILD_GH_BRANCH_NAME}] not found in branch configs: $configBranches"
    exit 1
fi