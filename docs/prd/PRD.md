# Product Requirements Document (PRD) — Automated Semantic Versioning & Release Engine

**Document Version**: 1.0.0  
**Document Status**: Approved / Master Greenfield Specification  
**Target Execution Environment**: Language-Agnostic / Multi-Platform (Go, TypeScript, Rust, Python, CI/CD Runners)

---

## 1. Product Vision & Strategic Objectives

### 1.1 Executive Summary & Problem Statement
In modern software engineering organizations managing decentralized microservices, blockchain smart contracts, libraries, and containerized workloads, managing software versioning manually or via ad-hoc scripts leads to significant operational friction:

1. **Version Collisions & Merge Conflicts**: Parallel feature branches modifying version files (`pom.xml`, `package.json`, `Chart.yaml`) suffer constant git merge conflicts and broken builds.
2. **Inconsistent Pre-Release Lifecycles**: Lack of standardized pre-release tags (`-dev.N`, `-rc.N`) pollutes artifact registries where development builds accidentally overwrite release candidates.
3. **Traceability Breakdown Between CI/CD & Issue Trackers**: Releases built in CI/CD are disconnected from issue trackers (e.g., JIRA), making it difficult for QA and Release Managers to identify which tickets are included in a specific build.
4. **Fragile Historical State**: Traditional tools rely solely on local git tags, which can be wiped, missed during shallow clones (`fetch-depth: 1`), or out of sync with actual published artifacts in remote registries.
5. **Rigid Tooling Coupling**: Custom versioning scripts hardcoded to specific CI platforms cannot easily be ported across runner environments or modernized tech stacks.

---

### 1.2 Core Value Proposition
The **Automated Semantic Versioning & Release Engine** is a **stateless, declarative, registry-aware version calculation engine** that serves as the single source of truth for software release packaging.

```
[ Git Commits / PRs ]      +-----------------------------------------+      [ Updated Manifests ]
[ Branch / Tag Context ] -> |  AUTOMATED SEMANTIC VERSIONING &        | ->   [ Artifact Registry Tags ]
[ Controller Config ]      |  RELEASE ENGINE                         | ->   [ JIRA Releases / Tickets]
[ Artifact Registry ]      +-----------------------------------------+      [ Pipeline Exports ]
```

#### Key Differentiators
- **Registry-as-State**: Discovers the true "last published version" by querying remote artifact repositories via API (with automatic pagination) rather than relying solely on local git tags.
- **Multi-Tier SemVer Lifecycle**: Natively manages five distinct streams: Core Releases (`X.Y.Z`), Release Candidates (`X.Y.Z-rc.N`), Development Builds (`X.Y.Z-dev.N`), Hotfixes (`X.Y.Z-hf.N`), and Build Metadata (`+bld.<run>.<attempt>`).
- **Declarative Rule Engine**: Every aspect of version calculation (branch regexes, message keywords, version files, target tokens) is configured via external YAML files.
- **Bi-Directional Issue Sync**: Automatically creates JIRA versions, archives obsolete release candidates, extracts ticket IDs from commit logs, and tags `fixVersions`.

---

### 1.3 Target Personas & User Scenarios

#### Personas
- **DevOps / Platform Engineer**: Wants a reusable, deterministic versioning engine that works across all microservices without per-repo maintenance.
- **Software Developer**: Wants automated versioning on pull requests without manual file edits or git tag friction.
- **Release Manager / QA Lead**: Requires clear traceability showing which JIRA tickets and commits are deployed in each candidate build.

#### Primary User Scenarios
- **Scenario A: Developer Feature Branch PR**:
  - *Context*: Developer pushes commits to a `feature/JIRA-101` branch.
  - *Engine Behavior*: Detects branch matching `DEV` scope $\rightarrow$ Queries registry for highest `X.Y.Z-dev.*` artifact $\rightarrow$ Increments trailing integer ($N + 1$) to produce `1.2.0-dev.4` $\rightarrow$ Replaces version tokens in workspace manifests.
- **Scenario B: Release Candidate Staging**:
  - *Context*: Code merges into a `release/1.2.0` branch.
  - *Engine Behavior*: Detects branch matching `RC` scope $\rightarrow$ Calculates `1.2.0-rc.1` $\rightarrow$ Posts JIRA API to create release `RC_service-name-1.2.0-rc.1` $\rightarrow$ Scans commit log for `PROJ-*` tickets and updates their `fixVersions` field in JIRA.
