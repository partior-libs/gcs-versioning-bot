#!/bin/bash +e 
# Shebang: Specifies the script should be executed with bash.
# '+e': Disables the 'exit immediately if a command exits with a non-zero status' behavior (set -e). 
#       This means the script will attempt to continue even if some commands fail, which might be intentional or risky depending on context.

## Reading action's global setting
# This section attempts to locate and load a global configuration file named 'general.ini'.
# It defines variables and settings used throughout the script and potentially other related scripts.
if [[ ! -z $BASH_SOURCE ]]; then
    # If BASH_SOURCE is set (usually true when the script is sourced or executed directly),
    # find 'general.ini' in the parent directory of the script's location.
    ACTION_BASE_DIR=$(dirname $BASH_SOURCE) 
    source $(find $ACTION_BASE_DIR/.. -type f -name general.ini) 
elif [[ $(find . -type f -name general.ini | wc -l) > 0 ]]; then
    # If not found relative to the script source, look in the current directory (.).
    source $(find . -type f -name general.ini) 
elif [[ $(find .. -type f -name general.ini | wc -l) > 0 ]]; then
    # If not found in the current directory, look in the parent directory (..).
    source $(find .. -type f -name general.ini) 
else
    # If 'general.ini' cannot be found in any of the expected locations, print an error and exit.
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to find and source general.ini" 
    exit 1 
fi

# Assign command-line arguments to variables for clarity.
artifactName="$1"          # Argument 1: The name of the artifact being versioned.
currentBranch=$(echo $2 | cut -d'/' -f1) # Argument 2: The source branch name (extracts branch name if format is 'refs/heads/branch').
currentLabel="$3"          # Argument 3: Label associated with the current context (e.g., GitHub label, potentially a file path).
currentTag="$4"            # Argument 4: Tag associated with the current context (e.g., Git tag, potentially a file path).
currentMsgTag="$5"         # Argument 5: Message tag (e.g., keywords in commit message, potentially a file path).
rebaseReleaseVersion="$6"  # Argument 6: Optional target release version for rebasing/hotfixing.
versionListFile="$7"       # Argument 7: Path to a file containing a list of existing versions (used for file-based increments).
isDebug="$8"               # Argument 8: Flag to enable verbose debug logging ('true' enables).

# Reset global state flags/files before processing.
# Ensures a clean state for each run, preventing interference from previous runs.
rm -f $CORE_VERSION_UPDATED_FILE       # File indicating if the core (X.Y.Z) version was programmatically updated.
rm -f $TRUNK_CORE_NEED_INCREMENT_FILE  # File indicating if the core version needs incrementing based on pre-release logic.
echo "$VBOT_NIL" > $TRUNK_CORE_NEED_INCREMENT_FILE # Initialize the 'need increment' flag to a 'nil' or 'false' state.

## Set the current branch - Export makes it available to sub-processes if needed.
export currentBranch="$currentBranch" 

## Trim away the build info (+metadata) from the last known versions read from files.
# Uses 'cut' to keep only the part before the first '+' symbol, adhering to SemVer parsing rules.
lastDevVersion=$(cat $ARTIFACT_LAST_DEV_VERSION_FILE | cut -d"+" -f1) # Last Development version (e.g., X.Y.Z-dev.N)
lastRCVersion=$(cat $ARTIFACT_LAST_RC_VERSION_FILE | cut -d"+" -f1)  # Last Release Candidate version (e.g., X.Y.Z-rc.N)
lastRelVersion=$(cat $ARTIFACT_LAST_REL_VERSION_FILE | cut -d"+" -f1) # Last full Release version (e.g., X.Y.Z)
lastBaseVersion=$(cat $ARTIFACT_LAST_BASE_VERSION_FILE | cut -d"+" -f1) # Last Base/Hotfix version (e.g., X.Y.Z-hf.N)

## Check if it's initial version
# Reads a flag from a file to determine if this is the very first version being generated for this artifact.
isInitialVersion=false 
if [[ -f "$FLAG_FILE_IS_INITIAL_VERSION" ]]; then 
    isInitialVersion=$(cat $FLAG_FILE_IS_INITIAL_VERSION) 
fi

# Log initial information and input parameters.
echo "[INFO] Start generating package version..." 
echo "[INFO] Artifact Name: $artifactName" 
echo "[INFO] Source branch: $currentBranch" 
echo "[INFO] Last Dev version in Artifactory: $lastDevVersion" 
echo "[INFO] Last RC version in Artifactory: $lastRCVersion" 
echo "[INFO] Last Release version in Artifactory: $lastRelVersion" 
echo "[INFO] Last Base version in Artifactory: $lastBaseVersion" 
echo "[INFO] Target rebase release version: ${rebaseReleaseVersion}" 
echo "[INFO] Initial version: $ARTIFACT_INITIAL_VERSION" # Likely the configured starting version (e.g., 0.1.0 or 1.0.0)
echo "[INFO] Is initial version?: $isInitialVersion" 

## Ensure dev and rel version are in sync
# Function: versionCompareLessOrEqual
# Compares two semantic versions ($1 and $2).
# Returns true (exit code 0) if $1 is less than or equal to $2 based on version sorting.
function versionCompareLessOrEqual() { 
    # Uses 'sort -V' (version sort) and checks if $1 is the first element after sorting.
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ] 
}

## Reset value to global variables
# Function: resetLastArtifactFiles
# Reloads the 'last*' version variables from their respective files, 
# again stripping build metadata. Useful after potentially updating these files mid-script.
function resetLastArtifactFiles() { 
    lastDevVersion=$(cat $ARTIFACT_LAST_DEV_VERSION_FILE | cut -d"+" -f1) 
    lastRCVersion=$(cat $ARTIFACT_LAST_RC_VERSION_FILE | cut -d"+" -f1) 
    lastRelVersion=$(cat $ARTIFACT_LAST_REL_VERSION_FILE | cut -d"+" -f1) 
    lastBaseVersion=$(cat $ARTIFACT_LAST_BASE_VERSION_FILE | cut -d"+" -f1) 

}
# Function: needToIncrementRelVersion
# Determines if the core release part (X.Y.Z) of a pre-release version ($1) necessitates 
# incrementing the current release version ($2).
# When increment pre-release, make sure the release version is considered
function needToIncrementRelVersion() { 
    local inputCurrentVersion=$1 # The pre-release version (e.g., 1.2.3-dev.5)
    local inputRelVersion=$2   # The release version to compare against (e.g., 1.2.3)
    
    # Handle cases where versions might be 'nil' (empty or placeholder)
    if [[ "$inputCurrentVersion" != "$VBOT_NIL" && "$inputRelVersion" == "$VBOT_NIL" ]]; then 
        # If there's a current pre-release but no last release, increment is not needed based on comparison.
        echo "false" 
    # Check if the core part of the pre-release matches the release version.
    elif [[  "$inputRelVersion" == "$(echo $inputCurrentVersion | cut -d'-' -f1)" ]]; then 
        # If core versions match (e.g., 1.2.3-dev.5 vs 1.2.3), increment is needed for the *next* release.
        echo "true" 
    # Use version sort to check if the pre-release (semantically) comes *before* the release version.
    elif [[ "$inputCurrentVersion" == "`echo -e "$inputCurrentVersion\n$inputRelVersion" | sort -V | head -n1`" ]]; then 
        # If the pre-release is older than the release (e.g., 1.2.3-dev.5 vs 1.3.0), increment is needed.
        echo "true" 
    else     
        # Otherwise (pre-release core is newer, e.g., 1.3.0-dev.1 vs 1.2.3), no increment needed based on this logic.
        echo "false" 
    fi
}

## Derive the top release version to be incremented
# Function: getNeededIncrementReleaseVersion
# Calculates the base X.Y.Z version that should be used for the *next* generated version,
# considering the last dev, rc, and release versions.
function getNeededIncrementReleaseVersion() { 
    local devVersion=$1     # Last Dev version
    local rcVersion=$2      # Last RC version
    local relVersion=$3     # Last Release version
    local newRelVersion=""  # Variable to hold the calculated next base release version

    # Check if Major and Minor increments are configured to come from external files.
    if [[ "$(checkReleaseVersionFile "${MAJOR_SCOPE}")" == "true" ]] && [[ "$(checkReleaseVersionFile "${MINOR_SCOPE}")" == "true" ]]; then 
        # If both are file-driven, no automatic increment needed here; use the existing release version.
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): MAJOR and MINOR are file referenced. No incrementation needed."; fi >&2;  
        newRelVersion=$relVersion 
    else 
        # Otherwise, determine if dev or rc versions require the base release to be incremented.
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): devVersion=$devVersion, rcVersion=$rcVersion, relVersion=$relVersion"; fi >&2;  
        # Check if the dev version necessitates incrementing the release version.
        local devIncrease=$(needToIncrementRelVersion "$devVersion" "$relVersion") 
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): getNeededIncrementReleaseVersion devIncrease=$devIncrease"; fi >&2;  
        newRelVersion=$relVersion # Start with the current release version

        # If devIncrease is false AND devVersion is not nil, it means the dev version's base (X.Y.Z) is *newer* # than the last release version. Update newRelVersion to match the dev version's base.
        if [[ "$devIncrease" == "false" && "$devVersion" != "$VBOT_NIL" ]]; then 
            newRelVersion=$(echo $devVersion | cut -d"-" -f1) 
            # Set a flag indicating the core version was updated based on pre-release logic.
            touch $CORE_VERSION_UPDATED_FILE 
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): getNeededIncrementReleaseVersion newRelVersion1=$newRelVersion"; fi >&2;  
        fi
        # Now, check if the rc version necessitates incrementing the potentially updated newRelVersion.
        local rcIncrease=$(needToIncrementRelVersion "$rcVersion" "$newRelVersion") 
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): getNeededIncrementReleaseVersion rcIncrease=$rcIncrease"; fi >&2;  
        # If rcIncrease is false AND rcVersion is not nil, the rc version's base is newer. Update newRelVersion.
        if [[ "$rcIncrease" == "false" && "$rcVersion" != "$VBOT_NIL" ]]; then 
            newRelVersion=$(echo $rcVersion | cut -d"-" -f1) 
            touch $CORE_VERSION_UPDATED_FILE # Set flag
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): getNeededIncrementReleaseVersion newRelVersion2=$newRelVersion"; fi >&2;  
        fi
    fi  
     
    ## Store the updated rel version in file for next incrementation consideration
    # This file acts as temporary storage for the calculated base X.Y.Z for subsequent steps.
    echo $newRelVersion > $ARTIFACT_UPDATED_REL_VERSION_FILE 
    echo $newRelVersion # Output the calculated base release version
}

