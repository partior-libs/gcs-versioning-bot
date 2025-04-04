#!/bin/bash +e

## ANTZ TEMPORARY
# source ./test-files/mock-base-variables.sh
# source run2.sh

artifactName="$1"
currentBranch=$(echo $2 | cut -d'/' -f1)
currentLabel="$3"
currentTag="$4"
currentMsgTag="$5"
rebaseReleaseVersion="$6"
versionListFile="$7"
isDebug="$8"
unitTestEnable="${9:-false}"

# Reading action's global setting
if [[ ! "${unitTestEnable}" == "true" ]]; then
    if [[ ! -z $BASH_SOURCE && "${unitTestEnable}" ]]; then
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
fi

# Reset global state
rm -f $CORE_VERSION_UPDATED_FILE
rm -f $TRUNK_CORE_NEED_INCREMENT_FILE
echo "$VBOT_NIL" > $TRUNK_CORE_NEED_INCREMENT_FILE

## Set the current branch
export currentBranch="$currentBranch"

## Trim away the build info
lastDevVersion=$(cat $ARTIFACT_LAST_DEV_VERSION_FILE | cut -d"+" -f1)
lastRCVersion=$(cat $ARTIFACT_LAST_RC_VERSION_FILE | cut -d"+" -f1)
lastRelVersion=$(cat $ARTIFACT_LAST_REL_VERSION_FILE | cut -d"+" -f1)
lastBaseVersion=$(cat $ARTIFACT_LAST_BASE_VERSION_FILE | cut -d"+" -f1)

## Check if it's initial version
isInitialVersion=false
if [[ -f "$FLAG_FILE_IS_INITIAL_VERSION" ]]; then
    isInitialVersion=$(cat $FLAG_FILE_IS_INITIAL_VERSION)
fi

echo "[INFO] Start generating package version..."
echo "[INFO] Artifact Name: $artifactName"
echo "[INFO] Source branch: $currentBranch"
echo "[INFO] Last Dev version in Artifactory: $lastDevVersion"
echo "[INFO] Last RC version in Artifactory: $lastRCVersion"
echo "[INFO] Last Release version in Artifactory: $lastRelVersion"
echo "[INFO] Last Base version in Artifactory: $lastBaseVersion"
echo "[INFO] Target rebase release version: ${rebaseReleaseVersion}"
echo "[INFO] Is initial version?: $isInitialVersion"


## Ensure dev and rel version are in sync
function versionCompareLessOrEqual() {
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}

# When increment pre-release, make sure the release version is considered
function needToIncrementRelVersion() {
    local inputCurrentVersion=$1
    local inputRelVersion=$2
    if [[ "$inputCurrentVersion" != "$VBOT_NIL" && "$inputRelVersion" == "$VBOT_NIL" ]]; then
        echo "false"
    elif [[  "$inputRelVersion" == "$(echo $inputCurrentVersion | cut -d'-' -f1)" ]]; then
        echo "true"
    elif [[ "$inputCurrentVersion" == "`echo -e "$inputCurrentVersion\n$inputRelVersion" | sort -V | head -n1`" ]]; then
        echo "true"
    else    
        echo "false"
    fi
}

## Derive the top release version to be incremented
function getNeededIncrementReleaseVersion() {
    local devVersion=$1
    local rcVersion=$2
    local relVersion=$3

    local devIncrease=$(needToIncrementRelVersion "$devVersion" "$relVersion")
    local newRelVersion=$relVersion

    if [[ "$devIncrease" == "false" && "$devVersion" != "$VBOT_NIL" ]]; then
        newRelVersion=$(echo $devVersion | cut -d"-" -f1)
        touch $CORE_VERSION_UPDATED_FILE
    fi
    local rcIncrease=$(needToIncrementRelVersion "$rcVersion" "$newRelVersion")
    if [[ "$rcIncrease" == "false" && "$rcVersion" != "$VBOT_NIL" ]]; then
        newRelVersion=$(echo $rcVersion | cut -d"-" -f1)
        touch $CORE_VERSION_UPDATED_FILE
    fi
    ## Store the updated rel version in file for next incrementation consideration
    echo $newRelVersion > $ARTIFACT_UPDATED_REL_VERSION_FILE
    echo $newRelVersion
}

## Increment the release version based on semantic position
function incrementReleaseVersion() {
    local inputVersion=$1
    local versionPos=$2
    local incrementalCount=${3:-1}

    local versionArray=''
    IFS='. ' read -r -a versionArray <<< "$inputVersion"
    versionArray[$versionPos]=$((versionArray[$versionPos]+incrementalCount))
    if [ $versionPos -lt 2 ]; then versionArray[2]=0; fi
    if [ $versionPos -lt 1 ]; then versionArray[1]=0; fi
    local incrementedRelVersion=$(local IFS=. ; echo "${versionArray[*]}")
    # Store in a file to be used in pre-release increment consideration later
    echo $incrementedRelVersion > $ARTIFACT_UPDATED_REL_VERSION_FILE
    echo $incrementedRelVersion
}

## Increment pre-release version based on identifier
function incrementPreReleaseVersion() {
    local inputVersion=$1
    local preIdentifider=$2

    local currentSemanticVersion=''
    local trunkCoreIncrement="$(cat $TRUNK_CORE_NEED_INCREMENT_FILE)"
    ## If not pre-release, then increment the core version too
    local lastRelVersion=$(cat $ARTIFACT_LAST_REL_VERSION_FILE)
    # If present, use the updated release version
    if [[ -f $ARTIFACT_UPDATED_REL_VERSION_FILE ]]; then
        lastRelVersion=$(cat $ARTIFACT_UPDATED_REL_VERSION_FILE)
    fi
    ## Return vanilla if not found
    if [[ "$inputVersion" == "$VBOT_NIL" ]]; then
        echo "[DEBUG] Pre-release version not found. Resetting to [$lastRelVersion-$preIdentifider.1]" >&2
        echo $lastRelVersion-$preIdentifider.1
        return 0
    fi
    currentSemanticVersion=$(echo $inputVersion | grep -Po "^\d+\.\d+\.\d+-$preIdentifider")
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to increase prerelease version. Invalid inputVersion format: $inputVersion" >&2
        echo "[ERROR_MSG] $currentSemanticVersion" >&2
        exit 1
    fi
    ## Clean up identifier
    currentSemanticVersion=$(echo $currentSemanticVersion | sed "s/-$preIdentifider//g")
    local currentPrereleaseNumber=$(echo $inputVersion | awk -F"-$preIdentifider." '{print $2}')

    ## Ensure it's digit
    if [[ ! "$currentPrereleaseNumber" =~ ^[0-9]+$ ]]; then
        currentPrereleaseNumber=0
    fi
    local nextPreReleaseNumber=$(( $currentPrereleaseNumber + 1 ))

    if [[ ! "$inputVersion" == *"-"* ]]; then
        if [[ "$lastRelVersion" = "" ]]; then
            currentSemanticVersion=$(incrementReleaseVersion $currentSemanticVersion ${PATCH_POSITION})
        else  ## Increment with last release version if present
            currentSemanticVersion=$(incrementReleaseVersion $lastRelVersion ${PATCH_POSITION})
        fi
    else
        local needIncreaseVersion=$(needToIncrementRelVersion "$inputVersion" "$lastRelVersion")
        if [[ "$trunkCoreIncrement" == "false" ]]; then
            currentSemanticVersion=$lastRelVersion
            nextPreReleaseNumber=1
        elif [[ -f $CORE_VERSION_UPDATED_FILE ]]; then
            currentSemanticVersion=$lastRelVersion
            nextPreReleaseNumber=1
        elif [[ "$trunkCoreIncrement" == "true" ]] || [[ "$needIncreaseVersion" == "true" ]]; then
            currentSemanticVersion=$(incrementReleaseVersion $lastRelVersion ${PATCH_POSITION})
            nextPreReleaseNumber=1
        elif [[ "$needIncreaseVersion" == "false" ]]; then
            nextPreReleaseNumber=$(( $(echo $inputVersion | awk -F"-$preIdentifider." '{print $2}') + 1))
        fi      
    fi
    local finalPrereleaseVersion=$currentSemanticVersion-$preIdentifider.$nextPreReleaseNumber
    echo [DEBUG] getPreleaseVersionFromPostTagsCountIncrement "$finalPrereleaseVersion" "$ARTIFACT_LAST_RC_VERSION_FILE" "$preIdentifider" >&2
    finalPrereleaseVersion=$(getPreleaseVersionFromPostTagsCountIncrement $finalPrereleaseVersion $ARTIFACT_LAST_RC_VERSION_FILE $preIdentifider)
    echo [DEBUG] getPreleaseVersionFromPostTagsCountIncrement "$finalPrereleaseVersion" "$ARTIFACT_LAST_DEV_VERSION_FILE" "$preIdentifider" >&2
    finalPrereleaseVersion=$(getPreleaseVersionFromPostTagsCountIncrement $finalPrereleaseVersion $ARTIFACT_LAST_DEV_VERSION_FILE $preIdentifider)
    echo $finalPrereleaseVersion
}