- **Scenario C: Production Release Merge**:
  - *Context*: Release branch merges into `main`.
  - *Engine Behavior*: Detects `main` branch matching `Release` scope $\rightarrow$ Calculates `1.2.0` $\rightarrow$ Queries JIRA for unreleased candidates matching `1.2.0-rc.*` and updates their state to `archived = true`.
- **Scenario D: Emergency Production Hotfix**:
  - *Context*: Critical production vulnerability patched on `hotfix/v1.2.0`.
  - *Engine Behavior*: Detects hotfix branch structure $\rightarrow$ Queries last base version (`1.2.0-hf.0`) $\rightarrow$ Increments hotfix patch number to `1.2.0-hf.1`.

---

### 1.4 Success Metrics (KPIs)
- **Zero Version Collisions**: 100% elimination of build failures caused by duplicate artifact version publishing.
- **100% Monotonic Progression**: Zero version regressions across all automated releases.
- **Sub-2-Second Latency Budget**: Version discovery, calculation, and file replacement completed in $< 2.0$ seconds (excluding remote network latency).
- **Zero-Database Operational Overhead**: 100% stateless execution requiring no internal persistent databases.

---

## 2. Domain Data Model & State Machine

### 2.1 Domain Entity Model

```
                     +---------------------------+
                     |       Configuration       |
                     +---------------------------+
                                   |
         +-------------------------+-------------------------+
         |                                                   |
         v                                                   v
+------------------+                               +------------------+
|   VersionScope   |                               | ArtifactRegistry |
| (MAJOR, MINOR,   |                               | (AQL / Docker /  |
|  PATCH, RC, DEV) |                               |  JIRA Source)    |
+------------------+                               +------------------+
         |                                                   |
         v                                                   v
+------------------+                               +------------------+
|    ScopeRule     |                               | ArtifactHistory  |
| (Branch, Tag,    |                               | (lastDev, lastRc,|
|  MsgTag, File)   |                               |  lastRel, base)  |
+------------------+                               +------------------+
         |                                                   |
         +-------------------------+-------------------------+
                                   |
                                   v
                         +-------------------+
                         |   VersionResult   |
                         |  (nextVersion)    |
                         +-------------------+
```

### 2.2 Data Schema Contracts