## Increment the release version based on semantic position
# Function: incrementReleaseVersion
# Increments the Major (0), Minor (1), or Patch (2) part of a version string.
function incrementReleaseVersion() { 
    local inputVersion=$1     # The version string (e.g., 1.2.3)
    local versionPos=$2     # Position to increment (0=Major, 1=Minor, 2=Patch)
    local incrementalCount=${3:-1} # Amount to increment by (defaults to 1)

    local versionArray='' 
    IFS='. ' read -r -a versionArray <<< "$inputVersion" # Split version into an array
    # Increment the specified position
    versionArray[$versionPos]=$((versionArray[$versionPos]+incrementalCount)) 
    # Reset lower-order positions if Major or Minor was incremented
    if [ $versionPos -lt 2 ]; then versionArray[2]=0; fi # Reset Patch if Major/Minor bumped
    if [ $versionPos -lt 1 ]; then versionArray[1]=0; fi # Reset Minor if Major bumped
    # Join the array back into a string
    local incrementedRelVersion=$(local IFS=. ; echo "${versionArray[*]}") 
    # Store in a file to be used in pre-release increment consideration later
    echo $incrementedRelVersion > $ARTIFACT_UPDATED_REL_VERSION_FILE 
    echo $incrementedRelVersion # Output the incremented version
}

## Increment pre-release version based on identifier
# Function: incrementPreReleaseVersion
# Handles the logic for incrementing pre-release versions (e.g., -dev.N, -rc.N).
function incrementPreReleaseVersion() { 
    local inputVersion=$1      # The *last* known version with this pre-release identifier (e.g., 1.2.3-dev.5 or 'nil')
    local preIdentifider=$2  # The identifier string (e.g., "dev", "rc")

    local currentSemanticVersion='' # Holds the calculated X.Y.Z part
    local trunkCoreIncrement="$(cat $TRUNK_CORE_NEED_INCREMENT_FILE)" # Check the flag set earlier
    ## If not pre-release, then increment the core version too (This comment seems slightly misleading based on the code)
    local lastRelVersion=$(cat $ARTIFACT_LAST_REL_VERSION_FILE) # Get the last release version
    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): lastRelVersion=$lastRelVersion" >&2; fi 

    # If a base X.Y.Z was calculated and stored earlier, use that.
    if [[ -f $ARTIFACT_UPDATED_REL_VERSION_FILE ]]; then 
        lastRelVersion=$(cat $ARTIFACT_UPDATED_REL_VERSION_FILE) 
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): lastRelVersion=$lastRelVersion" >&2; fi 
    fi
    ## If not fixed release (doesn't look like X.Y.Z), then reset (treat as no last release)
    if (! echo $lastRelVersion | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+$"); then 
        lastRelVersion="" 
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): lastRelVersion=$lastRelVersion" >&2; fi 
    fi

    ## Return vanilla if not found (if inputVersion is 'nil')
    if [[ "$inputVersion" == "$VBOT_NIL" ]]; then 
        # If no previous version with this identifier exists, start from .1 using the determined 'lastRelVersion'.
        echo "[DEBUG] Pre-release version not found. Resetting to [$lastRelVersion-$preIdentifider.1]" >&2 
        echo $lastRelVersion-$preIdentifider.1 
        return 0 
    fi
    # Extract the core version part (X.Y.Z) from the input pre-release version.
    currentSemanticVersion=$(echo $inputVersion | grep -Po "^\d+\.\d+\.\d+-$preIdentifider") 
    if [[ $? -ne 0 ]]; then 
        # Error if the input version format is invalid.
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to increase prerelease version. Invalid inputVersion format: $inputVersion" >&2 
        echo "[ERROR_MSG] $currentSemanticVersion" >&2 
        exit 1 
    fi
    ## Clean up identifier (remove '-identifier' part)
    currentSemanticVersion=$(echo $currentSemanticVersion | sed "s/-$preIdentifider//g") 
    # Extract the pre-release number (N from -identifier.N)
    local currentPrereleaseNumber=$(echo $inputVersion | awk -F"-$preIdentifider." '{print $2}') 

    ## Ensure it's digit
    if [[ ! "$currentPrereleaseNumber" =~ ^[0-9]+$ ]]; then 
        # If extraction failed or wasn't a number, default to 0.
        currentPrereleaseNumber=0 
    fi
    # Calculate the next pre-release number.
    local nextPreReleaseNumber=$(( $currentPrereleaseNumber + 1 )) 

    # Logic to determine the correct X.Y.Z part for the *next* pre-release version:
    if [[ ! "$inputVersion" == *"-"* ]]; then 
        # If the input wasn't actually a pre-release (e.g., just X.Y.Z was passed, though function expects pre-release)
        if [[ "$lastRelVersion" = "" ]]; then 
            # If no reference release, increment patch on the input version.
            currentSemanticVersion=$(incrementReleaseVersion $currentSemanticVersion ${PATCH_POSITION}) 
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): currentSemanticVersion=$currentSemanticVersion" >&2; fi 
        else  ## Increment with last release version if present
            # If reference release exists, increment patch on *that*.
            currentSemanticVersion=$(incrementReleaseVersion $lastRelVersion ${PATCH_POSITION}) 
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): currentSemanticVersion=$currentSemanticVersion" >&2; fi 
        fi
    else 
        # If the input *was* a pre-release:
        # Determine if the core release needs incrementing based on this input pre-release vs. the reference release.
        local needIncreaseVersion=$(needToIncrementRelVersion "$inputVersion" "$lastRelVersion") 
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): needToIncrementRelVersion inputVersion=$inputVersion, lastRelVersion=$lastRelVersion, needIncreaseVersion=$needIncreaseVersion" >&2; fi 
        
        # Complex conditions to decide the base X.Y.Z and if the pre-release number resets to 1:
        if [[ "$trunkCoreIncrement" == "false" ]]; then 
            # If the 'trunk core increment' flag is explicitly false, use the reference release version and reset to .1.
            currentSemanticVersion=$lastRelVersion 
            nextPreReleaseNumber=1 
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): currentSemanticVersion=$currentSemanticVersion" >&2; fi 
        elif [[ -f $CORE_VERSION_UPDATED_FILE ]]; then 
            # If the core version was updated earlier (e.g., by getNeededIncrementReleaseVersion), use that updated version and reset to .1.
            currentSemanticVersion=$lastRelVersion # (lastRelVersion would have been updated from the file)
            nextPreReleaseNumber=1 
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): currentSemanticVersion=$currentSemanticVersion" >&2; fi 
        elif [[ "$trunkCoreIncrement" == "true" ]] || [[ "$needIncreaseVersion" == "true" ]]; then 
            # If the trunk flag is true OR the pre-release necessitates an increment, increment the reference release (patch) and reset to .1.
            currentSemanticVersion=$(incrementReleaseVersion $lastRelVersion ${PATCH_POSITION}) 
            nextPreReleaseNumber=1 
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): currentSemanticVersion=$currentSemanticVersion" >&2; fi 
        elif [[ "$needIncreaseVersion" == "false" ]]; then 
            # If no increment needed, keep the same core version and just increment the pre-release number.
            nextPreReleaseNumber=$(( $(echo $inputVersion | awk -F"-$preIdentifider." '{print $2}') + 1)) 
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): currentSemanticVersion=$currentSemanticVersion" >&2; fi 
        fi      
    fi
    # Construct the preliminary next pre-release version string.
    local finalPrereleaseVersion=$currentSemanticVersion-$preIdentifider.$nextPreReleaseNumber 
    
    # Perform a final check/adjustment against other last known pre-release versions (RC and Dev).
    # This prevents potential version collisions if, e.g., the calculated dev version is lower than the existing RC version.
    echo [DEBUG] getPreleaseVersionFromPostTagsCountIncrement "$finalPrereleaseVersion" "$ARTIFACT_LAST_RC_VERSION_FILE" "$preIdentifider" >&2 
    finalPrereleaseVersion=$(getPreleaseVersionFromPostTagsCountIncrement $finalPrereleaseVersion $ARTIFACT_LAST_RC_VERSION_FILE $preIdentifider) 
    echo [DEBUG] getPreleaseVersionFromPostTagsCountIncrement "$finalPrereleaseVersion" "$ARTIFACT_LAST_DEV_VERSION_FILE" "$preIdentifider" >&2 
    finalPrereleaseVersion=$(getPreleaseVersionFromPostTagsCountIncrement $finalPrereleaseVersion $ARTIFACT_LAST_DEV_VERSION_FILE $preIdentifider) 
    
    echo $finalPrereleaseVersion # Output the final calculated pre-release version
}

# Function: getPreleaseVersionFromPostTagsCountIncrement
# Compares a candidate pre-release version ($1) against a reference version from a file ($2) 
# for the same identifier ($3). If the candidate is not strictly newer, it increments the 
# pre-release number to ensure it is.
function getPreleaseVersionFromPostTagsCountIncrement() { 
     
    local currentIncremented=$1 # Candidate version (e.g., 1.2.4-dev.1)
    local lastVersionFile=$2  # File containing reference version (e.g., path to last RC version file)
    local preIdentifider=$3   # Identifier (e.g., "dev", "rc")

    # Check if the reference file exists.
    if [[ ! -f $lastVersionFile ]]; then 
        echo "[ERROR1] $BASH_SOURCE (line:$LINENO): Version file not found: $lastVersionFile" >&2 
        exit 1 
    fi

    local currentSemanticVersion='' 
    # Extract X.Y.Z-identifier part from the candidate version.
    currentSemanticVersion=$(echo $currentIncremented | grep -Po "^\d+\.\d+\.\d+-$preIdentifider") 
    if [[ $? -ne 0 ]]; then 
        ## If not found matching (e.g., input was not a pre-release), return the original version.
        echo "$currentIncremented" 
        return 0 
    fi

    local currentPrereleaseNumber='' 
    # Extract the pre-release number (N) from the candidate version.
    currentPrereleaseNumber=$(echo $currentIncremented | awk -F"-$preIdentifider." '{print $2}' | grep -Po "^\d+") 
    if [[ $? -ne 0 ]]; then 
        # Error if format is invalid.
        echo "[ERROR2] $BASH_SOURCE (line:$LINENO): Invalid currentIncremented format: $currentIncremented" >&2
        echo "[ERROR_MSG] $currentPrereleaseNumber" >&2
        exit 1 
    fi

    local lastFileVersion='' 
    # Extract X.Y.Z-identifier part from the reference file's version.
    lastFileVersion=$(cat $lastVersionFile | grep -Po "^\d+\.\d+\.\d+-$preIdentifider") 
    if [[ $? -ne 0 ]]; then 
        ## If not found matching in the file, return the original candidate version.
        echo "$currentIncremented" 
        return 0 
    fi
    local lastVersionPrereleaseNumber='' 
    # Extract the pre-release number (N) from the reference file's version.
    lastVersionPrereleaseNumber=$(cat $lastVersionFile | awk -F"-$preIdentifider." '{print $2}' | grep -Po "^\d+") 
    if [[ $? -ne 0 ]]; then 
        # Error if file format is invalid.
        echo "[ERROR4] $BASH_SOURCE (line:$LINENO): Invalid lastVersionFile $lastVersionFile file format: $(cat $lastVersionFile)" >&2
        echo "[ERROR_MSG] $lastVersionPrereleaseNumber" >&2
        exit 1 
    fi

    local finalPrereleaseNumber=$currentPrereleaseNumber # Start with the candidate's number
    # Compare only if the X.Y.Z-identifier parts match.
    if [[ "$currentSemanticVersion" == "$lastFileVersion" ]]; then 
        # If the base versions match, ensure the final number is greater than both.
        if [[ $currentPrereleaseNumber -gt $lastVersionPrereleaseNumber ]]; then 
            # Candidate is already newer, keep its number.
            finalPrereleaseNumber=$((currentPrereleaseNumber)) 
        elif [[ $lastVersionPrereleaseNumber -gt $currentPrereleaseNumber ]]; then 
            # Reference file version is newer, increment it by 1.
            finalPrereleaseNumber=$((lastVersionPrereleaseNumber+1)) 
        else 
            # Numbers are equal, increment by 1.
            finalPrereleaseNumber=$((finalPrereleaseNumber+1)) 
        fi
    fi
    # Construct and output the potentially adjusted version string.
    echo $currentSemanticVersion.$finalPrereleaseNumber 

}

