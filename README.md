# gcs-versioning-bot
> Automatically computes the next semantic version for an artifact based on YAML configuration rules, branch context, commit messages, and JFrog/Jira version sources.

## Overview

`gcs-versioning-bot` is the central versioning engine for Partior's CI/CD pipelines. Given YAML importer files (produced by `gcs-yaml-importer`) that describe versioning rules and branch-level configuration, the bot:

1. Queries JFrog Artifactory (or Jira) for the current artifact version.
2. Evaluates branch name, PR labels, commit message tags, and configured rules.
3. Increments the appropriate version component (MAJOR / MINOR / PATCH).
4. Appends the correct pre-release identifier (`-dev.N`, `-rc.N`) or build metadata (`+bld.N`).
5. Outputs the full version string for downstream packaging and promotion steps.

## Usage

```yaml
- name: Compute next version
  id: version-bot
  uses: partior-libs/gcs-versioning-bot@partior-stable
  with:
    artifactory-username: svc-smc-read
    artifactory-password: ${{ secrets.ARTIFACTORY_TOKEN }}
    jira-username: ${{ secrets.JIRA_USERNAME }}
    jira-password: ${{ secrets.JIRA_API_TOKEN }}
    versioning-rules-importer-file: ${{ env.YAML_STD_CI_CONFIG_IMPORTER }}
    branch-packager-rules-importer-file: ${{ env.YAML_CI_BRANCH_CONFIG_IMPORTER }}
    consolidated-commit-msg: ${{ needs.read-config.outputs.delta-commit-msg }}
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `artifactory-username` | Conditional | — | JFrog username. Required when `jfrog-token` is not set |
| `artifactory-password` | Conditional | — | JFrog password. Required when `jfrog-token` is not set |
| `jfrog-token` | Conditional | — | JFrog access token. Required when username/password are not set |
| `artifactory-base-url` | No | `https://partior.jfrog.io/artifactory` | JFrog Artifactory base URL |
| `jira-username` | Conditional | — | Jira username. Required when `version-sources.jira.enabled: true` in YAML config |
| `jira-password` | Conditional | — | Jira API token. Required when `version-sources.jira.enabled: true` |
| `jira-base-url` | No | `https://partior.atlassian.net` | Jira base URL |
| `versioning-rules-importer-file` | **Yes** | — | Importer file from `gcs-yaml-importer` scoped to `.ci` (contains `artifact-base-name` and `artifact-auto-versioning` rules) |
| `branch-packager-rules-importer-file` | **Yes** | — | Importer file from `gcs-yaml-importer` scoped to `.ci.branches.<branch-name>` |
| `consolidated-commit-msg` | No | — | Newline-delimited commit messages from `git log <target>..<source>` — used for message-tag version bump detection |
| `artifact-type` | No | — | Artifact type hint (e.g., `docker`) for type-specific version query logic |
| `branch-name` | No | — | Override detected branch name. Use only for local testing |
| `debug` | No | `false` | Set `true` to enable verbose action logging |

## Outputs

| Output | Description |
|--------|-------------|
| `artifact-version-name` | Computed version string (e.g., `1.0.1`, `1.0.1-dev.1`, `1.0.1-rc.1`) |
| `artifact-full-version-name` | Version with artifact base name prepended (e.g., `my-service-1.0.1-dev.1`) |
| `artifact-old-version` | Previous version before increment (all three types — DEV, RC, REL — in a single string) |

## Version Bump Tags

Include one of these strings in a commit message to force the corresponding bump:

| Tag | Effect |
|-----|--------|
| `MAJOR_GH_CURRENT_MSGTAG` | Bumps the major version component |
| `MINOR_GH_CURRENT_MSGTAG` | Bumps the minor version component |
| `PATCH_GH_CURRENT_MSGTAG` | Bumps the patch version component |

These tags are also stored as files at the repository root for reference.

## YAML Configuration Schema

The bot reads configuration through the two importer files. The full schema is defined in `controller-config-files/projects/default.yml`. Key sections:

