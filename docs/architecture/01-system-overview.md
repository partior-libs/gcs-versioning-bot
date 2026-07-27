# 01 - System Overview & Core Mission

## 1. Executive Summary & Purpose

The **GCS Versioning Bot (`gcs-versioning-bot`)** is an enterprise-grade, composite GitHub Action and shell-based calculation engine designed to automate semantic versioning and release lifecycle management for software artifacts across multi-repository CI/CD pipelines.

In enterprise software engineering—particularly across decentralized microservice architectures, blockchain/DLT networks (e.g., Quorum/GoQuorum, Smart Contracts), Java/Maven libraries, Helm charts, and Dockerized microservices—maintaining consistent, automated, and conflict-free semantic versions across pull requests, release branches, feature branches, and hotfix workflows is critical.

`gcs-versioning-bot` acts as the single source of truth for version calculation. It inspects:
1. **Remote Artifact Repositories**: Queries JFrog Artifactory (via AQL), Docker Registries, or JIRA Boards to determine the last published versions across all release tiers.
2. **Git Branch & Trigger Context**: Inspects current branch names (`main`, `master`, `develop`, `release/*`, `hotfix/*`, `feature/*`), labels, git tags, and commit message tags (e.g., `[MAJOR-VERSION]`, `[MINOR-VERSION]`, `[PATCH-VERSION]`).
3. **YAML Controller Configurations**: Parses declarative pipeline configurations (`smc.ci` hierarchy) imported via `gcs-yaml-importer`.
4. **Local Version Files**: Reads version bounds or explicit release versions from project files (`MAJOR-VERSION=x`, `MINOR-VERSION=y`, `pom.xml`, `app-version.cfg`).

It then dynamically computes the next logical semantic version, writes the calculated state to temporary workspace files, updates specified source/configuration files (`pom.xml`, YAML files, tokenized manifests), creates/archives release entries in JIRA, and exports the result to GitHub Action outputs (`$GITHUB_OUTPUT`) and environment variables (`$GITHUB_ENV`).

---

## 2. Key Objectives & Architectural Goals

- **Strict SemVer 2.0.0 Parity**: Full compliance with Semantic Versioning 2.0.0 (`MAJOR.MINOR.PATCH-PRERELEASE+BUILD`).
- **Zero-Database / Stateless Execution**: Operates purely statelessly within transient GitHub Actions runner environments. State is externalized to artifact registries (Artifactory), issue trackers (JIRA), and git history.
- **Support for Multi-Language & Multi-Format Artifacts**: Handles Docker images, Helm files, Maven POMs, Go modules, generic tarballs, and raw text file replacements.
- **Dynamic Pre-Release Lifecycle Management**: Computes separate streams for Development (`-dev.N`), Release Candidate (`-rc.N`), Base Hotfix (`-hf.N`), and Full Release (`X.Y.Z`) versions.
- **Robustness Against Artifact Churn**: Uses paginated AQL queries (500 items per batch) to retrieve artifact history without running into memory caps or payload cutoffs.
- **Declarative Rule Configuration**: Every aspect of version calculation (branches, tags, message tags, file targets, replacement rules) is configurable via external YAML controller files without modifying pipeline scripts.

---

## 3. Semantic Versioning Specification & Version Tiers

`gcs-versioning-bot` divides the version lifecycle into five distinct tiers/scopes:

```
                          [ FULL SEMANTIC VERSION ]
                        MAJOR . MINOR . PATCH - PRERELEASE + BUILD
                        |___ CORE RELEASE ___|  |________|  |___|
                                   |                 |        |
                                 1.2.3            rc.1 / dev.4  bld.103.1
```

### 3.1 Core Release Version (`MAJOR.MINOR.PATCH`)
- **MAJOR**: Incremented when incompatible API changes or breaking contract updates are introduced.
- **MINOR**: Incremented when functionality is added in a backward-compatible manner.
- **PATCH**: Incremented when backward-compatible bug fixes or minor patches are applied.
- **Format**: Three non-negative integers separated by dots (e.g., `1.2.3`). No leading zeros permitted unless zero itself.

### 3.2 Development Version (`DEV`)
- **Purpose**: Assigned to feature branches, integration builds, or daily development commits before release candidate staging.
- **Format**: `MAJOR.MINOR.PATCH-dev.N` (e.g., `1.2.3-dev.1`, `2.0.0-dev.15`).
- **Identifier**: Configurable via `DEV_V_IDENTIFIER` (default: `dev`).