function getPreleaseVersionFromPostTagsCountIncrement() {
    
    local currentIncremented=$1
    local lastVersionFile=$2
    local preIdentifider=$3

    if [[ ! -f $lastVersionFile ]]; then
        echo "[ERROR1] $BASH_SOURCE (line:$LINENO): Version file not found: $lastVersionFile"
        exit 1
    fi

    local currentSemanticVersion=''
    currentSemanticVersion=$(echo $currentIncremented | grep -Po "^\d+\.\d+\.\d+-$preIdentifider")
    if [[ $? -ne 0 ]]; then
        ## If not found matching, return the original version
        echo "$currentIncremented"
        return 0
    fi

    local currentPrereleaseNumber=''
    currentPrereleaseNumber=$(echo $currentIncremented | awk -F"-$preIdentifider." '{print $2}' | grep -Po "^\d+")
    if [[ $? -ne 0 ]]; then
        echo "[ERROR2] $BASH_SOURCE (line:$LINENO): Invalid currentIncremented format: $currentIncremented"
        echo "[ERROR_MSG] $currentPrereleaseNumber"
        exit 1
    fi

    local lastFileVersion=''
    lastFileVersion=$(cat $lastVersionFile | grep -Po "^\d+\.\d+\.\d+-$preIdentifider")
    if [[ $? -ne 0 ]]; then
        ## If not found matching, return the original version
        echo "$currentIncremented"
        return 0
    fi
    local lastVersionPrereleaseNumber=''
    lastVersionPrereleaseNumber=$(cat $lastVersionFile | awk -F"-$preIdentifider." '{print $2}' | grep -Po "^\d+")
    if [[ $? -ne 0 ]]; then
        echo "[ERROR4] $BASH_SOURCE (line:$LINENO): Invalid lastVersionFile $lastVersionFile file format: $(cat $lastVersionFile)"
        echo "[ERROR_MSG] $lastVersionPrereleaseNumber"
        exit 1
    fi

    local finalPrereleaseNumber=$currentPrereleaseNumber
    if [[ "$currentSemanticVersion" == "$lastFileVersion" ]]; then
        if [[ $currentPrereleaseNumber -gt $lastVersionPrereleaseNumber ]]; then
            finalPrereleaseNumber=$((currentPrereleaseNumber))
        elif [[ $lastVersionPrereleaseNumber -gt $currentPrereleaseNumber ]]; then
            finalPrereleaseNumber=$((lastVersionPrereleaseNumber+1))
        else
            finalPrereleaseNumber=$((finalPrereleaseNumber+1))
        fi
    fi
    echo $currentSemanticVersion.$finalPrereleaseNumber

}

## Reset variables that's not used, to simplify requirement evaluation later
function degaussCoreVersionVariables() {
    local versionScope=$1
    local tmpVariable=source-$(date +%s)-core.tmp
    rm -f $tmpVariable

    local branchEnabled=${versionScope}_V_RULE_BRANCH_ENABLED
    local labelRuleEnabled=${versionScope}_V_LABEL_RULE_ENABLED
    local tagRuleEnabled=${versionScope}_V_RULE_TAG_ENABLED
    local msgTagRuleEnabled=${versionScope}_V_RULE_MSGTAG_ENABLED
    local versionFileRuleEnabled=${versionScope}_V_RULE_VFILE_ENABLED

    local vCurrentBranch=${versionScope}_GH_CURRENT_BRANCH
    local vCurrentLabel=${versionScope}_GH_CURRENT_LABEL
    local vCurrentTag=${versionScope}_GH_CURRENT_TAG
    local vCurrentMsgTag=${versionScope}_GH_CURRENT_MSGTAG
    local vCurrentVersionFile=${versionScope}_GH_CURRENT_VFILE

    echo "export ${vCurrentBranch}=$currentBranch" >> $tmpVariable

    if [[ -f $currentLabel ]]; then 
        cat $vCurrentTag > $vCurrentLabel
        echo "export ${vCurrentLabel}=${vCurrentLabel}" >> $tmpVariable
    else 
        echo "export ${vCurrentLabel}=${currentLabel}" >> $tmpVariable
    fi

    if [[ -f $currentTag ]]; then 
        cat $vCurrentTag > $vCurrentTag
        echo "export ${vCurrentTag}=${vCurrentTag}" >> $tmpVariable
    else 
        echo "export ${vCurrentTag}=${currentTag}" >> $tmpVariable
    fi

    if [[ -f $currentMsgTag ]]; then 
        cat $currentMsgTag > $vCurrentMsgTag
        echo "export ${vCurrentMsgTag}=${vCurrentMsgTag}" >> $tmpVariable
    else 
        echo "export ${vCurrentMsgTag}=\"${currentMsgTag}\"" >> $tmpVariable
    fi


    #echo "[DEBUG] branchEnabled==>${!branchEnabled}"
    if [[ ! "${!branchEnabled}" == "true" ]]; then
        echo "export ${versionScope}_V_CONFIG_BRANCHES=false" >> $tmpVariable
        echo "export ${vCurrentBranch}=false" >> $tmpVariable
    fi
    if [[ ! "${!labelRuleEnabled}" == "true" ]]; then
        echo "export ${versionScope}_V_CONFIG_LABELS=false" >> $tmpVariable
        echo "export ${vCurrentLabel}=false" >> $tmpVariable
    fi
    if [[ ! "${!tagRuleEnabled}" == "true" ]]; then
        echo "export ${versionScope}_V_CONFIG_TAGS=false" >> $tmpVariable
        echo "export ${vCurrentTag}=false" >> $tmpVariable
    fi
    if [[ ! "${!msgTagRuleEnabled}" == "true" ]]; then
        echo "export ${versionScope}_V_CONFIG_MSGTAGS=false" >> $tmpVariable
        echo "export ${vCurrentMsgTag}=false" >> $tmpVariable
    fi
    if [[ ! "${!versionFileRuleEnabled}" == "true" ]]; then
        echo "export ${versionScope}_V_CONFIG_VFILE_NAME=false" >> $tmpVariable
        echo "export ${vCurrentVersionFile}=false" >> $tmpVariable
    fi
    source ./$tmpVariable
    cat ./$tmpVariable
    rm -f $tmpVariable
}

## Reset variables that's not used, to simplify requirement evaluation later
function degaussReleaseVersionVariables() {
    local versionScope=$1
    local tmpVariable=source-$(date +%s)-release.tmp
    rm -f $tmpVariable

    local branchEnabled=${versionScope}_V_RULE_BRANCH_ENABLED
    local versionMergeRuleEnabled=${versionScope}_V_RULE_MERGE_ENABLED

    local ghCurrentBranch=${versionScope}_GH_CURRENT_BRANCH
    local ghCurrentMerge=${versionScope}_GH_CURRENT_MERGE

    echo "export ${vCurrentBranch}=$currentBranch" >> $tmpVariable
    echo "export ${vCurrentTag}=$currentTag" >> $tmpVariable

    #echo "[DEBUG] branchEnabled==>${!branchEnabled}"
    if [[ ! "${!branchEnabled}" == "true" ]]; then
        echo "export ${versionScope}_V_CONFIG_BRANCHES=false" >> $tmpVariable
        echo "export ${vCurrentBranch}=false" >> $tmpVariable
    fi
    if [[ ! "${!versionMergeRuleEnabled}" == "true" ]]; then
        echo "export ${versionScope}_V_CONFIG_VFILE_NAME=false" >> $tmpVariable
        echo "export ${vCurrentVersionFile}=false" >> $tmpVariable
    fi
    source ./$tmpVariable
    # rm -f $tmpVariable
}

