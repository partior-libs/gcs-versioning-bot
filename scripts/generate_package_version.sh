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
currentVersionFile=$6

lastDevVersion=$(cat $ARTIFACT_LAST_DEV_VERSION_FILE | cut -d"+" -f1)
lastRelVersion=$(cat $ARTIFACT_LAST_REL_VERSION_FILE | cut -d"+" -f1)

echo "[INFO] Start generating package version..."
echo "[INFO] Artifact Name: $artifactName"
echo "[INFO] Source branch: $currentBranch"
echo "[INFO] Last Dev version in Artifactory: $lastDevVersion"
echo "[INFO] Last Rel version in Artifactory: $lastRelVersion"

## Ensure dev and rel version are in sync
function versionCompareLessOrEqual() {
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}

function incrementCoreVersion() {
    local inputVersion=$1
    local versionPos=$2

    local versionArray=''
    IFS='. ' read -r -a versionArray <<< "$inputVersion"
    versionArray[$versionPos]=$((versionArray[$versionPos]+1))
    if [ $versionPos -lt 2 ]; then versionArray[2]=0; fi
    if [ $versionPos -lt 1 ]; then versionArray[1]=0; fi
    echo $(local IFS=. ; echo "${versionArray[*]}")
}

function incrementPreReleaseVersion() {
    local inputVersion=$1
    local preIdentifider=$2

    local currentSemanticVersion=$(echo $inputVersion | awk -F"-$preIdentifider." '{print $1}')
    local nextPreReleaseNumber=$(( $(echo $inputVersion | awk -F"-$preIdentifider." '{print $2}') + 1 ))
    ## If not pre-release, then increment the core version too
    if [[ ! "$inputVersion" == *"-"* ]]; then
        currentSemanticVersion=$(incrementCoreVersion $currentSemanticVersion ${PATCH_POSITION})
    fi
    echo $currentSemanticVersion-$preIdentifider.$nextPreReleaseNumber
}

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
    echo "export ${vCurrentLabel}=$currentLabel" >> $tmpVariable
    echo "export ${vCurrentTag}=$currentTag" >> $tmpVariable
    echo "export ${vCurrentMsgTag}=$currentMsgTag" >> $tmpVariable

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