### 3.3 Release Candidate Version (`RC`)
- **Purpose**: Assigned to release branches (`release/*`, `rc/*`) or pre-release tags during QA, security scanning, and user acceptance testing prior to production release.
- **Format**: `MAJOR.MINOR.PATCH-rc.N` (e.g., `1.2.3-rc.1`, `1.2.3-rc.2`).
- **Identifier**: Configurable via `RC_V_IDENTIFIER` (default: `rc`).

### 3.4 Hotfix / Rebase Version (`BASE` / `HF`)
- **Purpose**: Assigned to emergency hotfix branches branched off historic tags or production releases.
- **Format**: `MAJOR.MINOR.PATCH-hf.N` or `MAJOR.MINOR.PATCH-hf.N.M` (e.g., `1.2.3-hf.1`).
- **Identifier**: Configurable via `REBASE_V_IDENTIFIER` (default: `hf`).

### 3.5 Build Metadata (`BUILD`)
- **Purpose**: Appends CI job execution metadata for build traceability without affecting SemVer precedence order.
- **Format**: `+<BUILD_IDENTIFIER>.<RUN_NUMBER>.<RUN_ATTEMPT>` (e.g., `1.2.3-rc.1+bld.103.1`).
- **Identifier**: Configurable via `BUILD_V_IDENTIFIER` (default: `bld`).

---

## 4. Key Terminology & Domain Concepts

| Term | Definition |
| :--- | :--- |
| **Composite GitHub Action** | A GitHub Action that groups multiple workflow steps (shell scripts, commands) inside a single `action.yml` file without compiling a separate Docker container or JavaScript bundle. |
| **`gcs-yaml-importer`** | A partner GitHub Action (`partior-libs/gcs-yaml-importer`) used to parse hierarchical YAML controller files into raw environment key-value pairs written to `$GITHUB_ENV`. |
| **Controller Configuration File** | A YAML file residing in `controller-config-files/projects/` or a target repository defining versioning flags, branch patterns, file tokens, and JIRA project keys. |
| **`general.ini`** | A central shell configuration file in `config/general.ini` that maps raw YAML environment variable names (e.g. `artifact_auto_versioning__major_version__enabled`) to standardized shell scope variables (e.g. `MAJOR_V_RULES_ENABLED`). |
| **Degaussing** | The internal process of nullifying/neutralizing feature scope variables when their controlling flags are set to `false`. Prevents stale environment variables from triggering unwanted version bumps. |
| **Message Tag (`MSGTAG`)** | A keyword embedded within commit messages or pull request titles (e.g. `[MAJOR-VERSION]`, `#major`) that triggers automatic core version increments. |
| **AQL (Artifactory Query Language)** | A JSON-based query language used to search JFrog Artifactory for historical build artifacts and images by repository name, artifact name pattern, and path. |
| **Version File Override** | A mechanism allowing a file in the project repository (e.g. `app-version.cfg` containing `MAJOR-VERSION=2`) to explicitly set the base Major or Minor version, overriding auto-increment logic. |
| **FixVersion Tagging** | The automated process of updating JIRA issues referenced in git commit logs (e.g. `PROJ-1234`) with the newly created release version name in JIRA. |

---

## 5. System Invariants & Guarantees

1. **Monotonic Progression**: Calculated versions for a given branch stream will monotonically increase. A calculated version will never regress below the highest previously published version found in Artifactory/JIRA/Docker unless explicitly reset by controller configuration.
2. **Pre-Release Non-Bumping Invariant**: When a pre-release version (`dev.N` or `rc.N`) is actively incremented, the underlying Core Release Version (`X.Y.Z`) is frozen at the target release candidate number and is **not** simultaneously incremented.
3. **Immutability of Released Versions**: Full release versions (`X.Y.Z`) once published are considered immutable; subsequent commits on release branches increment the pre-release sequence (`rc.N+1`) or prepare the next patch version (`X.Y.Z+1`).
4. **Idempotent File Replacement**: Replacing version tokens in source files (e.g., `sed` token replacement or `mvn versions:set`) produces predictable, reproducible file states without leaving orphaned backup files or incomplete string fragments.