## Reset variables that's not used, to simplify requirement evaluation later
# Function: degaussCoreVersionVariables
# "Degausses" (neutralizes) variables related to MAJOR, MINOR, PATCH increment rules
# if the corresponding rule is disabled in the configuration.
# It sets the relevant GH_CURRENT_* variable to 'false' if the rule is off.
# This simplifies later 'check*FeatureFlag' functions.
function degaussCoreVersionVariables() { 
    local versionScope=$1 # Scope (e.g., MAJOR, MINOR, PATCH)
    local tmpVariable=source-$(date +%s)-core.tmp # Temporary file for sourcing exports
    rm -f $tmpVariable # Remove any pre-existing temp file

    # Get the names of the configuration variables for this scope.
    local branchEnabled=${versionScope}_V_RULE_BRANCH_ENABLED 
    local labelRuleEnabled=${versionScope}_V_LABEL_RULE_ENABLED 
    local tagRuleEnabled=${versionScope}_V_RULE_TAG_ENABLED 
    local msgTagRuleEnabled=${versionScope}_V_RULE_MSGTAG_ENABLED 
    local versionFileRuleEnabled=${versionScope}_V_RULE_VFILE_ENABLED 

    # Get the names of the corresponding "current context" variables.
    local vCurrentBranch=${versionScope}_GH_CURRENT_BRANCH 
    local vCurrentLabel=${versionScope}_GH_CURRENT_LABEL 
    local vCurrentTag=${versionScope}_GH_CURRENT_TAG 
    local vCurrentMsgTag=${versionScope}_GH_CURRENT_MSGTAG 
    local vCurrentVersionFile=${versionScope}_GH_CURRENT_VFILE 

    # Write export commands to the temporary file, initially setting current values.
    echo "export ${vCurrentBranch}=$currentBranch" >> $tmpVariable 

    # Handle cases where label/tag/msgtag might be file paths - read content if so.
    if [[ -f $currentLabel ]]; then  
        cat $currentLabel > $vCurrentLabel # If it's a file, variable name becomes file content? Risky?
        echo "export ${vCurrentLabel}=${vCurrentLabel}" >> $tmpVariable # This looks incorrect, should likely export the content.
    else  
        echo "export ${vCurrentLabel}=${currentLabel}" >> $tmpVariable # Export the string value.
    fi

    if [[ -f $currentTag ]]; then  
        cat $currentTag > $vCurrentTag # Same potential issue as label.
        echo "export ${vCurrentTag}=${vCurrentTag}" >> $tmpVariable 
    else  
        echo "export ${vCurrentTag}=${currentTag}" >> $tmpVariable 
    fi

    if [[ -f $currentMsgTag ]]; then  
        cat $currentMsgTag > $vCurrentMsgTag # Same potential issue.
        echo "export ${vCurrentMsgTag}=${vCurrentMsgTag}" >> $tmpVariable 
    else  
        # Ensure quotes are handled if the message tag is a string.
        echo "export ${vCurrentMsgTag}=\"${currentMsgTag}\"" >> $tmpVariable 
    fi


    # Check if each rule type is enabled. If not, write an export command to set the
    # corresponding config and current context variables to 'false' in the temp file.
    # `${!varName}` is indirect variable expansion (get value of variable whose name is in varName).
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
    
    # Source the temporary file to apply the exports in the current shell.
    source ./$tmpVariable 
    # Display the content of the temp file (for debugging).
    cat ./$tmpVariable 
    # rm -f $tmpVariable # Optionally remove the temp file (commented out).
}

## Reset variables that's not used, to simplify requirement evaluation later
# Function: degaussReleaseVersionVariables (Seems incomplete/potentially incorrect scope name)
# Similar to degaussCoreVersionVariables, but appears intended for release-specific rules (merge?).
# Note: Uses vCurrentBranch and vCurrentTag, but checks for MERGE rule. Logic might be mixed up.
function degaussReleaseVersionVariables() { 
    local versionScope=$1 
    local tmpVariable=source-$(date +%s)-release.tmp 
    rm -f $tmpVariable 

    local branchEnabled=${versionScope}_V_RULE_BRANCH_ENABLED 
    local versionMergeRuleEnabled=${versionScope}_V_RULE_MERGE_ENABLED # Merge rule check

    local ghCurrentBranch=${versionScope}_GH_CURRENT_BRANCH 
    local ghCurrentMerge=${versionScope}_GH_CURRENT_MERGE # Merge context variable

    # Exports initial values
    echo "export ${vCurrentBranch}=$currentBranch" >> $tmpVariable # Uses vCurrentBranch but named ghCurrentBranch above?
    echo "export ${vCurrentTag}=$currentTag" >> $tmpVariable       # Uses vCurrentTag - relevance to merge rule?

    #echo "[DEBUG] branchEnabled==>${!branchEnabled}" 
    if [[ ! "${!branchEnabled}" == "true" ]]; then 
        echo "export ${versionScope}_V_CONFIG_BRANCHES=false" >> $tmpVariable 
        echo "export ${vCurrentBranch}=false" >> $tmpVariable # Uses vCurrentBranch again
    fi
    # Checks MERGE rule, but neutralizes VFILE config and variable? Seems incorrect.
    if [[ ! "${!versionMergeRuleEnabled}" == "true" ]]; then 
        echo "export ${versionScope}_V_CONFIG_VFILE_NAME=false" >> $tmpVariable 
        echo "export ${vCurrentVersionFile}=false" >> $tmpVariable # Uses VFILE variable
    fi
    source ./$tmpVariable 
    # rm -f $tmpVariable 
}

## Reset variables that's not used, to simplify requirement evaluation later
# Function: degaussPreReleaseVersionVariables
# Degausses variables for Pre-Release scopes (RC, DEV). Checks Branch, Tag, and Version File rules.
function degaussPreReleaseVersionVariables() { 
    local versionScope=$1 # Scope (e.g., RC, DEV)
    local tmpVariable=source-$(date +%s)-prerelease.tmp 
    rm -f $tmpVariable 

    local branchEnabled=${versionScope}_V_RULE_BRANCH_ENABLED 
    local tagRuleEnabled=${versionScope}_V_RULE_TAG_ENABLED 
    local versionFileRuleEnabled=${versionScope}_V_RULE_VFILE_ENABLED 

    local vCurrentBranch=${versionScope}_GH_CURRENT_BRANCH 
    local vCurrentTag=${versionScope}_GH_CURRENT_TAG 
    local vCurrentVersionFile=${versionScope}_GH_CURRENT_VFILE 

    echo "export ${vCurrentBranch}=$currentBranch" >> $tmpVariable 
    echo "export ${vCurrentTag}=$currentTag" >> $tmpVariable # Handles file path case? Assumed string here.

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
    # rm -f $tmpVariable 
}

## Reset variables that's not used, to simplify requirement evaluation later
# Function: degaussVersionReplacementVariables
# Degausses variables for the Version Replacement scope (REPLACEMENT). Checks Branch, Tag, Label, MsgTag, VersionFile rules.
function degaussVersionReplacementVariables() { 
    local versionScope=$1 # Scope (REPLACEMENT)
    local tmpVariable=source-$(date +%s)-replacement.tmp 
    rm -f $tmpVariable 

    # Rules for replacement trigger
    local branchEnabled=${versionScope}_V_RULE_BRANCH_ENABLED 
    local tagRuleEnabled=${versionScope}_V_RULE_TAG_ENABLED 
    local labelRuleEnabled=${versionScope}_V_RULE_LABEL_ENABLED 
    local msgTagRuleEnabled=${versionScope}_V_RULE_MSGTAG_ENABLED 
    local versionFileRuleEnabled=${versionScope}_V_RULE_VFILE_ENABLED # VFile rule relevant for *triggering* replacement?

    # Context variables
    local vCurrentBranch=${versionScope}_GH_CURRENT_BRANCH 
    local vCurrentTag=${versionScope}_GH_CURRENT_TAG 
    local vCurrentLabel=${versionScope}_GH_CURRENT_LABEL 
    local vCurrentMsgTag=${versionScope}_GH_CURRENT_MSGTAG 
    local vCurrentVersionFile=${versionScope}_GH_CURRENT_VFILE # VFile context relevant?

    echo "export ${vCurrentBranch}=$currentBranch" >> $tmpVariable 
    echo "export ${vCurrentTag}=$currentTag" >> $tmpVariable # Assumes string

    #echo "[DEBUG] branchEnabled==>${!branchEnabled}" 
    if [[ ! "${!branchEnabled}" == "true" ]]; then 
        echo "export ${versionScope}_V_CONFIG_BRANCHES=false" >> $tmpVariable 
        echo "export ${vCurrentBranch}=false" >> $tmpVariable 
    fi
    if [[ ! "${!labelRuleEnabled}" == "true" ]]; then 
        echo "export ${versionScope}_V_CONFIG_LABELS=false" >> $tmpVariable 
        echo "export ${vCurrentLabel}=false" >> $tmpVariable # Doesn't handle file path case like core degauss
    fi
    if [[ ! "${!msgTagRuleEnabled}" == "true" ]]; then 
        echo "export ${versionScope}_V_CONFIG_MSGTAGS=false" >> $tmpVariable 
        echo "export ${vCurrentMsgTag}=false" >> $tmpVariable # Doesn't handle file path case
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
    rm -f $tmpVariable # Removes temp file
}

## Reset variables that's not used, to simplify requirement evaluation later
# Function: degaussBuildVersionVariables
# Degausses variables for the Build Metadata scope (BUILD). Only checks Branch rule.
function degaussBuildVersionVariables() { 
    local versionScope=$1 # Scope (BUILD)
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
    rm -f $tmpVariable # Removes temp file
}


