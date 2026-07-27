# 04 - Script & Function Specification Reference

This document provides a line-by-line functional specification of all scripts in `gcs-versioning-bot`. It outlines signature interfaces, positional arguments, return codes, stdout/stderr behavior, side effects, and internal logic for every file.

---

## 1. `action.yml` (GitHub Composite Action Specification)

- **Type**: Composite GitHub Action Manifest.
- **Inputs**:
  - `controller-config-file-path` (Required): Path to project controller YAML (e.g. `controller-config-files/projects/default.yml`).
  - `config-default-query-path` (Optional): Query path inside YAML (default: `.smc.ci`).
  - `artifactory-base-url` / `artifactory-username` / `artifactory-password`: JFrog Artifactory connection details.
  - `artifactory-target-group` / `artifactory-target-artifact-name`: Artifactory group/path and artifact base name.
  - `jira-username` / `jira-password` / `jira-base-url` / `jira-project-key-list`: JIRA connection and project details.
  - `is-debug`: Boolean string (`'true'`/`'false'`).
- **Outputs**:
  - `dev-version`: Previous DEV version string.
  - `rc-version`: Previous RC version string.
  - `release-version`: Previous Release version string.
  - `next-version`: Newly generated version string.

---

## 2. `config/general.ini` (Variable Mapping Dictionary)

- **Purpose**: Central ini file defining scope mappings between raw YAML importer outputs (`artifact_auto_versioning__*`) and standardized shell scope environment variables.
- **Scope Constants**:
  - `MAJOR_SCOPE="MAJOR"`, `MINOR_SCOPE="MINOR"`, `PATCH_SCOPE="PATCH"`
  - `RC_SCOPE="RC"`, `DEV_SCOPE="DEV"`, `BUILD_SCOPE="BUILD"`, `REPLACEMENT_SCOPE="REPLACE"`
- **Position Constants**:
  - `MAJOR_POSITION=0`, `MINOR_POSITION=1`, `PATCH_POSITION=2`
- **Identifier Constants**:
  - `DEV_V_IDENTIFIER="dev"`, `RC_V_IDENTIFIER="rc"`, `REBASE_V_IDENTIFIER="hf"`
- **State File Constants**:
  - `ARTIFACT_LAST_DEV_VERSION_FILE="artifact_last_dev_version.txt"`
  - `ARTIFACT_LAST_RC_VERSION_FILE="artifact_last_rc_version.txt"`
  - `ARTIFACT_LAST_REL_VERSION_FILE="artifact_last_release_version.txt"`
  - `ARTIFACT_LAST_BASE_VERSION_FILE="artifact_last_base_version.txt"`
  - `ARTIFACT_UPDATED_REL_VERSION_FILE="artifact_updated_release_version.txt"`
  - `ARTIFACT_NEXT_VERSION_FILE="artifact_next_version.txt"`
  - `CORE_VERSION_UPDATED_FILE="core.updated"`
  - `FLAG_FILE_IS_INITIAL_VERSION="is_initial.flag"`

---

## 3. `scripts/bot-libs.sh` (Shared Helper Library)

- **Functions**:
  - `digestRebaseBranchSetup(rebaseReleaseVersion, versionFileTmp)`: Parses hotfix/rebase branch arguments. If `rebaseReleaseVersion` is populated, reads the base version from file and configures rebase state files.

---

## 4. `scripts/inject_config_vars.sh` (Environment Injection)

- **Purpose**: Converts raw YAML importer variables into exported `$GITHUB_ENV` scope variables.
- **Input**: `yaml-importer-tmp` file in workspace.
- **Logic**: Reads raw properties, applies default fallbacks (e.g. if scope rule is unset, sets rules enabled to `false`), formats values, and writes `echo "VAR=VALUE" >> $GITHUB_ENV`.

---

## 5. `scripts/verify_prerequisite.sh` (Branch Validation)

- **Positional Arguments**:
  - `$1`: Scope list to check (e.g., `MAJOR MINOR PATCH RC DEV`).
- **Logic**:
  Iterates over each enabled scope. Checks if current branch (`BUILD_GH_BRANCH_NAME`) or tag (`BUILD_GH_TAG_NAME`) matches the configured branch/tag filter for that scope.
- **Exit Code**: `0` on validation success; `1` if no active scope permits execution on current branch.

---

## 6. `scripts/get_latest_version.sh` (Historical Version Query Engine)

- **Positional Arguments**:
  - `$1`: Target artifact repository (`targetRepo`)
  - `$2`: Target DEV repository (`targetDevRepo`)
  - `$3`: Target Release repository (`targetReleaseRepo`)
  - `$4`: Version output file path (`versionOutputFile`)
  - `$5`: Prepend version label (`inputPrependVersionLabel`)
  - `$6`: Docker query flag (`isDockerOutput`)
