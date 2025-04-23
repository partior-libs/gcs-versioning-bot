#!/bin/bash
TEST_SUITE_PATH="./test-files"
TEST_SPEC_FILE="unit-test-spec.yml"
GET_LATEST_VERSION_SCRIPT_PATH="./scripts/get_latest_version.sh"
YAML_IMPORTER_SCRIPT_PATH="./test-files/scripts/yaml-converter.sh"
YAML_IMPORTER_FILE="yaml-importer-tmp"
GENERAL_CONFIG="config/general.ini"
BASE_CONTROLLER_CONFIG_DIR="controller-config-files/projects"
DEFAULT_CONTROLLER_CONFIG_FILE="controller-config-files/projects/default.yml"
ARTIFACTORY_BASE_URL="https://partior.jfrog.io/artifactory"
JIRA_BASE_URL="https://partior.atlassian.net"

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

function getVersionExclusionString(){
    versionExclusionString="${artifact_auto_versioning__exclude_tagname}"
    if [[ -z "$versionExclusionString" ]]; then
        versionExclusionString="latest"
    fi
    echo "[INFO] versionExclusionString=$versionExclusionString" >&2
    echo "${versionExclusionString}"
}

# Function to run the actual test
function runTest() {
    local jfrogToken="$1"
    local jiraUserName="$2"
    local jiraPassword="$3"
    local versionFile="$4"
    local artifactoryUsername="$5"
    local artifactoryPassword="$6"

    local versionPrependLabel
    if [[ "${artifact_auto_versioning__prepend_version__enabled}" == "true" ]]; then
        versionPrependLabel=$(getVersionPrependLabel "${testCasePath}")
        echo "BUILD_GH_VERSION_PREPEND_LABEL: ${versionPrependLabel}"
    fi

    versionFilter=$(getVersionExclusionString)
    echo "[INFO] getVersionExclusionString: $versionFilter"

    echo "[DEBUG]" "${GET_LATEST_VERSION_SCRIPT_PATH}" "\"${ARTIFACTORY_BASE_URL}\"" \
        "\"${branches__default__artifact__packager__artifactory_repo}\"" \
        "\"${branches__default__artifact__packager__artifactory_dev_repo}\"" \
        "\"${branches__default__artifact__packager__artifactory_release_repo}\"" \
        "\"${branches__default__artifact__packager__group}\"" \
        "\"${artifact_base_name}\"" \
        "\"${BUILD_GH_BRANCH_NAME}\"" \
        "\"${artifact_auto_versioning__initial_release_version}\"" \
        "\"${artifactoryUserName}\"" \
        "\"${artifactoryPassword}\"" \
        "\"${jfrogToken}\"" \
        "\"${jiraUserName}\"" \
        "\"${jiraPassword}\"" \
        "\"${JIRA_BASE_URL}\"" \
        "\"${artifact_auto_versioning__version_sources__jira__project_keys}\"" \
        "\"${artifact_auto_versioning__version_sources__jira__enabled}\"" \
        "\"${artifact_auto_versioning__version_sources__jira__version_identifier}\"" \
        "\"${artifactType}\"" \
        "\"${versionPrependLabel}\"" \
        "\"${versionFilter}\"" \
        "\"${version}\"" \
        "\"${versionFile}\""

    source "${GET_LATEST_VERSION_SCRIPT_PATH}" "${ARTIFACTORY_BASE_URL}" \
        "${branches__default__artifact__packager__artifactory_repo}" \
        "${branches__default__artifact__packager__artifactory_dev_repo}" \
        "${branches__default__artifact__packager__artifactory_release_repo}" \
        "${branches__default__artifact__packager__group}" \
        "${artifact_base_name}" \
        "${BUILD_GH_BRANCH_NAME}" \
        "${artifact_auto_versioning__initial_release_version}" \
        "${artifactoryUserName}" \
        "${artifactoryPassword}" \
        "${jfrogToken}" \
        "${jiraUserName}" \
        "${jiraPassword}" \
        "${JIRA_BASE_URL}" \
        "${artifact_auto_versioning__version_sources__jira__project_keys}" \
        "${artifact_auto_versioning__version_sources__jira__enabled}" \
        "${artifact_auto_versioning__version_sources__jira__version_identifier}" \
        "${artifactType}" \
        "${versionPrependLabel}" \
        "${versionFilter}" \
        "${version}" \
        "${versionFile}"
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

# Function to run all tests
function runTests() {
    local scopeOfConfigFiles="$1"
    local scopeOfTestSuite="$2"
    local jfrogToken="$3"
    local jiraUserName="$4"
    local jiraPassword="$5"
    local artifactoryUsername="$6"
    local artifactoryPassword="$7"

    echo "scopeOfTestSuite: $scopeOfTestSuite"
    echo "scopeOfConfigFiles: $scopeOfConfigFiles"

    local testCaseList=()
    for testcase in $scopeOfTestSuite; do
        testCaseList+=("$testcase")
    done

    # Sort a list of test cases numerically
    for tcPath in $(printf "%s\n" "${testCaseList[@]}" | sort -V); do
        echo "[DEBUG] Running the $(basename $tcPath) from config: $scopeOfConfigFiles"
        if [[ -d $tcPath ]]; then
            testSpecPullPath="${tcPath}/${TEST_SPEC_FILE}"

            versionFileTmp=$(yq e ".test-spec.file.versionFileTmp" $testSpecPullPath)
            versionFileFullPath="${tcPath}/${versionFileTmp}"

            echo "[INFO] versionFileTmp: $versionFileTmp"

            configFilePath=$(findConfigFile "${scopeOfConfigFiles}" "${BASE_CONTROLLER_CONFIG_DIR}")
            echo "configFilePath: $configFilePath"

            startYamlImporter "${YAML_IMPORTER_FILE}" "${configFilePath}"
            source "${YAML_IMPORTER_FILE}"

            runTest "${jfrogToken}" "${jiraUserName}" "${jiraPassword}" "${versionFileFullPath}" "${artifactoryUsername}" "${artifactoryPassword}"
        fi
    done
}

function mainTestRunner(){
    local suiteCollection="$1"
    local configFile="$2"
    local scope="$3"
    local jfrogToken="$4"
    local jiraUserName="$5"
    local jiraPassword="$6"
    local artifactoryUsername="$7"
    local artifactoryPassword="$8"

    # Check if arguments are provided
    if [ $# -eq 0 ]; then
        echo "Usage: $0 [all | specific_testcase | range_of_testcases]"
        exit 1
    fi

    # Case 1: Run one config file + a specific testcase (e.g., testcase1, testcase2)
    if [[ $configFile != "all" && $scope =~ ^[0-9]+$ ]]; then
        runTests "$configFile" "${TEST_SUITE_PATH}/${suiteCollection}/${configFile}/testcase${scope}" "${jfrogToken}" "${jiraUserName}" "${jiraPassword}" "${artifactoryUsername}" "${artifactoryPassword}"

    # Case 2: Run one config file + all testcases (e.g., testcase1, testcase2, ...)
    elif [[ $configFile != "all" && $scope == "all" ]]; then
        runTests "$configFile" "${TEST_SUITE_PATH}/${suiteCollection}/${configFile}/testcase*" "${jfrogToken}" "${jiraUserName}" "${jiraPassword}" "${artifactoryUsername}" "${artifactoryPassword}"

    else
        echo "Invalid option. Usage: $0 [all | specific_testcase | range_of_testcases]"
        exit 1
    fi
}

# Handle options
suiteCollection="$1"
configFile="$2"
scope="$3"
jfrogToken="$4"
jiraUserName="$5"
jiraPassword="$6"
artifactoryUsername="$7"
artifactoryPassword="$8"

mainTestRunner "${suiteCollection}" "${configFile}" "${scope}" "${jfrogToken}" "${jiraUserName}" "${jiraPassword}" "${artifactoryUsername}" "${artifactoryPassword}"