## Reset variables that's not used, to simplify requirement evaluation later
function degaussPreReleaseVersionVariables() {
    local versionScope=$1
    local tmpVariable=source-$(date +%s)-prerelease.tmp
    rm -f $tmpVariable

    local branchEnabled=${versionScope}_V_RULE_BRANCH_ENABLED
    local tagRuleEnabled=${versionScope}_V_RULE_TAG_ENABLED
    local versionFileRuleEnabled=${versionScope}_V_RULE_VFILE_ENABLED

    local vCurrentBranch=${versionScope}_GH_CURRENT_BRANCH
    local vCurrentTag=${versionScope}_GH_CURRENT_TAG
    local vCurrentVersionFile=${versionScope}_GH_CURRENT_VFILE

    echo "export ${vCurrentBranch}=$currentBranch" >> $tmpVariable
    echo "export ${vCurrentTag}=$currentTag" >> $tmpVariable

    #echo "[DEBUG] branchEnabled==>${!branchEnabled}"
    if [[ ! "${!branchEnabled}" == "true" ]]; then
        echo "export ${versionScope}_V_CONFIG_BRANCHES=false" >> $tmpVariable
        echo "export ${vCurrentBranch}=false" >> $tmpVariable
    fi
    if [[ ! "${!tagRuleEnabled}" == "true" ]]; then
        echo "export ${versionScope}_V_CONFIG_TAGS=false" >> $tmpVariable
        echo "export ${vCurrentTag}=false" >> $tmpVariable
    fi
    if [[ ! "${!versionFileRuleEnabled}" == "true" ]]; then
        echo "export ${versionScope}_V_CONFIG_VFILE_NAME=false" >> $tmpVariable
        echo "export ${vCurrentVersionFile}=false" >> $tmpVariable
    fi
    source ./$tmpVariable
    rm -f $tmpVariable
}

## Reset variables that's not used, to simplify requirement evaluation later
function degaussVersionReplacementVariables() {
    local versionScope=$1
    local tmpVariable=source-$(date +%s)-replacement.tmp
    rm -f $tmpVariable

    local branchEnabled=${versionScope}_V_RULE_BRANCH_ENABLED
    local tagRuleEnabled=${versionScope}_V_RULE_TAG_ENABLED
    local labelRuleEnabled=${versionScope}_V_RULE_LABEL_ENABLED
    local msgTagRuleEnabled=${versionScope}_V_RULE_MSGTAG_ENABLED
    local versionFileRuleEnabled=${versionScope}_V_RULE_VFILE_ENABLED

    local vCurrentBranch=${versionScope}_GH_CURRENT_BRANCH
    local vCurrentTag=${versionScope}_GH_CURRENT_TAG
    local vCurrentLabel=${versionScope}_GH_CURRENT_LABEL
    local vCurrentMsgTag=${versionScope}_GH_CURRENT_MSGTAG
    local vCurrentVersionFile=${versionScope}_GH_CURRENT_VFILE

    echo "export ${vCurrentBranch}=$currentBranch" >> $tmpVariable
    echo "export ${vCurrentTag}=$currentTag" >> $tmpVariable

    #echo "[DEBUG] branchEnabled==>${!branchEnabled}"
    if [[ ! "${!branchEnabled}" == "true" ]]; then
        echo "export ${versionScope}_V_CONFIG_BRANCHES=false" >> $tmpVariable
        echo "export ${vCurrentBranch}=false" >> $tmpVariable
    fi
    if [[ ! "${!labelRuleEnabled}" == "true" ]]; then
        echo "export ${versionScope}_V_CONFIG_LABELS=false" >> $tmpVariable
        echo "export ${vCurrentLabel}=false" >> $tmpVariable
    fi
    if [[ ! "${!msgTagRuleEnabled}" == "true" ]]; then
        echo "export ${versionScope}_V_CONFIG_MSGTAGS=false" >> $tmpVariable
        echo "export ${vCurrentMsgTag}=false" >> $tmpVariable
    fi
    if [[ ! "${!tagRuleEnabled}" == "true" ]]; then
        echo "export ${versionScope}_V_CONFIG_TAGS=false" >> $tmpVariable
        echo "export ${vCurrentTag}=false" >> $tmpVariable
    fi
    if [[ ! "${!versionFileRuleEnabled}" == "true" ]]; then
        echo "export ${versionScope}_V_CONFIG_VFILE_NAME=false" >> $tmpVariable
        echo "export ${vCurrentVersionFile}=false" >> $tmpVariable
    fi
    source ./$tmpVariable
    rm -f $tmpVariable
}

## Reset variables that's not used, to simplify requirement evaluation later
function degaussBuildVersionVariables() {
    local versionScope=$1
    local tmpVariable=source-$(date +%s)-build.tmp
    rm -f $tmpVariable

    local branchEnabled=${versionScope}_V_RULE_BRANCH_ENABLED
    local vCurrentBranch=${versionScope}_GH_CURRENT_BRANCH

    echo "export ${vCurrentBranch}=$currentBranch" >> $tmpVariable

    #echo "[DEBUG] branchEnabled==>${!branchEnabled}"
    if [[ ! "${!branchEnabled}" == "true" ]]; then
        echo "export ${versionScope}_V_CONFIG_BRANCHES=false" >> $tmpVariable
        echo "export ${vCurrentBranch}=false" >> $tmpVariable
    fi
    source ./$tmpVariable
    rm -f $tmpVariable
}


