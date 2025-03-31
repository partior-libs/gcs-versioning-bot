#!/bin/bash
source run2.sh

# Path to the files
inputFile1="${ARTIFACT_LAST_DEV_VERSION_FILE}"
inputFile2="${ARTIFACT_LAST_RC_VERSION_FILE}"
inputFile3="${ARTIFACT_LAST_REL_VERSION_FILE}"
inputFile4="${ARTIFACT_LAST_BASE_VERSION_FILE}"

actualOutputFile="${ARTIFACT_NEXT_VERSION_FILE}"
scriptPath="./scripts/generate_package_version.sh"
logFile="test_log.txt"

# Function to log messages
function logMessage() {
    local logLevel=$1
    local message=$2
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp [$logLevel] $message" >> "$logFile"
}

# Function to initialize the log file
function initializeLog() {
    echo "Starting test run at $(date '+%Y-%m-%d %H:%M:%S')" > "$logFile"
    logMessage "INFO" "Log file initialized"
}

# # Function to restore the original contents of the input files
function restoreOriginalFiles() {
    logMessage "INFO" "Restoring original helm files"
    sed -i "s/^version: .*/version: @@VERSION_BOT_TOKEN@@/" "helm/goquorum-node/Chart.yaml"
}

# Function to modify input files for the test case
function modifyFilesForTestCase() {
    local devVersion="$1"
    local RcVersion="$2"
    local releaseVersion="$3"
    local appVersion="$4"
    local sourceBranch="$5"

    local majorVersion
    local minorVersion

    logMessage "INFO" "Modifying input files for test case"
    echo "$devVersion" > "$inputFile1"
    echo "$RcVersion" > "$inputFile2"
    echo "$releaseVersion" > "$inputFile3"
    logMessage "INFO" "Last Dev version $(cat $inputFile1)"
    logMessage "INFO" "Last RC version $(cat $inputFile2)"
    logMessage "INFO" "Last Release version $(cat $inputFile3)"

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

        # Show the content of app-version.cfg
        cat "${MAJOR_V_CONFIG_VFILE_NAME}"
        cat "${MINOR_V_CONFIG_VFILE_NAME}"
    fi

    if [[ -z "${sourceBranch}" ]]; then
        echo "[ERROR] Source Branch is empty. Please add the branch name into runTest!"
        exit 1
    else
        if [[ "${sourceBranch}" =~ ^hotfix-base/* ]]; then
            branchName=$(echo "$sourceBranch" | cut -d'/' -f1)
            baseVersion=$(echo "$sourceBranch" | cut -d'/' -f2)
            echo "branchName: $branchName"
            echo "baseVersion: $baseVersion"
            echo "$baseVersion" > "$inputFile4"
            logMessage "INFO" "Last Base version $(cat $inputFile4)"

            sed -i "s/^BUILD_GH_BRANCH_NAME=.*/BUILD_GH_BRANCH_NAME=$branchName/" "run2.sh"

        else
            echo "" > "$inputFile4"
            sed -i "s/^BUILD_GH_BRANCH_NAME=.*/BUILD_GH_BRANCH_NAME=$sourceBranch/" "run2.sh"
        fi 
    fi
}

# Function to run the actual test
function runTest() {
    local testName=$1
    local devVersion="$2"
    local RcVersion="$3"
    local releaseVersion="$4"
    local baseVersion="${5:-}"
    local expectedOutput="$6"
    local versionFileTmp="$7"
    local appVersion="$8"
    local sourceBranch="$9"

    # Modify the input files for the test case
    modifyFilesForTestCase "$devVersion" "$RcVersion" "$releaseVersion" "$appVersion" "$sourceBranch"

    # Get the actual output from the script
    bash "${scriptPath}" "goquorum-node" "${sourceBranch}" "${BUILD_GH_LABEL_FILE}" "${BUILD_GH_TAG_FILE}" "${BUILD_GH_COMMIT_MESSAGE_FILE}" "${baseVersion}" "${versionFileTmp}" "true"

    local actualOutput=$(cat "$actualOutputFile")
    
    # Compare the actual output with the expected output
    if [ "$actualOutput" == "$expectedOutput" ]; then
        logMessage "SUCCESS" "$testName PASSED. As Expected: '$expectedOutput'"
        logMessage "INFO" "---------------------------------------------"
        echo "$testName PASSED"
    else
        logMessage "ERROR" "$testName FAILED. Expected: '$expectedOutput', but Actual: '$actualOutput'"
        logMessage "INFO" "---------------------------------------------"
        echo "$testName FAILED"
    fi

    # Restore the original files after the test
    restoreOriginalFiles
}

# Function to run all tests
function runTests() {
    # runTest <Name> <Last Dev version> <Last RC version> <Last Release version> <Expected Value> <version temp file> <app-version>
    
    logMessage "INFO" "Starting test execution"
    logMessage "INFO" "---------------------------------------------"

    # Test case 1
    # runTest "Test Case 1" "22.4.28-dev.2" "22.4.26-rc.3" "22.4.27" "" "22.5.0-dev.1" "testcase1/versionFile.tmp" "22.5" "feature"

    # Test case 2
    # runTest "Test Case 2" "22.5.0-dev.1" "22.4.26-rc.3" "22.4.27" "" "22.5.0-dev.2" "testcase2/versionFile.tmp" "22.5" "feature"

    # Test case 3
    # runTest "Test Case 3" "22.5.0-dev.2" "22.4.26-rc.3" "22.4.27" "" "22.4.28-dev.3" "testcase3/versionFile.tmp" "22.4" "feature"

    # Test case 4
    runTest "Test Case 4" "24.3.0-dev.2" "1.2.10-rc.2" "25.1.0" "24.3.0-hf.0" "24.3.0-hf.1" "testcase4/versionFile.tmp" "24.3" "hotfix-base/24.3.0"

    # Test case 5
    runTest "Test Case 5" "24.3.0-dev.2" "1.2.10-rc.2" "25.1.0" "" "25.1.1-dev.1" "testcase5/versionFile.tmp" "25.1" "feature"

    # Test case 6
    runTest "Test Case 6" "25.1.2-dev.1" "1.2.10-rc.2" "25.1.0" "" "25.1.2-dev.2" "testcase6/versionFile.tmp" "25.1" "feature"

    # Test case 7
    runTest "Test Case 7" "25.1.2-dev.2" "1.2.10-rc.2" "25.1.0" "" "24.3.0-dev.3" "testcase6/versionFile.tmp" "24.3" "feature"

    # Add more tests here as needed
    logMessage "INFO" "Test execution completed"
}

# Initialize the log file
initializeLog

# Run the tests
runTests

