# 03 - Versioning Rules & Decision Engine

## 1. Scope Feature Flag Evaluation Engine

Every versioning rule in `gcs-versioning-bot` is conditioned on a boolean evaluation matrix. The engine inspects four core scope dimensions:
1. **`MAJOR` / `MINOR` / `PATCH`**: Core Release Version parts.
2. **`RC` / `DEV`**: Pre-Release Version tags.
3. **`BUILD`**: Build metadata suffix.
4. **`REPLACEMENT`**: Target file version updates.

### 1.1 Release Scope Feature Flag (`checkReleaseVersionFeatureFlag`)
A release scope (e.g. `MAJOR`) is considered active if and only if **all four** of the following conditions evaluate to `true`:
$$\text{FeatureActive}(\text{Scope}) = \text{BotEnabled} \land \text{ScopeRulesEnabled} \land \text{BranchMatch} \land (\text{LabelMatch} \lor \text{TagMatch} \land \text{MsgTagMatch})$$

```bash
if [[ "$VERSIONING_BOT_ENABLED" == "true" ]] && \
   [[ "${!vRulesEnabled}" == "true" ]] && \
   [[ $(checkIsSubstring "${!vConfigBranches}" "${!ghCurrentBranch}") == "true" ]] && \
   ( [[ $(checkListIsSubstringInFileContent "${!vConfigLabels}" "${!ghCurrentLabel}") == "true" ]] || \
     [[ $(checkListIsSubstringInFileContent "${!vConfigTags}" "${!ghCurrentTag}") == "true" ]] && \
     [[ $(checkListIsSubstringInFileContent "${!vConfigMsgTags}" "${!ghCurrentMsgTag}") == "true" ]] ); then
    echo "true"
else
    echo "false"
fi
```

### 1.2 Pre-Release Feature Flag (`checkPreReleaseVersionFeatureFlag`)
A pre-release scope (e.g. `RC` or `DEV`) is active when:
1. `VERSIONING_BOT_ENABLED == "true"`
2. `<SCOPE>_V_RULES_ENABLED == "true"`
3. Current git branch matches configured branch list (`<SCOPE>_V_CONFIG_BRANCHES`).
4. Current tag/trigger matches configured tag list (`<SCOPE>_V_CONFIG_TAGS`).

---

## 2. Decision Logic Pipeline & Evaluation Order

When `generate_package_version.sh` executes, it evaluates version increments in a strict sequential order:

```
                          [ START VERSION ENGINE ]
                                     |
                                     v
                       Is Rebase/Hotfix Parameter Set?
                                 /       \
                               /           \
                             YES           NO
                             /               \
                            v                 v
                 [ Hotfix Calculation ]   1. [ Base Version Selection ]
                 Increment -hf.N suffix      getNeededIncrementReleaseVersion()
                                                      |
                                                      v
                                          2. [ Auto Core Increment ]
                                             Check MAJOR -> MINOR -> PATCH
                                                      |
                                                      v
                                          3. [ Version File Override ]
                                             processWithReleaseVersionFile()
                                                      |
                                                      v
                                          4. [ Pre-Release Increment ]
                                             check RC -> DEV auto/file rules
                                                      |
                                                      v
                                          5. [ Build Metadata Suffix ]
                                             +bld.<run>.<attempt>
                                                      |
                                                      v
                                          6. [ Source File Replacement ]
                                             Update pom.xml / tokenized files
```

---

## 3. Detailed Algorithmic Step Breakdown

### Step 1: Base Version Selection (`getNeededIncrementReleaseVersion`)
Determines the starting base `X.Y.Z` version by comparing last published `DEV`, `RC`, and `Release` versions:

- **Rule 1.1**: If `lastRelVersion` equals `lastDevVersion` AND `lastRelVersion` equals `lastRcVersion`, the base is `lastRelVersion`.
- **Rule 1.2**: If `lastRcVersion` is greater than or equal to `lastDevVersion`, extract the `X.Y.Z` prefix of `lastRcVersion`.
- **Rule 1.3**: If `lastDevVersion` is greater than `lastRcVersion`, extract the `X.Y.Z` prefix of `lastDevVersion`.
- **Rule 1.4**: If pre-release versions are uninitialized (`nil` or empty), fall back to `lastRelVersion`.

```bash
function getNeededIncrementReleaseVersion() {
    local inputDevVer="$1"
    local inputRcVer="$2"
    local inputRelVer="$3"
    
    # Strip pre-release suffixes (-dev.N, -rc.N) to compare core X.Y.Z parts
    local devVerOnly=$(echo $inputDevVer | grep -oE "^[0-9]+\.[0-9]+\.[0-9]+")
    local rcVerOnly=$(echo $inputRcVer | grep -oE "^[0-9]+\.[0-9]+\.[0-9]+")
    
    if [[ "$devVerOnly" == "$rcVerOnly" ]] && [[ "$devVerOnly" == "$inputRelVer" ]]; then
        echo "$inputRelVer"
    elif [[ "$rcVerOnly" > "$devVerOnly" ]] || [[ "$rcVerOnly" == "$devVerOnly" ]]; then
        echo "$rcVerOnly"
    elif [[ "$devVerOnly" > "$rcVerOnly" ]]; then
        echo "$devVerOnly"
    else
        echo "$inputRelVer"
    fi
}
```

