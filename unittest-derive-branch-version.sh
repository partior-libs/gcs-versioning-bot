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
    ## The full build identifier, which becomes the git tag and the candidate
    ## container tag.
    assertField version "$1" "$2" "$3" "$4"
}

function assertTarget() {
    ## The version the build is heading for, which is what goes in the pom.
    ## Asserting this separately matters: the pom must never carry the -dev
    ## label, because Maven orders that label above a hotfix label.
    assertField target "$1" "$2" "$3" "$4"
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
assertVersion "mainline derives the line's .0" "27.1.0-dev.1" main
assertTarget "the target carries no build label" "27.1.0" main
git -C "$FIXTURE" tag 27.1.0-dev.1
assertVersion "counter counts build identifiers" "27.1.0-dev.2" main
git -C "$FIXTURE" tag 27.1.0
assertRefused "mainline declaration goes stale once the line ships" "already has release tags" main
teardownFixture

echo "===== mainline staleness counts hotfix-only lines ====="
setupFixture
setLine 30 1
git -C "$FIXTURE" tag 30.1.0_hf.1
assertRefused "a line whose only release is a hotfix still counts as shipped" \
    "already has release tags" main
teardownFixture

echo "===== release branch ====="
setupFixture
git -C "$FIXTURE" tag 27.1.0
assertVersion "infers the next patch" "27.1.1-dev.1" release/27.1
assertTarget "the pom version is the plain patch" "27.1.1" release/27.1
git -C "$FIXTURE" tag 27.1.1
git -C "$FIXTURE" tag 27.1.1_hf.1
assertVersion "hotfix tags do not perturb patch inference" "27.1.2-dev.1" release/27.1
assertRefused "branch and declaration must agree" "disagrees with the declaration" release/27.2
teardownFixture

echo "===== release branch, shallow clone guard ====="
setupFixture
setLine 29 9
assertRefused "no visible line tags is a broken checkout" "shallow clone or unfetched tags" \
    release/29.9
teardownFixture

echo "===== the version config ====="
setupFixture
writeVersionConfig "# the line this branch builds toward
MAJOR-VERSION=27

MINOR-VERSION=1
"
assertVersion "comments, blank lines and order do not matter" "27.1.0-dev.1" main
writeVersionConfig "MAJOR-VERSION = 27
MINOR-VERSION = 1"
assertVersion "surrounding whitespace is tolerated" "27.1.0-dev.1" main
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
assertVersion "a key that merely contains the name is not mistaken for it" "27.1.0-dev.1" main
assertRefused "a missing config file is refused" "not found" main no-such-file.cfg
teardownFixture

echo "===== the complete-version override is withdrawn ====="
setupFixture
git -C "$FIXTURE" tag 27.1.1
writeVersionConfig "MAJOR-VERSION=27
MINOR-VERSION=1
FULL-VERSION=27.1.1_hf.1"
assertVersion "an unknown key is ignored, so no override sneaks back in" \
    "27.1.2-dev.1" release/27.1
teardownFixture

echo "===== general hotfix line ====="
setupFixture
git -C "$FIXTURE" tag 27.1.7
assertVersion "first hotfix on the general line" "27.1.7_hf.1-dev.1" hotfix/27.1.7_hf
assertTarget "the pom version is the hotfix version" "27.1.7_hf.1" hotfix/27.1.7_hf
fixtureCommit "hotfix work"
git -C "$FIXTURE" tag 27.1.7_hf.1
assertVersion "next hotfix on the same line" "27.1.7_hf.2-dev.1" hotfix/27.1.7_hf
teardownFixture

echo "===== variant hotfix line ====="
setupFixture
git -C "$FIXTURE" tag 27.1.7
assertVersion "first hotfix on a variant line" "27.1.7_v2.1-dev.1" hotfix/27.1.7_v2
fixtureCommit "variant work"
git -C "$FIXTURE" tag 27.1.7_v2.1
assertVersion "next hotfix on the variant line" "27.1.7_v2.2-dev.1" hotfix/27.1.7_v2
teardownFixture

echo "===== lines are independent ====="
setupFixture
git -C "$FIXTURE" tag 27.1.7
## The general line ships a fix on its own branch. A variant cut from the
## release must not be refused for lacking it, and must not continue its
## numbering either.
git -C "$FIXTURE" checkout -qb generalwork
fixtureCommit "general fix"
git -C "$FIXTURE" tag 27.1.7_hf.1
git -C "$FIXTURE" checkout -q 27.1.7
assertVersion "a variant ignores the general line's tags" "27.1.7_v2.1-dev.1" \
    hotfix/27.1.7_v2
teardownFixture

echo "===== anchor guard is per line ====="
setupFixture
git -C "$FIXTURE" tag 27.1.7
git -C "$FIXTURE" checkout -qb hotfixwork
fixtureCommit "shipped hotfix"
git -C "$FIXTURE" tag 27.1.7_hf.1
## Re-anchor at the release tag, which misses the shipped hotfix of this line.
git -C "$FIXTURE" checkout -q 27.1.7
assertRefused "anchoring below the latest tag of the same line drops a shipped fix" \
    "not in this branch's history" hotfix/27.1.7_hf
teardownFixture

echo "===== hotfix branch naming ====="
setupFixture
git -C "$FIXTURE" tag 27.1.7
assertRefused "a hotfix branch must carry a label" "hotfix branches are named" \
    hotfix/27.1.7
assertRefused "the dev label is reserved for candidates" "reserved" \
    hotfix/27.1.7_dev
assertRefused "a variant of a variant is refused" "hotfix branches are named" \
    hotfix/27.1.7_v2_v5
assertRefused "a label must start with a letter" "hotfix branches are named" \
    hotfix/27.1.7_2v
assertRefused "an uppercase label is refused" "hotfix branches are named" \
    hotfix/27.1.7_V2
assertRefused "the anchor release must be visible" "is not visible" \
    hotfix/27.1.9_hf
teardownFixture

echo "===== unversioned branch ====="
setupFixture
assertRefused "feature branches are not versioned here" "not a versioned branch" \
    feature/DSO-1234_something
teardownFixture

echo ""
echo "===== passed: $passCount, failed: $failCount ====="
[[ $failCount -eq 0 ]]
