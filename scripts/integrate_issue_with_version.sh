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

jiraUsername=$1
jiraPassword=$2
jiraBaseUrl=$3
deltaMessage=$4
projectKey=$5
newVersion=$6

echo "[INFO] Jira base URL: $jiraBaseUrl"
echo "[INFO] Consolidated commit message: $deltaMessage"
echo "[INFO] Jira project key: $projectKey"
echo "[INFO] New version: $newVersion"

function extractIssueKey() {
    deltaMessage=$1
    projectKey=$2
    local issueKeys=()
    for eachWord in $deltaMessage; do
        issueKeys+=("$(grep $projectKey)")
    done
    for key in {issueKeys[@]}; do
        echo "Issue keys:::$key"
    done
