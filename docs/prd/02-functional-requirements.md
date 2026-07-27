# 02 - Functional Requirements Specification

This document details the functional requirements (FRs) for the Greenfield Automated Semantic Versioning & Release Engine. All requirements are categorized and assigned unique IDs for traceability.

---

## 1. Requirement Categories Summary

| Category ID | Category Name | Description |
| :--- | :--- | :--- |
| **FR-VER** | Version Tiers & Calculation | Core SemVer 2.0.0 calculation, pre-release streams, hotfixes, and build metadata. |
| **FR-REG** | Registry Discovery & State Retrieval | Remote querying of JFrog Artifactory (AQL), Docker Registries, and JIRA. |
| **FR-RUL** | Rules Engine & Condition Evaluation | Branch pattern matching, git tags, commit message keywords, and file overrides. |
| **FR-REP** | File Replacement & Source Updates | Updating tokens, Maven POMs, and YAML query paths in source files. |
| **FR-JIR** | Issue Tracker Integration | Creating versions, archiving candidates, extracting ticket keys, and updating `fixVersions`. |
| **FR-EXP** | Pipeline Output Exports | Writing results to pipeline environment variables and step outputs. |

---

## 2. Functional Requirements Detail

### 2.1 Category FR-VER: Version Tiers & Calculation Engine

- **FR-VER-1 (SemVer 2.0.0 Parity)**: The engine MUST format calculated versions in compliance with Semantic Versioning 2.0.0 specification (`MAJOR.MINOR.PATCH-PRERELEASE+BUILD`).
- **FR-VER-2 (Base Release Selection)**: The engine MUST compare the highest published `DEV`, `RC`, and `Release` versions to establish the base `MAJOR.MINOR.PATCH` version before applying increments.
- **FR-VER-3 (Pre-Release Identifier Streams)**:
  - Development builds MUST default to pre-release identifier `-dev.N` (configurable).
  - Release Candidates MUST default to pre-release identifier `-rc.N` (configurable).
  - Hotfix/Rebase builds MUST default to pre-release identifier `-hf.N` (configurable).
- **FR-VER-4 (Pre-Release Counter Progression)**:
  - If the base `X.Y.Z` version changes (e.g. from `1.2.0` to `1.3.0`), the pre-release counter MUST reset to `1` (e.g. `1.3.0-rc.1`).
  - If the base `X.Y.Z` version remains unchanged, the pre-release counter MUST increment by $+1$ (e.g. `1.2.0-rc.2` $\rightarrow$ `1.2.0-rc.3`).
- **FR-VER-5 (Pre-Release Suppression Invariant)**: When an automatic `DEV` or `RC` pre-release increment is active for the current branch, the core `MAJOR`/`MINOR`/`PATCH` auto-increment MUST be suppressed to prevent double-incrementing the base version.
- **FR-VER-6 (Build Metadata Appending)**: If build metadata is enabled, the engine MUST append `+<IDENTIFIER>.<RUN_NUMBER>.<RUN_ATTEMPT>` (e.g. `+bld.103.1`) to the calculated version string.

---

### 2.2 Category FR-REG: Registry Discovery & Historical State Retrieval

- **FR-REG-1 (Artifactory AQL Discovery)**: The engine MUST query JFrog Artifactory using Artifactory Query Language (AQL) to fetch published artifacts matching target repository names and path patterns.
- **FR-REG-2 (AQL Paginated Querying)**:
  - The AQL discovery client MUST execute queries using page-based pagination (`offset` and `limit` set to $500$).
  - The client MUST continue fetching subsequent pages until the result count on a page is $< 500$.
- **FR-REG-3 (Docker Registry Tag Discovery)**: The engine MUST support querying Docker Registry V2 APIs to retrieve image tag lists when Docker image tags are the primary source of version state.
- **FR-REG-4 (Prepend Label Filtering)**: The engine MUST filter retrieved artifact lists using the active Version Prepend Label (e.g. `SERVICE_NAME-1.2.0`) before determining highest versions.
- **FR-REG-5 (Initial Repository Fallback)**: If no previous artifacts exist in remote registries, the engine MUST mark `is_initial_version = true` and initialize from `1.0.0` or configured initial bounds.

---

### 2.3 Category FR-RUL: Rules Engine & Condition Evaluation

- **FR-RUL-1 (Branch Matching)**: Every version scope (`MAJOR`, `MINOR`, `PATCH`, `RC`, `DEV`, `BUILD`, `REPLACEMENT`) MUST support a list of comma-separated target branch patterns (e.g. `main,master`, `release/*`, `feature/*`).
- **FR-RUL-2 (Commit Message Keyword Parsing / Multi-Bump)**:
  - The engine MUST inspect commit messages or PR titles for configured message tags (e.g. `[MAJOR-VERSION]`, `#minor`).
  - The engine MUST count occurrences of message tags. If $K$ matching tags are found, the corresponding version part MUST be incremented by $+K$.
- **FR-RUL-3 (Version File Overrides)**:
  - The engine MUST support reading explicit `MAJOR` or `MINOR` version numbers from repository files (e.g. `app-version.cfg` containing `MAJOR-VERSION=2`).
  - When a file rule is active, the engine MUST override auto-calculated numbers with the explicit file value while ensuring trailing parts (`PATCH`) reset appropriately.

---

### 2.4 Category FR-REP: Source Code & Manifest File Updates

- **FR-REP-1 (Generic Token Substitution)**: The engine MUST support replacing token placeholders formatted as `@@<TOKEN_NAME>@@` in designated text files.
- **FR-REP-2 (Maven POM Updates)**: The engine MUST support updating the version in Maven `pom.xml` files using standard Maven plugin interfaces (`mvn versions:set -DnewVersion=<VER>`).
- **FR-REP-3 (YAML Path Updates)**: The engine MUST support updating specific YAML paths (e.g. `.image.tag`) in YAML configuration manifests using `yq` or equivalent structured YAML parsers.
- **FR-REP-4 (Idempotent Replacement)**: File update operations MUST be fully idempotent and leave no backup files (e.g. `pom.xml.versionsBackup`) in the repository workspace.

---

### 2.5 Category FR-JIR: Issue Tracker Synchronization

- **FR-JIR-1 (Version Creation)**: The engine MUST support creating new JIRA Version objects (`POST /rest/api/2/version`) containing start date, target release date ($+14$ days), and workflow run URL.
- **FR-JIR-2 (Obsolete Version Archiving)**: Upon publishing a fixed release version (`X.Y.Z`), the engine MUST query unreleased JIRA versions and update superseded release candidates to `archived = true`.
- **FR-JIR-3 (Commit Message Key Extraction)**: The engine MUST parse git commit message logs delta between previous release tag and `HEAD` using regex `([A-Z]+-[0-9]+)+` to extract JIRA issue keys.
- **FR-JIR-4 (Issue FixVersion Tagging)**: The engine MUST append the newly calculated version string to the `fixVersions` field of extracted JIRA issue keys (`PUT /rest/api/3/issue/<KEY>`).

---

### 2.6 Category FR-EXP: Pipeline Environment Output & Exports

- **FR-EXP-1 (Step Output Export)**: The engine MUST write calculated version properties (`dev-version`, `rc-version`, `release-version`, `next-version`) to standard pipeline step outputs (`$GITHUB_OUTPUT` or equivalent).
- **FR-EXP-2 (Environment Variable Export)**: The engine MUST export `BUILD_GH_VERSION_NEXT=<VER>` to pipeline runner environment variables (`$GITHUB_ENV` or equivalent).