## Instead of increment with logical 1, this function allow user to pick version from defined file and keyword, to increment release version
# Function: incrementReleaseVersionByFile
# Sets a specific part (Major, Minor, Patch) of a release version based on a value read from an external file.
function incrementReleaseVersionByFile() { 
    local inputVersion=$1     # The version string to modify (e.g., 1.2.3)
    local versionPos=$2     # Position to set (0=Major, 1=Minor, 2=Patch)
    local versionScope=$3     # Scope (e.g., MAJOR) to find config variable names

    # Get the filename and key from configuration variables for the scope.
    local vConfigVersionFile=${versionScope}_V_CONFIG_VFILE_NAME 
    local vConfigVersionFileKey=${versionScope}_V_CONFIG_VFILE_KEY 
    echo "-------------- [DEBUG]: Reading version file: [${!vConfigVersionFile}]" >&2 
    # Check if the configured version file exists.
    if [[ ! -f ${!vConfigVersionFile} ]]; then 
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate version file: [${!vConfigVersionFile}]" >&2 
        return 1 # Return error code
    fi
    # Read the file, grep for the key, and extract the value after '='.
    local tmpVersion=$(cat ./${!vConfigVersionFile} | grep -E "^${!vConfigVersionFileKey}" 2>/dev/null | cut -d"=" -f2) 
     
    # Check if a value was successfully extracted.
    if [[ -z "$tmpVersion" ]]; then 
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to retrieve version value using key [${!vConfigVersionFileKey}] in version file: [${!vConfigVersionFile}]" >&2 
        return 1 # Return error code
    fi
    local versionArray='' 
    echo "-------------- [DEBUG]: inputVersion: [${inputVersion}]" >&2 
    IFS='. ' read -r -a versionArray <<< "$inputVersion" # Split version into array
    # Set the specified position to the value read from the file.
    versionArray[$versionPos]=$tmpVersion 
    # Join array back into a version string and output it.
    echo $(local IFS=. ; echo "${versionArray[*]}") 

}

## Instead of increment with logical 1, this function allow user to pick version from defined file and keyword, to increment pre-release version
# Function: incrementPreReleaseVersionByFile
# Sets the pre-release number (N in -identifier.N) based on a value read from an external file.
# It still calculates the base X.Y.Z part based on standard logic.
function incrementPreReleaseVersionByFile() { 
    local inputVersion=$1      # The *last* known version with this pre-release identifier (e.g., 1.2.3-dev.5 or 'nil')
    local preIdentifider=$2  # The identifier string (e.g., "dev", "rc")
    local versionScope=$3      # Scope (e.g., RC, DEV) to find config variable names

    # Get the filename and key from configuration.
    local vConfigVersionFileName=${versionScope}_V_CONFIG_VFILE_NAME 
    local vConfigVersionFileKey=${versionScope}_V_CONFIG_VFILE_KEY 

    # Check if the file exists.
    if [[ ! -f ${!vConfigVersionFileName} ]]; then 
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate version file: [${!vConfigVersionFileName}]" >&2 
        return 1 # Return error code
    fi
    # Read the pre-release number from the file using the key.
    local preReleaseVersionFromFile=$(cat ./${!vConfigVersionFileName} | grep -E "^${!vConfigVersionFileKey}" 2>/dev/null | cut -d"=" -f2) 

    # Extract the base X.Y.Z part from the input version.
    local currentSemanticVersion=$(echo $inputVersion | awk -F"-$preIdentifider." '{print $1}') 

    ## If not pre-release, then increment the core version too (Comment seems misleading)
    local lastRelVersion=$(cat $ARTIFACT_LAST_REL_VERSION_FILE) 
    # If present, use the updated release version stored earlier.
    if [[ -f $ARTIFACT_UPDATED_REL_VERSION_FILE ]]; then 
        lastRelVersion=$(cat $ARTIFACT_UPDATED_REL_VERSION_FILE) 
    fi
    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): currentSemanticVersion=$currentSemanticVersion" >&2; fi 
    
    # Logic to determine the base X.Y.Z (similar to incrementPreReleaseVersion, but doesn't increment the number).
    if [[ ! "$inputVersion" == *"-"* ]]; then # Input wasn't pre-release
        if [[ "$lastRelVersion" = "" ]]; then # No reference release
            currentSemanticVersion=$(incrementReleaseVersion $currentSemanticVersion ${PATCH_POSITION}) 
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): currentSemanticVersion=$currentSemanticVersion" >&2; fi 
        else  ## Increment with last release version if present
            currentSemanticVersion=$(incrementReleaseVersion $lastRelVersion ${PATCH_POSITION}) 
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): currentSemanticVersion=$currentSemanticVersion" >&2; fi 
        fi
    else # Input was pre-release
        local needIncreaseVersion=$(needToIncrementRelVersion "$inputVersion" "$lastRelVersion") 
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): needIncreaseVersion=$needIncreaseVersion" >&2; fi 
        # Determine base X.Y.Z based on flags and comparison.
        if [[ -f $CORE_VERSION_UPDATED_FILE ]]; then 
            currentSemanticVersion=$lastRelVersion 
            # nextPreReleaseNumber=1 # Not needed here as number comes from file
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): currentSemanticVersion=$currentSemanticVersion" >&2; fi 
        elif [[ "$needIncreaseVersion" == "true" ]]; then 
            currentSemanticVersion=$(incrementReleaseVersion $lastRelVersion ${PATCH_POSITION}) 
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): currentSemanticVersion=$currentSemanticVersion" >&2; fi 
        fi      
    fi

    # Construct the final version using the calculated base and the number from the file.
    echo $currentSemanticVersion-$preIdentifider.$preReleaseVersionFromFile 
}


## Check if given substring is in the comma delimited list
# Function: checkIsSubstring
# Checks if any element in a comma-separated list ($1) is found as a substring within another string ($2).
function checkIsSubstring(){ 
    local listString=$1 # Comma-separated list (e.g., "feat,fix")
    local subString=$2  # String to search within (e.g., "feature/abc")
    local listArray='' 

    # Handle empty inputs: considered a match.
    if [[ -z $listString ]] && [[ -z $subString ]]; then 
        echo "true" 
        return 0 
    fi

    IFS=', ' read -r -a listArray <<< "$listString" # Split list into array
    for eachString in "${listArray[@]}"; 
    do  
        # Check if the current list element is a substring of the target string.
        if [[ "$subString" == *"$eachString"* ]]; then 
            echo "true" # Match found
            return 0 
        fi
    done
    echo "false" # No match found
}

## Check if given comma delimited string is in the content of a file
# Function: checkListIsSubstringInFileContent
# Checks if any element in a comma-separated list ($1) exists as a line/pattern within a file ($2).
# If $2 is not a file path, it falls back to checking if list elements are substrings of the $2 string itself.
function checkListIsSubstringInFileContent () { 
    local listString=$1      # Comma-separated list (e.g., "#major,#minor")
    local fileContentPath=$2 # Path to a file OR a string (e.g., path to commit message file or a label string)
    local listArray='' 

    # Handle empty inputs: considered a match.
    if [[ -z $listString ]] && [[ -z $fileContentPath ]]; then 
        echo "true" 
        return 0 
    fi

    # If $2 is not a file, treat it as a string and use checkIsSubstring logic.
    if [[ ! -f $fileContentPath ]]; then 
        echo $(checkIsSubstring "$listString" "$fileContentPath") 
        return 0 
    fi

    # If $2 is a file, iterate through the list.
    IFS=', ' read -r -a listArray <<< "$listString" 
    for eachString in "${listArray[@]}"; 
    do  
        # Use grep -q (quiet) to check if the string exists in the file content.
        if (grep -q "$eachString" $fileContentPath); then 
            echo "true" # Match found
            return 0 
        fi
    done
    echo "false" # No match found
}

## Check if required flags for incrementing Release version (Major, Minor or Patch) is enabled
# Function: checkReleaseVersionFeatureFlag
# Determines if the conditions are met to trigger a specific release version increment (Major, Minor, or Patch).
# Combines global enable flags, scope-specific rules, and context checks (branch, label, tag, message tag).
function checkReleaseVersionFeatureFlag() { 
    local versionScope=$1 # Scope (MAJOR, MINOR, PATCH)
     
    # Get names of configuration and context variables using the scope.
    local vRulesEnabled=${versionScope}_V_RULES_ENABLED 
    local vConfigBranches=${versionScope}_V_CONFIG_BRANCHES 
    local ghCurrentBranch=${versionScope}_GH_CURRENT_BRANCH 
    local vConfigLabels=${versionScope}_V_CONFIG_LABELS 
    local ghCurrentLabel=${versionScope}_GH_CURRENT_LABEL 
    local vConfigTags=${versionScope}_V_CONFIG_TAGS 
    local ghCurrentTag=${versionScope}_GH_CURRENT_TAG 
    local vConfigMsgTags=${versionScope}_V_CONFIG_MSGTAGS 
    local ghCurrentMsgTag=${versionScope}_GH_CURRENT_MSGTAG 

    # Debugging output (commented out)
    # if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): VERSIONING_BOT_ENABLED=$VERSIONING_BOT_ENABLED" >&2;  
    # ... (other debug lines)

    # Check all conditions: Bot enabled? Scope rule enabled? Branch matches? Label matches? Tag matches? MsgTag matches?
    # Uses helper functions checkIsSubstring (for branch) and checkListIsSubstringInFileContent (for others).
    # Assumes 'degauss' functions have set context variables to 'false' if rules are disabled.
    if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && \
       [[ "${!vRulesEnabled}" == "true" ]] && \
       [[ $(checkIsSubstring "${!vConfigBranches}" "${!ghCurrentBranch}") == "true" ]] && \
       [[ $(checkListIsSubstringInFileContent "${!vConfigLabels}" "${!ghCurrentLabel}") == "true" ]] && \
       [[ $(checkListIsSubstringInFileContent "${!vConfigTags}" "${!ghCurrentTag}") == "true" ]] && \
       [[ $(checkListIsSubstringInFileContent "${!vConfigMsgTags}" "${!ghCurrentMsgTag}") == "true" ]]; then 
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): checkReleaseVersionFeatureFlag=true" >&2; fi 
        echo "true" # All conditions met
    else 
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): checkReleaseVersionFeatureFlag=false" >&2; fi 
        echo "false" # One or more conditions failed
    fi
}

## Check if required flags for incrementing Pre-Release version (Dev or RC) is enabled
# Function: checkPreReleaseVersionFeatureFlag
# Determines if conditions are met to trigger a pre-release increment (RC or Dev).
# Checks Bot enabled, scope rule enabled, branch match, and tag match.
function checkPreReleaseVersionFeatureFlag() { 
    local versionScope=$1 # Scope (RC, DEV)
     
    # Get names of relevant variables.
    local vRulesEnabled=${versionScope}_V_RULES_ENABLED 
    local vConfigBranches=${versionScope}_V_CONFIG_BRANCHES 
    local ghCurrentBranch=${versionScope}_GH_CURRENT_BRANCH 
    local vConfigTags=${versionScope}_V_CONFIG_TAGS 
    local ghCurrentTag=${versionScope}_GH_CURRENT_TAG 

    # Check conditions: Bot enabled? Scope rule enabled? Branch matches? Tag matches?
    if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && \
       [[ "${!vRulesEnabled}" == "true" ]] &&  \
       [[ $(checkIsSubstring "${!vConfigBranches}" "${!ghCurrentBranch}") == "true" ]] && \
       [[ $(checkListIsSubstringInFileContent "${!vConfigTags}" "${!ghCurrentTag}") == "true"  ]]; then 
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): checkPreReleaseVersionFeatureFlag=true" >&2; fi 
        echo "true" # Conditions met
    else 
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): checkPreReleaseVersionFeatureFlag=false" >&2; fi 
        echo "false" # Conditions failed
    fi
}

