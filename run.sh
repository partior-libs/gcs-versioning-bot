#!/bin/bash +e

function checkIsSubstring(){
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
        if [[ "$eachString" == "$subString" ]]; then
            echo "true"
            return 0
        fi
    done
    echo "false"
}