# 07 - Testing Framework & Validation Suite

To ensure absolute reliability across complex version calculation edge cases, `gcs-versioning-bot` includes a dedicated, self-contained unit testing framework and test suite.

This document details the test framework architecture, test specification schema, execution commands, mock state isolation, assertion routines, and test report generation.

---

## 1. Test Suite Architecture & Runners

The testing architecture consists of three core entry points:

1. **`unittest-versioning-bot.sh`**: Main test runner script. Iterates through test suites in `test-files/`, loads controller YAML configs, sets mock input files, executes version calculations, and asserts outputs.
2. **`unittest-get-latest-version.sh`**: Focused unit test runner for validating Artifactory AQL pagination, regex parsing, and version trimming.
3. **`test.sh`**: Standalone integration sandbox for testing real AQL queries against live Artifactory endpoints.

```
                      +---------------------------------------+
                      |       unittest-versioning-bot.sh      |
                      +---------------------------------------+
                                          |
                +-------------------------+-------------------------+
                |                                                   |
                v                                                   v
  +---------------------------+                       +---------------------------+
  |    test-files/ Suite      |                       |    Controller Configurations |
  |  - local/                 |                       |  - default.yml            |
  |  - jfrog/                 |                       |  - enable-std-rules.yml   |
  |  - jira/                  |                       |  - enable-trunk-vers...   |
  |  - maven/                 |                       |  - enable-msgtag.yml      |
  +---------------------------+                       +---------------------------+
                |                                                   |
                +-------------------------+-------------------------+
                                          |
                                          v
                      +---------------------------------------+
                      |         runTest() Assertion           |
                      |  Compare actual vs expectedValue      |
                      |  Verify file replacements             |
                      +---------------------------------------+
                                          |
                                          v
                      +---------------------------------------+
                      |        unit-test-report-*.txt         |
                      +---------------------------------------+
```

---

## 2. Test Case Specification Schema (`unit-test-spec.yml`)

Every test case inside `test-files/<suite>/<config_name>/testcase<N>/` is driven by a declarative `unit-test-spec.yml` specification file.

### 2.1 Schema Definition
```yaml
test-spec:
  info:
    name: "Standard Patch Increment on Main Branch"
    description: "Validates that a standard commit on main branch increments the PATCH version part."
    
  input:
    lastDevVersion: "1.2.0-dev.4"    # Mock last DEV version from Artifactory
    lastRcVersion: "1.2.0-rc.2"      # Mock last RC version from Artifactory
    lastReleaseVersion: "1.2.0"     # Mock last Release version from Artifactory
    lastRebaseVersion: "null"        # Mock last Base/Hotfix version
    targetBaseVersion: ""            # Target base version override
    branchName: "main"               # Simulated git branch name
    appVersion: "1.2"                # Version string in app-version.cfg
    
  file:
    versionFileTmp: "versionFile.tmp"# Name of version file override inside testcase folder
    
  output:
    expectedValue: "1.2.1"           # Expected final calculated version string
```

---

## 3. Test Runner Execution & Command Interface

The test runner script accepts four positional arguments:

```bash
./unittest-versioning-bot.sh <SUITE_COLLECTION> <CONFIG_FILE> <SCOPE> <EXCLUDED_LIST>
```

### 3.1 Parameter Options
- `<SUITE_COLLECTION>`: Test suite folder under `test-files/` (`local`, `jfrog`, `jira`, `maven`).
- `<CONFIG_FILE>`: Specific controller config name (e.g. `enable-std-rules`) or `all` to run all configs in the suite.
- `<SCOPE>`: Specific testcase number (e.g. `1`, `2`) or `all` to run every testcase.
- `<EXCLUDED_LIST>`: Comma-separated list of config names to skip during bulk execution.

### 3.2 Common Command Examples

1. **Run a single test case**:
   ```bash
   ./unittest-versioning-bot.sh local enable-std-rules 1
   ```

2. **Run all test cases for a specific configuration**:
   ```bash
   ./unittest-versioning-bot.sh local enable-std-rules all
   ```

3. **Run the entire local test suite across all configurations**:
   ```bash
   ./unittest-versioning-bot.sh local all all
   ```

---

## 4. Mock State Isolation & Verification Protocol

When `unittest-versioning-bot.sh` executes a test case:

1. **Environment Clean Isolation**: Creates temporary environment files (`env.tmp`, `yaml-importer-tmp`).
2. **Version State Pre-loading**: Writes `lastDevVersion`, `lastRcVersion`, `lastReleaseVersion`, and `lastRebaseVersion` directly into the temporary state files (`artifact_last_dev_version.txt`, etc.).
3. **Controller Ingestion**: Invokes `test-files/scripts/yaml-converter.sh` to parse the target YAML configuration into environment exports.
4. **Core Script Invocation**: Sources `scripts/generate_package_version.sh` in unit-test mode (`isUnitTest="true"`).
5. **Output Assertion (`verifyOutput`)**:
   - Reads calculated output from `artifact_next_version.txt`.
   - Asserts exact string equality between actual output and `expectedValue`.
   - If file replacement rules (`REPLACE_V_RULES_ENABLED`) are active, checks that the target manifest (`pom.xml`, `deployment.yaml`, `values.yaml`) was correctly updated with `expectedValue`.
6. **State Cleanup & Restoration (`restoreReplacementFiles`)**: Restores original mock file tokens (`@@VERSION_BOT_TOKEN@@`) so subsequent test runs remain clean and deterministic.

---

## 5. Summary Report Generation

At the conclusion of a test run, `unittest-versioning-bot.sh` generates a formatted report file named `unit-test-report-<TIMESTAMP>.txt`:

```
===============================
Test Summary Report
===============================

Config Name: enable-std-rules
- Test Case 1 PASS
- Test Case 2 PASS
- Test Case 3 PASS
Result: 3 passed / 3 total

Config Name: enable-msgtag
- Test Case 1 PASS
- Test Case 2 PASS
Result: 2 passed / 2 total

===============================
Overall Summary
-------------------------------
Total Configs:     2
Total Test Cases:  5
Passed:            5
Failed:            0
===============================
```