## Check if required flags for incrementing Build version (Build) is enabled
# Function: checkBuildVersionFeatureFlag
# Determines if conditions are met to append build metadata.
# Checks Bot enabled, scope rule enabled, and branch match.
function checkBuildVersionFeatureFlag() { 
    local versionScope=$1 # Scope (BUILD)
     
    local vRulesEnabled=${versionScope}_V_RULES_ENABLED 
    local vConfigBranches=${versionScope}_V_CONFIG_BRANCHES 
    local ghCurrentBranch=${versionScope}_GH_CURRENT_BRANCH 

    # Check conditions: Bot enabled? Scope rule enabled? Branch matches?
    if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && \
       [[ "${!vRulesEnabled}" == "true" ]] && \
       [[ $(checkIsSubstring "${!vConfigBranches}" "${!ghCurrentBranch}") == "true" ]]; then 
        echo "true" # Conditions met
    else 
        echo "false" # Conditions failed
    fi
}

## Check if required flags for incrementing version with external file is enabled 
# Function: checkReplacementFeatureFlag (Name is slightly confusing, checks if *replacement* is enabled)
# Determines if version replacement in files (pom.xml, etc.) should be performed.
# Checks Bot enabled and scope rule enabled. Scope is REPLACEMENT.
function checkReplacementFeatureFlag() { 
    local versionScope=$1 # Scope (REPLACEMENT)
     
    local vRulesEnabled=${versionScope}_V_RULES_ENABLED 
    # Check conditions: Bot enabled? Scope rule enabled?
    if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && [[ "${!vRulesEnabled}" == "true" ]]; then 
        echo "true" # Conditions met
    else 
        echo "false" # Conditions failed
    fi
}

## Return true if MAJOR, MINOR or PATCH uses versionFile
# Function: checkReleaseVersionFile
# Checks if a specific release scope (Major, Minor, Patch) is both *active* (based on checkReleaseVersionFeatureFlag)
# AND configured to use a version file for its value.
function checkReleaseVersionFile() { 
    local versionScope="$1" # Scope (MAJOR, MINOR, PATCH)
    local versionFileRuleEnabled=${versionScope}_V_RULE_VFILE_ENABLED # Get name of file rule flag
    # Check if the overall feature for this scope is active AND the file rule specifically is enabled.
    if [[ "$(checkReleaseVersionFeatureFlag ${versionScope})" == "true" ]] && [[ "${!versionFileRuleEnabled}" == "true" ]]; then 
        echo "true" 
    else 
        echo "false" 
    fi
}

## Engine to increment Release Version with external file value
# Function: processWithReleaseVersionFile
# This is a complex function that handles setting a release version part (Major, Minor, Patch)
# based on an external file value, BUT it also cross-references a list of existing versions (`versionListFile`)
# to determine the *final* version, potentially overriding the value from the simple key=value file.
# It aims to find the highest existing version matching the new Major[.Minor] prefix and increment appropriately.
function processWithReleaseVersionFile() { 
    local inputVersion="$1"     # Current candidate version (e.g., 1.2.3 or output from previous step)
    local versionPos="$2"     # Position being processed (0, 1, or 2)
    local versionScope="$3"     # Scope (MAJOR, MINOR, PATCH)
    local versionListFile="$4"  # Path to the file listing existing versions

    echo "---------------- [DEBUG] processWithReleaseVersionFile started " >&2 
    # Debug logs for inputs
    echo "[DEBUG] $BASH_SOURCE (line:$LINENO): inputVersion=$inputVersion" >&2 
    echo "[DEBUG] $BASH_SOURCE (line:$LINENO): versionPos=$versionPos" >&2 
    echo "[DEBUG] $BASH_SOURCE (line:$LINENO): versionScope=$versionScope" >&2 
    echo "[DEBUG] $BASH_SOURCE (line:$LINENO): versionListFile=$versionListFile" >&2 

    local versionFileRuleEnabled=${versionScope}_V_RULE_VFILE_ENABLED # Get file rule flag name
    local currentIncrementedVersion="$inputVersion" # Start with the input version

    echo "[DEBUG] $BASH_SOURCE (line:$LINENO): checkReleaseVersionFeatureFlag=$(checkReleaseVersionFeatureFlag ${versionScope}) and versionFileRuleEnabled=${!versionFileRuleEnabled}" >&2 
    # Proceed only if the feature flag for this scope is true AND the file rule is enabled.
    if [[ "$(checkReleaseVersionFeatureFlag ${versionScope})" == "true" ]] && [[ "${!versionFileRuleEnabled}" == "true" ]]; then 
        echo "[DEBUG] $BASH_SOURCE (line:$LINENO): currentIncrementedVersion=$currentIncrementedVersion" >&2 
        # First, get the version part from the simple key=value file.
        currentIncrementedVersion=$(incrementReleaseVersionByFile $currentIncrementedVersion ${versionPos} ${versionScope}) 
        if [[ $? -ne 0 ]]; then 
            # Error if reading from the key=value file failed.
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed retrieving version from version file." >&2 
            echo "[ERROR_MSG] $currentIncrementedVersion" >&2 
            return 1 # Return error code
        fi
        echo "[DEBUG] $BASH_SOURCE (line:$LINENO): Ater incrementReleaseVersionByFile, versionScope=$versionScope, currentIncrementedVersion=$currentIncrementedVersion" >&2 
        
        # For MINOR and PATCH file-based increments, perform the complex lookup in versionListFile.
        if [[ "$versionScope" == "$MINOR_SCOPE" ]] || [[ "$versionScope" == "$PATCH_SCOPE" ]]; then 
            # Check if the version list file exists.
            if [[ ! -f "$versionListFile" ]]; then 
                echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate versionListFile [$versionListFile]" >&2 
                return 1 
            fi
            local tmpPos=$(( versionPos + 1 )) # Position level for prefix (1 for Major, 2 for Major.Minor)

            # Create the prefix to search for (e.g., "1.2" if processing PATCH for 1.2.X)
            local tmpInputVersion=$(echo $currentIncrementedVersion | cut -d"." -f1-"$tmpPos") 
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): tmpInputVersion=$tmpInputVersion" >&2; fi 
            
            # If processing MINOR, ensure the initial candidate version ends in .0 (e.g., 1.3.0)
            if [[ "$versionScope" == "$MINOR_SCOPE" ]]; then 
                currentIncrementedVersion="$tmpInputVersion.0" 
            fi

            # Find the highest existing version in versionListFile matching the prefix (tmpInputVersion).
            # Extracts the version string (assumed to be the 4th double-quoted field on the line).
            local foundVersion=$(cat "$versionListFile" | grep -E "\"$tmpInputVersion(\.|+|-|$|\"|_)*" | sort -rV | head -n1 | cut -d"\"" -f4) 
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): foundVersion=$foundVersion" >&2; fi 

            ## if empty, need to reset (No existing versions match the prefix)
            if [[ -z "$foundVersion" ]]; then 
                ## Reset the core version update flags (as we are resetting based on file lookup).
                rm -f $CORE_VERSION_UPDATED_FILE 
                echo "false" > $TRUNK_CORE_NEED_INCREMENT_FILE 
                # Reset the lower parts of the version (e.g., 1.2 becomes 1.2.0)
                currentIncrementedVersion="$tmpInputVersion"$(resetCoreRelease "$versionPos") 
                if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): currentIncrementedVersion=$currentIncrementedVersion" >&2; fi 
            ## Found the version with correct format (SemVer-like)
            elif (echo $foundVersion | grep -qE '([0-9]+\.){2}[0-9]+(((-|\+)[0-9a-zA-Z]+\.[0-9]+)*(\+[0-9a-zA-Z]+\.[0-9\.]+)*$)'); then  
                # Extract just the X.Y.Z part of the highest found version.
                local releasedVersionOnly=$(echo $foundVersion | grep -oE "^[0-9]+\.[0-9]+\.[0-9]+") 
                ## If fixed release version (X.Y.Z exactly), increment the next logical part.
                if (echo $foundVersion | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+$"); then 
                    echo "false" > $TRUNK_CORE_NEED_INCREMENT_FILE # Reset flag
                    echo $foundVersion > $ARTIFACT_UPDATED_REL_VERSION_FILE # Store the found version as the base
                    # Increment the part *after* the one defined by versionPos (e.g., if versionPos=1 (Minor), increment Patch).
                    currentIncrementedVersion=$(incrementCoreReleaseByPos "$versionPos" "$foundVersion") 
                    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): releasedVersionOnly=$releasedVersionOnly, currentIncrementedVersion=$currentIncrementedVersion" >&2; fi 
                else # The highest found version was a pre-release (e.g., 1.2.3-rc.1)
                    # echo "true" > $TRUNK_CORE_NEED_INCREMENT_FILE # Old logic
                    echo "false" > $TRUNK_CORE_NEED_INCREMENT_FILE # Reset flag      
                    # Check if the exact X.Y.Z part already exists as a full release in the list.
                    if (cat "$versionListFile" | grep -qE "\"$releasedVersionOnly\""); then 
                        # If X.Y.Z exists, store it as the base and increment the next logical part.
                        echo $releasedVersionOnly > $ARTIFACT_UPDATED_REL_VERSION_FILE 
                        currentIncrementedVersion=$(incrementCoreReleaseByPos "$versionPos" "$foundVersion") # Use foundVersion (which includes pre-release) base for increment? Check incrementCoreReleaseByPos logic.
                        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): releasedVersionOnly=$releasedVersionOnly, currentIncrementedVersion=$currentIncrementedVersion" >&2; fi 
                    else 
                        # If X.Y.Z does *not* exist as a full release, use that X.Y.Z as the next version.
                        # (This means the next version will be the release version of the highest pre-release found).
                        echo "[DEBUG] $BASH_SOURCE (line:$LINENO): foundVersion=$foundVersion" >&2 
                        # currentIncrementedVersion=$(incrementReleaseVersion $releasedVersionOnly ${PATCH_POSITION}) # Old commented logic
                        currentIncrementedVersion=$releasedVersionOnly # Use the base X.Y.Z
                        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): versionScope=$versionScope, releasedVersionOnly=$releasedVersionOnly, currentIncrementedVersion=$currentIncrementedVersion" >&2; fi 
                    fi
                         
                fi
                ## Store the latest pre-release into files for post processing later
                # Based on the determined 'releasedVersionOnly', find the highest RC/Dev/Base versions with that prefix in the list file
                # and update the corresponding ARTIFACT_LAST_*_VERSION_FILEs. This synchronizes the 'last known' state.
                if (grep -qE "$releasedVersionOnly\-$RC_V_IDENTIFIER\." $versionListFile); then 
                    lastRCVersion=$(cat "$versionListFile" | grep -E "$releasedVersionOnly\-$RC_V_IDENTIFIER\." | sort -rV | head -n1 | cut -d"\"" -f4) 
                    echo "$lastRCVersion" > $ARTIFACT_LAST_RC_VERSION_FILE 
                else 
                    lastRCVersion="$releasedVersionOnly-$RC_V_IDENTIFIER.0" # Default if none found 
                    echo "$lastRCVersion" > $ARTIFACT_LAST_RC_VERSION_FILE 
                fi
                if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): Reset last RC version to $lastRCVersion" >&2; fi 

                if (grep -qE "$releasedVersionOnly\-$DEV_V_IDENTIFIER\." $versionListFile); then 
                    lastDevVersion=$(cat "$versionListFile" | grep -E "$releasedVersionOnly\-$DEV_V_IDENTIFIER\." | sort -rV | head -n1 | cut -d"\"" -f4) 
                    echo "$lastDevVersion" > $ARTIFACT_LAST_DEV_VERSION_FILE 
                else 
                    lastDevVersion="$releasedVersionOnly-$DEV_V_IDENTIFIER.0" # Default if none found 
                    echo "$lastDevVersion"  > $ARTIFACT_LAST_DEV_VERSION_FILE 
                fi
                if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): Reset last DEV version to $lastDevVersion" >&2; fi 

                if (grep -qE "$releasedVersionOnly\-$REBASE_V_IDENTIFIER\." $versionListFile); then 
                    lastBaseVersion=$(cat "$versionListFile" | grep -E "$releasedVersionOnly\-$REBASE_V_IDENTIFIER\." | sort -rV | head -n1 | cut -d"\"" -f4) 
                    echo "$lastBaseVersion" > $ARTIFACT_LAST_BASE_VERSION_FILE 
                else 
                    lastBaseVersion="$releasedVersionOnly-$REBASE_V_IDENTIFIER.0" # Default if none found 
                    echo "$lastBaseVersion" > $ARTIFACT_LAST_BASE_VERSION_FILE 
                fi
                if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): Reset last REBASE version to $lastBaseVersion" >&2; fi 
                 
            fi # End of foundVersion format check

        fi # End of MINOR/PATCH scope check
    fi # End of feature flag / file rule check
    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): currentIncrementedVersion=$currentIncrementedVersion" >&2; fi 
    # Store the final calculated version if it's a full release.
    # if (echo $currentIncrementedVersion | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+$"); then
    #     echo $currentIncrementedVersion > $ARTIFACT_UPDATED_REL_VERSION_FILE
    #     if [[ "$isDebug" == "true" ]]; then echo "==================================[DEBUG] $BASH_SOURCE (line:$LINENO): currentIncrementedVersion=$currentIncrementedVersion" >&2; fi
    # fi
    echo $currentIncrementedVersion # Output the final version determined by this function
}