#### Entity: `Version`
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "raw_string": { "type": "string", "example": "1.2.3-rc.1+bld.103.1" },
    "major": { "type": "integer", "minimum": 0 },
    "minor": { "type": "integer", "minimum": 0 },
    "patch": { "type": "integer", "minimum": 0 },
    "prerelease": {
      "type": "object",
      "properties": {
        "identifier": { "type": "string", "enum": ["dev", "rc", "hf"] },
        "number": { "type": "integer", "minimum": 0 }
      }
    },
    "build_metadata": {
      "type": "object",
      "properties": {
        "identifier": { "type": "string" },
        "run_number": { "type": "integer" },
        "run_attempt": { "type": "integer" }
      }
    }
  },
  "required": ["raw_string", "major", "minor", "patch"]
}
```

#### Entity: `ArtifactHistory`
```json
{
  "type": "object",
  "properties": {
    "last_dev_version": { "type": "string", "nullable": true },
    "last_rc_version": { "type": "string", "nullable": true },
    "last_release_version": { "type": "string", "nullable": true },
    "last_base_version": { "type": "string", "nullable": true },
    "is_initial_version": { "type": "boolean", "default": false }
  }
}
```

---

### 2.3 SemVer 2.0.0 Comparison & Precedence Algebra
When comparing two version objects $V_A$ and $V_B$ to establish "highest existing version":

1. **Core Part Comparison**: Compare $MAJOR$, $MINOR$, $PATCH$ numerically in order:
   - If $V_A.major \neq V_B.major$, return $\text{max}(V_A.major, V_B.major)$.
   - If $V_A.minor \neq V_B.minor$, return $\text{max}(V_A.minor, V_B.minor)$.
   - If $V_A.patch \neq V_B.patch$, return $\text{max}(V_A.patch, V_B.patch)$.

2. **Pre-Release vs Release Precedence**:
   - A normal release version ($1.2.0$) has **higher precedence** than a pre-release version ($1.2.0-rc.1$) with identical $MAJOR.MINOR.PATCH$:
   $$\text{"1.2.0"} > \text{"1.2.0-rc.5"} > \text{"1.2.0-dev.12"}$$

3. **Numeric Pre-Release Comparison**:
   - Compare pre-release numeric suffixes as integers, **not as raw strings**:
   $$\text{"1.2.0-rc.10"} > \text{"1.2.0-rc.9"}$$

4. **Build Metadata Ignored in Precedence**:
   - Build metadata (`+bld.103.1`) MUST BE IGNORED when determining version precedence:
   $$\text{"1.2.0-rc.1+bld.103.1"} \equiv \text{"1.2.0-rc.1+bld.104.1"}$$

---

### 2.4 Finite State Machine (FSM) Diagram

```
    [ UNINITIALIZED ]
            |
            v
  ( Query Registries )
            |
            +-----------------------> [ INITIAL_VERSION_STATE ]
            |                         ( Set is_initial = true, default 1.0.0 )
            v
  [ HISTORICAL_STATE_LOADED ]
  ( lastDev, lastRc, lastRel )
            |
            v
  ( Select Base X.Y.Z )
            |
            v
  [ BASE_CORE_SELECTED ]
            |
            +---> ( Core File Rule Enabled? ) ----> [ FILE_OVERRIDE_APPLIED ]
            |                                               |
            +---> ( Auto Core Triggered? ) ------> [ CORE_INCREMENTED ]
            |                                               |
            v                                               v
  [ BASE_CORE_FINALIZED ] <----------------------------------+
            |
            v
  ( Active Branch Scope? )
            |
            +---> ( Branch matches DEV ) --------> [ DEV_PRERELEASE_STATE ]
            |                                      ( Format: X.Y.Z-dev.N )
            |
            +---> ( Branch matches RC ) ---------> [ RC_PRERELEASE_STATE ]
            |                                      ( Format: X.Y.Z-rc.N )
            |
            +---> ( Branch matches Release ) ----> [ FULL_RELEASE_STATE ]
                                                   ( Format: X.Y.Z )
            |
            v
  [ OUTPUT_EXPORTED ]
```

---

### 2.5 Scope Evaluation Truth Table

| Current Branch | Scope Rules Enabled | Feature Flag Active? | Last Dev | Last RC | Last Rel | Trigger Msg Tag | Output Version Result |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| `feature/abc` | `DEV` active | Yes | `1.2.0-dev.2` | `1.2.0-rc.1` | `1.2.0` | None | `1.2.0-dev.3` |
| `feature/abc` | `DEV` + `MINOR` | Yes | `1.2.0-dev.2` | `1.2.0-rc.1` | `1.2.0` | `#minor` | `1.3.0-dev.1` |
| `release/1.2.0`| `RC` active | Yes | `1.2.0-dev.5` | `1.2.0-rc.1` | `1.2.0` | None | `1.2.0-rc.2` |
| `release/1.3.0`| `RC` active | Yes | `1.3.0-dev.10`| `None` | `1.2.0` | None | `1.3.0-rc.1` |
| `main` | `PATCH` active| Yes | `1.2.0-dev.5` | `1.2.0-rc.2` | `1.2.0` | None | `1.2.1` |
| `main` | `MAJOR` active| Yes | `1.2.0-dev.5` | `1.2.0-rc.2` | `1.2.0` | `#major,#major`| `3.0.0` |
| `hotfix/v1.2` | `HOTFIX` active| Yes | `1.2.0-dev.1` | `None` | `1.2.0` | None (`rebase=1.2.0`)| `1.2.0-hf.1` |

---

## 3. Functional Requirements Specification

### 3.1 Category FR-VER: Version Tiers & Calculation Engine

- **FR-VER-1 (SemVer 2.0.0 Parity)**: The engine MUST format calculated versions in compliance with Semantic Versioning 2.0.0 specification (`MAJOR.MINOR.PATCH-PRERELEASE+BUILD`).
- **FR-VER-2 (Base Release Selection)**: The engine MUST compare the highest published `DEV`, `RC`, and `Release` versions to establish the base `MAJOR.MINOR.PATCH` version before applying increments:
  - If `lastRel` == `lastDev` == `lastRc`, base = `lastRel`.
  - If `lastRc` $\ge$ `lastDev`, base = `lastRc` core part.
  - If `lastDev` > `lastRc`, base = `lastDev` core part.
  - Fallback to `lastRel`.
