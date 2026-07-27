# 01 - Product Vision & Strategic Objectives

## 1. Problem Statement & Operational Pain Points

In high-velocity software engineering organizations managing hundreds of repositories (microservices, smart contracts, SDKs, Helm charts, Docker images), managing version numbers manually or with primitive scripts leads to significant operational friction:

1. **Version Collisions & Merge Conflicts**: Developers manually incrementing `pom.xml`, `package.json`, or `Chart.yaml` in parallel feature branches suffer constant git merge conflicts and broken builds.
2. **Inconsistent Pre-Release Lifecycles**: Lack of standardized pre-release tags (`-dev.N`, `-rc.N`) leads to polluted artifact registries where development builds overwrite release candidate tags.
3. **Traceability Breakdown Between CI/CD & Project Management**: Releases built in CI/CD are disconnected from issue trackers (e.g. JIRA), making it difficult for QA and release managers to identify which tickets are included in a specific build.
4. **Fragile Historical State**: Traditional tools rely on local git tags, which can be wiped, missed during shallow clones (`fetch-depth: 1`), or out of sync with actual published artifacts in remote registries (JFrog Artifactory, Docker Hub, ECR).
5. **Rigid Tooling Coupling**: Custom versioning scripts hardcoded to specific CI platforms (e.g. pure Bash composite GitHub Actions) cannot easily be reused across different runner environments or modernized tech stacks.

---

## 2. Product Value Proposition

The **Automated Semantic Versioning & Release Engine** solves these challenges by providing a **stateless, declarative, registry-aware version calculation engine**.

```
[ Git Commits / PRs ]      +-----------------------------------------+      [ Updated Manifests ]
[ Branch / Tag Context ] -> |  AUTOMATED SEMANTIC VERSIONING &        | ->   [ Artifact Registry Tags ]
[ Controller Config ]      |  RELEASE ENGINE                         | ->   [ JIRA Releases / Tickets]
[ Artifact Registry ]      +-----------------------------------------+      [ Pipeline Exports ]
```

### Key Differentiators
- **Registry-as-State**: Discovers the true "last published version" by querying remote artifact repositories via API (with automatic pagination) rather than relying solely on local git tags.
- **Multi-Tier SemVer Lifecycle**: Natively manages four distinct streams:
  - **Core Releases**: `X.Y.Z`
  - **Release Candidates**: `X.Y.Z-rc.N`
  - **Development Builds**: `X.Y.Z-dev.N`
  - **Hotfixes**: `X.Y.Z-hf.N`
  - **Build Metadata**: `+bld.<run>.<attempt>`
- **Declarative Rule Engine**: Every aspect of version calculation (branch regexes, message keywords, version files, target tokens) is configured via external YAML files.
- **Bi-Directional Issue Sync**: Automatically creates JIRA versions, archives obsolete release candidates, extracts ticket IDs from commit logs, and tags `fixVersions`.

---

## 3. Target Personas & Primary User Scenarios

### 3.1 Target Personas

| Persona | Role | Key Goals & Needs |
| :--- | :--- | :--- |
| **DevOps / Platform Engineer** | CI/CD Infrastructure Owner | Wants a reusable, deterministic versioning engine that works across all microservices without per-repo maintenance. |
| **Software Developer** | Microservice / Smart Contract Author | Wants automated versioning on pull requests without manual file edits or git tag friction. |
| **Release Manager / QA Lead** | Release Orchestrator | Requires clear traceability showing which JIRA tickets and commits are deployed in each candidate build. |

---

### 3.2 Primary User Scenarios

#### Scenario A: Developer Feature Branch PR
- **User Story**: As a Developer pushing commits to a `feature/JIRA-101` branch, I want the pipeline to automatically calculate a unique `-dev.N` version and update my deployment files so that I can publish development images without polluting release tags.
- **System Behavior**:
  1. Engine detects branch `feature/JIRA-101` matching `DEV` scope.
  2. Queries artifact registry for highest `X.Y.Z-dev.*` artifact.
  3. Increments trailing integer ($N + 1$) to produce `1.2.0-dev.4`.
  4. Replaces version tokens in workspace manifests.

#### Scenario B: Release Candidate Staging
- **User Story**: As a QA Lead merging code into a `release/1.2.0` branch, I want the system to calculate `1.2.0-rc.1`, create a matching Release object in JIRA, and tag referenced tickets so that UAT can begin.
- **System Behavior**:
  1. Engine detects branch `release/1.2.0` matching `RC` scope.
  2. Calculates `1.2.0-rc.1`.
  3. Invokes JIRA API to create release `RC_service-name-1.2.0-rc.1`.
  4. Scans commit log for `PROJ-*` tickets and updates their `fixVersions` field in JIRA.

#### Scenario C: Production Release Merge
- **User Story**: As a Release Manager merging a release branch into `main`, I want a clean `1.2.0` production version created, and all prior `-rc.*` entries in JIRA marked as archived/released.
- **System Behavior**:
  1. Engine detects `main` branch matching `Release` scope.
  2. Calculates `1.2.0`.
  3. Queries JIRA for unreleased candidates matching `1.2.0-rc.*` and updates their state to `archived = true`.

#### Scenario D: Emergency Production Hotfix
- **User Story**: As a Developer patching a critical production vulnerability on `hotfix/v1.2.0`, I want the engine to calculate a dedicated `1.2.0-hf.1` version without disturbing active development on `main`.
- **System Behavior**:
  1. Engine detects hotfix parameter / branch structure.
  2. Queries last base version (`1.2.0-hf.0`).
  3. Increments hotfix patch number to `1.2.0-hf.1`.

---

## 4. Key Performance Indicators (KPIs) & Success Metrics

- **Zero Version Collisions**: 100% elimination of build failures caused by duplicate artifact version publishing.
- **100% Monotonic Compliance**: Zero version regressions across all automated releases.
- **Sub-5-Second Latency Budget**: Version discovery, calculation, and file replacement completed in $< 5$ seconds per workflow execution.
- **Zero-Database Operational Overhead**: 100% stateless execution requiring no internal persistent databases.