# Function: newfunc
# Appears to be a duplicate or leftover development version of `incrementReleaseVersionByFile`.
# It reads a version part from a key=value file.
function newfunc() { 
    local inputVersion=$1 
    local versionPos=$2 
    local versionScope=$3 
       
    local vConfigVersionFile=${versionScope}_V_CONFIG_VFILE_NAME 
    local vConfigVersionFileKey=${versionScope}_V_CONFIG_VFILE_KEY 
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

# Function: incrementCoreReleaseByPos
# Helper function used by `processWithReleaseVersionFile`.
# Given a position (0 for Major, 1 for Minor) and a version (e.g., 1.2.3),
# it increments the *next* position and resets subsequent ones.
# Example: pos=0, input=1.2.3 => outputs 1.3.0 (increments Minor, resets Patch)
# Example: pos=1, input=1.2.3 => outputs 1.2.4 (increments Patch)
function incrementCoreReleaseByPos { 
    local versionPos="$1"    # Position indicating *which part was just set* (0 or 1)
    local inputVersion="$2"  # The version string (X.Y.Z)

    local majorPosVersion=$(echo $inputVersion | cut -d"." -f1) 
    local minorPosVersion=$(echo $inputVersion | cut -d"." -f2) 
    local patchPosVersion=$(echo $inputVersion | cut -d"." -f3 | grep -oE '^[0-9]+') # Ensure only digits for patch
    local currentNeededPosVersion=0 
    local nextNeededPosVersion=0 
    if [[ $versionPos -eq 0 ]]; then # If Major was set/found
        currentNeededPosVersion=$minorPosVersion 
        nextNeededPosVersion=$(( currentNeededPosVersion + 1)) # Increment Minor
        echo "$majorPosVersion.$nextNeededPosVersion.0" # Reset Patch
    elif [[ $versionPos -eq 1 ]]; then # If Minor was set/found
        currentNeededPosVersion=$patchPosVersion 
        nextNeededPosVersion=$(( currentNeededPosVersion + 1)) # Increment Patch
        echo "$majorPosVersion.$minorPosVersion.$nextNeededPosVersion" 
    # TBC - If versionPos is 2 (Patch), this function doesn't define behavior (implicitly no change?)
    fi
}

# Function: resetCoreRelease
# Helper function used by `processWithReleaseVersionFile`.
# Returns the suffix needed to reset version parts based on the position.
# Example: pos=0 => returns ".0.0"
# Example: pos=1 => returns ".0"
function resetCoreRelease { 
    local versionPos="$1" 
    if [[ $versionPos -eq 0 ]]; then 
        echo ".0.0" 
    elif [[ $versionPos -eq 1 ]]; then 
        echo ".0" 
    fi
}

## Function to replace defined token with input version
# Function: replaceVersionInFile
# Replaces a placeholder token (e.g., @@VERSION@@) in a specified file with the calculated version string.
function replaceVersionInFile() { 
    local inputVersion=$1 # The calculated version string
    local targetFile=$2   # Path to the file to modify
    local targetReplacementToken=$(echo $3 | sed "s/@@//g") # Token name (removes surrounding @@ if present)

    # Check if target file exists
    if [[ ! -f "$targetFile" ]]; then 
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate version file to be replaced: [$targetFile]" >&2
        exit 1 
    fi

    # Check if token is provided
    if [[ -z "$targetReplacementToken" ]]; then 
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Replacement token cannot be empty" >&2
        exit 1 
    fi
    ## Replacement start here
    # Use sed -i (in-place) to replace @@TOKEN@@ with the version. Uses '|' as delimiter for sed.
    sed -r -i "s|@@${targetReplacementToken}@@|${inputVersion}|g" $targetFile 
    if [[ $? -ne 0 ]]; then 
        # Error if sed command failed
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed replacing token [@@${targetReplacementToken}@@] in file $targetFile" >&2
        exit 1 
    fi
}

## Replace version in maven POM file
# Function: replaceVersionForMaven
# Uses the Maven versions plugin (`mvn versions:set`) to update the version in a pom.xml file.
function replaceVersionForMaven() { 
    local inputVersion=$1 # The calculated version string
    local targetPomFile=$2 # Path to the pom.xml file

    ## Validate mvn command first
    mvn --version 
    if [[ $? -ne 0 ]]; then 
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Maven command not executable" >&2
        exit 1 
    fi
    # Check if POM file exists
    if [[ ! -f "$targetPomFile" ]]; then 
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate maven POM file: [$targetPomFile]" >&2
        exit 1 
    fi

    ## Replacement start here
    # Execute mvn versions:set command. -q for quiet, -DforceStdout might suppress XML output to console.
    mvn -f $targetPomFile versions:set -DnewVersion=$inputVersion -q -DforceStdout 
    if [[ $? -ne 0 ]]; then 
        # Error if maven command failed
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed setting version in maven POM file [$targetPomFile]" >&2
        exit 1 
    fi
}

## Replace version in yaml file
# Function: replaceVersionForYamlFile
# Uses the 'yq' tool to update a value at a specific path within a YAML file.
function replaceVersionForYamlFile() { 
    local inputVersion="$1"       # The calculated version string
    local targetYamlFile="$2"     # Path to the YAML file
    local targetYamlQueryPath="$3" # yq query path (e.g., '.app.version')

    ## Validate yq command first
    yq --version 
    if [[ $? -ne 0 ]]; then 
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): YQ command not executable" >&2
        exit 1 
    fi
    # Check if YAML file exists
    if [[ ! -f "$targetYamlFile" ]]; then 
        # Typo in error message (PomFile)
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to locate YAML file: [$targetYamlFile]" >&2 # Corrected targetPomFile -> targetYamlFile, Added >&2
        exit 1 
    fi

    ## Replacement start here
    # Use yq -i (in-place) to set the value at the query path. Ensures inputVersion is quoted.
    yq -i "$targetYamlQueryPath = \"$inputVersion\"" $targetYamlFile 
    if [[ $? -ne 0 ]]; then 
        # Error if yq command failed
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed updating version in YAML file [$targetYamlFile]" >&2
        exit 1 
    fi
}

## Get incremental count on release version
# Function: getIncrementalCount
# Counts the total occurrences of specified keywords (comma-separated list $1)
# within a file or string ($2). Used to increment version by more than 1 based on commit messages/tags.
function getIncrementalCount() { 
    local listString=$1      # Comma-separated list of keywords (e.g., "#major,#MAJOR")
    local fileContentPath=$2 # Path to file (e.g., commit message) or a string
    local listArray='' 

    # Handle empty inputs: default increment is 1 (or maybe 0? Code returns 1).
    if [[ -z $listString ]] && [[ -z $fileContentPath ]]; then 
        echo "1" # Returns 1 if inputs are empty.
        return 0 
    fi

    local incrementCounter=0 
    IFS=', ' read -r -a listArray <<< "$listString" # Split keywords
    for eachString in "${listArray[@]}"; 
    do  
        local foundPatternCount=0 
        if [[ -f $fileContentPath ]]; then 
            # If it's a file, count occurrences using grep -o (only matching) and wc -l (line count). Case-insensitive (-i).
            foundPatternCount=$(grep -o -i "$eachString" $fileContentPath | wc -l) 
             
        else 
            # If it's a string, use echo | grep | wc. Case-insensitive.
            foundPatternCount=$(echo $fileContentPath | grep -o -i "$eachString" | wc -l) 
        fi
        # Add count for this keyword to the total.
        incrementCounter=$((incrementCounter + foundPatternCount)) 
    done
    
    # Return the total count, or 0 if no keywords were found.
    if [[ $incrementCounter -eq 0 ]]; then 
        echo 0 
    else 
        echo $incrementCounter 
    fi
    return 0 # Success exit code

}