## Instead of increment with logical 1, this function allow user to pick version from defined file and keyword, to increment release version
function incrementReleaseVersionByFile() {
    local inputVersion=$1
    local versionPos=$2
    local versionScope=$3
       
    local vConfigVersionFile=${versionScope}_V_CONFIG_VFILE_NAME
    local vConfigVersionFileKey=${versionScope}_V_CONFIG_VFILE_KEY
    echo "-------------- [DEBUG]: Reading version file: [${!vConfigVersionFile}]" >&2
    if [[ ! -f ${!vConfigVersionFile} ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate version file: [${!vConfigVersionFile}]" >&2
        return 1
    fi
    local tmpVersion=$(cat ./${!vConfigVersionFile} | grep -E "^${!vConfigVersionFileKey}" 2>/dev/null | cut -d"=" -f2)
    
    if [[ -z "$tmpVersion" ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to retrieve version value using key [${!vConfigVersionFileKey}] in version file: [${!vConfigVersionFile}]" >&2
        return 1
    fi
    local versionArray=''
    IFS='. ' read -r -a versionArray <<< "$inputVersion"
    versionArray[$versionPos]=$tmpVersion
    echo $(local IFS=. ; echo "${versionArray[*]}")

}

## Instead of increment with logical 1, this function allow user to pick version from defined file and keyword, to increment pre-release version
function incrementPreReleaseVersionByFile() {
    local inputVersion=$1
    local preIdentifider=$2
    local versionScope=$3

    local vConfigVersionFileName=${versionScope}_V_CONFIG_VFILE_NAME
    local vConfigVersionFileKey=${versionScope}_V_CONFIG_VFILE_KEY

    if [[ ! -f ${!vConfigVersionFileName} ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate version file: [${!vConfigVersionFileName}]"
        return 1
    fi
    local preReleaseVersionFromFile=$(cat ./${!vConfigVersionFileName} | grep -E "^${!vConfigVersionFileKey}" 2>/dev/null | cut -d"=" -f2)

    local currentSemanticVersion=$(echo $inputVersion | awk -F"-$preIdentifider." '{print $1}')

    ## If not pre-release, then increment the core version too
    local lastRelVersion=$(cat $ARTIFACT_LAST_REL_VERSION_FILE)
    # If present, use the updated release version
    if [[ -f $ARTIFACT_UPDATED_REL_VERSION_FILE ]]; then
        lastRelVersion=$(cat $ARTIFACT_UPDATED_REL_VERSION_FILE)
    fi

    if [[ ! "$inputVersion" == *"-"* ]]; then
        if [[ "$lastRelVersion" = "" ]]; then
            currentSemanticVersion=$(incrementReleaseVersion $currentSemanticVersion ${PATCH_POSITION})
        else  ## Increment with last release version if present
            currentSemanticVersion=$(incrementReleaseVersion $lastRelVersion ${PATCH_POSITION})
        fi
    else
        local needIncreaseVersion=$(needToIncrementRelVersion "$inputVersion" "$lastRelVersion")
        if [[ -f $CORE_VERSION_UPDATED_FILE ]]; then
            currentSemanticVersion=$lastRelVersion
            nextPreReleaseNumber=1
        elif [[ "$needIncreaseVersion" == "true" ]]; then
            currentSemanticVersion=$(incrementReleaseVersion $lastRelVersion ${PATCH_POSITION})
        fi       
    fi

    echo $currentSemanticVersion-$preIdentifider.$preReleaseVersionFromFile
}


## Check if given substring is in the comma delimited list
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
        if [[ "$subString" == *"$eachString"* ]]; then
            echo "true"
            return 0
        fi
    done
    echo "false"
}

## Check if given comma delimited string is in the content of a file
function checkListIsSubstringInFileContent () {
    local listString=$1
    local fileContentPath=$2
    local listArray=''

    if [[ -z $listString ]] && [[ -z $fileContentPath ]]; then
        echo "true"
        return 0
    fi

    if [[ ! -f $fileContentPath ]]; then
        echo $(checkIsSubstring "$listString" "$fileContentPath")
        return 0
    fi

    IFS=', ' read -r -a listArray <<< "$listString"
    for eachString in "${listArray[@]}";
    do 
        if (grep -q "$eachString" $fileContentPath); then
            echo "true"
            return 0
        fi
    done
    echo "false"
}

## Check if required flags for incrementing Release version (Major, Minor or Patch) is enabled
function checkReleaseVersionFeatureFlag() {
    local versionScope=$1
    
    local vRulesEnabled=${versionScope}_V_RULES_ENABLED
    local vConfigBranches=${versionScope}_V_CONFIG_BRANCHES
    local ghCurrentBranch=${versionScope}_GH_CURRENT_BRANCH
    local vConfigLabels=${versionScope}_V_CONFIG_LABELS
    local ghCurrentLabel=${versionScope}_GH_CURRENT_LABEL
    local vConfigTags=${versionScope}_V_CONFIG_TAGS
    local ghCurrentTag=${versionScope}_GH_CURRENT_TAG
    local vConfigMsgTags=${versionScope}_V_CONFIG_MSGTAGS
    local ghCurrentMsgTag=${versionScope}_GH_CURRENT_MSGTAG

    # if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): VERSIONING_BOT_ENABLED=$VERSIONING_BOT_ENABLED" >&2; 
    # if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): \${!vRulesEnabled}=${!vRulesEnabled}" >&2; 
    # if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO):" checkIsSubstring=$(checkIsSubstring "${!vConfigBranches}" "${!ghCurrentBranch}") >&2; 
    # if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO):" checkListIsSubstringInFileContent=$(checkListIsSubstringInFileContent "${!vConfigLabels}" "${!ghCurrentLabel}") >&2; 
    # if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO):" checkListIsSubstringInFileContent=$(checkListIsSubstringInFileContent "${!vConfigTags}" ${!ghCurrentTag}) >&2; 
    # if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO):" checkListIsSubstringInFileContent=$(checkListIsSubstringInFileContent "${!vConfigMsgTags}" "${!ghCurrentMsgTag}") >&2; 

    if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && [[ "${!vRulesEnabled}" == "true" ]] && [[ $(checkIsSubstring "${!vConfigBranches}" "${!ghCurrentBranch}") == "true" ]] && [[ $(checkListIsSubstringInFileContent "${!vConfigLabels}" "${!ghCurrentLabel}") == "true" ]] && [[ $(checkListIsSubstringInFileContent "${!vConfigTags}" "${!ghCurrentTag}") == "true" ]] && [[ $(checkListIsSubstringInFileContent "${!vConfigMsgTags}" "${!ghCurrentMsgTag}") == "true" ]]; then
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): checkReleaseVersionFeatureFlag=true" >&2; fi
        echo "true"
    else
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): checkReleaseVersionFeatureFlag=false" >&2; fi
        echo "false"
    fi
}

## Check if required flags for incrementing Pre-Release version (Dev or RC) is enabled
function checkPreReleaseVersionFeatureFlag() {
    local versionScope=$1
    
    local vRulesEnabled=${versionScope}_V_RULES_ENABLED
    local vConfigBranches=${versionScope}_V_CONFIG_BRANCHES
    local ghCurrentBranch=${versionScope}_GH_CURRENT_BRANCH
    local vConfigTags=${versionScope}_V_CONFIG_TAGS
    local ghCurrentTag=${versionScope}_GH_CURRENT_TAG

    ##if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && [[ "${!vRulesEnabled}" == "true" ]] &&  [[ $(checkIsSubstring "${!vConfigBranches}" "${!ghCurrentBranch}") == "true" ]] && [[ $(checkListIsSubstringInFileContent "${!vConfigTags}" "${!ghCurrentTag}") == "true" ]] && [[ ! "$(checkReleaseVersionFeatureFlag ${MAJOR_SCOPE})" == "true" ]] && [[ ! "$(checkReleaseVersionFeatureFlag ${MINOR_SCOPE})" == "true" ]] && [[ ! "$(checkReleaseVersionFeatureFlag ${PATCH_SCOPE})" == "true" ]]; then
    ## echo [antz22] "VERSIONING_BOT_ENABLED=$VERSIONING_BOT_ENABLED", "vRulesEnabled=${!vRulesEnabled}", checkIsSubstring=$(checkIsSubstring "${!vConfigBranches}" "${!ghCurrentBranch}"), checkListIsSubstringInFileContent=$(checkListIsSubstringInFileContent "${!vConfigTags}" "${!ghCurrentTag}"), checkReleaseVersionFeatureFlag="$(checkReleaseVersionFeatureFlag ${PATCH_SCOPE})" >&2
    ##if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && [[ "${!vRulesEnabled}" == "true" ]] &&  [[ $(checkIsSubstring "${!vConfigBranches}" "${!ghCurrentBranch}") == "true" ]] && [[ $(checkListIsSubstringInFileContent "${!vConfigTags}" "${!ghCurrentTag}") == "true" ]] && [[ "$(checkReleaseVersionFeatureFlag ${PATCH_SCOPE})" == "true" ]]; then
    if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && [[ "${!vRulesEnabled}" == "true" ]] &&  [[ $(checkIsSubstring "${!vConfigBranches}" "${!ghCurrentBranch}") == "true" ]] && [[ $(checkListIsSubstringInFileContent "${!vConfigTags}" "${!ghCurrentTag}") == "true"  ]]; then
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): checkPreReleaseVersionFeatureFlag=true" >&2; fi
        echo "true"
    else
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): checkPreReleaseVersionFeatureFlag=false" >&2; fi
        echo "false"
    fi
}

## Check if required flags for incrementing Build version (Build) is enabled
function checkBuildVersionFeatureFlag() {
    local versionScope=$1
    
    local vRulesEnabled=${versionScope}_V_RULES_ENABLED
    local vConfigBranches=${versionScope}_V_CONFIG_BRANCHES
    local ghCurrentBranch=${versionScope}_GH_CURRENT_BRANCH

    if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && [[ "${!vRulesEnabled}" == "true" ]] && [[ $(checkIsSubstring "${!vConfigBranches}" "${!ghCurrentBranch}") == "true" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

## Check if required flags for incrementing version with external file is enabled
function checkReplacementFeatureFlag() {
    local versionScope=$1
    
    local vRulesEnabled=${versionScope}_V_RULES_ENABLED
    if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && [[ "${!vRulesEnabled}" == "true" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

## Engine to increment Release Version with external file value
function processWithReleaseVersionFile() {
    local inputVersion="$1"
    local versionPos="$2"
    local versionScope="$3"
    local versionListFile="$4"

    echo "[DEBUG] $BASH_SOURCE (line:$LINENO): inputVersion=$inputVersion" >&2
    echo "[DEBUG] $BASH_SOURCE (line:$LINENO): versionPos=$versionPos" >&2
    echo "[DEBUG] $BASH_SOURCE (line:$LINENO): versionScope=$versionScope" >&2
    echo "[DEBUG] $BASH_SOURCE (line:$LINENO): versionListFile=$versionListFile" >&2

    local versionFileRuleEnabled=${versionScope}_V_RULE_VFILE_ENABLED
    local currentIncrementedVersion="$inputVersion"
    echo "[DEBUG] $BASH_SOURCE (line:$LINENO): checkReleaseVersionFeatureFlag=$(checkReleaseVersionFeatureFlag ${versionScope}) and versionFileRuleEnabled=${!versionFileRuleEnabled}" >&2
    if [[ "$(checkReleaseVersionFeatureFlag ${versionScope})" == "true" ]] && [[ "${!versionFileRuleEnabled}" == "true" ]]; then
        currentIncrementedVersion=$(incrementReleaseVersionByFile $currentIncrementedVersion ${versionPos} ${versionScope})
        if [[ $? -ne 0 ]]; then
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed retrieving version from version file." >&2
            echo "[ERROR_MSG] $currentIncrementedVersion" >&2
            return 1
        fi
                echo "-------------- [DEBUG]: versionScope: [${versionScope}]" >&2
        if [[ "$versionScope" == "$MINOR_SCOPE" ]] || [[ "$versionScope" == "$PATCH_SCOPE" ]]; then
            if [[ ! -f "$versionListFile" ]]; then
                echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate versionListFile [$versionListFile]" >&2
                return 1
            fi
            local tmpPos=$(( versionPos + 1 ))

            local tmpInputVersion=$(echo $currentIncrementedVersion | cut -d"." -f1-"$tmpPos")
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): tmpInputVersion=$tmpInputVersion" >&2; fi

            local foundVersion=$(cat "$versionListFile" | grep -E "\"$tmpInputVersion(\.|+|-|$|\"|_)*" | sort -rV | head -n1 | cut -d"\"" -f4)
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): foundVersion=$foundVersion" >&2; fi

            ## if empty, need to reset
            if [[ -z "$foundVersion" ]]; then
                ## Reset the core version update if found
                rm -f $CORE_VERSION_UPDATED_FILE
                echo "false" > $TRUNK_CORE_NEED_INCREMENT_FILE
                currentIncrementedVersion="$tmpInputVersion"$(resetCoreRelease "$versionPos")
                if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): currentIncrementedVersion=$currentIncrementedVersion" >&2; fi
            elif (echo $foundVersion | grep -qE '([0-9]+\.){2}[0-9]+(((-|\+)[0-9a-zA-Z]+\.[0-9]+)*(\+[0-9a-zA-Z]+\.[0-9\.]+)*$)'); then 
                local releasedVersionOnly=""
                if (echo $foundVersion | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+$"); then
                    echo "false" > $TRUNK_CORE_NEED_INCREMENT_FILE
                    releasedVersionOnly=$(echo $foundVersion | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$")
                    currentIncrementedVersion=$(incrementCoreReleaseByPos "$versionPos" "$foundVersion")
                    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): releasedVersionOnly=$releasedVersionOnly, currentIncrementedVersion=$currentIncrementedVersion" >&2; fi
                else
                    echo "true" > $TRUNK_CORE_NEED_INCREMENT_FILE
                    releasedVersionOnly=$(echo $foundVersion | grep -oE "^[0-9]+\.[0-9]+\.[0-9]+")
                    # Do not need to increment because it's a pre-release version
                    currentIncrementedVersion=$releasedVersionOnly
                    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): releasedVersionOnly=$releasedVersionOnly, currentIncrementedVersion=$currentIncrementedVersion" >&2; fi
                fi
                ## Store the latest pre-release into files for post processing later
                if (grep -qE "$releasedVersionOnly\-$RC_V_IDENTIFIER\." $versionListFile); then
                    lastRCVersion=$(cat "$versionListFile" | grep -E "$releasedVersionOnly\-$RC_V_IDENTIFIER\." | sort -rV | head -n1 | cut -d"\"" -f4)
                    echo $lastRCVersion > $ARTIFACT_LAST_RC_VERSION_FILE
                    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): Reset last RC version to $lastRCVersion" >&2; fi
                fi
                if (grep -qE "$releasedVersionOnly\-$DEV_V_IDENTIFIER\." $versionListFile); then
                    lastDevVersion=$(cat "$versionListFile" | grep -E "$releasedVersionOnly\-$DEV_V_IDENTIFIER\." | sort -rV | head -n1 | cut -d"\"" -f4)
                    echo $lastDevVersion > $ARTIFACT_LAST_DEV_VERSION_FILE
                    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): Reset last DEV version to $lastDevVersion" >&2; fi
                fi
                if (grep -qE "$releasedVersionOnly\-$REBASE_V_IDENTIFIER\." $versionListFile); then
                    lastBaseVersion=$(cat "$versionListFile" | grep -E "$releasedVersionOnly\-$REBASE_V_IDENTIFIER\." | sort -rV | head -n1 | cut -d"\"" -f4)
                    echo $lastBaseVersion > $ARTIFACT_LAST_REBASE_VERSION_FILE
                    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): Reset last REBASE version to $lastBaseVersion" >&2; fi
                fi
                
            fi

        fi
    fi
    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): currentIncrementedVersion=$currentIncrementedVersion" >&2; fi
    echo $currentIncrementedVersion > $ARTIFACT_UPDATED_REL_VERSION_FILE
    echo $currentIncrementedVersion
}