- **Key Functions**:
  - `getLatestVersionFromArtifactory()`: Executes AQL pagination loop (page size 500) via `curl` or `jf rt curl`. Aggregates results into `$versionOutputFile.combined.tmp`, extracts version strings via regex, filters by `inputPrependVersionLabel`, and writes results to state files.
  - `getLatestVersionFromDocker()`: Queries Docker V2 registry tags API using `curl`, sorts tags via `sort -V`, and extracts matching versions.
  - `getLatestVersionFromJira()`: Queries JIRA REST API (`/rest/api/3/project/$key/versions`) to fetch published/unreleased versions.

---

## 7. `scripts/generate_package_version.sh` (Core Version Calculation Engine)

- **Positional Arguments**:
  - `$1`: Artifact base name
  - `$2`: Current branch name
  - `$3`: Label file path
  - `$4`: Tag file path
  - `$5`: Commit message file path
  - `$6`: Rebase release version
  - `$7`: Version file temporary path
  - `$8`: Dry-run / unit-test flag (`isUnitTest`)
- **Key Functions**:
  - `degaussCoreVersionVariables(scope)`: Resets/neutralizes variables for disabled core rules.
  - `checkReleaseVersionFeatureFlag(scope)`: Evaluates if core release rule conditions are satisfied.
  - `checkPreReleaseVersionFeatureFlag(scope)`: Evaluates if pre-release rule conditions are satisfied.
  - `getNeededIncrementReleaseVersion(devVer, rcVer, relVer)`: Selects starting `X.Y.Z` base version.
  - `incrementReleaseVersion(inputVer, pos, count)`: Bumps core release integer at position `pos` by `count` and resets trailing parts.
  - `incrementPreReleaseVersion(inputVer, identifier)`: Increments trailing pre-release integer ($N+1$).
  - `processWithReleaseVersionFile(inputVer, pos, scope, versionListFile)`: Handles file-driven core overrides and cross-references published versions list.
  - `replaceVersionInFile(inputVer, targetFile, token)`: Runs `sed` to replace `@@TOKEN@@`.
  - `replaceVersionForMaven(inputVer, targetPomFile)`: Invokes `mvn versions:set`.
  - `replaceVersionForYamlFile(inputVer, yamlFile, queryPath)`: Invokes `yq` in-place update.

---

## 8. `scripts/read_old_version.sh` & `scripts/read_new_version.sh`

- **`read_old_version.sh`**:
  - Accepts optional prepend label `$1`.
  - Reads `artifact_last_dev_version.txt`, `artifact_last_rc_version.txt`, `artifact_last_release_version.txt`.
  - Outputs formatted string: `dev=1.2.0-dev.1, rc=1.2.0-rc.1, rel=1.2.0`.
- **`read_new_version.sh`**:
  - Accepts optional prepend label `$1`.
  - Reads `artifact_next_version.txt`.
  - Outputs computed version string (e.g. `1.2.1` or `PREPEND-1.2.1`).

---

## 9. `scripts/store_version_in_jira.sh` (JIRA Version Management)

- **Positional Arguments**:
  - `$1`: JIRA username
  - `$2`: JIRA password/API token
  - `$3`: JIRA base URL
  - `$4`: Comma-separated JIRA project keys
  - `$5`: New version string
  - `$6`: JIRA version identifier prefix
  - `$7`: Version prepend label
- **Key Functions**:
  - `getJiraProjectId(key)`: Fetches numerical project ID from JIRA API.
  - `createArtifactNextVersionInJira()`: Posts new version object (`POST /rest/api/2/version`).
  - `updateJiraVersion()`: Updates version release/archive state (`PUT /rest/api/3/version/$id`).
  - `startArchiveJiraVersions()`: Iterates through unreleased versions in JIRA; archives any pre-release versions less than or equal to the newly released fixed version.

---

## 10. `scripts/tag_fixversion_in_jira.sh` & `scripts/get_commit_message.sh`

- **`get_commit_message.sh`**:
  - positional arguments: `$1` (newVersion), `$2` (commitMessageFile).
  - Uses `git log v<lastRelease>..HEAD` to extract commit delta between previous tag and `HEAD` and saves to `$commitMessageFile`.
- **`tag_fixversion_in_jira.sh`**:
  - Positional arguments: JIRA credentials, project keys, new version, message file.
  - Uses regex `grep -oP '([A-Z]+-[0-9]+)+'` to extract all JIRA ticket keys from commit messages.
  - Calls `PUT /rest/api/3/issue/$issueKey` to add the new version to the issue's `fixVersions` field.
