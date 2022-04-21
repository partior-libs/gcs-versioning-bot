# Partior Artifact Versioning Bot (partior-stable)
This action generate the next incremented semantic version of artifact with the input parameters from Jfrog artifact path and YAML configuration schema from [CICD controller](https://github.com/partior-quorum/controller-smc-pipelines).

# Usage
<!-- start usage -->
```yaml
- uses: partior-libs/gcs-versioning-bot@partior-stable
  with:
    # Jfrog username to query last artifact version
    # Mandatory: Yes if jfrog-token is empty. Otherwise must provide the username.
    artifactory-username: ''

    # Jfrog password to query last artifact version
    # Mandatory: Yes if jfrog-token is empty. Otherwise must provide the password.
    artifactory-password: ''

    # Jfrog password to query last artifact version
    # Mandatory: Yes if artifactory-username/password is empty. Otherwise must provide the token.
    jfrog-token: ''
    
    # Artifactory base URL for query endpoint
    # Mandatory: No
    # Default: ${{ github.token }}
    artifactory-base-url: 'https://partior.jfrog.io/artifactory'
    
    # Jira username to query versions
    # Mandatory: false (Mandatory if version-sources.jira.enabled in yaml config is true)
    jira-username: ''
    
    # Jira password to query versions
    # Mandatory: false (Mandatory if version-sources.jira.enabled in yaml config is true)
    jira-password: ''
    
    # Jira base URL for query endpoint
    # Mandatory: No
    # Default: ${{ github.token }}
    jira-base-url: 'https://partior.atlassian.net'

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
## Output
The action has two outputs:
```yaml
    # This is the incremented version from the bot. Example: 1.0.1, 1.0.1-dev.1, 1.0.1-rc.1, 1.0.1-dev.1+bld.2.1
    artifact-version-name: ''

    # This is the version before being incremented. All three version types (DEV, RC, REL) are constructed in single string format
    artifact-old-name: ''

    # This is the incremented version from the bot with artifact base name prepended. Example: artifact-name-1.0.1, artifact-name-1.0.1-dev.1, artifact-name-1.0.1-rc.1, artifact-name-1.0.1-dev.1+bld.2.1
    artifact-full-version-name: ''
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
      initial-release-version: 1.0.0
      version-sources:
          artifactory:
            enabled: false
          jira:
            enabled: true
            project-key: ""
            version-identifier: ""
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
          jira-username: ${{ secrets.JIRA_USERNAME }}
          jira-password: ${{ secrets.JIRA_API_TOKEN }}
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