function newfunc() {
    local inputVersion=$1
    local versionPos=$2
    local versionScope=$3
       
    local vConfigVersionFile=${versionScope}_V_CONFIG_VFILE_NAME
    local vConfigVersionFileKey=${versionScope}_V_CONFIG_VFILE_KEY
    if [[ ! -f ${!vConfigVersionFile} ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate version file: [${!vConfigVersionFile}]"
        return 1
    fi
    local tmpVersion=$(cat ./${!vConfigVersionFile} | grep -E "^${!vConfigVersionFileKey}" 2>/dev/null | cut -d"=" -f2)
    
    if [[ -z "$tmpVersion" ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to retrieve version value using key [${!vConfigVersionFileKey}] in version file: [${!vConfigVersionFile}]"
        return 1
    fi
    local versionArray=''
    IFS='. ' read -r -a versionArray <<< "$inputVersion"
    versionArray[$versionPos]=$tmpVersion
    echo $(local IFS=. ; echo "${versionArray[*]}")
}

function incrementCoreReleaseByPos {
    local versionPos="$1"
    local inputVersion="$2"

    local majorPosVersion=$(echo $inputVersion | cut -d"." -f1)
    local minorPosVersion=$(echo $inputVersion | cut -d"." -f2)
    local patchPosVersion=$(echo $inputVersion | cut -d"." -f3)
    local currentNeededPosVersion=0
    local nextNeededPosVersion=0
    if [[ $versionPos -eq 0 ]]; then
        currentNeededPosVersion=$minorPosVersion
        nextNeededPosVersion=$(( currentNeededPosVersion + 1))
        echo "$majorPosVersion.$nextNeededPosVersion.0"
    elif [[ $versionPos -eq 1 ]]; then
        currentNeededPosVersion=$patchPosVersion
        nextNeededPosVersion=$(( currentNeededPosVersion + 1))
        echo "$majorPosVersion.$minorPosVersion.$nextNeededPosVersion"
    fi
}

function resetCoreRelease {
    local versionPos="$1"
    if [[ $versionPos -eq 0 ]]; then
        echo ".0.0"
    elif [[ $versionPos -eq 1 ]]; then
        echo ".0"
    fi
}

## Function to replace defined token with input version
function replaceVersionInFile() {
    local inputVersion=$1
    local targetFile=$2
    local targetReplacementToken=$(echo $3 | sed "s/@@//g")

    if [[ ! -f "$targetFile" ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate version file to be replaced: [$targetFile]"
        exit 1
    fi

    if [[ -z "$targetReplacementToken" ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Replacement token cannot be empty"
        exit 1
    fi
    ## Replacement start here
    sed -r -i "s|@@${targetReplacementToken}@@|${inputVersion}|g" $targetFile
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed replacing token [@@${targetReplacementToken}@@] in file $targetFile"
        exit 1
    fi
}

## Replace version in maven POM file
function replaceVersionForMaven() {
    local inputVersion=$1
    local targetPomFile=$2

    ## Validate mvn command first
    mvn --version
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Maven command not executable"
        exit 1
    fi
    if [[ ! -f "$targetPomFile" ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate maven POM file: [$targetPomFile]"
        exit 1
    fi

    ## Replacement start here
    mvn -f $targetPomFile versions:set -DnewVersion=$inputVersion -q -DforceStdout
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed setting version in maven POM file [$targetPomFile]"
        exit 1
    fi
}

## Replace version in yaml file
function replaceVersionForYamlFile() {
    local inputVersion="$1"
    local targetYamlFile="$2"
    local targetYamlQueryPath="$3"

    ## Validate yq command first
    yq --version
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): YQ command not executable"
        exit 1
    fi
    if [[ ! -f "$targetYamlFile" ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate YAML file: [$targetPomFile]"
        exit 1
    fi

    ## Replacement start here
    yq -i "$targetYamlQueryPath = \"$inputVersion\"" $targetYamlFile
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed updating version in YAML file [$targetYamlFile]"
        exit 1
    fi
}

## Get incremental count on release version
function getIncrementalCount() {
    local listString=$1
    local fileContentPath=$2
    local listArray=''

    if [[ -z $listString ]] && [[ -z $fileContentPath ]]; then
        echo "1"
        return 0
    fi

    local incrementCounter=0
    IFS=', ' read -r -a listArray <<< "$listString"
    for eachString in "${listArray[@]}";
    do 
        local foundPatternCount=0
        if [[ -f $fileContentPath ]]; then
            foundPatternCount=$(grep -o -i "$eachString" $fileContentPath | wc -l)
            
        else
            foundPatternCount=$(echo $fileContentPath | grep -o -i "$eachString" | wc -l)
        fi
        incrementCounter=$((incrementCounter + foundPatternCount))
    done
    if [[ $incrementCounter -eq 0 ]]; then
        echo 0
    else
        echo $incrementCounter
    fi
    return 0

}

## Check if contain non release incrementation (rc, dev, bld, etc)
function isPreReleaseIncrementation() {
    local preReleaseFlag='false'
    if [[ "$(checkPreReleaseVersionFeatureFlag ${RC_SCOPE})" == "true" ]] && [[ ! "${RC_V_RULE_VFILE_ENABLED}" == "true" ]]; then
        preReleaseFlag='true'

    elif [[ "$(checkPreReleaseVersionFeatureFlag ${DEV_SCOPE})" == "true" ]] && [[ ! "${DEV_V_RULE_VFILE_ENABLED}" == "true" ]]; then
        preReleaseFlag='true'
    elif [[ "$(checkBuildVersionFeatureFlag ${BUILD_SCOPE})" == "true" ]]; then
        preReleaseFlag='true'
    fi

    echo "$preReleaseFlag"
}

## For debugging purpose
function debugReleaseVersionVariables() {
    local versionScope=$1
    echo ==========================================
    echo [DEBUG] SCOPE: $versionScope

    local vRulesEnabled=${versionScope}_V_RULES_ENABLED
    local vConfigBranches=${versionScope}_V_CONFIG_BRANCHES
    local vConfigLabels=${versionScope}_V_CONFIG_LABELS
    local vConfigTags=${versionScope}_V_CONFIG_TAGS 
    local vConfigMSGTAGs=${versionScope}_V_CONFIG_MSGTAGS 

    local vCurrentBranch=${versionScope}_GH_CURRENT_BRANCH
    local vCurrentLabel=${versionScope}_GH_CURRENT_LABEL
    local vCurrentTag=${versionScope}_GH_CURRENT_TAG
    local vCurrentMsgTag=${versionScope}_GH_CURRENT_MSGTAG

    local ruleBranchEnabled=${versionScope}_V_RULE_BRANCH_ENABLED
    local ruleVersionFileEnabled=${versionScope}_V_RULE_VFILE_ENABLED

    echo checkReleaseVersionFeatureFlag=$(checkReleaseVersionFeatureFlag "${versionScope}")
    echo VERSIONING_BOT_ENABLED=$VERSIONING_BOT_ENABLED
    echo $vRulesEnabled=${!vRulesEnabled} 
    echo $ruleBranchEnabled=${!ruleBranchEnabled} 
    echo $ruleVersionFileEnabled=${!ruleVersionFileEnabled} 
    echo $vConfigBranches=${!vConfigBranches} 
    echo $vCurrentBranch=${!vCurrentBranch} 
    echo $vConfigLabels=${!vConfigLabels} 
    echo $vCurrentLabel=${!vCurrentLabel} 
    echo $vConfigTags=${!vConfigTags}  
    echo $vCurrentTag=${!vCurrentTag} 
    echo $vConfigMSGTAGs=${!vConfigMSGTAGs}  
    echo $vCurrentMsgTag=${!vCurrentMsgTag} 
    echo ==========================================
}

## For debugging purpose
function debugPreReleaseVersionVariables() {
    local versionScope=$1
    echo ==========================================
    echo [DEBUG] SCOPE: $versionScope

    local vRulesEnabled=${versionScope}_V_RULES_ENABLED
    local vConfigBranches=${versionScope}_V_CONFIG_BRANCHES
    local vConfigTags=${versionScope}_V_CONFIG_TAGS 
    
    local vCurrentBranch=${versionScope}_GH_CURRENT_BRANCH
    local vCurrentTag=${versionScope}_GH_CURRENT_TAG
    
    local ruleBranchEnabled=${versionScope}_V_RULE_BRANCH_ENABLED
    local ruleVersionFileEnabled=${versionScope}_V_RULE_VFILE_ENABLED

    echo checkPreReleaseVersionFeatureFlag=$(checkPreReleaseVersionFeatureFlag "${versionScope}")
    echo VERSIONING_BOT_ENABLED=$VERSIONING_BOT_ENABLED
    echo $vRulesEnabled=${!vRulesEnabled} 
    echo $ruleBranchEnabled=${!ruleBranchEnabled} 
    echo $ruleVersionFileEnabled=${!ruleVersionFileEnabled} 
    echo $vConfigBranches=${!vConfigBranches} 
    echo $vCurrentBranch=${!vCurrentBranch} 
    echo $vConfigTags=${!vConfigTags}  
    echo $vCurrentTag=${!vCurrentTag} 
    echo ==========================================
}

## For debugging purpose
function debugBuildVersionVariables() {
    local versionScope=$1
    echo ==========================================
    echo [DEBUG] SCOPE: $versionScope
    
    local vRulesEnabled=${versionScope}_V_RULES_ENABLED
    local vConfigBranches=${versionScope}_V_CONFIG_BRANCHES
    local ghCurrentBranch=${versionScope}_GH_CURRENT_BRANCH

   
    echo checkBuildVersionFeatureFlag=$(checkBuildVersionFeatureFlag "${versionScope}") 
    echo VERSIONING_BOT_ENABLED=$VERSIONING_BOT_ENABLED
    echo $vRulesEnabled=${!vRulesEnabled} 
    echo $vConfigBranches=${!vConfigBranches} 
    echo $ghCurrentBranch=${!ghCurrentBranch} 
    echo ==========================================
}

## Instrument core version variables which can be made dummy based on the config 
degaussCoreVersionVariables $MAJOR_SCOPE
degaussCoreVersionVariables $MINOR_SCOPE
degaussCoreVersionVariables $PATCH_SCOPE
degaussPreReleaseVersionVariables $RC_SCOPE
degaussPreReleaseVersionVariables $DEV_SCOPE

## Start incrementing
## Debug section
if [[ "$isDebug" == "true" ]]; then
    debugReleaseVersionVariables MAJOR
    debugReleaseVersionVariables MINOR
    debugReleaseVersionVariables PATCH
fi

currentInitialVersion=""    
if [[ ! -z "${rebaseReleaseVersion}" ]]; then
    baseCurrentVersion="$lastBaseVersion"
    if [[ -z "$lastBaseVersion" ]]; then
        baseCurrentVersion="${rebaseReleaseVersion}-$REBASE_V_IDENTIFIER.0"
    fi
    currentRebasePatchNum=$(echo "$baseCurrentVersion" | awk -F"-$REBASE_V_IDENTIFIER." '{print $2}')
    nextRebasePatchNum=$((currentRebasePatchNum + 1))
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed incrementation on hf version."
        echo "[DEBUG] baseCurrentVersion=$baseCurrentVersion, currentRebasePatchNum=$currentRebasePatchNum"
        exit 1
    fi
    nextVersion=${rebaseReleaseVersion}-$REBASE_V_IDENTIFIER.$nextRebasePatchNum

else
    nextVersion=$(getNeededIncrementReleaseVersion "$lastDevVersion" "$lastRCVersion" "$lastRelVersion")
    currentInitialVersion=$nextVersion
    echo [INFO] Before incremented: $nextVersion

    ## Process incrementation on MAJOR, MINOR and PATCH
    if [[ "$isInitialVersion" == "true" ]]; then
        echo "[INFO] This is initial version. So no core release incrementation needed: $nextVersion"
    elif [[ "$(checkReleaseVersionFeatureFlag ${MAJOR_SCOPE})" == "true" ]] && [[ ! "${MAJOR_V_RULE_VFILE_ENABLED}" == "true" ]]; then
        # echo [DEBUG] currentRCSemanticVersion=$nextVersion
        touch $CORE_VERSION_UPDATED_FILE
        vConfigMsgTags=${MAJOR_SCOPE}_V_CONFIG_MSGTAGS
        ghCurrentMsgTag=${MAJOR_SCOPE}_GH_CURRENT_MSGTAG
        ## If there's commit message
        if [[ $(checkListIsSubstringInFileContent "${!vConfigMsgTags}" "${!ghCurrentMsgTag}") == "true" ]]; then
            nextVersion=$(incrementReleaseVersion $lastRelVersion ${MAJOR_POSITION} $(getIncrementalCount "${!vConfigMsgTags}" "${!ghCurrentMsgTag}"))
        elif [[ "$(isPreReleaseIncrementation)" == 'true' ]]; then
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): Not incrementing PATCH because isPreReleaseIncrementation=true" >&2; fi
        else
            nextVersion=$(incrementReleaseVersion $nextVersion ${MAJOR_POSITION})
        fi
        
        echo [DEBUG] MAJOR INCREMENTED $nextVersion
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): MAJOR INCREMENTED=$nextVersion" >&2; fi
    elif [[ "$(checkReleaseVersionFeatureFlag ${MINOR_SCOPE})" == "true" ]] && [[ ! "${MINOR_V_RULE_VFILE_ENABLED}" == "true" ]]; then
        # echo [DEBUG] currentRCSemanticVersion=$nextVersion
        touch $CORE_VERSION_UPDATED_FILE
        # nextVersion=$(incrementReleaseVersion $nextVersion ${MINOR_POSITION})
        vConfigMsgTags=${MINOR_SCOPE}_V_CONFIG_MSGTAGS
        ghCurrentMsgTag=${MINOR_SCOPE}_GH_CURRENT_MSGTAG
        ## If there's commit message
        if [[ $(checkListIsSubstringInFileContent "${!vConfigMsgTags}" "${!ghCurrentMsgTag}") == "true" && "${!vConfigMsgTags}" != "false" ]]; then
            nextVersion=$(incrementReleaseVersion $lastRelVersion ${MINOR_POSITION} $(getIncrementalCount "${!vConfigMsgTags}" "${!ghCurrentMsgTag}"))
        elif [[ "$(isPreReleaseIncrementation)" == 'true' ]]; then
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): Not incrementing PATCH because isPreReleaseIncrementation=true" >&2; fi
        else
            nextVersion=$(incrementReleaseVersion $nextVersion ${MINOR_POSITION})
        fi
        echo [DEBUG] MINOR INCREMENTED $nextVersion
    elif [[ "$(checkReleaseVersionFeatureFlag ${PATCH_SCOPE})" == "true" ]] && [[ ! "${PATCH_V_RULE_VFILE_ENABLED}" == "true" ]] && [[ ! "${MAJOR_V_RULE_VFILE_ENABLED}" == "true" ]] && [[ ! "${MINOR_V_RULE_VFILE_ENABLED}" == "true" ]]; then
        # echo [DEBUG] currentRCSemanticVersion=$nextVersion
        touch $CORE_VERSION_UPDATED_FILE
        # nextVersion=$(incrementReleaseVersion $nextVersion ${PATCH_POSITION})
        vConfigMsgTags=${PATCH_SCOPE}_V_CONFIG_MSGTAGS
        ghCurrentMsgTag=${PATCH_SCOPE}_GH_CURRENT_MSGTAG
        ## If there's commit message
        if [[ $(checkListIsSubstringInFileContent "${!vConfigMsgTags}" "${!ghCurrentMsgTag}") == "true" && "${!vConfigMsgTags}" != "false" ]]; then
            nextVersion=$(incrementReleaseVersion $lastRelVersion ${PATCH_POSITION} $(getIncrementalCount "${!vConfigMsgTags}" "${!ghCurrentMsgTag}"))
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): After incrementReleaseVersion: $nextVersion" >&2; fi
        elif [[ "$(isPreReleaseIncrementation)" == 'true' ]]; then
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): Not incrementing PATCH because isPreReleaseIncrementation=true" >&2; fi
        else
            nextVersion=$(incrementReleaseVersion $nextVersion ${PATCH_POSITION})
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): After incrementReleaseVersion: $nextVersion" >&2; fi
        fi
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): PATCH INCREMENTED=$nextVersion" >&2; fi
    fi
    echo [INFO] After core version incremented: $nextVersion

    ## Process incrementation on MAJOR, MINOR and PATCH via version file (manual). Skip if is initial version
    # if [[ "$isInitialVersion" == "true" ]]; then
    #     echo "[INFO] This is initial version. So no core version file incrementation needed: $nextVersion"
    # else
    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): nextVersion=$nextVersion, lastDevVersion=$lastDevVersion, lastRcVersion=$lastRCVersion, lastBaseVersion=$lastBaseVersion, lastRelVersion=$lastRelVersion" >&2; fi
    nextVersion=$(processWithReleaseVersionFile "${nextVersion}" "${MAJOR_POSITION}" "${MAJOR_SCOPE}" "${versionListFile}")
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed processing incrementation on MAJOR, MINOR and PATCH via version file on MAJOR VERSION." >&2
        echo "[ERROR_MSG] $nextVersion" >&2
        exit 1
    fi
    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): nextVersion=$nextVersion, lastDevVersion=$lastDevVersion, lastRcVersion=$lastRCVersion, lastBaseVersion=$lastBaseVersion, lastRelVersion=$lastRelVersion" >&2; fi
    nextVersion=$(processWithReleaseVersionFile "${nextVersion}" "${MINOR_POSITION}" "${MINOR_SCOPE}" "${versionListFile}")
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed processing incrementation on MAJOR, MINOR and PATCH via version file on MINOR VERSION." >&2
        echo "[ERROR_MSG] $nextVersion" >&2
        exit 1
    fi
    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): nextVersion=$nextVersion, lastDevVersion=$lastDevVersion, lastRcVersion=$lastRCVersion, lastBaseVersion=$lastBaseVersion, lastRelVersion=$lastRelVersion" >&2; fi
    nextVersion=$(processWithReleaseVersionFile "${nextVersion}" "${PATCH_POSITION}" "${PATCH_SCOPE}" "${versionListFile}")
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed processing incrementation on MAJOR, MINOR and PATCH via version file on PATCH VERSION." >&2
        echo "[ERROR_MSG] $nextVersion" >&2
        exit 1
    fi
    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): nextVersion=$nextVersion, lastDevVersion=$lastDevVersion, lastRcVersion=$lastRCVersion, lastBaseVersion=$lastBaseVersion, lastRelVersion=$lastRelVersion" >&2; fi

    # if ([[ "${MAJOR_V_RULE_VFILE_ENABLED}" == "true" ]] || [[ "${MINOR_V_RULE_VFILE_ENABLED}" == "true" ]]) && [[ ! "${PATCH_V_RULE_VFILE_ENABLED}" == "true" ]]; then
    #     echo " "
    # else
    #     nextVersion=$(processWithReleaseVersionFile "${nextVersion}" "${PATCH_POSITION}" "${PATCH_SCOPE}" "${versionListFile}")
    #     if [[ $? -ne 0 ]]; then
    #         echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed processing incrementation on MAJOR, MINOR and PATCH via version file on PATCH VERSION."
    #         echo "[ERROR_MSG] $nextVersion"
    #         exit 1
    #     fi
    # fi
    echo [INFO] After core version file incremented: [$nextVersion]