---

### Step 2: Automatic Core Release Increment (`incrementReleaseVersion`)
When `MAJOR`, `MINOR`, or `PATCH` rules are triggered without a version file:

- **Position Parameters**: `MAJOR_POSITION=0`, `MINOR_POSITION=1`, `PATCH_POSITION=2`.
- **Commit Message Tag Multi-Increment**: If commit messages contain multiple matching tags (e.g. three `#minor` tags), `getIncrementalCount` returns `3`, incrementing the position value by `3` instead of `1`.
- **Reset Invariant**: When position `P` is incremented, all positions $> P$ are reset to `0`.
  - Incremented position 0 (`MAJOR`): `1.2.3` $\rightarrow$ `2.0.0`
  - Incremented position 1 (`MINOR`): `1.2.3` $\rightarrow$ `1.3.0`
  - Incremented position 2 (`PATCH`): `1.2.3` $\rightarrow$ `1.2.4`

- **Pre-Release Invariant Protection (`isPreReleaseIncrementation`)**:
  If an automatic `RC` or `DEV` pre-release increment is active on the current branch, the core `MAJOR`/`MINOR`/`PATCH` auto-increment is **suppressed** to prevent double-bumping the base version.

---

### Step 3: File-Driven Version Override (`processWithReleaseVersionFile`)
When version numbers are defined in repository files (e.g. `MAJOR-VERSION=2` in `app-version.cfg`):

1. Reads the configured key from the target version file.
2. Updates position `P` with the file value.
3. Performs a historical lookup in `versionListFile` (list of existing published versions) for the prefix `MAJOR.MINOR`.
4. If the highest existing version matching the prefix is a full release (`X.Y.Z`), increments position $P+1$.
5. Synchronizes last known pre-release state files (`artifact_last_rc_version.txt`, `artifact_last_dev_version.txt`) for the selected prefix.

---

### Step 4: Pre-Release Increment (`incrementPreReleaseVersion`)
Calculates pre-release numbers (`-rc.N` or `-dev.N`):

- **New Pre-Release Cycle**: If the base `X.Y.Z` version was newly incremented in Step 2 or 3, the pre-release counter resets to `1` (e.g. `1.3.0-rc.1`).
- **Existing Pre-Release Cycle**: If base `X.Y.Z` matches the previous pre-release base, the numeric counter increment is applied ($N + 1$):
  $$\text{"1.2.0-rc.3"} \xrightarrow{\text{increment}} \text{"1.2.0-rc.4"}$$

```bash
function incrementPreReleaseVersion() {
    local inputVersion="$1"      # e.g., "1.2.0-rc.3"
    local versionIdentifier="$2" # e.g., "rc"
    
    local baseVersion=$(echo $inputVersion | cut -d"-" -f1)
    local preReleaseNum=$(echo $inputVersion | awk -F"-$versionIdentifier." '{print $2}')
    local nextNum=$(( preReleaseNum + 1 ))
    
    echo "${baseVersion}-${versionIdentifier}.${nextNum}"
}
```

---

### Step 5: Hotfix / Rebase Branch Versioning
When `rebaseReleaseVersion` is passed as argument 6 to `generate_package_version.sh`:

1. Inspects `lastBaseVersion` (e.g. `1.2.0-hf.2`).
2. If `lastBaseVersion` is uninitialized, starts at `${rebaseReleaseVersion}-hf.1`.
3. Extracts the trailing integer ($N$), increments $N + 1$, and constructs the hotfix string:
   $$\text{"1.2.0-hf.2"} \rightarrow \text{"1.2.0-hf.3"}$$

---

### Step 6: File Version Token Replacements

After the final version string is computed, three optional substitution tools update repository files:

#### 6.1 Generic Token Replacement (`replaceVersionInFile`)
Replaces instances of `@@<TOKEN_NAME>@@` in a target file using `sed`:
```bash
sed -r -i "s|@@${targetReplacementToken}@@|${inputVersion}|g" $targetFile
```

#### 6.2 Maven POM Replacement (`replaceVersionForMaven`)
Invokes Maven versions plugin to safely update `pom.xml`:
```bash
mvn -f $targetPomFile versions:set -DnewVersion=$inputVersion -q -DforceStdout
```

#### 6.3 YAML Path Replacement (`replaceVersionForYamlFile`)
Uses `yq` to update targeted YAML nodes:
```bash
yq -i "$targetYamlQueryPath = \"$inputVersion\"" $targetYamlFile
```