- **FR-VER-3 (Pre-Release Identifier Streams)**:
  - Development builds MUST default to pre-release identifier `-dev.N` (configurable).
  - Release Candidates MUST default to pre-release identifier `-rc.N` (configurable).
  - Hotfix/Rebase builds MUST default to pre-release identifier `-hf.N` (configurable).
- **FR-VER-4 (Pre-Release Counter Progression)**:
  - If the base `X.Y.Z` version changes (e.g., from `1.2.0` to `1.3.0`), the pre-release counter MUST reset to `1` (e.g., `1.3.0-rc.1`).
  - If the base `X.Y.Z` version remains unchanged, the pre-release counter MUST increment by $+1$ (e.g., `1.2.0-rc.2` $\rightarrow$ `1.2.0-rc.3`).
- **FR-VER-5 (Pre-Release Suppression Invariant)**: When an automatic `DEV` or `RC` pre-release increment is active for the current branch, the core `MAJOR`/`MINOR`/`PATCH` auto-increment MUST be suppressed to prevent double-incrementing the base version.
- **FR-VER-6 (Build Metadata Appending)**: If build metadata is enabled, the engine MUST append `+<IDENTIFIER>.<RUN_NUMBER>.<RUN_ATTEMPT>` (e.g., `+bld.103.1`) to the calculated version string.

---

### 3.2 Category FR-REG: Registry Discovery & Historical State Retrieval

- **FR-REG-1 (Artifactory AQL Discovery)**: The engine MUST query JFrog Artifactory using Artifactory Query Language (AQL) to fetch published artifacts matching target repository names and path patterns.
- **FR-REG-2 (AQL Paginated Querying)**:
  - The AQL discovery client MUST execute queries using page-based pagination (`offset` and `limit` set to $500$).
  - The client MUST continue fetching subsequent pages until the result count on a page is $< 500$.
- **FR-REG-3 (Docker Registry Tag Discovery)**: The engine MUST support querying Docker Registry V2 APIs to retrieve image tag lists when Docker image tags are the primary source of version state.
- **FR-REG-4 (Prepend Label Filtering)**: The engine MUST filter retrieved artifact lists using the active Version Prepend Label (e.g., `SERVICE_NAME-1.2.0`) before determining highest versions.
- **FR-REG-5 (Initial Repository Fallback)**: If no previous artifacts exist in remote registries, the engine MUST mark `is_initial_version = true` and initialize from `1.0.0` or configured initial bounds.

---

### 3.3 Category FR-RUL: Rules Engine & Condition Evaluation

- **FR-RUL-1 (Branch Matching)**: Every version scope (`MAJOR`, `MINOR`, `PATCH`, `RC`, `DEV`, `BUILD`, `REPLACEMENT`) MUST support a list of comma-separated target branch patterns (e.g., `main,master`, `release/*`, `feature/*`).
- **FR-RUL-2 (Commit Message Keyword Parsing / Multi-Bump)**:
  - The engine MUST inspect commit messages or PR titles for configured message tags (e.g., `[MAJOR-VERSION]`, `#minor`).
  - The engine MUST count occurrences of message tags. If $K$ matching tags are found, the corresponding version part MUST be incremented by $+K$.
- **FR-RUL-3 (Version File Overrides)**:
  - The engine MUST support reading explicit `MAJOR` or `MINOR` version numbers from repository files (e.g., `app-version.cfg` containing `MAJOR-VERSION=2`).
  - When a file rule is active, the engine MUST override auto-calculated numbers with the explicit file value while ensuring trailing parts (`PATCH`) reset appropriately.

---

### 3.4 Category FR-REP: Source Code & Manifest File Updates

- **FR-REP-1 (Generic Token Substitution)**: The engine MUST support replacing token placeholders formatted as `@@<TOKEN_NAME>@@` in designated text files.
- **FR-REP-2 (Maven POM Updates)**: The engine MUST support updating the version in Maven `pom.xml` files using standard Maven plugin interfaces (`mvn versions:set -DnewVersion=<VER>`).
- **FR-REP-3 (YAML Path Updates)**: The engine MUST support updating specific YAML paths (e.g., `.image.tag`) in YAML configuration manifests using `yq` or equivalent structured YAML parsers.
- **FR-REP-4 (Idempotent Replacement)**: File update operations MUST be fully idempotent and leave no backup files (e.g., `pom.xml.versionsBackup`) in the repository workspace.

