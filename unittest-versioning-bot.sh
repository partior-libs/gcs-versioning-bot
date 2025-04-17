#!/bin/bash
TEST_SUITE_PATH="./test-files"
TEST_SPEC_FILE="unit-test-spec.yml"
GENERATE_VERSION_SCRIPT_PATH="./scripts/generate_package_version.sh"
YAML_IMPORTER_SCRIPT_PATH="./test-files/scripts/yaml-converter.sh"
LOG_FILE="unit-test-report-$(date +%s).txt"
YAML_IMPORTER_FILE="yaml-importer-tmp"
GENERAL_CONFIG="config/general.ini"
BASE_CONTROLLER_CONFIG_DIR="controller-config-files/projects"
DEFAULT_CONTROLLER_CONFIG_FILE="controller-config-files/projects/default.yml"
BUILD_GH_COMMIT_MESSAGE_FILE="commit-message-tmp"

# Function to log messages
function logMessage() {
    local logLevel=$1
    local message=$2
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp [$logLevel] $message" >> "$LOG_FILE"
}

# Function to modify input version files for the test case
function modifyVersionFilesForTestCase() {
    local devVersion="$1"
    local rcVersion="$2"
    local releaseVersion="$3"
    local appVersion="$4"
    local sourceBranch="$5"
    local rebaseVersion="$6"

    local majorVersion
    local minorVersion

    echo "" > env.tmp

    echo "BUILD_GH_BRANCH_NAME=feature" >> env.tmp
    echo "MAJOR_GH_CURRENT_BRANCH=$BUILD_GH_BRANCH_NAME" >> env.tmp
    echo "MINOR_GH_CURRENT_BRANCH=$BUILD_GH_BRANCH_NAME" >> env.tmp
    echo "PATCH_GH_CURRENT_BRANCH=$BUILD_GH_BRANCH_NAME" >> env.tmp
    echo "RC_GH_CURRENT_BRANCH=$BUILD_GH_BRANCH_NAME" >> env.tmp
    echo "DEV_GH_CURRENT_BRANCH=$BUILD_GH_BRANCH_NAME" >> env.tmp
    echo "GITHUB_RUN_NUMBER=103" >> env.tmp
    echo "GITHUB_RUN_ATTEMPT=1" >> env.tmp

    logMessage "INFO" "Modifying input files for test case"
    echo "$devVersion" > "$ARTIFACT_LAST_DEV_VERSION_FILE"
    echo "$rcVersion" > "$ARTIFACT_LAST_RC_VERSION_FILE"
    echo "$releaseVersion" > "$ARTIFACT_LAST_REL_VERSION_FILE"
    logMessage "INFO" "Last Dev version $(cat $ARTIFACT_LAST_DEV_VERSION_FILE)"
    logMessage "INFO" "Last RC version $(cat $ARTIFACT_LAST_RC_VERSION_FILE)"
    logMessage "INFO" "Last Release version $(cat $ARTIFACT_LAST_REL_VERSION_FILE)"

    if [[ -z "${appVersion}" ]]; then
        echo "[ERROR] $BASH_SOURCE (line:$LINENO): Missing app version values"
        exit 1
    else
        majorVersion=$(echo "$appVersion" | cut -d '.' -f 1)
        minorVersion=$(echo "$appVersion" | cut -d '.' -f 2)
        if [ -f "${MAJOR_V_CONFIG_VFILE_NAME}" ]; then
            sed -i "s/^MAJOR-VERSION=.*/MAJOR-VERSION=$majorVersion/" "${MAJOR_V_CONFIG_VFILE_NAME}"
        fi

        if [ -f "${MINOR_V_CONFIG_VFILE_NAME}" ]; then
            sed -i "s/^MINOR-VERSION=.*/MINOR-VERSION=$minorVersion/" "${MINOR_V_CONFIG_VFILE_NAME}"
        fi
    fi

    if [[ -z "${sourceBranch}" ]]; then
        echo "[ERROR] Source Branch is empty. Please add the branch name into runTest!"
        exit 1
    else
        if [[ "${sourceBranch}" =~ ^hotfix-base/* ]]; then
            branchName=$(echo "$sourceBranch" | cut -d'/' -f1)
            echo "branchName: $branchName"
            echo "rebaseVersion: $rebaseVersion"
            echo "$rebaseVersion" > "$ARTIFACT_LAST_BASE_VERSION_FILE"
            logMessage "INFO" "Last Base version $(cat $ARTIFACT_LAST_BASE_VERSION_FILE)"
            sed -i "s/^BUILD_GH_BRANCH_NAME=.*/BUILD_GH_BRANCH_NAME=$branchName/" "env.tmp"
        else
            echo "" > "$ARTIFACT_LAST_BASE_VERSION_FILE"
            sed -i "s/^BUILD_GH_BRANCH_NAME=.*/BUILD_GH_BRANCH_NAME=$sourceBranch/" "env.tmp"
        fi
        source env.tmp
        rm -f env.tmp
    fi
}

# Function to modify input envronment variables for the test case
function modifyEnvVarsForTestCase() {
    local yamlImporterFile="$1"
    local testCasePath="$2"
    
    echo "[INFO] yamlImporterFile: $yamlImporterFile"
    echo "[INFO] testCasePath: $testCasePath"

    sed -i "s#^artifact_auto_versioning__major_version__rules__file__target=.*#artifact_auto_versioning__major_version__rules__file__target=$testCasePath/${artifact_auto_versioning__major_version__rules__file__target#./}#" "${yamlImporterFile}"
    sed -i "s#^artifact_auto_versioning__minor_version__rules__file__target=.*#artifact_auto_versioning__minor_version__rules__file__target=$testCasePath/${artifact_auto_versioning__minor_version__rules__file__target#./}#" "${yamlImporterFile}"
    sed -i "s#^artifact_auto_versioning__patch_version__rules__file__target=.*#artifact_auto_versioning__patch_version__rules__file__target=$testCasePath/${artifact_auto_versioning__patch_version__rules__file__target#./}#" "${yamlImporterFile}"
    sed -i "s#^artifact_auto_versioning__release_candidate_version__rules__file__target=.*#artifact_auto_versioning__release_candidate_version__rules__file__target=$testCasePath/${artifact_auto_versioning__release_candidate_version__rules__file__target#./}#" "${yamlImporterFile}"
    sed -i "s#^artifact_auto_versioning__development_version__rules__file__target=.*#artifact_auto_versioning__development_version__rules__file__target=$testCasePath/${artifact_auto_versioning__development_version__rules__file__target#./}#" "${yamlImporterFile}"

    sed -i "s#^artifact_auto_versioning__replacement__file_token__target=.*#artifact_auto_versioning__replacement__file_token__target=$testCasePath/${artifact_auto_versioning__replacement__file_token__target#./}#" "${yamlImporterFile}"
    sed -i "s#^artifact_auto_versioning__replacement__yaml_update__target=.*#artifact_auto_versioning__replacement__yaml_update__target=$testCasePath/${artifact_auto_versioning__replacement__yaml_update__target#./}#" "${yamlImporterFile}"
    sed -i "s#^artifact_auto_versioning__replacement__maven_pom__target=.*#artifact_auto_versioning__replacement__maven_pom__target=$testCasePath/${artifact_auto_versioning__replacement__maven_pom__target#./}#" "${yamlImporterFile}"
}

# Function to run the actual test
function runTest() {
    local testName="$1"
    local expectedOutput="$2"
    local versionFileTmp="$3"
    local sourceBranch="$4"
    local lastBaseVersion="$5"
    local testCasePath="$6"

    local versionPrependLabel
    if [[ "${artifact_auto_versioning__prepend_version__enabled}" == "true" ]]; then
        versionPrependLabel=$(getVersionPrependLabel "${testCasePath}")
        echo "BUILD_GH_VERSION_PREPEND_LABEL: ${BUILD_GH_VERSION_PREPEND_LABEL}"
    fi

    # Get the actual output from the script
    source "${GENERATE_VERSION_SCRIPT_PATH}" "${artifact_base_name}" "${sourceBranch}" "${BUILD_GH_LABEL_FILE}" "${BUILD_GH_TAG_FILE}" "${testCasePath}/${BUILD_GH_COMMIT_MESSAGE_FILE}" "${lastBaseVersion}" "${versionFileTmp}" "true"

    if [[ "${artifact_auto_versioning__prepend_version__enabled}" == "true" ]]; then
        getFinalPrependedVersion "${versionPrependLabel}"
    fi

    verifyOutput "${expectedOutput}"

    # Restore the original files after the test
    if [[ "${REPLACE_V_RULES_ENABLED}" == "true" ]]; then
        restoreReplacementFiles
    fi
    logMessage "INFO" "---------------------------------------------"
}

function verifyOutput(){
    local expectedOutput="$1"
    local actualOutput=$(cat "$ARTIFACT_NEXT_VERSION_FILE")
    local testPassed="false"

    # Compare the actual output with the expected output
    if [ "$actualOutput" == "$expectedOutput" ]; then
        testPassed=true
    fi

    # Additional rule if flag is enabled
    if [[ "$REPLACE_V_RULES_ENABLED" == "true" ]]; then
        if [[ "${REPLACE_V_RULE_YAMLPATH_ENABLED}" == "true" ]]; then
            if [[ -f "${REPLACE_V_CONFIG_YAMLPATH_FILE}" ]]; then
                if grep -qF "$expectedOutput" "${REPLACE_V_CONFIG_YAMLPATH_FILE}"; then
                    logMessage "INFO" "The replacement file has been updated with the new version: $expectedOutput" 
                    testPassed=true
                fi
            else
                logMessage "ERROR" "The replacement file does not exist"
                testPassed="false"
            fi
        fi

        if [[ "${REPLACE_V_RULE_FILETOKEN_ENABLED}" == "true" ]]; then
            if [[ -f "${REPLACE_V_CONFIG_FILETOKEN_FILE}" ]]; then
                if grep -qF "$expectedOutput" "${REPLACE_V_CONFIG_FILETOKEN_FILE}"; then
                    logMessage "INFO" "The replacement file has been updated with the new version: $expectedOutput" 
                    testPassed=true
                fi
            else
                logMessage "ERROR" "The replacement file does not exist"
                testPassed="false"
            fi
        fi

        if [[ "${REPLACE_V_RULE_MAVEN_ENABLED}" == "true" ]]; then
            if [[ -f "${REPLACE_V_CONFIG_MAVEN_POMFILE}" ]]; then
                if grep -qF "$expectedOutput" "${REPLACE_V_CONFIG_MAVEN_POMFILE}"; then
                    logMessage "INFO" "The replacement file has been updated with the new version: $expectedOutput" 
                    testPassed=true
                fi
            else
                logMessage "ERROR" "The replacement file does not exist"
                testPassed="false"
            fi
        fi
    fi

    # Print result
    if [ "$testPassed" == "true" ]; then
        logMessage "SUCCESS" "$testName PASSED. As Expected: '$expectedOutput'"
        echo "$testName PASSED"
        eval "$resultVar+=(\"- $testName PASS\")"
        ((configPassCount++))
        ((totalPass++))
    else
        logMessage "ERROR" "$testName FAILED. Expected: '$expectedOutput', but Actual: '$actualOutput'"
        echo "$testName FAILED"
        eval "$resultVar+=(\"- $testName FAILED\")"
        ((configFailCount++))
        ((totalFail++))
    fi
}

function summaryReport(){
    # After finishing whole unit test execution, generate a report 
    echo "" >> $LOG_FILE
    echo "===============================" >> $LOG_FILE
    echo "Test Summary Report" >> $LOG_FILE
    echo "===============================" >> $LOG_FILE

    for config in "${!configPassCounts[@]}"; do
        sanitizedConfigName="$(echo "$config" | tr '-' '_')"
        resultVar="config_${sanitizedConfigName}_results"

        echo "" >> $LOG_FILE
        echo "Config Name: $config" >> $LOG_FILE
        eval "for line in \"\${$resultVar[@]}\"; do echo \"\$line\" >> $LOG_FILE; done"
        echo "Result: ${configPassCounts[$config]} passed / $((${configPassCounts[$config]} + ${configFailCounts[$config]})) total" >> $LOG_FILE
    done

    # Overall Summary
    echo "" >> $LOG_FILE
    echo "===============================" >> $LOG_FILE
    echo "Overall Summary" >> $LOG_FILE
    echo "-------------------------------" >> $LOG_FILE
    echo "Total Configs:     $totalConfig" >> $LOG_FILE
    echo "Total Test Cases:  $totalTests" >> $LOG_FILE
    echo "Passed:            $totalPass" >> $LOG_FILE
    echo "Failed:            $totalFail" >> $LOG_FILE
    echo "===============================" >> $LOG_FILE
}

# Function to restore the original contents of the input files
function restoreReplacementFiles() {
    if [[ "${REPLACE_V_RULE_YAMLPATH_ENABLED}" == "true" ]]; then
        if [[ -f "${REPLACE_V_CONFIG_YAMLPATH_FILE}" ]]; then
            logMessage "INFO" "Restoring the YAML file to its original state" 
            sed -i "s/^version: .*/version: @@VERSION_BOT_TOKEN@@/" "${REPLACE_V_CONFIG_YAMLPATH_FILE}"
        else
            logMessage "ERROR" "The YAML file does not exist"
        fi
    fi

    if [[ "${REPLACE_V_RULE_FILETOKEN_ENABLED}" == "true" ]]; then
        if [[ -f "${REPLACE_V_CONFIG_FILETOKEN_FILE}" ]]; then
            logMessage "INFO" "Restoring the file token to its original state"
            sed -i -E 's#<version>.*</version>#<version>@@VERSION_BOT_TOKEN@@</version>#' "${REPLACE_V_CONFIG_FILETOKEN_FILE}"
        else
            logMessage "ERROR" "The file token does not exist"
        fi
    fi

    if [[ "${REPLACE_V_RULE_MAVEN_ENABLED}" == "true" ]]; then
        if [[ -f "${REPLACE_V_CONFIG_MAVEN_POMFILE}" ]]; then
            logMessage "INFO" "Restoring the maven pom file to its original state"
            sed -i -E 's#<version>.*</version>#<version>12</version>#' "${REPLACE_V_CONFIG_MAVEN_POMFILE}"
        else
            logMessage "ERROR" "The maven pom file does not exist"
        fi
    fi
}

function startYamlImporter(){
    importerFileName="$1"
    configFiles="$2"

    echo "importerFileName: $importerFileName"
    if [[ ! -f $importerFileName ]]; then
        touch $importerFileName
        touch $importerFileName.2
    else
        echo "" > $importerFileName
        echo "" > $importerFileName.2
    fi

    bash $YAML_IMPORTER_SCRIPT_PATH "${DEFAULT_CONTROLLER_CONFIG_FILE}" ".smc.ci" "${importerFileName}" "" false

    # Remove lines containing '>> $GITHUB_OUTPUT' and 'echo'
    echo "[INFO] Remove lines containing >> \$GITHUB_OUTPUT and 'echo'"
    sed -i 's/>> $GITHUB_ENV//g' "$importerFileName"
    sed -i '/>> $GITHUB_OUTPUT/d' "$importerFileName"
    sed -i 's/echo //g' "$importerFileName"

    source $importerFileName

    bash $YAML_IMPORTER_SCRIPT_PATH "${configFiles}" ".smc.ci" "${importerFileName}" "" false

    # Remove lines containing '>> $GITHUB_OUTPUT' and 'echo'
    echo "[INFO] Remove lines containing >> \$GITHUB_OUTPUT and 'echo'"
    sed -i 's/>> $GITHUB_ENV//g' "$importerFileName"
    sed -i '/>> $GITHUB_OUTPUT/d' "$importerFileName"
    sed -i 's/echo //g' "$importerFileName"

    source $importerFileName
}

function findConfigFile() {
    local scopeConfigFile="$1"
    local baseDir="$2"

    foundFile=$(find "${baseDir}" -type f \( -name "${scopeConfigFile}.yml" -o -name "${scopeConfigFile}.yaml" \))

    if [[ -z "$foundFile" ]]; then
        echo "[ERROR] No config file found containing: ${scopeConfigFile}" >&2
        exit 1
    fi
    
    echo "${foundFile}"
}

function getVersionPrependLabel(){
    local testCasePath="$1"

    echo "[INFO] Retrieving version append label..." >&2
    versionLabelFile="${testCasePath}/${artifact_auto_versioning__prepend_version__rules__file__target#./}"
    versionLabelPropKey="${artifact_auto_versioning__prepend_version__rules__file__key}"
    if [[ ! -f "$versionLabelFile" ]]; then
        echo "[ERROR] Unable to locate version label file: $versionLabelFile" >&2
        exit 1
    fi
    if [[ -z "$versionLabelPropKey" ]]; then
        echo "[ERROR] Version label key is missing in controller. Please check the controller config and try again." >&2
        exit 1
    fi
    echo "[INFO] Reading label from $versionLabelFile" >&2
    versionPrependLabel=$(cat "$versionLabelFile" | grep -v "^#" | grep "$versionLabelPropKey" | cut -d"=" -f1 --complement)
    if [[ -z "$versionPrependLabel" ]]; then
        echo "[ERROR] Version label value for key [$versionLabelPropKey] is missing in config file: $versionLabelFile" >&2
        echo "[DEBUG] Content of version config:" >&2
        exit 1
    fi
    echo "[INFO] Version prepend label: $versionPrependLabel" >&2
    echo "${versionPrependLabel}"
}

function getFinalPrependedVersion(){
    local prependVersionLabel="$1"

    echo "$(./scripts/read_new_version.sh $prependVersionLabel)" > "${ARTIFACT_NEXT_VERSION_FILE}"
    echo "[INFO] nextVersion after prepending: $(cat $ARTIFACT_NEXT_VERSION_FILE)"
}

# Function to run all tests
function runTests() {
    local scopeOfConfigFiles="$1"
    local scopeOfTestSuite="$2"

    configPassCount=0
    configFailCount=0
    configTotal=0

    sanitizedConfigName="$(echo "$scopeOfConfigFiles" | tr '-' '_')"
    resultVar="config_${sanitizedConfigName}_results"
    eval "$resultVar=()"

    echo "scopeOfTestSuite: $scopeOfTestSuite"
    echo "scopeOfConfigFiles: $scopeOfConfigFiles"
    
    logMessage "INFO" "Starting test execution"
    logMessage "INFO" "---------------------------------------------"

    local testCaseList=()
    for testcase in $scopeOfTestSuite; do
        testCaseList+=("$testcase")
    done

    # Sort a list of test cases numerically
    for tcPath in $(printf "%s\n" "${testCaseList[@]}" | sort -V); do
        if [[ -d $tcPath ]]; then
            logMessage "INFO" "Running the test from config: $scopeOfConfigFiles"

            testSpecPullPath="${tcPath}/${TEST_SPEC_FILE}"

            name=$(yq e ".test-spec.info.name" $testSpecPullPath)
            description=$(yq e ".test-spec.info.description" $testSpecPullPath)
            lastDevVersion=$(yq e ".test-spec.input.lastDevVersion" $testSpecPullPath)
            lastRcVersion=$(yq e ".test-spec.input.lastRcVersion" $testSpecPullPath)
            lastReleaseVersion=$(yq e ".test-spec.input.lastReleaseVersion" $testSpecPullPath)
            lastRebaseVersion=$(yq e ".test-spec.input.lastRebaseVersion" $testSpecPullPath)
            targetBaseVersion=$(yq e ".test-spec.input.targetBaseVersion" $testSpecPullPath)
            branchName=$(yq e ".test-spec.input.branchName" $testSpecPullPath)
            appVersion=$(yq e ".test-spec.input.appVersion" $testSpecPullPath)
            versionFileTmp=$(yq e ".test-spec.file.versionFileTmp" $testSpecPullPath)
            expectedValue=$(yq e ".test-spec.output.expectedValue" $testSpecPullPath)

            versionFileFullPath="${tcPath}/${versionFileTmp}"

            logMessage "INFO" "$name"
            logMessage "INFO" "Description: $description"

            echo "[INFO] lastDevVersion: $lastDevVersion"
            echo "[INFO] lastRcVersion: $lastRcVersion"
            echo "[INFO] lastReleaseVersion: $lastReleaseVersion"
            echo "[INFO] lastRebaseVersion: $lastRebaseVersion"
            echo "[INFO] targetBaseVersion: $targetBaseVersion"
            echo "[INFO] branchName: $branchName"
            echo "[INFO] appVersion: $appVersion"
            echo "[INFO] versionFileTmp: $versionFileTmp"
            echo "[INFO] expectedValue: $expectedValue"

            configFilePath=$(findConfigFile "${scopeOfConfigFiles}" "${BASE_CONTROLLER_CONFIG_DIR}")
            echo "configFilePath: $configFilePath"

            startYamlImporter "${YAML_IMPORTER_FILE}" "${configFilePath}"

            modifyEnvVarsForTestCase "${YAML_IMPORTER_FILE}" "${tcPath}"
            source "${GENERAL_CONFIG}"

            # Modify the input files for the test case
            modifyVersionFilesForTestCase "${lastDevVersion}" "${lastRcVersion}" "${lastReleaseVersion}" "${appVersion}" "${branchName}" "${lastRebaseVersion}"

            source "${YAML_IMPORTER_FILE}"
            echo "BUILD_GH_RUN_NUMBER: $BUILD_GH_RUN_NUMBER"
            echo "BUILD_GH_RUN_ATTEMPT: $BUILD_GH_RUN_ATTEMPT"
            runTest "${name}" "${expectedValue}" "${versionFileFullPath}" "${branchName}" "${targetBaseVersion}" "${tcPath}"
            ((totalTests++))
        fi
    done
}

function mainTestRunner(){
    local configFile="$1"
    local scope="$2"

    local baseConfigName

    echo "Starting test run at $(date '+%Y-%m-%d %H:%M:%S')" > "$LOG_FILE"
    logMessage "INFO" "Log file initialized"

    # Check if arguments are provided
    if [ $# -eq 0 ]; then
        echo "Usage: $0 [all | specific_testcase | range_of_testcases]"
        exit 1
    fi

    # Case 1: Run one config file + a specific testcase (e.g., testcase1, testcase2)
    if [[ $configFile != "all" && $scope =~ ^[0-9]+$ ]]; then
        runTests "$configFile" "${TEST_SUITE_PATH}/${configFile}/testcase${scope}"

        # echo "" >> $LOG_FILE
        # echo "Config: ${configFile}" >> $LOG_FILE
        # echo "-----------------------------" >> $LOG_FILE

        # echo "Result: $configPassCount passed / $configTotal total" >> $LOG_FILE
        # ((totalConfig++))

        configPassCounts["$configFile"]=$configPassCount
        configFailCounts["$configFile"]=$configFailCount
        ((totalConfig++))

    # Case 2: Run one config file + all testcases (e.g., testcase1, testcase2, ...)
    elif [[ $configFile != "all" && $scope == "all" ]]; then
        runTests "$configFile" "${TEST_SUITE_PATH}/${configFile}/testcase*"

        configPassCounts["$configFile"]=$configPassCount
        configFailCounts["$configFile"]=$configFailCount
        ((totalConfig++))

    # Case 3: Run all config files + their whole testcases (e.g., testcase1, testcase2, ...)
    elif [[ $configFile == "all" && $scope == "all" ]]; then
        for configPath in "$TEST_SUITE_PATH"/*; do
            if [[ -d "$configPath" ]]; then
                baseConfigName="$(basename "$configPath")"
                runTests "$baseConfigName" "$configPath/testcase*"

                configPassCounts["$baseConfigName"]=$configPassCount
                configFailCounts["$baseConfigName"]=$configFailCount
                ((totalConfig++))
            fi
        done
    else
        echo "Invalid option. Usage: $0 [all | specific_testcase | range_of_testcases]"
        exit 1
    fi

    # Add more tests as needed
    logMessage "INFO" "Test execution completed"
    
    summaryReport
}

# Handle options
configFile="$1"
scope="$2"

# Global environment variables
declare -A configPassCounts
declare -A configFailCounts

totalConfig=0
totalTests=0
totalPass=0
totalFail=0

mainTestRunner "${configFile}" "${scope}"




