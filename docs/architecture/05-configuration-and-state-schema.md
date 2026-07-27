# 05 - Configuration, State & File Schemas

## 1. Controller YAML Configuration Schema (`smc.ci`)

All operational behaviors of `gcs-versioning-bot` are declared in YAML files under the `.smc.ci` root path. The hierarchy is parsed by `gcs-yaml-importer` and flattened into environment variables.

### 1.1 Complete YAML Schema Structure

```yaml
smc:
  ci:
    artifact_base_name: "my-service" # Base artifact identifier
    
    artifact_auto_versioning:
      enabled: true                  # Master toggle for versioning bot
      
      # Version discovery source configuration
      version_sources:
        artifactory:
          enabled: true
          repo: "helmfile-release-local"
          dev_repo: "helmfile-dev-local"
          release_repo: "helmfile-release-local"
        docker:
          enabled: false
          registry_url: "https://index.docker.io/v1/"
          image_name: "partior/my-service"
        jira:
          enabled: false
          project_keys: "PROJ1,PROJ2"
          
      # Core Version Part Rules
      major_version:
        enabled: true
        rules:
          branch:
            enabled: true
            target: "main,master"
          tag:
            enabled: false
            target: ""
          msg_tag:
            enabled: true
            target: "[MAJOR-VERSION],#major"
          file:
            enabled: false
            target: "./app-version.cfg"
            key: "MAJOR-VERSION"

      minor_version:
        enabled: true
        rules:
          branch:
            enabled: true
            target: "main,master,develop"
          tag:
            enabled: false
            target: ""
          msg_tag:
            enabled: true
            target: "[MINOR-VERSION],#minor"
          file:
            enabled: false
            target: "./app-version.cfg"
            key: "MINOR-VERSION"

      patch_version:
        enabled: true
        rules:
          branch:
            enabled: true
            target: "main,master,develop"
          tag:
            enabled: false
            target: ""
          msg_tag:
            enabled: true
            target: "[PATCH-VERSION],#patch"
          file:
            enabled: false
            target: ""
            key: ""

      # Pre-Release Version Part Rules
      release_candidate_version:
        enabled: true
        rules:
          branch:
            enabled: true
            target: "release/*,rc/*"
          tag:
            enabled: true
            target: "rc-tag"
          file:
            enabled: false
            target: ""
            key: ""

      development_version:
        enabled: true
        rules:
          branch:
            enabled: true
            target: "feature/*,bugfix/*,develop"
          tag:
            enabled: false
            target: ""
          file:
            enabled: false
            target: ""
            key: ""

      # Prepend Version Label Rules
      prepend_version:
        enabled: false
        rules:
          file:
            target: "./version-label.cfg"
            key: "PREPEND-LABEL"

      # Replacement Rules (File Updates)
      replacement:
        enabled: true
        file_token:
          enabled: true
          target: "./deployment.yaml"
          name: "APP_VERSION"
        maven_pom:
          enabled: false
          target: "./pom.xml"
        yaml_update:
          enabled: false
          target: "./values.yaml"
          query_path: ".image.tag"
```

---

## 2. General INI Environment Variable Dictionary

`config/general.ini` maps the flattened YAML importer outputs into standardized shell variables. Below is the mapping dictionary:

| Target Scope Variable Name | Mapped Raw Importer Variable Name | Description / Valid Values |
| :--- | :--- | :--- |
| `VERSIONING_BOT_ENABLED` | `artifact_auto_versioning__enabled` | `true` or `false`. Master switch. |
| `MAJOR_V_RULES_ENABLED` | `artifact_auto_versioning__major_version__enabled` | `true`/`false`. Enable MAJOR scope. |
| `MAJOR_V_RULE_BRANCH_ENABLED` | `...__major_version__rules__branch__enabled` | `true`/`false`. Check branch for MAJOR. |
| `MAJOR_V_CONFIG_BRANCHES` | `...__major_version__rules__branch__target` | Comma-separated branch patterns. |
| `MAJOR_V_CONFIG_MSGTAGS` | `...__major_version__rules__msg_tag__target` | Comma-separated commit tags. |
| `MAJOR_V_RULE_VFILE_ENABLED` | `...__major_version__rules__file__enabled` | `true`/`false`. Enable file override. |
| `MAJOR_V_CONFIG_VFILE_NAME` | `...__major_version__rules__file__target` | Path to version config file. |
| `MAJOR_V_CONFIG_VFILE_KEY` | `...__major_version__rules__file__key` | Property key inside file. |
| `RC_V_RULES_ENABLED` | `...__release_candidate_version__enabled` | `true`/`false`. Enable RC scope. |
| `RC_V_CONFIG_BRANCHES` | `...__release_candidate_version__rules__branch__target` | Branch patterns for RC (e.g. `release/*`). |
| `DEV_V_RULES_ENABLED` | `...__development_version__enabled` | `true`/`false`. Enable DEV scope. |
| `DEV_V_CONFIG_BRANCHES` | `...__development_version__rules__branch__target` | Branch patterns for DEV (e.g. `feature/*`). |
| `REPLACE_V_RULES_ENABLED` | `...__replacement__enabled` | `true`/`false`. Enable file replacement. |
| `REPLACE_V_RULE_FILETOKEN_ENABLED`| `...__replacement__file_token__enabled` | `true`/`false`. Enable `sed` token replace. |
| `REPLACE_V_CONFIG_FILETOKEN_FILE` | `...__replacement__file_token__target` | Path to target file. |
| `REPLACE_V_CONFIG_FILETOKEN_NAME` | `...__replacement__file_token__name` | Token name (e.g. `APP_VERSION`). |
| `REPLACE_V_RULE_MAVEN_ENABLED` | `...__replacement__maven_pom__enabled` | `true`/`false`. Enable `mvn versions:set`. |
| `REPLACE_V_CONFIG_MAVEN_POMFILE` | `...__replacement__maven_pom__target` | Path to `pom.xml`. |

---

## 3. Preset Controller Configurations

`gcs-versioning-bot` ships with preset controller templates in `controller-config-files/projects/`:

| Preset File Name | Operational Use Case | Key Enabled Features |
| :--- | :--- | :--- |
| `default.yml` | Base template | Fallback defaults for all scopes. |
| `enable-std-rules.yml` | Standard microservice release | DEV on feature branches, RC on release branches, PATCH on main. |
| `enable-trunk-versioning.yml` | Trunk-based development | Continuous release versioning directly on main/master trunk. |
| `enable-msgtag.yml` | Message tag driven versioning | Increments MAJOR/MINOR/PATCH based on `#major`, `#minor` commit tags. |
| `enable-ver-from-file.yml` | File-referenced versioning | Reads base MAJOR/MINOR numbers from `app-version.cfg`. |
| `enable-replace-file-version.yml` | Manifest token substitution | Replaces `@@APP_VERSION@@` in deployment files. |
| `enable-replace-maven-pom.yml` | Java / Maven projects | Executes `mvn versions:set` on `pom.xml`. |
| `enable-jira-versions.yml` | Enterprise JIRA tracking | Syncs releases and fixVersions directly to JIRA projects. |

---

## 4. Temporary Workspace State File Directory

During action execution, state is persisted across script steps using temporary files in the current workspace directory:

```
[ WORKSPACE DIRECTORY ]
├── artifact_last_dev_version.txt    <-- Stores last DEV version (e.g. "1.2.0-dev.4")
├── artifact_last_rc_version.txt     <-- Stores last RC version (e.g. "1.2.0-rc.2")
├── artifact_last_rel_version.txt    <-- Stores last Release version (e.g. "1.2.0")
├── artifact_last_base_version.txt   <-- Stores last Base/Hotfix version (e.g. "1.2.0-hf.1")
├── artifact_updated_release_version.txt <-- Stores updated base release X.Y.Z
├── artifact_next_version.txt        <-- Stores calculated next version (e.g. "1.2.0-rc.3")
├── is_initial.flag                  <-- Created if repository has no prior artifacts
├── core.updated                     <-- Touch flag indicating core release bumped
├── commit-message-tmp               <-- Git commit log delta between tags
├── yaml-importer-tmp                <-- Environment export file from importer
└── responseOutFile.tmp              <-- Temporary API response buffer
```
