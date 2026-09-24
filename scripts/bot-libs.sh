#!/bin/bash +e

## Reading action's global setting
if [[ ! -z $BASH_SOURCE ]]; then
    ACTION_BASE_DIR=$(dirname $BASH_SOURCE)
    source $(find $ACTION_BASE_DIR/.. -type f -name general.ini)
elif [[ $(find . -type f -name general.ini | wc -l) > 0 ]]; then
    source $(find . -type f -name general.ini)
elif [[ $(find .. -type f -name general.ini | wc -l) > 0 ]]; then
    source $(find .. -type f -name general.ini)
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
        echo "matches=true" | tee -a >> $GITHUB_OUTPUT
        echo "version=${currentBranchRefenceName#v*}" | tee -a >> $GITHUB_OUTPUT
    else
        echo "matches=false" | tee -a >> $GITHUB_OUTPUT
        echo "[INFO] Skipping rebase branch setup..."
    fi
        
}

## Read one KEY=VALUE from a version config file, for example app-version.cfg:
##
##     MAJOR-VERSION=26      # a trailing comment is ignored
##     MINOR-VERSION=1
##
## Usage: getVFileValue <rulesEnabled> <vFileEnabled> <fileName> <key>
##
## Returns $VBOT_NIL when the rule is off, the file is absent, or the key is
## not present, so a caller can tell "no value" apart from an empty value.
## The key is anchored, so APP-MAJOR-VERSION cannot answer for MAJOR-VERSION.
## Keys are plain words; a key holding regular-expression characters is not
## supported.
function getVFileValue() {
    local rulesEnabled="$1"
    local rulesVFileEnabled="$2"
    local rulesVFileName="$3"
    local rulesVFileKey="$4"

    local foundValue="$VBOT_NIL"
    if [[ "$rulesEnabled" == "true" ]] && [[ "$rulesVFileEnabled" == "true" ]]; then
        if [[ -f "$rulesVFileName" ]]; then
            ## Spaces around '=' are tolerated, everything after the first '='
            ## is the value, a trailing '#' comment is cut, and the result is
            ## trimmed.
            local rawValue
            rawValue=$(grep -E "^[[:space:]]*${rulesVFileKey}[[:space:]]*=" "$rulesVFileName" \
                | head -1 | cut -d"=" -f2- | cut -d"#" -f1 \
                | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            if [[ -n "$rawValue" ]]; then
                foundValue="$rawValue"
            fi
        fi
    fi
    echo "$foundValue"
}