function incrementCoreVersionByFile() {
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

function checkCoreVersionFeatureFlag() {
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

    if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && [[ "${!vRulesEnabled}" == "true" ]] && [[ "$(checkIsSubstring \"${!vConfigBranches}\" \"${!ghCurrentBranch}\")" == "true" ]] && [[ "$(checkIsSubstring \"${!vConfigLabels}\" \"${!ghCurrentLabel}\")" == "true" ]] && [[ "$(checkIsSubstring \"${!vConfigTags}\" \"${!ghCurrentTag}\")" == "true" ]] && [[ "$(checkIsSubstring \"${!vConfigMsgTags}\" \"${!ghCurrentMsgTag}\")" == "true" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

function checkPreReleaseVersionFeatureFlag() {
    local versionScope=$1
    
    local vRulesEnabled=${versionScope}_V_RULES_ENABLED
    local vConfigBranches=${versionScope}_V_CONFIG_BRANCHES
    local ghCurrentBranch=${versionScope}_GH_CURRENT_BRANCH
    local vConfigTags=${versionScope}_V_CONFIG_TAGS
    local ghCurrentTag=${versionScope}_GH_CURRENT_TAG

    if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && [[ "${!vRulesEnabled}" == "true" ]] &&  [[ "$(checkIsSubstring \"${!vConfigBranches}\" \"${!ghCurrentBranch}\")" == "true" ]] && [[ "$(checkIsSubstring \"${!vConfigTags}\" \"${!ghCurrentTag}\")" == "true" ]] && [[ ! "$(checkCoreVersionFeatureFlag ${MAJOR_SCOPE})" == "true" ]] && [[ ! "$(checkCoreVersionFeatureFlag ${MINOR_SCOPE})" == "true" ]] && [[ ! "$(checkCoreVersionFeatureFlag ${PATCH_SCOPE})" == "true" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

function checkBuildVersionFeatureFlag() {
    local versionScope=$1
    
    local vRulesEnabled=${versionScope}_V_RULES_ENABLED
    local vConfigBranches=${versionScope}_V_CONFIG_BRANCHES
    local ghCurrentBranch=${versionScope}_GH_CURRENT_BRANCH

    if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && [[ "${!vRulesEnabled}" == "true" ]] && [[ "$(checkIsSubstring \"${!vConfigBranches}\" \"${!ghCurrentBranch}\")" == "true" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

function checkReplacementFeatureFlag() {
    local versionScope=$1
    
    local vRulesEnabled=${versionScope}_V_RULES_ENABLED
    if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && [[ "${!vRulesEnabled}" == "true" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

function processWithCoreVersionFile() {
    local inputVersion=$1
    local versionPos=$2
    local versionScope=$3

    local versionFileRuleEnabled=${versionScope}_V_RULE_VFILE_ENABLED
    local currentIncrementedVersion="$inputVersion"
    if [[ "$(checkCoreVersionFeatureFlag ${versionScope})" == "true" ]] && [[ "${!versionFileRuleEnabled}" == "true" ]]; then
        currentIncrementedVersion=$(incrementCoreVersionByFile $currentIncrementedVersion ${versionPos} ${versionScope})
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


function debugCoreVersionVariables() {
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

    echo $vRulesEnabled=${!vRulesEnabled} 
    echo $ruleBranchEnabled=${!ruleBranchEnabled} 
    echo $ruleVersionFileEnabled=${!ruleVersionFileEnabled} 
    echo $vConfigBranches=${!vConfigBranches} 
    echo $vCurrentBranch=${!vCurrentBranch} 
    echo $vConfigTags=${!vConfigTags}  
    echo $vCurrentTag=${!vCurrentTag} 
    echo ==========================================
}

## Read the versions generated from get_latest_version.sh
currentDevSemanticVersion=$(echo $lastDevVersion | awk -F'-dev' '{print $1}')
currentRelSemanticVersion=$(echo $lastRelVersion | awk -F'-rc' '{print $1}')

## Ensure the latest read version sequence is valid
versionCompareLessOrEqual $currentRelSemanticVersion $currentDevSemanticVersion $ && VERSION_VALID=$(echo "checked") || VERSION_VALID=$(echo "no")
echo "[INFO] Version validation: [$VERSION_VALID]"
if [[ "" == "no" ]]; then
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed version validation. Release/PROD version should not be ahead of Dev/RC version"
    exit 1
fi

## Instrument core version variables which can be made dummy based on the config 
degaussCoreVersionVariables $MAJOR_SCOPE
degaussCoreVersionVariables $MINOR_SCOPE
degaussCoreVersionVariables $PATCH_SCOPE
degaussPreReleaseVersionVariables $RC_SCOPE
degaussPreReleaseVersionVariables $DEV_SCOPE

## Start incrementing
## Debug section
debugCoreVersionVariables MAJOR
debugCoreVersionVariables MINOR
debugCoreVersionVariables PATCH

nextVersion=$currentRelSemanticVersion
echo [INFO] Before incremented: $currentRelSemanticVersion
## Process incrementation on MAJOR, MINOR and PATCH
if [[ "$(checkCoreVersionFeatureFlag ${MAJOR_SCOPE})" == "true" ]] && [[ ! "${MAJOR_V_RULE_VFILE_ENABLED}" == "true" ]]; then
    # echo [DEBUG] currentRelSemanticVersion=$nextVersion
    nextVersion=$(incrementCoreVersion $nextVersion ${MAJOR_POSITION})
    echo [DEBUG] MAJOR INCREMENTED $nextVersion
elif [[ "$(checkCoreVersionFeatureFlag ${MINOR_SCOPE})" == "true" ]] && [[ ! "${MINOR_V_RULE_VFILE_ENABLED}" == "true" ]]; then
    # echo [DEBUG] currentRelSemanticVersion=$nextVersion
    nextVersion=$(incrementCoreVersion $nextVersion ${MINOR_POSITION})
    echo [DEBUG] MINOR INCREMENTED $nextVersion
elif [[ "$(checkCoreVersionFeatureFlag ${PATCH_SCOPE})" == "true" ]] && [[ ! "${PATCH_V_RULE_VFILE_ENABLED}" == "true" ]]; then
    # echo [DEBUG] currentRelSemanticVersion=$nextVersion
    nextVersion=$(incrementCoreVersion $nextVersion ${PATCH_POSITION})
    echo [DEBUG] PATCH INCREMENTED $nextVersion
fi
echo [INFO] After core version incremented: $nextVersion
## Process incrementation on MAJOR, MINOR and PATCH via version file (manual)
nextVersion=$(processWithCoreVersionFile ${nextVersion} ${MAJOR_POSITION} ${MAJOR_SCOPE})
if [[ $? -ne 0 ]]; then
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed processing incrementation on MAJOR, MINOR and PATCH via version file on MAJOR VERSION."
    echo "[ERROR_MSG] $nextVersion"
    exit 1
fi
nextVersion=$(processWithCoreVersionFile ${nextVersion} ${MINOR_POSITION} ${MINOR_SCOPE})
if [[ $? -ne 0 ]]; then
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed processing incrementation on MAJOR, MINOR and PATCH via version file on MINOR VERSION."
    echo "[ERROR_MSG] $nextVersion"
    exit 1
fi
nextVersion=$(processWithCoreVersionFile ${nextVersion} ${PATCH_POSITION} ${PATCH_SCOPE})
if [[ $? -ne 0 ]]; then
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed processing incrementation on MAJOR, MINOR and PATCH via version file on PATCH VERSION."
    echo "[ERROR_MSG] $nextVersion"
    exit 1
fi
echo [INFO] After core version file incremented: $nextVersion



## Debug section
debugPreReleaseVersionVariables $RC_SCOPE
debugPreReleaseVersionVariables $DEV_SCOPE

## Process incrementation on RC and DEV 
echo [INFO] Before release version incremented: $lastRelVersion
echo [INFO] Before dev version incremented: $lastDevVersion
if [[ "$(checkPreReleaseVersionFeatureFlag ${RC_SCOPE})" == "true" ]] && [[ ! "${RC_V_RULE_VFILE_ENABLED}" == "true" ]]; then
    nextVersion=$(incrementPreReleaseVersion "$lastRelVersion" "$RC_V_IDENTIFIER")
    if [[ "$MOCK_ENABLED" == "true" ]]; then
        if [[ ! -f $MOCK_FILE ]]; then
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate mock file: [$MOCK_FILE]"
            exit 1
        fi
        cat $MOCK_FILE | grep -v "${MOCK_REL_VERSION_KEYNAME}" > $MOCK_FILE.tmp
        mv $MOCK_FILE.tmp $MOCK_FILE
        echo ${MOCK_REL_VERSION_KEYNAME}=$nextVersion >> $MOCK_FILE
    fi
elif [[ "$(checkPreReleaseVersionFeatureFlag ${DEV_SCOPE})" == "true" ]] && [[ ! "${DEV_V_RULE_VFILE_ENABLED}" == "true" ]]; then
    nextVersion=$(incrementPreReleaseVersion "$lastDevVersion" "$DEV_V_IDENTIFIER")
    if [[ "$MOCK_ENABLED" == "true" ]]; then
        if [[ ! -f $MOCK_FILE ]]; then
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate mock file: [$MOCK_FILE]"
            exit 1
        fi
        cat $MOCK_FILE | grep -v "${MOCK_DEV_VERSION_KEYNAME}" > $MOCK_FILE.tmp
        mv $MOCK_FILE.tmp $MOCK_FILE
        echo ${MOCK_DEV_VERSION_KEYNAME}=$nextVersion >> $MOCK_FILE
    fi
fi
echo [INFO] After prerelease version incremented: $nextVersion

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
elif [[ "$(checkReplacementFeatureFlag ${REPLACEMENT_SCOPE})" == "true" ]] && [[ "$REPLACE_V_RULE_MAVEN_ENABLED" == "true" ]]; then
    replaceVersionForMaven "$nextVersion" "$REPLACE_V_CONFIG_MAVEN_POMFILE"
    echo "[INFO] Version updated successfully in maven POM file: $REPLACE_V_CONFIG_MAVEN_POMFILE"
fi


# echo "[INFO] nextVersion = $nextVersion"
# echo $artifactName-$nextVersion > $ARTIFACT_NEXT_VERSION_FILE



