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

function derive() {
    ## derive <branch> <declaration>
    "$SCRIPT_ABS" "$1" "$2" "$FIXTURE" 2>&1
}

function assertField() {
    ## assertField <field> <description> <expected> <branch> <declaration>
    local field="$1" description="$2" expected="$3" output actual
    output="$(derive "$4" "$5")"
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
    ## assertRefused <description> <expectedReasonPattern> <branch> <declaration>
    local description="$1" pattern="$2" output
    output="$(derive "$3" "$4")"
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
assertVersion "mainline derives the line's .0" "27.1.0-dev.1" main 27.1
assertTarget "the target carries no build label" "27.1.0" main 27.1
git -C "$FIXTURE" tag 27.1.0-dev.1
assertVersion "counter counts build identifiers" "27.1.0-dev.2" main 27.1
assertRefused "mainline rejects a complete version" "must be a release line" main 27.1.0
git -C "$FIXTURE" tag 27.1.0
assertRefused "mainline declaration goes stale once the line ships" "already has release tags" main 27.1
teardownFixture

echo "===== mainline staleness counts hotfix-only lines ====="
setupFixture
git -C "$FIXTURE" tag 30.1.0_hf.1
assertRefused "a line whose only release is a hotfix still counts as shipped" \
    "already has release tags" main 30.1
teardownFixture

echo "===== release branch ====="
setupFixture
git -C "$FIXTURE" tag 27.1.0
assertVersion "infers the next patch" "27.1.1-dev.1" release/27.1 27.1
assertTarget "the pom version is the plain patch" "27.1.1" release/27.1 27.1
git -C "$FIXTURE" tag 27.1.1
git -C "$FIXTURE" tag 27.1.1_hf.1
assertVersion "hotfix tags do not perturb patch inference" "27.1.2-dev.1" release/27.1 27.1
assertRefused "branch and declaration must agree" "disagrees with the declaration" release/27.2 27.1
teardownFixture

echo "===== release branch, shallow clone guard ====="
setupFixture
assertRefused "no visible line tags is a broken checkout" "shallow clone or unfetched tags" \
    release/29.9 29.9
teardownFixture

echo "===== the complete-version override is withdrawn ====="
setupFixture
git -C "$FIXTURE" tag 27.1.1
assertRefused "a release branch no longer accepts a complete version" \
    "must be a release line" release/27.1 27.1.1_hf.1
teardownFixture

echo "===== general hotfix line ====="
setupFixture
git -C "$FIXTURE" tag 27.1.7
assertVersion "first hotfix on the general line" "27.1.7_hf.1-dev.1" hotfix/27.1.7_hf 27.1
assertTarget "the pom version is the hotfix version" "27.1.7_hf.1" hotfix/27.1.7_hf 27.1
fixtureCommit "hotfix work"
git -C "$FIXTURE" tag 27.1.7_hf.1
assertVersion "next hotfix on the same line" "27.1.7_hf.2-dev.1" hotfix/27.1.7_hf 27.1
teardownFixture

echo "===== variant hotfix line ====="
setupFixture
git -C "$FIXTURE" tag 27.1.7
assertVersion "first hotfix on a variant line" "27.1.7_v2.1-dev.1" hotfix/27.1.7_v2 27.1
fixtureCommit "variant work"
git -C "$FIXTURE" tag 27.1.7_v2.1
assertVersion "next hotfix on the variant line" "27.1.7_v2.2-dev.1" hotfix/27.1.7_v2 27.1
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
    hotfix/27.1.7_v2 27.1
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
    "not in this branch's history" hotfix/27.1.7_hf 27.1
teardownFixture

echo "===== hotfix branch naming ====="
setupFixture
git -C "$FIXTURE" tag 27.1.7
assertRefused "a hotfix branch must carry a label" "hotfix branches are named" \
    hotfix/27.1.7 27.1
assertRefused "the dev label is reserved for candidates" "reserved" \
    hotfix/27.1.7_dev 27.1
assertRefused "a variant of a variant is refused" "hotfix branches are named" \
    hotfix/27.1.7_v2_v5 27.1
assertRefused "a label must start with a letter" "hotfix branches are named" \
    hotfix/27.1.7_2v 27.1
assertRefused "an uppercase label is refused" "hotfix branches are named" \
    hotfix/27.1.7_V2 27.1
assertRefused "the anchor release must be visible" "is not visible" \
    hotfix/27.1.9_hf 27.1
teardownFixture

echo "===== unversioned branch ====="
setupFixture
assertRefused "feature branches are not versioned here" "not a versioned branch" \
    feature/DSO-1234_something 27.1
teardownFixture

echo ""
echo "===== passed: $passCount, failed: $failCount ====="
[[ $failCount -eq 0 ]]
