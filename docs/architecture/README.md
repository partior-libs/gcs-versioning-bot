# GCS Versioning Bot — Architecture Documentation Suite

Welcome to the comprehensive architecture documentation for **`gcs-versioning-bot`**. 

This documentation suite provides an exhaustive, production-grade, reconstruction-level technical specification of the `gcs-versioning-bot` system. It covers every component, script, configuration variable, state transition, REST/AQL integration API, versioning algorithm, edge-case rule, and unit testing mechanism in complete detail.

The primary objective of this documentation suite is to enable a software engineer or DevOps architect to **understand, maintain, extend, or fully reconstruct** the application from scratch in any programming language or environment without requiring access to the original source code.

---

## 📚 Table of Contents & Document Index

| Document | Title | Description |
| :--- | :--- | :--- |
| **[01-system-overview.md](file:///home/user/ws/partior-libs/gcs-versioning-bot/docs/architecture/01-system-overview.md)** | System Overview & Core Mission | High-level mission, core objectives, SemVer 2.0 specs, version tiers (DEV, RC, Release, Rebase/Hotfix), and system terminology. |
| **[02-architecture-and-pipeline-flow.md](file:///home/user/ws/partior-libs/gcs-versioning-bot/docs/architecture/02-architecture-and-pipeline-flow.md)** | Architecture & Pipeline Execution Flow | Component topology, GitHub composite action orchestration flow, Mermaid sequence diagrams for PRs, direct pushes, trunk versioning, and hotfix branches. |
| **[03-versioning-rules-and-decision-engine.md](file:///home/user/ws/partior-libs/gcs-versioning-bot/docs/architecture/03-versioning-rules-and-decision-engine.md)** | Versioning Rules & Decision Engine | Complete mathematical/logical decision engine, core vs pre-release state machine, message tag parsing, file-driven versioning, and reset logic. |
| **[04-script-and-function-reference.md](file:///home/user/ws/partior-libs/gcs-versioning-bot/docs/architecture/04-script-and-function-reference.md)** | Script & Function Specification Reference | Exhaustive line-by-line function specifications for all scripts in `scripts/`, including arguments, return values, stdout/stderr channels, side effects, and error codes. |
| **[05-configuration-and-state-schema.md](file:///home/user/ws/partior-libs/gcs-versioning-bot/docs/architecture/05-configuration-and-state-schema.md)** | Configuration, State & File Schemas | Data dictionary for `config/general.ini`, YAML configuration schema (`smc.ci`), environment variable mappings, and temporary state file directory. |
| **[06-integrations-and-external-systems.md](file:///home/user/ws/partior-libs/gcs-versioning-bot/docs/architecture/06-integrations-and-external-systems.md)** | External Integrations & API Specifications | Deep-dive REST/AQL protocol specifications for JFrog Artifactory (AQL pagination), Docker Registry, JIRA REST API v2/v3, and GitHub Actions runtime contract. |
| **[07-testing-framework-and-validation.md](file:///home/user/ws/partior-libs/gcs-versioning-bot/docs/architecture/07-testing-framework-and-validation.md)** | Testing Framework & Validation Suite | Specification of `unittest-versioning-bot.sh`, `unittest-get-latest-version.sh`, `unit-test-spec.yml` spec format, test matrices, and mock state generation. |
| **[08-reconstruction-and-implementation-guide.md](file:///home/user/ws/partior-libs/gcs-versioning-bot/docs/architecture/08-reconstruction-and-implementation-guide.md)** | Reconstruction & Implementation Blueprint | Step-by-step re-implementation guide, core algorithm pseudocode, state transition matrix, and strict verification checklist. |

---

## 🏛️ System Core Architecture Summary

```
                      +------------------------------------------+
                      |         GitHub Actions Workflow          |
                      +------------------------------------------+
                                           |
                                           v
                      +------------------------------------------+
                      |        gcs-yaml-importer (Action)        |
                      |  Converts controller YAML to $GITHUB_ENV  |
                      +------------------------------------------+
                                           |
                                           v
                      +------------------------------------------+
                      |         inject_config_vars.sh            |
                      | Validates and maps scope flags & rules   |
                      +------------------------------------------+
                                           |
                                           v
                      +------------------------------------------+
                      |          get_latest_version.sh           |
                      |  Queries Artifactory (AQL) / JIRA / Docker|
                      |  Generates: artifact_last_*.txt files    |
                      +------------------------------------------+
                                           |
                                           v
                      +------------------------------------------+
                      |       generate_package_version.sh        |
                      |   Core SemVer 2.0 Calculation Engine    |
                      |  Generates: artifact_next_version.txt    |
                      +------------------------------------------+
                                           |
            +------------------------------+------------------------------+
            |                              |                              |
            v                              v                              v
+-----------------------+     +-----------------------+     +-----------------------+
|  File Replacements    |     |  JIRA Synchronization |     |    Export Outputs     |
| - sed file tokens     |     | - store_version_in_.. |     | - GITHUB_OUTPUT       |
| - mvn versions:set    |     | - tag_fixversion_in_..|     | - GITHUB_ENV          |
| - yq yaml paths       |     +-----------------------+     +-----------------------+
+-----------------------+
```

---

## 🔍 Key Architectural Principles

1. **Deterministic Calculation**: Version calculation is purely deterministic based on repository history (Artifactory/JIRA/Docker state), controller flags, commit message tags, and current branch context.
2. **Stateless Workflow Execution**: The composite action maintains no persistent database; state is entirely externalized in artifact repositories (JFrog Artifactory), issue trackers (JIRA), and local workspace temporary files during run execution.
3. **Flexible Scope Modularization**: Rules for `MAJOR`, `MINOR`, `PATCH`, `RC`, `DEV`, `BUILD`, and `REPLACEMENT` operate as independent, composable feature scopes controlled via standardized environment flags.
4. **Resilient Artifactory Querying**: Historical artifact discovery uses Artifactory Query Language (AQL) with 500-item page-based pagination to reliably handle repositories with high artifact churn and large file counts.
5. **Fail-Safe Replacements**: File replacement mechanics (e.g. `mvn versions:set`) include automatic error traps and status validation to prevent partial or corrupted version commits.

---

## 📁 Repository Structure Overview

- **`action.yml`**: GitHub Composite Action entry point defining input parameters, step executions, and output mappings.
- **`config/general.ini`**: Sourced mapping file converting YAML configuration keys into standardized bash scope variable names.
- **`scripts/`**: Core shell script modules implementing configuration injection, prerequisite validation, historical version retrieval, semantic version calculation, file token substitution, and JIRA synchronization.
- **`controller-config-files/projects/`**: Standard YAML configuration presets representing enterprise operational modes (e.g. Maven, Docker, Generic token replacement, Trunk versioning).
- **`test-files/`**: Comprehensive test suites containing mocked versions, test specifications (`unit-test-spec.yml`), and sample project structures.
- **`unittest-versioning-bot.sh`**: Automated runner for executing the full test matrix against all controller configuration presets.
