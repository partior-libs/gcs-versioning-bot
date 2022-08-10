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
## ANTZ TEMPORARY
# source ./test-files/mock-base-variables.sh

artifactName=$1
currentBranch=$(echo $2 | cut -d"/" -f1)
currentLabel=$3
currentTag=$4
currentMsgTag=$5
isDebug=$6


## Trim away the build info
lastDevVersion=$(cat $ARTIFACT_LAST_DEV_VERSION_FILE | cut -d"+" -f1)
lastRCVersion=$(cat $ARTIFACT_LAST_RC_VERSION_FILE | cut -d"+" -f1)
lastRelVersion=$(cat $ARTIFACT_LAST_REL_VERSION_FILE | cut -d"+" -f1)

echo "[INFO] Start generating package version..."
echo "[INFO] Artifact Name: $artifactName"
echo "[INFO] Source branch: $currentBranch"
echo "[INFO] Last Dev version in Artifactory: $lastDevVersion"
echo "[INFO] Last RC version in Artifactory: $lastRCVersion"
echo "[INFO] Last Release version in Artifactory: $lastRelVersion"

## Ensure dev and rel version are in sync
function versionCompareLessOrEqual() {
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}

# When increment pre-release, make sure the release version is considered
function needToIncrementRelVersion() {
    local inputCurrentVersion=$1
    local inputRelVersion=$2
    if [[  "$inputRelVersion" == "$(echo $inputCurrentVersion | cut -d'-' -f1)" ]]; then
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
    if [[ "$devIncrease" == "false" ]]; then
        newRelVersion=$(echo $devVersion | cut -d"-" -f1)
    fi
    local rcIncrease=$(needToIncrementRelVersion "$rcVersion" "$newRelVersion")
    if [[ "$rcIncrease" == "false" ]]; then
        newRelVersion=$(echo $rcVersion | cut -d"-" -f1)
    fi
    ## Store the updated rel version in file for next incrementation consideration
    #echo $newRelVersion > $ARTIFACT_UPDATED_REL_VERSION_FILE
    echo $newRelVersion
}

## Increment the release version based on semantic position
function incrementReleaseVersion() {
    local inputVersion=$1
    local versionPos=$2

    local versionArray=''
    IFS='. ' read -r -a versionArray <<< "$inputVersion"
    versionArray[$versionPos]=$((versionArray[$versionPos]+1))
    if [ $versionPos -lt 2 ]; then versionArray[2]=0; fi
    if [ $versionPos -lt 1 ]; then versionArray[1]=0; fi
    local incrementedRelVersion=$(local IFS=. ; echo "${versionArray[*]}")
    # Store in a file to be used in pre-release increment consideration later
    CORE_VERSION_UPDATED=true
    echo $incrementedRelVersion > $ARTIFACT_UPDATED_REL_VERSION_FILE
    echo $incrementedRelVersion
}

## Increment pre-release version based on identifier
function incrementPreReleaseVersion() {
    local inputVersion=$1
    local preIdentifider=$2

    # if ($(echo $inputVersion | grep -E -q '[+-]\w*\.\w*')); then

    # fi
    local currentSemanticVersion=$(echo $inputVersion | awk -F"-$preIdentifider." '{print $1}')
    local currentPrereleaseNumber=$(echo $inputVersion | awk -F"-dev." '{print $2}')
    ## Ensure it's digit
    if [[ ! "$currentPrereleaseNumber" =~ ^[0-9]+$ ]]; then
        currentPrereleaseNumber=0
    fi
    local nextPreReleaseNumber=$(( $currentPrereleaseNumber + 1 ))
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

        if [[ "$CORE_VERSION_UPDATED" == "true" ]]; then
            currentSemanticVersion=$lastRelVersion
            nextPreReleaseNumber=1
        elif [[ "$needIncreaseVersion" == "true" ]]; then
            currentSemanticVersion=$(incrementReleaseVersion $lastRelVersion ${PATCH_POSITION})
            nextPreReleaseNumber=1
        elif [[ "$needIncreaseVersion" == "false" ]]; then
            nextPreReleaseNumber=$(( $(echo $inputVersion | awk -F"-$preIdentifider." '{print $2}') + 1 ))
        fi      
    fi
    echo $currentSemanticVersion-$preIdentifider.$nextPreReleaseNumber
}

