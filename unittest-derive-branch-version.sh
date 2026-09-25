#!/bin/bash
## Unit tests for scripts/derive_branch_version.sh
##
## Builds disposable git repositories and drives the script through every
## derivation path and every refusal. No network, no mocking of git.
##
## Run:  ./unittest-derive-branch-version.sh

DERIVE_SCRIPT_PATH="./scripts/derive_branch_version.sh"
SCRIPT_ABS="$(cd "$(dirname "$DERIVE_SCRIPT_PATH")" && pwd)/$(basename "$DERIVE_SCRIPT_PATH")"

passCount=0
failCount=0
FIXTURE=""

function setupFixture() {
    FIXTURE="$(mktemp -d)"
    git init -q -b main "$FIXTURE"
    git -C "$FIXTURE" config user.email unittest@partior.com
    git -C "$FIXTURE" config user.name unittest
    setLine 27 1
    fixtureCommit "init"
}

function teardownFixture() {
    [[ -n "$FIXTURE" ]] && rm -rf "$FIXTURE"
}

function fixtureCommit() {
    echo "$1" >> "$FIXTURE/file.txt"
    git -C "$FIXTURE" add -A
    git -C "$FIXTURE" commit -qm "$1"
}

function writeVersionConfig() {
    ## writeVersionConfig <contents>
    printf '%s\n' "$1" > "$FIXTURE/app-version.cfg"
}

function setLine() {
    ## setLine <major> <minor>
    writeVersionConfig "MAJOR-VERSION=$1
MINOR-VERSION=$2"
}

function derive() {
    ## derive <branch> [configFile]
    "$SCRIPT_ABS" "$1" "${2:-app-version.cfg}" "$FIXTURE" 2>&1
}

function assertField() {
    ## assertField <field> <description> <expected> <branch> [configFile]
    local field="$1" description="$2" expected="$3" output actual
    output="$(derive "$4" "${5:-}")"
    if [[ $? -ne 0 ]]; then
        echo "[FAIL] $description - refused unexpectedly: $output"
        failCount=$((failCount + 1))
        return
    fi
    actual="$(echo "$output" | grep "^${field}=" | cut -d= -f2)"
    if [[ "$actual" == "$expected" ]]; then
        echo "[PASS] $description"
        passCount=$((passCount + 1))
    else
        echo "[FAIL] $description - expected $field [$expected] but got [$actual]"
        failCount=$((failCount + 1))
    fi
}

function assertVersion() {
    ## The Build Tag, which is also the artifact version. There is no separate
    ## target any more: promotion adds a Milestone Tag, it does not renumber.
    assertField version "$1" "$2" "$3" "$4"
}

function assertRefused() {
    ## assertRefused <description> <expectedReasonPattern> <branch> [configFile]
    local description="$1" pattern="$2" output
    output="$(derive "$3" "${4:-}")"
    if [[ $? -eq 0 ]]; then
        echo "[FAIL] $description - expected a refusal but got: $output"
        failCount=$((failCount + 1))
    elif echo "$output" | grep -q "$pattern"; then
        echo "[PASS] $description"
        passCount=$((passCount + 1))
    else
        echo "[FAIL] $description - refused for the wrong reason: $output"
        failCount=$((failCount + 1))
    fi
}


echo "===== mainline ====="
setupFixture
assertVersion "a fresh line starts at .0" "27.1.0" main
git -C "$FIXTURE" tag 27.1.0
assertVersion "every commit takes the next number" "27.1.1" main
git -C "$FIXTURE" tag 27.1.1
git -C "$FIXTURE" tag 27.1.2
assertVersion "burnt numbers are skipped, not reused" "27.1.3" main
teardownFixture

echo "===== mainline stops once its line is cut ====="
setupFixture
git -C "$FIXTURE" tag 27.1.0
git -C "$FIXTURE" branch release/27.1
assertRefused "the mainline refuses while release/<line> exists" \
    "release/27.1 already exists" main
teardownFixture

setupFixture
git -C "$FIXTURE" tag 27.1.0
git -C "$FIXTURE" update-ref refs/remotes/origin/release/27.1 HEAD
assertRefused "a release branch on a remote counts too" \
    "release/27.1 already exists" main
teardownFixture

setupFixture
git -C "$FIXTURE" tag 27.1.0
git -C "$FIXTURE" branch release/27.2
assertVersion "another line's release branch does not block this one" "27.1.1" main
teardownFixture

echo "===== milestone tags never affect build numbering ====="
setupFixture
git -C "$FIXTURE" tag 27.1.0
git -C "$FIXTURE" tag R27.1.1
assertVersion "an R tag is not a build tag" "27.1.1" main
teardownFixture

