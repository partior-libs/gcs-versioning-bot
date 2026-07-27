# 08 - Reconstruction & Implementation Blueprint

This document serves as the complete technical blueprint for software engineers seeking to **reconstruct, port, or rewrite** `gcs-versioning-bot` from scratch in any modern programming language (e.g., **Go**, **Python**, **TypeScript / Node.js**, or **Rust**) or CI/CD platform (e.g., GitLab CI, Azure DevOps, Jenkins).

It contains high-level design guidelines, structural mappings, complete core algorithm pseudocode, state transition matrices, and an exhaustive verification checklist.

---

## 1. High-Level Language Modular Mapping

When rebuilding the bot in an object-oriented or functional language (e.g., Go or TypeScript), map the shell script capabilities into clean, strongly typed modules:

```
gcs-versioning-bot/
├── config/
│   ├── Schema.go / .ts          <-- Type-safe struct matching YAML (.smc.ci)
│   ├── INIMapper.go / .ts       <-- Scope feature flag parser
├── artifactory/
│   ├── AQLClient.go / .ts       <-- Paginated AQL search client (offset/limit 500)
├── docker/
│   ├── RegistryClient.go / .ts  <-- V2 API Docker tag search client
├── jira/
│   ├── JiraClient.go / .ts      <-- REST API client for Version & Issue tagging
├── engine/
│   ├── BaseSelector.go / .ts    <-- getNeededIncrementReleaseVersion logic
│   ├── CoreCalculator.go / .ts  <-- SemVer 2.0 Major/Minor/Patch incrementor
│   ├── PreReleaseEngine.go / .ts<-- Dev / RC / Hotfix incrementor
│   ├── FileReplacer.go / .ts    <-- Token, Maven POM, YAML paths updater
└── main.go / index.ts           <-- CLI / Action entry point
```

---

## 2. Core Calculation Engine Pseudocode

The following pseudocode captures the complete decision matrix implemented across `generate_package_version.sh`:

```python
def calculate_next_version(
    config: Configuration,
    history: ArtifactHistory, # Contains last_dev, last_rc, last_rel, last_base
    branch_name: str,
    commit_messages: List[str],
    rebase_version_arg: Optional[str]
) -> str:

    # 1. Hotfix / Rebase Branch Scenario
    if rebase_version_arg:
        base = history.last_base if history.last_base else f"{rebase_version_arg}-hf.0"
        patch_num = extract_trailing_integer(base)
        return f"{rebase_version_arg}-hf.{patch_num + 1}"

    # 2. Select Base Core Version (X.Y.Z)
    base_version = select_base_release_version(
        history.last_dev, 
        history.last_rc, 
        history.last_rel
    )
    current_version = base_version

    # 3. Check for File-Driven Major/Minor Overrides
    if config.major.file_rule_enabled:
        file_major = read_file_key(config.major.file_path, config.major.file_key)
        current_version = set_version_part(current_version, pos=0, value=file_major)
        current_version = resolve_with_history(current_version, pos=0, history)

    if config.minor.file_rule_enabled:
        file_minor = read_file_key(config.minor.file_path, config.minor.file_key)
        current_version = set_version_part(current_version, pos=1, value=file_minor)
        current_version = resolve_with_history(current_version, pos=1, history)

    # 4. Automatic Core Release Increment (If no file override)
    is_prerelease_active = is_prerelease_increment_active(config, branch_name)
    core_was_incremented = False

    if config.major.is_active(branch_name) and not config.major.file_rule_enabled:
        count = count_message_tags(commit_messages, config.major.msg_tags)
        if count > 0:
            current_version = increment_part(history.last_rel, pos=0, count=count)
            core_was_incremented = True
        elif not is_prerelease_active:
            current_version = increment_part(current_version, pos=0, count=1)
            core_was_incremented = True

    elif config.minor.is_active(branch_name) and not config.minor.file_rule_enabled:
        count = count_message_tags(commit_messages, config.minor.msg_tags)
        if count > 0:
            current_version = increment_part(history.last_rel, pos=1, count=count)
            core_was_incremented = True
        elif not is_prerelease_active:
            current_version = increment_part(current_version, pos=1, count=1)
            core_was_incremented = True

    elif config.patch.is_active(branch_name) and not config.patch.file_rule_enabled and not core_was_incremented:
        count = count_message_tags(commit_messages, config.patch.msg_tags)
        if count > 0:
            current_version = increment_part(history.last_rel, pos=2, count=count)
            core_was_incremented = True
        elif not is_prerelease_active:
            current_version = increment_part(current_version, pos=2, count=1)
            core_was_incremented = True

    # 5. Pre-Release Increment (RC or DEV)
    if config.rc.is_active(branch_name):
        if core_was_incremented:
            current_version = f"{current_version}-rc.1"
        else:
            current_version = increment_prerelease(history.last_rc, "rc")

    elif config.dev.is_active(branch_name):
        if core_was_incremented:
            current_version = f"{current_version}-dev.1"
        else:
            current_version = increment_prerelease(history.last_dev, "dev")

    # 6. Append Build Metadata (If enabled)
    if config.build.is_active(branch_name):
        current_version += f"+bld.{config.build.run_number}.{config.build.run_attempt}"

    return current_version
```