## Check if contain non release incrementation (rc, dev, bld, etc)
# Function: isPreReleaseIncrementation
# Determines if any *automatic* (non-file-based) pre-release (RC, Dev) or build incrementation is active.
function isPreReleaseIncrementation() { 
    local preReleaseFlag='false' # Default to false
    # Check if RC increment is active AND not driven by a file.
    if [[ "$(checkPreReleaseVersionFeatureFlag ${RC_SCOPE})" == "true" ]] && [[ ! "${RC_V_RULE_VFILE_ENABLED}" == "true" ]]; then 
        preReleaseFlag='true' 
    # Check if Dev increment is active AND not driven by a file.
    elif [[ "$(checkPreReleaseVersionFeatureFlag ${DEV_SCOPE})" == "true" ]] && [[ ! "${DEV_V_RULE_VFILE_ENABLED}" == "true" ]]; then 
        preReleaseFlag='true' 
    # Check if Build metadata appending is active.
    elif [[ "$(checkBuildVersionFeatureFlag ${BUILD_SCOPE})" == "true" ]]; then 
        preReleaseFlag='true' 
    fi

    echo "$preReleaseFlag" # Output true or false
}

## For debugging purpose
# Function: debugReleaseVersionVariables
# Prints the state of configuration and context variables for a given release scope (Major, Minor, Patch).
function debugReleaseVersionVariables() { 
    local versionScope=$1 
    echo ========================================== 
    echo [DEBUG] SCOPE: $versionScope 

    # Variable name setup
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

    # Print variable values using indirect expansion ${!varName}
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
# Function: debugPreReleaseVersionVariables
# Prints the state of variables for a pre-release scope (RC, Dev).
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
# Function: debugBuildVersionVariables
# Prints the state of variables for the build scope (BUILD).
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

# ============================================================
#                      MAIN SCRIPT LOGIC
# ============================================================

## Instrument core version variables which can be made dummy based on the config 
# Call degauss functions to neutralize variables for disabled rules.
degaussCoreVersionVariables $MAJOR_SCOPE 
degaussCoreVersionVariables $MINOR_SCOPE 
degaussCoreVersionVariables $PATCH_SCOPE 
degaussPreReleaseVersionVariables $RC_SCOPE 
degaussPreReleaseVersionVariables $DEV_SCOPE 

## Start incrementing
## Debug section - Print variable states if debug mode is enabled.
if [[ "$isDebug" == "true" ]]; then 
    debugReleaseVersionVariables MAJOR 
    debugReleaseVersionVariables MINOR 
    debugReleaseVersionVariables PATCH 
fi

currentInitialVersion=""  # Initialize variable, purpose unclear here.
# Initialize nextVersion - will hold the calculated version throughout the process.
nextVersion="" 

# Check if this is a rebase/hotfix scenario (based on input argument 6).
if [[ ! -z "${rebaseReleaseVersion}" ]]; then 
    # --- Hotfix/Rebase Branch Logic ---
    baseCurrentVersion="$lastBaseVersion" # Use the last known base/hotfix version.
    if [[ -z "$lastBaseVersion" ]] || [[ "$lastBaseVersion" == "$VBOT_NIL" ]]; then # Handle nil/empty case
        # If no previous base version, start from .0 using the provided rebase release version.
        baseCurrentVersion="${rebaseReleaseVersion}-$REBASE_V_IDENTIFIER.0" 
    fi
    # Extract the current rebase/hotfix number (N from -hf.N).
    currentRebasePatchNum=$(echo "$baseCurrentVersion" | awk -F"-$REBASE_V_IDENTIFIER." '{print $2}') 
    # Increment the rebase/hotfix number.
    nextRebasePatchNum=$((currentRebasePatchNum + 1)) 
    if [[ $? -ne 0 ]] || [[ ! "$nextRebasePatchNum" =~ ^[0-9]+$ ]]; then # Add check if increment failed or result not number
        # Error if increment failed.
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed incrementation on hf version." >&2
        echo "[DEBUG] baseCurrentVersion=$baseCurrentVersion, currentRebasePatchNum=$currentRebasePatchNum" >&2
        exit 1 
    fi
    # Construct the next rebase/hotfix version string.
    nextVersion=${rebaseReleaseVersion}-$REBASE_V_IDENTIFIER.$nextRebasePatchNum 

else 
    # --- Standard Version Logic ---
    echo "[INFO] Before getNeededIncrementReleaseVersion: $nextVersion" # Should be empty here
    # 1. Determine the base X.Y.Z version for the next increment.
    nextVersion=$(getNeededIncrementReleaseVersion "$lastDevVersion" "$lastRCVersion" "$lastRelVersion") 
    currentInitialVersion=$nextVersion # Store this initial base version.
    echo "[INFO] After getNeededIncrementReleaseVersion: $nextVersion" 

    ## Process incrementation on MAJOR, MINOR and PATCH (Automatic increments based on flags/tags)
    if [[ "$isInitialVersion" == "true" ]]; then 
        # If this is the very first version, skip automatic core increments.
        echo "[INFO] This is initial version. So no core release incrementation needed: $nextVersion" 
    elif [[ "$(checkReleaseVersionFile "${MAJOR_SCOPE}")" == "true" ]] && [[ "$(checkReleaseVersionFile "${MINOR_SCOPE}")" == "true" ]]; then 
        # If Major and Minor are set via files, skip automatic core increments.
        echo "[INFO] MAJOR and MINOR will be file referenced. No incrementation needed" 
    # 2a. Check for MAJOR increment trigger (feature flag active, not using version file).
    elif [[ "$(checkReleaseVersionFeatureFlag ${MAJOR_SCOPE})" == "true" ]] && [[ ! "${MAJOR_V_RULE_VFILE_ENABLED}" == "true" ]]; then 
        # echo [DEBUG] currentRCSemanticVersion=$nextVersion # Old debug
        touch $CORE_VERSION_UPDATED_FILE # Mark core as updated
        vConfigMsgTags=${MAJOR_SCOPE}_V_CONFIG_MSGTAGS 
        ghCurrentMsgTag=${MAJOR_SCOPE}_GH_CURRENT_MSGTAG 
        ## If triggered by commit message tag(s)
        if [[ $(checkListIsSubstringInFileContent "${!vConfigMsgTags}" "${!ghCurrentMsgTag}") == "true" ]] && [[ "${!vConfigMsgTags}" != "false" ]]; then # Added check for "false" string
            # Increment using the count from commit messages. Use lastRelVersion as base for multi-increments.
            nextVersion=$(incrementReleaseVersion $lastRelVersion ${MAJOR_POSITION} $(getIncrementalCount "${!vConfigMsgTags}" "${!ghCurrentMsgTag}")) 
        elif [[ "$(isPreReleaseIncrementation)" == 'true' ]]; then
            # If a pre-release is also being bumped, *do not* auto-increment Major (avoids double bump).
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): Not incrementing MAJOR because isPreReleaseIncrementation=true" >&2; fi
        else 
            # Standard single increment.
            nextVersion=$(incrementReleaseVersion $nextVersion ${MAJOR_POSITION}) 
        fi
         
        echo "[DEBUG] MAJOR INCREMENTED $nextVersion" # Debug log
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): MAJOR INCREMENTED=$nextVersion" >&2; fi 
    # 2b. Check for MINOR increment trigger (feature flag active, not using version file).
    elif [[ "$(checkReleaseVersionFeatureFlag ${MINOR_SCOPE})" == "true" ]] && [[ ! "${MINOR_V_RULE_VFILE_ENABLED}" == "true" ]]; then 
        # echo [DEBUG] currentRCSemanticVersion=$nextVersion # Old debug
        touch $CORE_VERSION_UPDATED_FILE # Mark core as updated
        vConfigMsgTags=${MINOR_SCOPE}_V_CONFIG_MSGTAGS 
        ghCurrentMsgTag=${MINOR_SCOPE}_GH_CURRENT_MSGTAG 
        ## If triggered by commit message tag(s)
        if [[ $(checkListIsSubstringInFileContent "${!vConfigMsgTags}" "${!ghCurrentMsgTag}") == "true" && "${!vConfigMsgTags}" != "false" ]]; then # Added check for "false" string
             # Increment using the count from commit messages. Use lastRelVersion as base.
            nextVersion=$(incrementReleaseVersion $lastRelVersion ${MINOR_POSITION} $(getIncrementalCount "${!vConfigMsgTags}" "${!ghCurrentMsgTag}")) 
        elif [[ "$(isPreReleaseIncrementation)" == 'true' ]]; then
            # If a pre-release is also being bumped, *do not* auto-increment Minor.
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): Not incrementing MINOR because isPreReleaseIncrementation=true" >&2; fi # Corrected PATCH -> MINOR
        else 
            # Standard single increment.
            nextVersion=$(incrementReleaseVersion $nextVersion ${MINOR_POSITION}) 
        fi
        echo "[DEBUG] MINOR INCREMENTED $nextVersion" # Debug log
    # 2c. Check for PATCH increment trigger (feature flag active, not using file, Major/Minor file rules off, core not already updated).
    elif [[ "$(checkReleaseVersionFeatureFlag ${PATCH_SCOPE})" == "true" ]] && \
         [[ ! "${PATCH_V_RULE_VFILE_ENABLED}" == "true" ]] && \
         [[ ! "${MAJOR_V_RULE_VFILE_ENABLED}" == "true" ]] && \
         [[ ! "${MINOR_V_RULE_VFILE_ENABLED}" == "true" ]] && \
         [[ ! -f "$CORE_VERSION_UPDATED_FILE" ]]; then # Check if core wasn't already bumped by Dev/RC logic or Major/Minor rule
        # echo [DEBUG] currentRCSemanticVersion=$nextVersion # Old debug
        touch $CORE_VERSION_UPDATED_FILE # Mark core as updated
        vConfigMsgTags=${PATCH_SCOPE}_V_CONFIG_MSGTAGS 
        ghCurrentMsgTag=${PATCH_SCOPE}_GH_CURRENT_MSGTAG 
        ## If triggered by commit message tag(s)
        if [[ $(checkListIsSubstringInFileContent "${!vConfigMsgTags}" "${!ghCurrentMsgTag}") == "true" && "${!vConfigMsgTags}" != "false" ]]; then # Added check for "false" string
            # Increment using the count from commit messages. Use lastRelVersion as base.
            nextVersion=$(incrementReleaseVersion $lastRelVersion ${PATCH_POSITION} $(getIncrementalCount "${!vConfigMsgTags}" "${!ghCurrentMsgTag}")) 
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): After incrementReleaseVersion (MsgTag): $nextVersion" >&2; fi # Corrected message
        elif [[ "$(isPreReleaseIncrementation)" == 'true' ]]; then
            # If a pre-release is also being bumped, *do not* auto-increment Patch.
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): Not incrementing PATCH because isPreReleaseIncrementation=true" >&2; fi 
        else 
            # Standard single increment.
            nextVersion=$(incrementReleaseVersion $nextVersion ${PATCH_POSITION}) 
            if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): After incrementReleaseVersion (Auto): $nextVersion" >&2; fi # Corrected message
        fi
        if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): PATCH INCREMENTED=$nextVersion" >&2; fi 
    fi
    echo "[INFO] After core version incremented (without version file reference): $nextVersion" 

    ## Process incrementation on MAJOR, MINOR and PATCH via version file (manual). 
    # 3. Apply file-based overrides/increments sequentially (Major -> Minor -> Patch).
    #    This uses the complex 'processWithReleaseVersionFile' function.
    #    Skip if initial version? No, current logic runs it even for initial version if flags are set.
    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): Processing MAJOR file: nextVersion=$nextVersion, lastDevVersion=$lastDevVersion, lastRcVersion=$lastRCVersion, lastBaseVersion=$lastBaseVersion, lastRelVersion=$lastRelVersion" >&2; fi # Added details
    # Process MAJOR using file rules.
    nextVersion=$(processWithReleaseVersionFile "${nextVersion}" "${MAJOR_POSITION}" "${MAJOR_SCOPE}" "${versionListFile}") 
    if [[ $? -ne 0 ]]; then 
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed processing incrementation on MAJOR, MINOR and PATCH via version file on MAJOR VERSION." >&2 
        echo "[ERROR_MSG] $nextVersion" >&2 
        exit 1 
    fi
    # Reset last artifact files as processWithReleaseVersionFile might have updated them.
    resetLastArtifactFiles 
    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): Processing MINOR file: nextVersion=$nextVersion, lastDevVersion=$lastDevVersion, lastRcVersion=$lastRCVersion, lastBaseVersion=$lastBaseVersion, lastRelVersion=$lastRelVersion" >&2; fi # Added details
    # Process MINOR using file rules.
    nextVersion=$(processWithReleaseVersionFile "${nextVersion}" "${MINOR_POSITION}" "${MINOR_SCOPE}" "${versionListFile}") 
    if [[ $? -ne 0 ]]; then 
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed processing incrementation on MAJOR, MINOR and PATCH via version file on MINOR VERSION." >&2 
        echo "[ERROR_MSG] $nextVersion" >&2 
        exit 1 
    fi
    # Reset last artifact files again.
    resetLastArtifactFiles 
    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): Processing PATCH file: nextVersion=$nextVersion, lastDevVersion=$lastDevVersion, lastRcVersion=$lastRCVersion, lastBaseVersion=$lastBaseVersion, lastRelVersion=$lastRelVersion" >&2; fi # Added details
    # Process PATCH using file rules.
    nextVersion=$(processWithReleaseVersionFile "${nextVersion}" "${PATCH_POSITION}" "${PATCH_SCOPE}" "${versionListFile}") 
    if [[ $? -ne 0 ]]; then 
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Failed processing incrementation on MAJOR, MINOR and PATCH via version file on PATCH VERSION." >&2 
        echo "[ERROR_MSG] $nextVersion" >&2 
        exit 1 
    fi
    # Reset last artifact files one last time.
    resetLastArtifactFiles 
    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): After all file processing: nextVersion=$nextVersion, lastDevVersion=$lastDevVersion, lastRcVersion=$lastRCVersion, lastBaseVersion=$lastBaseVersion, lastRelVersion=$lastRelVersion" >&2; fi # Added details

    echo "[INFO] After core version file incremented: [$nextVersion]" 

    # Store the final X.Y.Z part in the update file if it's a clean release version.
    # This is used by subsequent pre-release increment functions.
    if (echo $nextVersion | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+$"); then 
        echo $nextVersion > $ARTIFACT_UPDATED_REL_VERSION_FILE 
    fi

    ## Debug section for pre-release variables.
    if [[ "$isDebug" == "true" ]]; then 
        debugPreReleaseVersionVariables $RC_SCOPE 
        debugPreReleaseVersionVariables $DEV_SCOPE 
    fi

    ## Process incrementation on RC and DEV 
    # 4. Handle automatic RC/Dev increments.
    echo "[INFO] Before RC version incremented: $lastRCVersion" 
    echo "[INFO] Before DEV version incremented: $lastDevVersion" 
    echo "[INFO] Before BASE version incremented: $lastBaseVersion" # Base is not incremented here?
    echo "[INFO] Before nextVersion version incremented: $nextVersion" # Should be X.Y.Z at this point

    # Check if RC increment is triggered (feature active, not file-based).
    if [[ "$(checkPreReleaseVersionFeatureFlag ${RC_SCOPE})" == "true" ]] && [[ ! "${RC_V_RULE_VFILE_ENABLED}" == "true" ]]; then 
        # Increment RC based on the last known RC version.
        nextVersion=$(incrementPreReleaseVersion "$lastRCVersion" "$RC_V_IDENTIFIER") 
    # Check if DEV increment is triggered (feature active, not file-based).
    elif [[ "$(checkPreReleaseVersionFeatureFlag ${DEV_SCOPE})" == "true" ]] && [[ ! "${DEV_V_RULE_VFILE_ENABLED}" == "true" ]]; then 
        # Increment Dev based on the last known Dev version.
        nextVersion=$(incrementPreReleaseVersion "$lastDevVersion" "$DEV_V_IDENTIFIER") 
    fi
    echo "[INFO] After prerelease version incremented: [$nextVersion]" 

    ## Process incrementation on RC and DEV with version file
    # 5. Handle file-based RC/Dev increments (sets pre-release number from file).
    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): RC_V_RULE_VFILE_ENABLED=$RC_V_RULE_VFILE_ENABLED, DEV_V_RULE_VFILE_ENABLED=$DEV_V_RULE_VFILE_ENABLED" >&2; fi 
    if [[ "$isDebug" == "true" ]]; then echo "[DEBUG] $BASH_SOURCE (line:$LINENO): \$(checkPreReleaseVersionFeatureFlag ${RC_SCOPE})=$(checkPreReleaseVersionFeatureFlag ${RC_SCOPE}),\$(checkPreReleaseVersionFeatureFlag ${DEV_SCOPE})=$(checkPreReleaseVersionFeatureFlag ${DEV_SCOPE})" >&2; fi 

    # Check if RC file-based increment is triggered.
    if [[ "$(checkPreReleaseVersionFeatureFlag ${RC_SCOPE})" == "true" ]] && [[ "${RC_V_RULE_VFILE_ENABLED}" == "true" ]]; then 
        # Set RC version using number from file.
        nextVersion=$(incrementPreReleaseVersionByFile "$lastRCVersion" "$RC_V_IDENTIFIER" "${RC_SCOPE}") 
    # Check if DEV file-based increment is triggered.
    elif [[ "$(checkPreReleaseVersionFeatureFlag ${DEV_SCOPE})" == "true" ]] && [[ "${DEV_V_RULE_VFILE_ENABLED}" == "true" ]]; then 
        # Set Dev version using number from file.
        nextVersion=$(incrementPreReleaseVersionByFile "$lastDevVersion" "$DEV_V_IDENTIFIER" "${DEV_SCOPE}") 
    fi
    echo "[INFO] After prerelease version incremented with input from version file: [$nextVersion]" 

    # Degauss variables for Build scope.
    degaussBuildVersionVariables "$BUILD_SCOPE" 
    ## Debug section for Build scope.
    if [[ "$isDebug" == "true" ]]; then 
        debugBuildVersionVariables "$BUILD_SCOPE" 
    fi
    ## Append build number infos if enabled
    # 6. Append build metadata if feature is enabled.
    if [[ "$(checkBuildVersionFeatureFlag ${BUILD_SCOPE})" == "true" ]]; then 
        # Check required build info variables are set (likely from environment/CI).
        if [[ -z "$BUILD_V_IDENTIFIER" ]]; then 
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Missing build identifier" >&2
            exit 1 
        fi
        if [[ -z "$BUILD_GH_RUN_NUMBER" ]]; then 
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Missing GitHub job number" >&2
            exit 1 
        fi
        if [[ -z "$BUILD_GH_RUN_ATTEMPT" ]]; then 
            echo "[ERROR] $BASH_SOURCE (line:$LINENO): Missing GitHub job attempt number" >&2
            exit 1 
        fi
        # Append build metadata in the format +Identifier.RunNumber.RunAttempt
        nextVersion=${nextVersion}+${BUILD_V_IDENTIFIER}.${BUILD_GH_RUN_NUMBER}.${BUILD_GH_RUN_ATTEMPT} 
        echo "[INFO] After appending build version: $nextVersion" 
    fi