# fi

    # Store in a file to be used in pre-release increment consideration later
    echo $nextVersion > $ARTIFACT_UPDATED_REL_VERSION_FILE

    ## Debug section
    if [[ "$isDebug" == "true" ]]; then
        debugPreReleaseVersionVariables $RC_SCOPE
        debugPreReleaseVersionVariables $DEV_SCOPE
    fi

    ## Process incrementation on RC and DEV 
    echo [INFO] Before RC version incremented: $lastRCVersion
    echo [INFO] Before DEV version incremented: $lastDevVersion
    echo [INFO] Before BASE version incremented: $lastBaseVersion
    echo [INFO] Before nextVersion version incremented: $nextVersion

    if [[ "$(checkPreReleaseVersionFeatureFlag ${RC_SCOPE})" == "true" ]] && [[ ! "${RC_V_RULE_VFILE_ENABLED}" == "true" ]]; then
        nextVersion=$(incrementPreReleaseVersion "$lastRCVersion" "$RC_V_IDENTIFIER")
    elif [[ "$(checkPreReleaseVersionFeatureFlag ${DEV_SCOPE})" == "true" ]] && [[ ! "${DEV_V_RULE_VFILE_ENABLED}" == "true" ]]; then
        nextVersion=$(incrementPreReleaseVersion "$lastDevVersion" "$DEV_V_IDENTIFIER")
    fi
    echo [INFO] After prerelease version incremented: [$nextVersion]

    ## Process incrementation on RC and DEV with version file
    if [[ "$(checkPreReleaseVersionFeatureFlag ${RC_SCOPE})" == "true" ]] && [[ "${RC_V_RULE_VFILE_ENABLED}" == "true" ]]; then
        nextVersion=$(incrementPreReleaseVersionByFile "$lastRCVersion" "$RC_V_IDENTIFIER" "${RC_SCOPE}")
    elif [[ "$(checkPreReleaseVersionFeatureFlag ${DEV_SCOPE})" == "true" ]] && [[ "${DEV_V_RULE_VFILE_ENABLED}" == "true" ]]; then
        nextVersion=$(incrementPreReleaseVersionByFile "$lastDevVersion" "$DEV_V_IDENTIFIER" "${DEV_SCOPE}")
    fi
    echo [INFO] After prerelease version incremented with input from version file: [$nextVersion]

    degaussBuildVersionVariables "$BUILD_SCOPE"
    ## Debug section
    if [[ "$isDebug" == "true" ]]; then
        debugBuildVersionVariables "$BUILD_SCOPE"
    fi
    ## Append build number infos if enabled
    if [[ "$(checkBuildVersionFeatureFlag ${BUILD_SCOPE})" == "true" ]]; then
        if [[ -z "$BUILD_V_IDENTIFIER" ]]; then
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Missing build identifier"
            exit 1
        fi
        if [[ -z "$BUILD_GH_RUN_NUMBER" ]]; then
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Missing GitHub job number"
            exit 1
        fi
        if [[ -z "$BUILD_GH_RUN_ATTEMPT" ]]; then
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Missing GitHub job attempt number"
            exit 1
        fi
        nextVersion=${nextVersion}+${BUILD_V_IDENTIFIER}.${BUILD_GH_RUN_NUMBER}.${BUILD_GH_RUN_ATTEMPT}
        echo [INFO] After appending build version: $nextVersion
    fi

    # ## If due to any circumstances the increment on nextVersion doesnt happen, it's likely due to unhandled versioning format. In that situation, try to force the patch increment by 1
    # if [[ "$nextVersion" == "$lastRelVersion" ]]; then
    #     echo [DEBUG] nextVersion and lastRelVersion are still identical [$nextVersion]. Force increment patch version...
    #     nextVersion=$(incrementReleaseVersion $nextVersion ${PATCH_POSITION})
    #     echo [DEBUG] PATCH INCREMENTED $nextVersion
    # fi
