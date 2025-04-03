#!/bin/bash
TEST_SUITE_PATH="./test-files/mocked"
TEST_SPEC_FILE="unit-test-spec.yml"
APP_VERSION_FILE="app-version.cfg"
HELM_FILE="goquorum-node/Chart.yaml"
SCRIPT_PATH="./scripts/generate_package_version.sh"
LOG_FILE="unit-test-report.txt"


# Function to log messages
function logMessage() {
    local logLevel=$1
    local message=$2
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp [$logLevel] $message" >> "$LOG_FILE"
}

# Function to initialize the log file
function initializeLog() {
    echo "Starting test run at $(date '+%Y-%m-%d %H:%M:%S')" > "$LOG_FILE"
    logMessage "INFO" "Log file initialized"
}

# Function to modify input version files for the test case
function modifyVersionFilesForTestCase() {
    local devVersion="$1"
    local rcVersion="$2"
    local releaseVersion="$3"
    local appVersion="$4"
    local sourceBranch="$5"
    local rebaseVersion="$6"
    local mockedEnvFile="$7"

    local majorVersion
    local minorVersion

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
            sed -i "s/^BUILD_GH_BRANCH_NAME=.*/BUILD_GH_BRANCH_NAME=$branchName/" "${mockedEnvFile}"
        else
            echo "" > "$ARTIFACT_LAST_BASE_VERSION_FILE"
            sed -i "s/^BUILD_GH_BRANCH_NAME=.*/BUILD_GH_BRANCH_NAME=$sourceBranch/" "${mockedEnvFile}"
        fi 
    fi
}

# Function to modify input envronment files for the test case
function modifyEnvFilesForTestCase() {
    local mockedEnvFile="$1"
    local testCasePath="$2"

    echo "[INFO] mockedEnvFile: $mockedEnvFile"
    echo "[INFO] testCasePath: $testCasePath"

    sed -i "s#^MAJOR_V_CONFIG_VFILE_NAME=.*#MAJOR_V_CONFIG_VFILE_NAME=$testCasePath/$APP_VERSION_FILE#" "${mockedEnvFile}"
    sed -i "s#^MINOR_V_CONFIG_VFILE_NAME=.*#MINOR_V_CONFIG_VFILE_NAME=$testCasePath/$APP_VERSION_FILE#" "${mockedEnvFile}"
    sed -i "s#^PATCH_V_CONFIG_VFILE_NAME=.*#PATCH_V_CONFIG_VFILE_NAME=$testCasePath/$APP_VERSION_FILE#" "${mockedEnvFile}"
    sed -i "s#^RC_V_CONFIG_VFILE_NAME=.*#RC_V_CONFIG_VFILE_NAME=$testCasePath/$APP_VERSION_FILE#" "${mockedEnvFile}"
    sed -i "s#^DEV_V_CONFIG_VFILE_NAME=.*#DEV_V_CONFIG_VFILE_NAME=$testCasePath/$APP_VERSION_FILE#" "${mockedEnvFile}"

    sed -i "s#^REPLACE_V_CONFIG_FILETOKEN_FILE=.*#REPLACE_V_CONFIG_FILETOKEN_FILE=$testCasePath/$HELM_FILE#" "${mockedEnvFile}"
    sed -i "s#^REPLACE_V_CONFIG_YAMLPATH_FILE=.*#REPLACE_V_CONFIG_YAMLPATH_FILE=$testCasePath/$HELM_FILE#" "${mockedEnvFile}"
}

# Function to run the actual test
function runTest() {
    local testName=$1
    local expectedOutput="$2"
    local versionFileTmp="$3"
    local sourceBranch="$4"
    local mockedEnvFile="$5"
    local lastBaseVersion="$6"

    # Get the actual output from the script
    bash "${SCRIPT_PATH}" "goquorum-node" "${sourceBranch}" "${BUILD_GH_LABEL_FILE}" "${BUILD_GH_TAG_FILE}" "${BUILD_GH_COMMIT_MESSAGE_FILE}" "${lastBaseVersion}" "${versionFileTmp}" "true" "${mockedEnvFile}"

    local actualOutput=$(cat "$ARTIFACT_NEXT_VERSION_FILE")
    
    # Compare the actual output with the expected output
    if [ "$actualOutput" == "$expectedOutput" ]; then
        logMessage "SUCCESS" "$testName PASSED. As Expected: '$expectedOutput'"
        echo "$testName PASSED"
    else
        logMessage "ERROR" "$testName FAILED. Expected: '$expectedOutput', but Actual: '$actualOutput'"
        echo "$testName FAILED"
    fi

    # Restore the original files after the test
    restoreOriginalHelmFiles
    logMessage "INFO" "---------------------------------------------"
}

