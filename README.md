# Partior Artifact Versioning Bot (partior-stable)
This action generate the next incremented semantic version of artifact with the input parameters from Jfrog artifact path and YAML configuration schema from [CICD controller](https://github.com/partior-quorum/controller-smc-pipelines).

# Usage
<!-- start usage -->
```yaml
- uses: partior-libs/gcs-versioning-bot@partior-stable
  with:
    # Jfrog username to query last artifact version
    # Mandatory: Yes
    artifactory-username: ''

    # Jfrog password to query last artifact version
    # Mandatory: Yes
    artifactory-username: ''

    # Artifactory base URL for query endpoint
    # Mandatory: No
    # Default: ${{ github.token }}
    artifactory-base-url: 'https://partior.jfrog.io/artifactory'


    # Branch name of the triggered repository. Use this only for testing purpose. Leave empty for action to retrieve branch name correctly
    # Example: feature, release, main, bugfix
    # Mandatory: No
    branch-name: ''

    # This is the file generated from yaml importer for  versioning section "<parent>.artifact-base-name" and "<parent>.artifact-auto-versioning"
    # Mandatory: Yes
    versioning-rules-importer-file: ''

    # This is the file generated from yaml importer for branches section "<parent>.branches.<branch-name>"
    # Mandatory: Yes
    branch-packager-rules-importer-file: ''

    # This is consolidated commit message using command 'git log <target-merge-branch>..<source-branch> --pretty=format:"%s"'
    # Mandatory: No (If not used for PR), Yes (if trigger event require info from commit message)
    consolidated-commit-msg: ''

    # Use to display more logs during action execution
    # Mandatory: No
    # Default: false
    debug: ''
```
<!-- end usage -->

# Sample YAML input for CICD Controller
```yaml
---
smc:
  ci:
    artifact-base-name: default-artifact-name
    artifact-auto-versioning:
      enabled: false
      major-version:
        enabled: true
        rules:
          branches: 
            target: release
            enabled: true
          labels: 
            target: MAJOR-VERSION 
            enabled: true
          tag: 
            target: MAJOR-VERSION 
            enabled: true
          message-tag: 
            target: MAJOR-VERSION 
            enabled: true
          file:
            enabled: false
            target: ./app-version.cfg
            key: MAJOR-VERSION
      minor-version:
        enabled: true
        rules:
          branches: 
            target: release
            enabled: true
          tag: 
            target: MINOR-VERSION 
            enabled: true
          message-tag: 
            target: MINOR-VERSION 
            enabled: true
          labels: 
            target: MINOR-VERSION  
            enabled: true
          file:
            enabled: false
            target: ./app-version.cfg
            key: MINOR-VERSION
      patch-version:
        enabled: true
        rules:
          branches: 
            target: release
            enabled: true
          tag: 
            target: PATCH-VERSION 
            enabled: true
          message-tag: 
            target: PATCH-VERSION 
            enabled: true
          labels: 
            target: PATCH-VERSION
            enabled: true
          file:
            enabled: false
            target: ./app-version.cfg
            key: PATCH-VERSION
      release-candidate-version:
        enabled: true
        identifier: rc
        rules:
          branches: 
            target: release
            enabled: true
          tag: 
            target: RC-VERSION
            enabled: false
          file:
            enabled: false
            target: ./app-version.cfg
            key: RC-VERSION
      development-version:
        enabled: true
        identifier: dev
        rules:
          branches: 
            target: develop,feature
            enabled: true
          tag: 
            target: DEV-VERSION
            enabled: false
          file:
            enabled: false
            target: ./app-version.cfg
            key: DEV-VERSION
      build-version:
        enabled: false
        identifier: bld
        rules:
          branches: 
            target: develop,feature
            enabled: true
      replacement:
        enabled: false
        file-token: 
          enabled: false
          target: pom.xml
          token: '@@VERSION_BOT_TOKEN@@'
        maven-pom: 
          enabled: false
          target: pom.xml

    branches:
      default:
        node-version: 14
        truffle-compile:
          enabled: true
        solc-compile:
          enabled: false
        gitleaks:
          enabled: true
          scan-depth: 2
        codacy:
          upload-coverage:
            enabled: true
            coverage-file: ./coverage/lcov.info
          spotbugs:
            enabled: false
        unit-test:
          enabled: true
        artifact:
          packager:
            enabled: false
            group: partior
            artifactory-username: svc-smc-read
            artifactory-dev-repo: smc-generic-dev
            artifactory-release-repo: smc-generic-release
            folder-list: build,config,migrations,scripts
            file-list: deployment.conf,truffle-config.js,deploy.sh,compile.sh,package.json,package-lock.json
      main:
        artifact:
          packager:
            group: antztest
      feature:
        artifact:
          packager:
            group: antztest
      release:
        artifact:
          packager:
            group: antztest
      hotfix:
        artifact:
          packager:
            group: antztest
      bugfix:
        artifact:
          packager:
            group: antztest
      develop:
        artifact:
          packager:
            group: antztest
```


# Sample GitHub Action Workflow
```yaml
name: Versioning sample
on:
  pull_request:
  pull_request_review:
    types: [submitted]
  push:
    branches: [ master, main ]

env:
  YAML_STD_CI_CONFIG_IMPORTER: std_rule
  YAML_CI_BRANCH_CONFIG_IMPORTER: yaml_ci_branch_importer

jobs:
  read-config:
    runs-on: ubuntu-latest
    outputs:
      branch-name: ${{ steps.get-repo.outputs.branch-name }}
      pr-exist: ${{ steps.get-repo.outputs.is-PR }}
      pr-target-branch: ${{ steps.get-repo.outputs.pr-target-branch }}
      repo-name: ${{ steps.get-repo.outputs.name }}
      source-branch: ${{ steps.get-repo.outputs.source-branch }}
      delta-commit-msg: ${{ steps.get-repo.outputs.delta-commit-msg }}
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0

      - name: Get repo details
        id: get-repo
        run: |
          branchName="$(echo ${GITHUB_REF_NAME} | cut -d"/" -f1)"
          sourceBranch=${GITHUB_REF_NAME}
          prTargetBranch=''
          isPR=false
          commitMessages=''
          if [[ ! -z "$GITHUB_HEAD_REF" ]]; then
            branchName=$(echo $GITHUB_HEAD_REF | cut -d"/" -f1)
            sourceBranch=${GITHUB_HEAD_REF}
            isPR=true
            prTargetBranch=remotes/origin/${GITHUB_BASE_REF}
            git fetch --all
            git branch --all
            echo git log $prTargetBranch..HEAD
            commitMessages=$(git log $prTargetBranch..HEAD --pretty=format:"%s")
          fi
          
          echo ::set-output name=branch-name::${branchName}
          echo ::set-output name=is-PR::${isPR}
          echo ::set-output name=pr-target-branch::${prTargetBranch}
          echo ::set-output name=name::$(echo ${GITHUB_REPOSITORY}  | cut -d"/" -f2)
          echo ::set-output name=delta-commit-msg::${commitMessages}
          echo ::set-output name=source-branch::${sourceBranch}

      - name: Generate CI branch importer
        uses: partior-libs/gcs-yaml-importer@partior-stable
        with:
          yaml-file: controller-config-files/projects/default.yml
          query-path: .smc.ci.branches.${{ steps.get-repo.outputs.branch-name }}
          output-file: ${{ env.YAML_CI_BRANCH_CONFIG_IMPORTER }}
          yaml-file-for-default: controller-config-files/projects/default.yml
          query-path-for-default: .smc.ci.branches.default
          upload: true

  read-std-config:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Generate CI branch importer
        uses: partior-libs/gcs-yaml-importer@partior-stable
        with:
          yaml-file: controller-config-files/projects/enable-std-rules.yml
          query-path: .smc.ci
          output-file: ${{ env.YAML_STD_CI_CONFIG_IMPORTER }}
          yaml-file-for-default: controller-config-files/projects/default.yml
          query-path-for-default: .smc.ci
          upload: true

  trigger-example:
    needs: [ read-config, read-std-config ]
    runs-on: ubuntu-latest
    env:
      BRANCH_NAME: ${{ needs.read-config.outputs.branch-name }}
      REPO_NAME: ${{ needs.read-config.outputs.repo-name }}
      ALL_DELTA_COMMIT_MSG: ${{ needs.read-config.outputs.delta-commit-msg }}
      SOURCE_BRANCH: ${{ needs.read-config.outputs.source-branch }}
    steps:
      - uses: actions/checkout@v2
      - uses: actions/download-artifact@v2
        with:
          name: ${{ env.YAML_CI_BRANCH_CONFIG_IMPORTER }}

      - uses: actions/download-artifact@v2
        with:
          name: ${{ env.YAML_STD_CI_CONFIG_IMPORTER }}

      - name: View Version File - Before
        run: |
          echo [INFO] Viewing versioning file - Pre Activity
          cat ./test-files/sample-version-file.xml

      - name: View Maven POM File - Before
        run: |
          echo [INFO] Viewing Maven POM file - Pre Activity
          cat ./test-files/sample-pom-file.xml

      - name: Start versioning bot
        id: version-bot
        uses: partior-libs/gcs-versioning-bot@main
        with:
          artifactory-username: svc-smc-read
          artifactory-password: ${{ secrets.ARTIFACTORY_NPM_TOKEN_SVC_SMC_READ }}
          versioning-rules-importer-file: ${{ env.YAML_STD_CI_CONFIG_IMPORTER }}
          branch-packager-rules-importer-file: ${{ env.YAML_CI_BRANCH_CONFIG_IMPORTER }}
          consolidated-commit-msg: ${{ env.ALL_DELTA_COMMIT_MSG }}

      - name: View Version File - After
        run: |
          echo [INFO] Viewing versioning file - Post Activity
          cat ./test-files/sample-version-file.xml

      - name: View Maven POM File - After
        run: |
          echo [INFO] Viewing Maven POM file - Post Activity
          cat ./test-files/sample-pom-file.xml

      - name: Before version update - ${{ steps.version-bot.outputs.artifact-old-version}}
        run: |
          echo [INFO] Final version: ${{ steps.version-bot.outputs.artifact-old-version}}

      - name: Final version - ${{ steps.version-bot.outputs.artifact-version-name}}
        run: |
          echo [INFO] Final version: ${{ steps.version-bot.outputs.artifact-version-name}}
          echo "" > rslt-${{ std-config }}_${{ env.BRANCH_NAME }}--${{ steps.version-bot.outputs.artifact-version-name}}

      - uses: actions/upload-artifact@v2
        with:
          name: rslt-read-std-config_${{ env.BRANCH_NAME }}--${{ steps.version-bot.outputs.artifact-version-name}}
          path: rslt-read-std-config_${{ env.BRANCH_NAME }}--${{ steps.version-bot.outputs.artifact-version-name}}
          retention-days: 1

```

<p align="center">
  <a href="https://github.com/actions/checkout"><img alt="GitHub Actions status" src="https://github.com/actions/checkout/workflows/test-local/badge.svg"></a>
</p>

# Checkout V3

This action checks-out your repository under `$GITHUB_WORKSPACE`, so your workflow can access it.

Only a single commit is fetched by default, for the ref/SHA that triggered the workflow. Set `fetch-depth: 0` to fetch all history for all branches and tags. Refer [here](https://help.github.com/en/articles/events-that-trigger-workflows) to learn which commit `$GITHUB_SHA` points to for different events.

The auth token is persisted in the local git config. This enables your scripts to run authenticated git commands. The token is removed during post-job cleanup. Set `persist-credentials: false` to opt-out.

When Git 2.18 or higher is not in your PATH, falls back to the REST API to download the files.

# What's new

- Updated to the node16 runtime by default
  - This requires a minimum [Actions Runner](https://github.com/actions/runner/releases/tag/v2.285.0) version of v2.285.0 to run, which is by default available in GHES 3.4 or later.

# Usage

<!-- start usage -->
```yaml
- uses: actions/checkout@v3
  with:
    # Repository name with owner. For example, actions/checkout
    # Default: ${{ github.repository }}
    repository: ''

    # The branch, tag or SHA to checkout. When checking out the repository that
    # triggered a workflow, this defaults to the reference or SHA for that event.
    # Otherwise, uses the default branch.
    ref: ''

    # Personal access token (PAT) used to fetch the repository. The PAT is configured
    # with the local git config, which enables your scripts to run authenticated git
    # commands. The post-job step removes the PAT.
    #
    # We recommend using a service account with the least permissions necessary. Also
    # when generating a new PAT, select the least scopes necessary.
    #
    # [Learn more about creating and using encrypted secrets](https://help.github.com/en/actions/automating-your-workflow-with-github-actions/creating-and-using-encrypted-secrets)
    #
    # Default: ${{ github.token }}
    token: ''

    # SSH key used to fetch the repository. The SSH key is configured with the local
    # git config, which enables your scripts to run authenticated git commands. The
    # post-job step removes the SSH key.
    #
    # We recommend using a service account with the least permissions necessary.
    #
    # [Learn more about creating and using encrypted secrets](https://help.github.com/en/actions/automating-your-workflow-with-github-actions/creating-and-using-encrypted-secrets)
    ssh-key: ''

    # Known hosts in addition to the user and global host key database. The public SSH
    # keys for a host may be obtained using the utility `ssh-keyscan`. For example,
    # `ssh-keyscan github.com`. The public key for github.com is always implicitly
    # added.
    ssh-known-hosts: ''

    # Whether to perform strict host key checking. When true, adds the options
    # `StrictHostKeyChecking=yes` and `CheckHostIP=no` to the SSH command line. Use
    # the input `ssh-known-hosts` to configure additional hosts.
    # Default: true
    ssh-strict: ''

    # Whether to configure the token or SSH key with the local git config
    # Default: true
    persist-credentials: ''

    # Relative path under $GITHUB_WORKSPACE to place the repository
    path: ''

    # Whether to execute `git clean -ffdx && git reset --hard HEAD` before fetching
    # Default: true
    clean: ''

    # Number of commits to fetch. 0 indicates all history for all branches and tags.
    # Default: 1
    fetch-depth: ''

    # Whether to download Git-LFS files
    # Default: false
    lfs: ''

    # Whether to checkout submodules: `true` to checkout submodules or `recursive` to
    # recursively checkout submodules.
    #
    # When the `ssh-key` input is not provided, SSH URLs beginning with
    # `git@github.com:` are converted to HTTPS.
    #
    # Default: false
    submodules: ''
```
<!-- end usage -->

# Scenarios

- [Fetch all history for all tags and branches](#Fetch-all-history-for-all-tags-and-branches)
- [Checkout a different branch](#Checkout-a-different-branch)
- [Checkout HEAD^](#Checkout-HEAD)
- [Checkout multiple repos (side by side)](#Checkout-multiple-repos-side-by-side)
- [Checkout multiple repos (nested)](#Checkout-multiple-repos-nested)
- [Checkout multiple repos (private)](#Checkout-multiple-repos-private)
- [Checkout pull request HEAD commit instead of merge commit](#Checkout-pull-request-HEAD-commit-instead-of-merge-commit)
- [Checkout pull request on closed event](#Checkout-pull-request-on-closed-event)
- [Push a commit using the built-in token](#Push-a-commit-using-the-built-in-token)

## Fetch all history for all tags and branches

```yaml
- uses: actions/checkout@v3
  with:
    fetch-depth: 0
```

## Checkout a different branch

```yaml
- uses: actions/checkout@v3
  with:
    ref: my-branch
```

## Checkout HEAD^

```yaml
- uses: actions/checkout@v3
  with:
    fetch-depth: 2
- run: git checkout HEAD^
```

## Checkout multiple repos (side by side)

```yaml
- name: Checkout
  uses: actions/checkout@v3
  with:
    path: main

- name: Checkout tools repo
  uses: actions/checkout@v3
  with:
    repository: my-org/my-tools
    path: my-tools
```

## Checkout multiple repos (nested)

```yaml
- name: Checkout
  uses: actions/checkout@v3

- name: Checkout tools repo
  uses: actions/checkout@v3
  with:
    repository: my-org/my-tools
    path: my-tools
```

## Checkout multiple repos (private)

```yaml
- name: Checkout
  uses: actions/checkout@v3
  with:
    path: main

- name: Checkout private tools
  uses: actions/checkout@v3
  with:
    repository: my-org/my-private-tools
    token: ${{ secrets.GH_PAT }} # `GH_PAT` is a secret that contains your PAT
    path: my-tools
```

> - `${{ github.token }}` is scoped to the current repository, so if you want to checkout a different repository that is private you will need to provide your own [PAT](https://help.github.com/en/github/authenticating-to-github/creating-a-personal-access-token-for-the-command-line).


## Checkout pull request HEAD commit instead of merge commit

```yaml
- uses: actions/checkout@v3
  with:
    ref: ${{ github.event.pull_request.head.sha }}
```

## Checkout pull request on closed event

```yaml
on:
  pull_request:
    branches: [main]
    types: [opened, synchronize, closed]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
```

## Push a commit using the built-in token

```yaml
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: |
          date > generated.txt
          git config user.name github-actions
          git config user.email github-actions@github.com
          git add .
          git commit -m "generated"
          git push
```

# License

The scripts and documentation in this project are released under the [MIT License](LICENSE)
