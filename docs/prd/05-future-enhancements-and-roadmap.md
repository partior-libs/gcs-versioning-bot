# 05 - Future Enhancements & Product Roadmap

This document outlines the product roadmap and architectural vision for future iterations of the Greenfield Automated Versioning & Release Engine beyond 100% baseline feature parity.

---

## 1. Product Roadmap Horizons

```
[ HORIZON 1: BASELINE PARITY & CORE MODERNIZATION ]
├── Re-implement core engine in compiled/type-safe language (Go/TypeScript)
├── Sub-second execution latency & 100% stateless execution
└── Full unit test spec suite compatibility

[ HORIZON 2: SEMANTIC CONVENTIONAL COMMITS & AUTO-CHANGELOG ]
├── Native Conventional Commits v1.0.0 parser
├── Automated Markdown Changelog Generator
└── Slack / Teams / Discord Webhook Notifications

[ HORIZON 3: MULTI-REGISTRY DRIVERS & WORKSPACE ORCHESTRATION ]
├── Pluggable Registry Drivers (AWS ECR, GCP Artifact Registry, S3, OCI)
├── Pluggable Issue Trackers (GitHub Issues, GitLab Issues, Azure Boards)
└── Monorepo / Polyrepo Workspace Coordination Engine
```

---

## 2. Next-Generation Capability Specifications

### 2.1 Native Conventional Commits v1.0.0 Specification
In addition to custom message tags (e.g. `[MAJOR-VERSION]`), future versions of the engine WILL natively parse commit message headers structured per [Conventional Commits v1.0.0](https://www.conventionalcommits.org/):

| Commit Header Pattern | Semantic Version Scope Triggered | Example Commit Message |
| :--- | :--- | :--- |
| `fix(...)` / `fix:` | `PATCH` increment | `fix(auth): fix token refresh memory leak` |
| `feat(...)` / `feat:` | `MINOR` increment | `feat(api): add endpoint for batch order submit` |
| `BREAKING CHANGE:` or `feat!:` | `MAJOR` increment | `feat(db)!: drop legacy v1 schema tables` |

---

### 2.2 Automated Release Notes & Markdown Changelog Engine
Future iterations WILL include an automated changelog generator that executes upon full release publishing (`X.Y.Z`):

- **Capabilities**:
  - Groups commits between `v<PREVIOUS_RELEASE>` and `v<NEW_RELEASE>` into categories (`🚀 Features`, `🐛 Bug Fixes`, `⚠️ Breaking Changes`, `🧰 Maintenance`).
  - Automatically links extracted JIRA keys or GitHub PR numbers to remote issue URLs.
  - Updates `CHANGELOG.md` in the workspace or generates a release notes payload for GitHub Releases / GitLab Releases API.

---

### 2.3 Pluggable Artifact Registry Driver Architecture
To avoid hardcoding JFrog Artifactory or Docker V2 APIs, the engine WILL define a pluggable `RegistryDriver` interface:

```
                  +--------------------------------+
                  |  RegistryDriver (Interface)    |
                  +--------------------------------+
                                  |
    +-----------------+-----------+-----------+-----------------+
    |                 |                       |                 |
    v                 v                       v                 v
+-----------+   +-----------+           +-----------+     +-----------+
| JFrog AQL |   | AWS ECR   |           | GCP CAR   |     | Helm OCI  |
| Driver    |   | Driver    |           | Driver    |     | Registry  |
+-----------+   +-----------+           +-----------+     +-----------+
```

```go
type RegistryDriver interface {
    GetLatestArtifacts(ctx context.Context, req ArtifactQueryRequest) (*ArtifactHistory, error)
    PublishVersionMetadata(ctx context.Context, version Version) error
}
```

---

### 2.4 Pluggable Issue Tracker Driver Architecture
Abstracts JIRA-specific calls behind a generic `IssueTrackerDriver` interface to seamlessly support GitHub Issues, GitLab Issues, and Azure DevOps Boards:

```go
type IssueTrackerDriver interface {
    CreateReleaseVersion(ctx context.Context, version string, projectKey string) error
    ArchiveObsoleteVersions(ctx context.Context, currentVersion string, projectKey string) error
    TagFixVersion(ctx context.Context, issueKeys []string, version string) error
}
```

---

### 2.5 Monorepo & Multi-Package Workspace Coordination
For large monorepos containing multiple independent microservices or smart contract packages:

- **Capabilities**:
  - Inspects git diff paths (`git diff HEAD~1 -- packages/package-a`) to selectively trigger version calculation ONLY for modified sub-packages.
  - Generates synchronized dependency graph updates when library packages bump major versions.