---

## 3. State Machine Transition Table

The state of version calculation transitions across inputs as defined in this truth table:

| Trigger Branch | Last Release | Last RC | Last DEV | Core Bump Triggered? | Resulting Calculated Version |
| :--- | :---: | :---: | :---: | :---: | :--- |
| `feature/JIRA-1` | `1.2.0` | `1.2.0-rc.1` | `1.2.0-dev.3` | No | `1.2.0-dev.4` |
| `feature/JIRA-1` | `1.2.0` | `1.2.0-rc.1` | `1.2.0-dev.3` | Yes (`#minor`) | `1.3.0-dev.1` |
| `release/1.2.0` | `1.2.0` | `1.2.0-rc.2` | `1.2.0-dev.5` | No | `1.2.0-rc.3` |
| `release/1.3.0` | `1.2.0` | `None` | `1.3.0-dev.12` | No | `1.3.0-rc.1` |
| `main` | `1.2.0` | `1.2.1-rc.3` | `1.2.1-dev.8` | No | `1.2.1` |
| `main` | `1.2.0` | `1.2.0-rc.1` | `1.2.0-dev.1` | Yes (`#major`) | `2.0.0` |
| `hotfix/v1.2.0` | `1.2.0` | `None` | `None` | Hotfix (`rebase=1.2.0`) | `1.2.0-hf.1` |

---

## 4. Parity Verification Checklist

When verifying a new implementation of `gcs-versioning-bot`, run through this checklist to ensure 100% behavioral parity with the original codebase:

- [ ] **AQL Pagination**: Verify queries with $>500$ artifacts fetch all pages seamlessly without truncation.
- [ ] **SemVer Precedence**: Ensure `1.2.0-rc.10` is recognized as higher than `1.2.0-rc.9` (version sort `-V`).
- [ ] **Message Tag Counts**: Confirm multiple commit tags (e.g. two `#minor` tags) increment minor version by $+2$.
- [ ] **Pre-Release Suppression**: Ensure auto-incrementing PATCH on a feature branch does not increment PATCH twice when DEV pre-release is also active.
- [ ] **Maven POM Backup Clean**: Confirm `mvn versions:set` leaves no orphaned `pom.xml.versionsBackup` files.
- [ ] **Token Replacement Precision**: Confirm `sed` token replacement only replaces exact `@@TOKEN@@` patterns without breaking surrounding XML/YAML tags.
- [ ] **JIRA Archiving**: Verify that publishing `1.2.0` archives all unreleased `1.2.0-rc.*` versions in JIRA.
- [ ] **Unit Test Spec Parity**: Run the new implementation against all 50+ test cases in `test-files/` to ensure zero regression errors.