# # Function to restore the original contents of the input files
function restoreOriginalHelmFiles() {
    logMessage "INFO" "Restoring original helm files"
    sed -i "s/^version: .*/version: @@VERSION_BOT_TOKEN@@/" "${REPLACE_V_CONFIG_FILETOKEN_FILE}"
}
# Function to run all tests
function runTests() {
    local scopeOfTestSuite="$1"

    echo "scopeOfTestSuite: $scopeOfTestSuite"
    # runTest <Name> <Last Dev version> <Last RC version> <Last Release version> <Expected Value> <version temp file> <app-version>
    
    logMessage "INFO" "Starting test execution"
    logMessage "INFO" "---------------------------------------------"

    for tcPath in "${scopeOfTestSuite}"; do
        echo "[INFO] Processing folder: $tcPath"

        testSpecPullPath="${tcPath}/${TEST_SPEC_FILE}"

        name=$(yq e '.testInfo.name' $testSpecPullPath)
        description=$(yq e '.testInfo.description' $testSpecPullPath)
        lastDevVersion=$(yq e '.input.lastDevVersion' $testSpecPullPath)
        lastRcVersion=$(yq e '.input.lastRcVersion' $testSpecPullPath)
        lastReleaseVersion=$(yq e '.input.lastReleaseVersion' $testSpecPullPath)
        lastRebaseVersion=$(yq e '.input.lastRebaseVersion' $testSpecPullPath)
        targetBaseVersion=$(yq e '.input.targetBaseVersion' $testSpecPullPath)
        branchName=$(yq e '.input.branchName' $testSpecPullPath)
        appVersion=$(yq e '.input.appVersion' $testSpecPullPath)
        mockedEnvFile=$(yq e '.file.mockedEnvFile' $testSpecPullPath)
        versionFileTmp=$(yq e '.file.versionFileTmp' $testSpecPullPath)
        expectedValue=$(yq e '.output.expectedValue' $testSpecPullPath)

        versionFileFullPath="${tcPath}/${versionFileTmp}"
        mockedEnvFileFullPath="${tcPath}/${mockedEnvFile}"

        logMessage "INFO" "$name"
        logMessage "INFO" "Description: $description"

        # echo "[INFO] lastDevVersion: $lastDevVersion"
        # echo "[INFO] lastRcVersion: $lastRcVersion"
        # echo "[INFO] lastReleaseVersion: $lastReleaseVersion"
        # echo "[INFO] lastRebaseVersion: $lastRebaseVersion"
        # echo "[INFO] targetBaseVersion: $targetBaseVersion"
        # echo "[INFO] branchName: $branchName"
        # echo "[INFO] appVersion: $appVersion"
        # echo "[INFO] versionFileTmp: $versionFileTmp"
        # echo "[INFO] mockedEnvFile: $mockedEnvFile"
        # echo "[INFO] expectedValue: $expectedValue"

        modifyEnvFilesForTestCase "${mockedEnvFileFullPath}" "${tcPath}"
        source "${mockedEnvFileFullPath}"

        # Modify the input files for the test case
        modifyVersionFilesForTestCase "$lastDevVersion" "$lastRcVersion" "$lastReleaseVersion" "$appVersion" "$branchName" "$lastRebaseVersion" "$mockedEnvFileFullPath"

        runTest "${name}" "${expectedValue}" "${versionFileFullPath}" "${branchName}" "${mockedEnvFileFullPath}" "${targetBaseVersion}"
    done


    # Test case 1
    # runTest "Test Case 1" "22.4.28-dev.2" "22.4.26-rc.3" "22.4.27" "" "22.5.0-dev.1" "testcase1/versionFile.tmp" "22.5" "feature"

    # Test case 2
    # runTest "Test Case 2" "22.5.0-dev.1" "22.4.26-rc.3" "22.4.27" "" "22.5.0-dev.2" "testcase2/versionFile.tmp" "22.5" "feature"

    # Test case 3
    # runTest "Test Case 3" "22.5.0-dev.2" "22.4.26-rc.3" "22.4.27" "" "22.4.28-dev.3" "testcase3/versionFile.tmp" "22.4" "feature"

    # # Test case 4: Hotfix-base 24.3.0
    # runTest "Test Case 4" "24.3.0-dev.2" "1.2.10-rc.2" "25.1.0" "24.3.0-hf.0" "24.3.0-hf.1" "testcase4/versionFile.tmp" "24.3" "hotfix-base/24.3.0"

    # # # Test case 5: Feature/test-for-25.1
    # runTest "Test Case 5" "24.3.0-dev.2" "1.2.10-rc.2" "25.1.0" "" "25.1.1-dev.1" "testcase5/versionFile.tmp" "25.1" "feature"

    # # # Test case 6: Feature/test-for-25.1 with doing commit twice
    # runTest "Test Case 6" "25.1.2-dev.1" "1.2.10-rc.2" "25.1.0" "" "25.1.2-dev.2" "testcase6/versionFile.tmp" "25.1" "feature"

    # # # Test case 7: Commit on feature/24.3.0 concurrently with feature/test-for-25.1
    # runTest "Test Case 7" "25.1.2-dev.2" "1.2.10-rc.2" "25.1.0" "" "24.3.0-dev.3" "testcase7/versionFile.tmp" "24.3" "feature"

    # # # Test case 8: Hotfix-base with doing commit again
    # runTest "Test Case 8" "24.3.0-dev.2" "1.2.10-rc.2" "25.1.0" "24.3.0-hf.1" "24.3.0-hf.2" "testcase8/versionFile.tmp" "24.3" "hotfix-base/24.3.0"

    # # Test case 9: Merge feature/test-for-25.1 to main
    # runTest "Test Case 9" "25.1.1-dev.2" "1.2.10-rc.2" "25.1.0" "" "25.1.1" "testcase9/versionFile.tmp" "25.1" "main"

    # # Test case 10: Create release/v25.2.0 and test on feature/test-for-R-25.2.0
    # runTest "Test Case 10" "25.1.1-dev.2" "1.2.10-rc.2" "25.1.1" "" "25.2.0-dev.1" "testcase10/versionFile.tmp" "25.2" "feature"

    # # Test case 11: feature/test-for-R-25.2.0 with doing commit twice
    # runTest "Test Case 11" "25.2.0-dev.1" "1.2.10-rc.2" "25.1.1" "" "25.2.0-dev.2" "testcase11/versionFile.tmp" "25.2" "feature"

    # # Test case 12: release/v25.2.0
    # runTest "Test Case 12" "25.2.0-dev.2" "1.2.10-rc.2" "25.1.1" "" "25.2.0-rc.1" "testcase12/versionFile.tmp" "25.2" "release"

    # # Test case 13: feature/test2-for-R-25.2.0
    # runTest "Test Case 13" "25.2.0-dev.2" "25.2.0-rc.1" "25.1.1" "" "25.2.0-dev.3" "testcase13/versionFile.tmp" "25.2" "feature"

    # # Test case 14: feature/test2-for-R-25.2.0 with doing twice
    # runTest "Test Case 14" "25.2.0-dev.3" "25.2.0-rc.1" "25.1.1" "" "25.2.0-dev.4" "testcase14/versionFile.tmp" "25.2" "feature"

    # # Test case 15: release/v25.2.0 with doing twice
    # runTest "Test Case 15" "25.2.0-dev.4" "25.2.0-rc.1" "25.1.1" "" "25.2.0-rc.2" "testcase15/versionFile.tmp" "25.2" "release"

    # # Test case 16: Merge feature/test-for-R-25.2.0 to release
    # runTest "Test Case 16" "25.2.0-dev.4" "25.2.0-rc.2" "25.1.1" "" "25.2.0-rc.3" "testcase16/versionFile.tmp" "25.2" "release"

    # # Test case 17: Merge hotfix-base to main
    # runTest "Test Case 17" "25.2.0-dev.4" "25.2.0-rc.3" "25.1.1" "" "25.1.2" "testcase17/versionFile.tmp" "25.1" "main"

    # Add more tests here as needed
    logMessage "INFO" "Test execution completed"
}

initializeLog

# Check if arguments are provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 [all | specific_testcase | range_of_testcases]"
    exit 1
fi

# Handle options
scope=$1

# Case 1: Run a specific testcase (e.g., testcase1, testcase2)
if [[ $scope =~ ^[0-9]+$ ]]; then
    runTests "${TEST_SUITE_PATH}/testcase${scope}"

# Case 2: Run all testcases (e.g., testcase1, testcase2, ...)
elif [ "$scope" == "all" ]; then
    runTests "${TEST_SUITE_PATH}/testcase*"

# # Case 3: Run a range of testcases (e.g., testcase1-testcase5)
# elif [[ $option =~ ^([0-9]+)-([0-9]+)$ ]]; then
#     start=${BASH_REMATCH[1]}
#     end=${BASH_REMATCH[2]}

#     for ((i=start; i<=end; i++)); do
#         run_testcase "testcase$i"
#     done

else
    echo "Invalid option. Usage: $0 [all | specific_testcase | range_of_testcases]"
    exit 1
fi