fi # End of standard version logic (else block for rebase check)

# 7. Replace version string in configured files.
## Replace the version in file if enabled (Generic token replacement)
if [[ "$(checkReplacementFeatureFlag ${REPLACEMENT_SCOPE})" == "true" ]] && [[ "$REPLACE_V_RULE_FILETOKEN_ENABLED" == "true" ]]; then 
    replaceVersionInFile "$nextVersion" "$REPLACE_V_CONFIG_FILETOKEN_FILE" "$REPLACE_V_CONFIG_FILETOKEN_NAME" 
    echo "[INFO] Version updated successfully in $REPLACE_V_CONFIG_FILETOKEN_FILE" 
    if [[ "$isDebug" == "true" ]]; then 
        echo "[DEBUG] Updated $REPLACE_V_CONFIG_FILETOKEN_FILE:" 
        cat $REPLACE_V_CONFIG_FILETOKEN_FILE 
    fi
fi
## Replace the version in file if enabled (Maven POM replacement)
if [[ "$(checkReplacementFeatureFlag ${REPLACEMENT_SCOPE})" == "true" ]] && [[ "$REPLACE_V_RULE_MAVEN_ENABLED" == "true" ]]; then 
    replaceVersionForMaven "$nextVersion" "$REPLACE_V_CONFIG_MAVEN_POMFILE" 
    echo "[INFO] Version updated successfully in maven POM file: $REPLACE_V_CONFIG_MAVEN_POMFILE" 
    if [[ "$isDebug" == "true" ]]; then 
        echo "[DEBUG] Updated $REPLACE_V_CONFIG_MAVEN_POMFILE:" 
        cat $REPLACE_V_CONFIG_MAVEN_POMFILE 
    fi
fi
## TBC - Replace the version in file if enabled (YAML replacement)
# if [[ "$(checkReplacementFeatureFlag ${REPLACEMENT_SCOPE})" == "true" ]] && [[ "$REPLACE_V_RULE_YAMLPATH_ENABLED" == "true" ]]; then
#     replaceVersionForYamlFile "$nextVersion" "$REPLACE_V_CONFIG_YAMLPATH_FILE" "$REPLACE_V_CONFIG_YAMLPATH_QUERYPATH"
#     echo "[INFO] Version updated successfully in YAML file: $REPLACE_V_CONFIG_YAMLPATH_FILE"
# fi

# Final Output
echo # Blank line for readability
echo "[INFO] nextVersion = $nextVersion" 
# Write the final calculated version to the designated output file.
echo $nextVersion > $ARTIFACT_NEXT_VERSION_FILE
