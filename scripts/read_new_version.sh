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

cat $ARTIFACT_NEXT_VERSION_FILE