---

### 3.5 Category FR-JIR: Issue Tracker Synchronization

- **FR-JIR-1 (Version Creation)**: The engine MUST support creating new JIRA Version objects (`POST /rest/api/2/version`) containing start date, target release date ($+14$ days), and workflow run URL.
- **FR-JIR-2 (Obsolete Version Archiving)**: Upon publishing a fixed release version (`X.Y.Z`), the engine MUST query unreleased JIRA versions and update superseded release candidates to `archived = true`.
- **FR-JIR-3 (Commit Message Key Extraction)**: The engine MUST parse git commit message logs delta between previous release tag and `HEAD` using regex `([A-Z]+-[0-9]+)+` to extract JIRA issue keys.
- **FR-JIR-4 (Issue FixVersion Tagging)**: The engine MUST append the newly calculated version string to the `fixVersions` field of extracted JIRA issue keys (`PUT /rest/api/3/issue/<KEY>`).

---

### 3.6 Category FR-EXP: Pipeline Environment Output & Exports

- **FR-EXP-1 (Step Output Export)**: The engine MUST write calculated version properties (`dev-version`, `rc-version`, `release-version`, `next-version`) to standard pipeline step outputs (`$GITHUB_OUTPUT` or equivalent).
- **FR-EXP-2 (Environment Variable Export)**: The engine MUST export `BUILD_GH_VERSION_NEXT=<VER>` to pipeline runner environment variables (`$GITHUB_ENV` or equivalent).

---

## 4. Non-Functional Requirements (NFRs)

### 4.1 Performance & Scalability (NFR-PERF)
- **NFR-PERF-1 (Execution Latency Budget)**: Total version calculation execution time (excluding external network latency) MUST NOT exceed **2.0 seconds**. Total end-to-end workflow step execution time MUST NOT exceed **8.0 seconds** under nominal network conditions.
- **NFR-PERF-2 (Registry Pagination Scalability)**: The registry discovery client MUST gracefully process repositories containing $> 50,000$ historical artifact entries without running into memory allocation limits (`OOM`) or payload size caps. AQL page size MUST be fixed at $500$ items per request.
- **NFR-PERF-3 (Memory Footprint Ceiling)**: The runtime memory footprint of the core versioning process MUST remain under **64 MB** during peak evaluation.

---

### 4.2 Security & Credential Isolation (NFR-SEC)
- **NFR-SEC-1 (Zero-Disk Persistence of Credentials)**: API tokens, registry passwords, and JIRA user secrets MUST NEVER be written to temporary disk files or committed to workspace logs.
- **NFR-SEC-2 (Log Redaction & Sanitization)**: All debug output streams, HTTP curl logs, and command traces MUST automatically mask sensitive authorization headers (`Authorization: Bearer ***`, `-u user:***`).
- **NFR-SEC-3 (TLS / Transport Security)**: All outbound API communication with artifact registries, Docker endpoints, and JIRA instances MUST use TLS 1.2 or higher over HTTPS.

---

### 4.3 Reliability, Fault Tolerance & Idempotency (NFR-REL)
- **NFR-REL-1 (Fail-Fast Execution on Error)**: If a required configuration file is missing, or an API call to Artifactory/JIRA returns a fatal error status ($401, 403, 500$), the engine MUST log a clear error message with line context and exit immediately with exit code `1`.
- **NFR-REL-2 (Idempotency Guarantee)**: Executing the versioning engine multiple times on the exact same commit without repository state changes MUST produce identical calculated versions and file modifications without causing file corruption.
- **NFR-REL-3 (File Backup Rollback & Clean Workspace)**: If a file replacement operation fails mid-execution (e.g. `mvn versions:set` failure), the engine MUST clean up temporary working artifacts (`pom.xml.versionsBackup`, `*.tmp` files) to prevent repository contamination.

---