## Reset variables that's not used, to simplify requirement evaluation later
function degaussCoreVersionVariables() {
    local versionScope=$1
    local tmpVariable=source-$(date +%s).tmp
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
        echo "export ${vCurrentMsgTag}=${currentMsgTag}" >> $tmpVariable
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
    rm -f $tmpVariable
}

## Reset variables that's not used, to simplify requirement evaluation later
function degaussReleaseVersionVariables() {
    local versionScope=$1
    local tmpVariable=source-$(date +%s).tmp
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
    rm -f $tmpVariable
}

## Reset variables that's not used, to simplify requirement evaluation later
function degaussPreReleaseVersionVariables() {
    local versionScope=$1
    local tmpVariable=source-$(date +%s).tmp
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
    local tmpVariable=source-$(date +%s).tmp
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
    local tmpVariable=source-$(date +%s).tmp
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
        if [[ "$CORE_VERSION_UPDATED" == "true" ]]; then
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
        if [[ "$eachString" == "$subString" ]]; then
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

    if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && [[ "${!vRulesEnabled}" == "true" ]] && [[ $(checkIsSubstring "${!vConfigBranches}" "${!ghCurrentBranch}") == "true" ]] && [[ $(checkListIsSubstringInFileContent "${!vConfigLabels}" "${!ghCurrentLabel}") == "true" ]] && [[ $(checkListIsSubstringInFileContent "${!vConfigTags}" "${!ghCurrentTag}") == "true" ]] && [[ $(checkListIsSubstringInFileContent "${!vConfigMsgTags}" "${!ghCurrentMsgTag}") == "true" ]]; then
        echo "true"
    else
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
    if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && [[ "${!vRulesEnabled}" == "true" ]] &&  [[ $(checkIsSubstring "${!vConfigBranches}" "${!ghCurrentBranch}") == "true" ]] && [[ $(checkListIsSubstringInFileContent "${!vConfigTags}" "${!ghCurrentTag}") == "true" ]] && [[ ! "$(checkReleaseVersionFeatureFlag ${PATCH_SCOPE})" == "true" ]]; then
        echo "true"
    else
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
    local inputVersion=$1
    local versionPos=$2
    local versionScope=$3

    local versionFileRuleEnabled=${versionScope}_V_RULE_VFILE_ENABLED
    local currentIncrementedVersion="$inputVersion"
    if [[ "$(checkReleaseVersionFeatureFlag ${versionScope})" == "true" ]] && [[ "${!versionFileRuleEnabled}" == "true" ]]; then
        currentIncrementedVersion=$(incrementReleaseVersionByFile $currentIncrementedVersion ${versionPos} ${versionScope})
        if [[ $? -ne 0 ]]; then
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed retrieving version from version file."
            echo "[ERROR_MSG] $currentIncrementedVersion"
            return 1
        fi
    fi
    echo $currentIncrementedVersion
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

## Global variable
CORE_VERSION_UPDATED=false

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

nextVersion=$(getNeededIncrementReleaseVersion "$lastDevVersion" "$lastRCVersion" "$lastRelVersion")
echo [INFO] Before incremented: $nextVersion
## Process incrementation on MAJOR, MINOR and PATCH
if [[ "$(checkReleaseVersionFeatureFlag ${MAJOR_SCOPE})" == "true" ]] && [[ ! "${MAJOR_V_RULE_VFILE_ENABLED}" == "true" ]]; then
    # echo [DEBUG] currentRCSemanticVersion=$nextVersion
    nextVersion=$(incrementReleaseVersion $nextVersion ${MAJOR_POSITION})
    echo [DEBUG] MAJOR INCREMENTED $nextVersion
elif [[ "$(checkReleaseVersionFeatureFlag ${MINOR_SCOPE})" == "true" ]] && [[ ! "${MINOR_V_RULE_VFILE_ENABLED}" == "true" ]]; then
    # echo [DEBUG] currentRCSemanticVersion=$nextVersion
    nextVersion=$(incrementReleaseVersion $nextVersion ${MINOR_POSITION})
    echo [DEBUG] MINOR INCREMENTED $nextVersion
elif [[ "$(checkReleaseVersionFeatureFlag ${PATCH_SCOPE})" == "true" ]] && [[ ! "${PATCH_V_RULE_VFILE_ENABLED}" == "true" ]]; then
    # echo [DEBUG] currentRCSemanticVersion=$nextVersion
    nextVersion=$(incrementReleaseVersion $nextVersion ${PATCH_POSITION})
    echo [DEBUG] PATCH INCREMENTED $nextVersion
fi
echo [INFO] After core version incremented: $nextVersion

## Process incrementation on MAJOR, MINOR and PATCH via version file (manual)
nextVersion=$(processWithReleaseVersionFile ${nextVersion} ${MAJOR_POSITION} ${MAJOR_SCOPE})
if [[ $? -ne 0 ]]; then
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed processing incrementation on MAJOR, MINOR and PATCH via version file on MAJOR VERSION."
    echo "[ERROR_MSG] $nextVersion"
    exit 1
fi
nextVersion=$(processWithReleaseVersionFile ${nextVersion} ${MINOR_POSITION} ${MINOR_SCOPE})
if [[ $? -ne 0 ]]; then
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed processing incrementation on MAJOR, MINOR and PATCH via version file on MINOR VERSION."
    echo "[ERROR_MSG] $nextVersion"
    exit 1
fi
nextVersion=$(processWithReleaseVersionFile ${nextVersion} ${PATCH_POSITION} ${PATCH_SCOPE})
if [[ $? -ne 0 ]]; then
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed processing incrementation on MAJOR, MINOR and PATCH via version file on PATCH VERSION."
    echo "[ERROR_MSG] $nextVersion"
    exit 1
fi
echo [INFO] After core version file incremented: [$nextVersion]

## Debug section
if [[ "$isDebug" == "true" ]]; then
    debugPreReleaseVersionVariables $RC_SCOPE
    debugPreReleaseVersionVariables $DEV_SCOPE
fi

# ## Combined incremented release version with pre-release
# if [[ ! -z $lastRCVersion ]] && [[ ! -z $nextVersion ]]; then
#     tmpRCVersion=$(echo $lastRCVersion | cut -d"-" -f1 --complement)
#     nextVersion=$nextVersion-$tmpRCVersion
# fi
# if [[ ! -z $lastDevVersion ]] && [[ ! -z $nextVersion ]]; then
#     tmpDevVersion=$(echo $lastDevVersion | cut -d"-" -f1 --complement)
#     nextVersion=$nextVersion-$tmpDevVersion
# fi
## Process incrementation on RC and DEV 
echo [INFO] Before RC version incremented: $lastRCVersion
echo [INFO] Before DEV version incremented: $lastDevVersion
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

## Replace the version in file if enabled
if [[ "$(checkReplacementFeatureFlag ${REPLACEMENT_SCOPE})" == "true" ]] && [[ "$REPLACE_V_RULE_FILETOKEN_ENABLED" == "true" ]]; then
    replaceVersionInFile "$nextVersion" "$REPLACE_V_CONFIG_FILETOKEN_FILE" "$REPLACE_V_CONFIG_FILETOKEN_NAME"
    echo "[INFO] Version updated successfully in $REPLACE_V_CONFIG_FILETOKEN_FILE"
fi
if [[ "$(checkReplacementFeatureFlag ${REPLACEMENT_SCOPE})" == "true" ]] && [[ "$REPLACE_V_RULE_MAVEN_ENABLED" == "true" ]]; then
    replaceVersionForMaven "$nextVersion" "$REPLACE_V_CONFIG_MAVEN_POMFILE"
    echo "[INFO] Version updated successfully in maven POM file: $REPLACE_V_CONFIG_MAVEN_POMFILE"
fi
if [[ "$(checkReplacementFeatureFlag ${REPLACEMENT_SCOPE})" == "true" ]] && [[ "$REPLACE_V_RULE_YAMLPATH_ENABLED" == "true" ]]; then
    replaceVersionForYamlFile "$nextVersion" "$REPLACE_V_CONFIG_YAMLPATH_FILE" "$REPLACE_V_CONFIG_YAMLPATH_QUERYPATH"
    echo "[INFO] Version updated successfully in YAML file: $REPLACE_V_CONFIG_YAMLPATH_FILE"
fi

## If due to any circumstances the increment on nextVersion doesnt happen, it's likely due to unhandled versioning format. In that situation, try to force the patch increment by 1
if [[ "$nextVersion" == "$lastRelVersion" ]]; then
    echo [DEBUG] nextVersion and lastRelVersion are still identical [$nextVersion]. Force increment patch version...
    nextVersion=$(incrementReleaseVersion $nextVersion ${PATCH_POSITION})
    echo [DEBUG] PATCH INCREMENTED $nextVersion
fi

echo "[INFO] nextVersion = $nextVersion"
echo $nextVersion > $ARTIFACT_NEXT_VERSION_FILE