echo "===== release branch ====="
setupFixture
git -C "$FIXTURE" tag 27.1.0
git -C "$FIXTURE" tag 27.1.30
assertVersion "a release branch continues the line's numbering" "27.1.31" release/27.1
teardownFixture

setupFixture
setLine 27 2
git -C "$FIXTURE" tag 27.1.0
assertRefused "a branch that disagrees with its declaration is refused" \
    "disagrees with the declaration" release/27.1
teardownFixture

setupFixture
assertRefused "a release branch with no build tags proves a shallow clone" \
    "no build tags visible" release/27.1
teardownFixture

setupFixture
assertRefused "a malformed release branch name is refused" \
    "named release/X.Y" release/27.1.1
teardownFixture

echo "===== the version config ====="
setupFixture
writeVersionConfig "# the line this branch builds toward
MAJOR-VERSION=27

MINOR-VERSION=1
"
assertVersion "comments, blank lines and order do not matter" "27.1.0" main
writeVersionConfig "MAJOR-VERSION = 27
MINOR-VERSION = 1"
assertVersion "surrounding whitespace is tolerated" "27.1.0" main
writeVersionConfig "MAJOR-VERSION=27   # the line this branch builds toward
MINOR-VERSION=1"
assertVersion "a trailing comment is not part of the value" "27.1.0" main
writeVersionConfig "MINOR-VERSION=1"
assertRefused "a missing MAJOR-VERSION is refused" "MAJOR-VERSION" main
writeVersionConfig "MAJOR-VERSION=27"
assertRefused "a missing MINOR-VERSION is refused" "MINOR-VERSION" main
writeVersionConfig "MAJOR-VERSION=27
MINOR-VERSION=one"
assertRefused "a non-numeric value is refused" "must be a whole number" main
writeVersionConfig "APP-MAJOR-VERSION=99
MAJOR-VERSION=27
MINOR-VERSION=1"
assertVersion "a key that merely contains the name is not mistaken for it" "27.1.0" main
assertRefused "a missing config file is refused" "not found" main no-such-file.cfg
teardownFixture

echo "===== general hotfix line ====="
setupFixture
git -C "$FIXTURE" tag 27.1.30
assertVersion "no label means the general line, starting at .1" \
    "27.1.30_hf.1" hotfix-base/27.1.30
git -C "$FIXTURE" tag 27.1.30_hf.1
assertVersion "the general line counts its own builds" \
    "27.1.30_hf.2" hotfix-base/27.1.30
teardownFixture

echo "===== variant lines are independent ====="
setupFixture
git -C "$FIXTURE" tag 27.1.30
git -C "$FIXTURE" tag 27.1.30_hf.1
git -C "$FIXTURE" tag 27.1.30_hf.2
assertVersion "a variant starts at .1 and ignores the general line" \
    "27.1.30_v2.1" hotfix-base/27.1.30_v2
git -C "$FIXTURE" tag 27.1.30_v2.1
assertVersion "the general line ignores the variant" \
    "27.1.30_hf.3" hotfix-base/27.1.30
teardownFixture

echo "===== a hotfix line does not continue the release line ====="
setupFixture
git -C "$FIXTURE" tag 27.1.30
git -C "$FIXTURE" tag 27.1.31
assertVersion "later builds on the line do not renumber the hotfix line" \
    "27.1.30_hf.1" hotfix-base/27.1.30
teardownFixture

echo "===== hotfix branch naming ====="
setupFixture
git -C "$FIXTURE" tag 27.1.30
assertRefused "the dev label is reserved for pull request builds" \
    "reserved for pull request builds" hotfix-base/27.1.30_dev
assertRefused "a variant of a variant is refused" \
    "hotfix-base/X.Y.Z" hotfix-base/27.1.30_v2_v3
assertRefused "a label must start with a letter" \
    "hotfix-base/X.Y.Z" hotfix-base/27.1.30_2v
assertRefused "an uppercase label is refused" \
    "hotfix-base/X.Y.Z" hotfix-base/27.1.30_V2
assertRefused "the anchor build tag must be visible" \
    "is not visible" hotfix-base/27.1.99
assertRefused "the old hotfix/ prefix is not a versioned branch" \
    "not a versioned branch" hotfix/27.1.30_hf
teardownFixture

echo "===== numbering resumes above the highest, never in a gap ====="
setupFixture
git -C "$FIXTURE" tag 27.1.0
git -C "$FIXTURE" tag 27.1.2
git -C "$FIXTURE" tag 27.1.3
assertVersion "a gap in the sequence is left alone" "27.1.4" main
teardownFixture

echo "===== unversioned branch ====="
setupFixture
assertRefused "feature branches are not versioned here" \
    "not a versioned branch" feature/something
teardownFixture

echo ""
echo "===== passed: $passCount, failed: $failCount ====="
[[ $failCount -eq 0 ]]
