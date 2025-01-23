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

function digestRebaseBranchSetup() {
    local currentBranchType="$1"
    local currentBranchRefenceName="$2"
    local rebaseBranches="$3"
    
    echo "[INFO] currentBranchType=$currentBranchType"
    echo "[INFO] currentBranchRefenceName=$currentBranchRefenceName"
    echo "[INFO] rebaseBranches=$rebaseBranches"
    
    ## If matches any of the target branches
    if (echo "$rebaseBranches" | grep -qE "(^|,|\s)+$currentBranchType(\s|$|,)+" >/dev/null ) ; then
        echo "matches=${rebaseBranchMatch}" | tee -a >> $GITHUB_OUTPUT
        echo "version=${currentBranchRefenceName#v*}" | tee -a >> $GITHUB_OUTPUT
    else
        echo "matches=false" | tee -a >> $GITHUB_OUTPUT
        echo "[INFO] Skipping rebase branch setup..."
    fi
        
}