```yaml
smc:
  ci:
    artifact-base-name: my-service
    artifact-auto-versioning:
      enabled: true
      initial-release-version: 1.0.0
      version-sources:
        artifactory:
          enabled: true
        jira:
          enabled: false
          project-key: ""
          version-identifier: ""
      major-version:
        enabled: true
        rules:
          message-tag:
            target: MAJOR-VERSION
            enabled: true
      minor-version:
        enabled: true
        rules:
          message-tag:
            target: MINOR-VERSION
            enabled: true
      patch-version:
        enabled: false
      release-candidate-version:
        enabled: true
        identifier: rc
        rules:
          branches:
            target: release
            enabled: true
      development-version:
        enabled: true
        identifier: dev
        rules:
          branches:
            target: develop,feature
            enabled: true
      build-version:
        enabled: false
        identifier: bld
      replacement:
        enabled: false
        maven-pom:
          enabled: false
          target: pom.xml
        yaml-update:
          enabled: false
          target: helm/Chart.yaml
          query-path: .version

    branches:
      default:
        artifact:
          packager:
            enabled: false
      main:
        artifact:
          packager:
            group: my-org
```

## Full Pipeline Example

```yaml
name: CI Pipeline
on:
  push:
    branches: [main, develop, release/*, feature/*]
  pull_request:

env:
  YAML_STD_CI_CONFIG_IMPORTER: std-ci-rules
  YAML_CI_BRANCH_CONFIG_IMPORTER: branch-ci-config

jobs:
  read-config:
    runs-on: ubuntu-latest
    outputs:
      branch-name: ${{ steps.repo.outputs.branch-name }}
      delta-commit-msg: ${{ steps.repo.outputs.delta-commit-msg }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Get repo details
        id: repo
        run: |
          branchName="$(echo ${GITHUB_REF_NAME} | cut -d'/' -f1)"
          commitMessages=''
          if [[ -n "$GITHUB_HEAD_REF" ]]; then
            branchName=$(echo $GITHUB_HEAD_REF | cut -d'/' -f1)
            git fetch --all
            commitMessages=$(git log remotes/origin/${GITHUB_BASE_REF}..HEAD --pretty=format:"%s")
          fi
          echo "branch-name=${branchName}" >> $GITHUB_OUTPUT
          echo "delta-commit-msg=${commitMessages}" >> $GITHUB_OUTPUT

      - name: Generate branch config importer
        uses: partior-libs/gcs-yaml-importer@partior-stable
        with:
          yaml-file: controller-config-files/projects/default.yml
          query-path: .smc.ci.branches.${{ steps.repo.outputs.branch-name }}
          output-file: ${{ env.YAML_CI_BRANCH_CONFIG_IMPORTER }}
          yaml-file-for-default: controller-config-files/projects/default.yml
          query-path-for-default: .smc.ci.branches.default
          upload: true

      - name: Generate std rules importer
        uses: partior-libs/gcs-yaml-importer@partior-stable
        with:
          yaml-file: controller-config-files/projects/default.yml
          query-path: .smc.ci
          output-file: ${{ env.YAML_STD_CI_CONFIG_IMPORTER }}
          upload: true

  versioning:
    needs: read-config
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.bot.outputs.artifact-version-name }}
      full-version: ${{ steps.bot.outputs.artifact-full-version-name }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: ${{ env.YAML_CI_BRANCH_CONFIG_IMPORTER }}
      - uses: actions/download-artifact@v4
        with:
          name: ${{ env.YAML_STD_CI_CONFIG_IMPORTER }}

      - name: Run versioning bot
        id: bot
        uses: partior-libs/gcs-versioning-bot@partior-stable
        with:
          artifactory-username: svc-smc-read
          artifactory-password: ${{ secrets.ARTIFACTORY_TOKEN }}
          versioning-rules-importer-file: ${{ env.YAML_STD_CI_CONFIG_IMPORTER }}
          branch-packager-rules-importer-file: ${{ env.YAML_CI_BRANCH_CONFIG_IMPORTER }}
          consolidated-commit-msg: ${{ needs.read-config.outputs.delta-commit-msg }}

      - name: Print version
        run: |
          echo "Version: ${{ steps.bot.outputs.artifact-version-name }}"
          echo "Full:    ${{ steps.bot.outputs.artifact-full-version-name }}"
```

## Prerequisites

- **JFrog Artifactory** credentials with read access to the artifact repository (to look up the previous version).
- **Jira** credentials if `version-sources.jira.enabled: true` in the YAML config.
- Importer files generated by `gcs-yaml-importer@partior-stable` and either passed directly or downloaded as artifacts.
- The YAML config file (`controller-config-files/projects/default.yml` or equivalent) must be present in the triggering repository.

## Contributing

```
git commit -m "<TICKET_NUMBER> <COMMIT_MESSAGE>"
```

Example: `git commit -m "PLAT-999 Support build-version increment for feature branches"`

## License

See [LICENSE.md](LICENSE.md)