fi
## Replace the version in file if enabled
if [[ "$(checkReplacementFeatureFlag ${REPLACEMENT_SCOPE})" == "true" ]] && [[ "$REPLACE_V_RULE_FILETOKEN_ENABLED" == "true" ]]; then
    replaceVersionInFile "$nextVersion" "$REPLACE_V_CONFIG_FILETOKEN_FILE" "$REPLACE_V_CONFIG_FILETOKEN_NAME"
    echo "[INFO] Version updated successfully in $REPLACE_V_CONFIG_FILETOKEN_FILE"
    if [[ "$isDebug" == "true" ]]; then
        echo "[DEBUG] Updated $REPLACE_V_CONFIG_FILETOKEN_FILE:"
        cat $REPLACE_V_CONFIG_FILETOKEN_FILE
    fi
fi
if [[ "$(checkReplacementFeatureFlag ${REPLACEMENT_SCOPE})" == "true" ]] && [[ "$REPLACE_V_RULE_MAVEN_ENABLED" == "true" ]]; then
    replaceVersionForMaven "$nextVersion" "$REPLACE_V_CONFIG_MAVEN_POMFILE"
    echo "[INFO] Version updated successfully in maven POM file: $REPLACE_V_CONFIG_MAVEN_POMFILE"
    if [[ "$isDebug" == "true" ]]; then
        echo "[DEBUG] Updated $REPLACE_V_CONFIG_MAVEN_POMFILE:"
        cat $REPLACE_V_CONFIG_MAVEN_POMFILE
    fi
fi
# if [[ "$(checkReplacementFeatureFlag ${REPLACEMENT_SCOPE})" == "true" ]] && [[ "$REPLACE_V_RULE_YAMLPATH_ENABLED" == "true" ]]; then
#     replaceVersionForYamlFile "$nextVersion" "$REPLACE_V_CONFIG_YAMLPATH_FILE" "$REPLACE_V_CONFIG_YAMLPATH_QUERYPATH"
#     echo "[INFO] Version updated successfully in YAML file: $REPLACE_V_CONFIG_YAMLPATH_FILE"
# fi
echo
echo "[INFO] nextVersion = $nextVersion"
echo $nextVersion > $ARTIFACT_NEXT_VERSION_FILE