### 4.4 Maintainability, Modularity & Portability (NFR-MAINT)
- **NFR-MAINT-1 (Technology-Stack Portability)**: The architecture and data contracts MUST be completely decoupled from shell-specific scripting dialects. The system MUST be re-implementable in compiled languages (Go, Rust), managed languages (TypeScript, Java, Python), or native CI/CD plugins.
- **NFR-MAINT-2 (Strict Interface Separation)**: Modules for **Registry Discovery**, **Decision Calculation**, **File Replacement**, and **Issue Tracker Sync** MUST be isolated behind clean programming interfaces or abstraction layers.
- **NFR-MAINT-3 (100% Test Coverage Requirement)**: The core version calculation decision matrix MUST achieve 100% unit test statement and branch coverage across all combination permutations.

---

### 4.5 Developer Experience & Observability (NFR-UX)
- **NFR-UX-1 (Dry-Run / Unit-Test Execution Mode)**: The engine MUST support a `--dry-run` or `isUnitTest` mode where version calculation occurs entirely in memory and outputs are logged to console without invoking external network mutation APIs or modifying source files.
- **NFR-UX-2 (Configurable Debug Verbosity)**: When `is-debug` flag is enabled, the engine MUST output detailed scope state trees showing active feature flags, target branch regexes, matched commit tags, and intermediate version parts.
- **NFR-UX-3 (Human-Readable Error Classification)**: Error messages MUST be prefixed with standardized severity tags (`[ERROR]`, `[ACTION_CURL_ERROR]`, `[ACTION_RESPONSE_ERROR]`, `[WARNING]`).

---

## 5. Future Enhancements & Architectural Roadmap

### 5.1 Native Conventional Commits v1.0.0 Support
In addition to custom message tags (e.g., `[MAJOR-VERSION]`), future versions of the engine WILL natively parse commit message headers structured per [Conventional Commits v1.0.0](https://www.conventionalcommits.org/):

| Commit Header Pattern | Semantic Version Scope Triggered | Example Commit Message |
| :--- | :--- | :--- |
| `fix(...)` / `fix:` | `PATCH` increment | `fix(auth): fix token refresh memory leak` |
| `feat(...)` / `feat:` | `MINOR` increment | `feat(api): add endpoint for batch order submit` |
| `BREAKING CHANGE:` or `feat!:` | `MAJOR` increment | `feat(db)!: drop legacy v1 schema tables` |

---

### 5.2 Automated Release Notes & Markdown Changelog Engine
Future iterations WILL include an automated changelog generator that executes upon full release publishing (`X.Y.Z`):
- Groups commits between `v<PREVIOUS_RELEASE>` and `v<NEW_RELEASE>` into categories (`🚀 Features`, `🐛 Bug Fixes`, `⚠️ Breaking Changes`, `🧰 Maintenance`).
- Automatically links extracted JIRA keys or GitHub PR numbers to remote issue URLs.
- Updates `CHANGELOG.md` in the workspace or generates a release notes payload for GitHub Releases / GitLab Releases API.

---

### 5.3 Pluggable Artifact Registry Driver Architecture
To avoid hardcoding JFrog Artifactory or Docker V2 APIs, the engine WILL define a pluggable `RegistryDriver` interface:

```go
type RegistryDriver interface {
    GetLatestArtifacts(ctx context.Context, req ArtifactQueryRequest) (*ArtifactHistory, error)
    PublishVersionMetadata(ctx context.Context, version Version) error
}
```

Implementations WILL include:
- `JFrogAQLDriver` (Artifactory Query Language with offset/limit 500)
- `AWSECRDriver` (Amazon Elastic Container Registry)
- `GCPArtifactRegistryDriver` (Google Cloud Artifact Registry)
- `HelmOCIRegistryDriver` (OCI compliant chart registries)

---

### 5.4 Pluggable Issue Tracker Driver Architecture
Abstracts JIRA-specific calls behind a generic `IssueTrackerDriver` interface to seamlessly support GitHub Issues, GitLab Issues, and Azure DevOps Boards:

```go
type IssueTrackerDriver interface {
    CreateReleaseVersion(ctx context.Context, version string, projectKey string) error
    ArchiveObsoleteVersions(ctx context.Context, currentVersion string, projectKey string) error
    TagFixVersion(ctx context.Context, issueKeys []string, version string) error
}
```

---

### 5.5 Monorepo & Multi-Package Workspace Coordination
For large monorepos containing multiple independent microservices or smart contract packages:
- Inspects git diff paths (`git diff HEAD~1 -- packages/package-a`) to selectively trigger version calculation ONLY for modified sub-packages.
- Generates synchronized dependency graph updates when library packages bump major versions.
