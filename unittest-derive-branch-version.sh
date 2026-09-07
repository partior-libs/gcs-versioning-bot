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

function assertVersion() {
    ## assertVersion <description> <expectedVersion> <branch> <declaration>
    local description="$1" expected="$2" output actual
    output="$(derive "$3" "$4")"
    if [[ $? -ne 0 ]]; then
        echo "[FAIL] $description - refused unexpectedly: $output"
        failCount=$((failCount + 1))
        return
    fi
    actual="$(echo "$output" | grep '^version=' | cut -d= -f2)"
    if [[ "$actual" == "$expected" ]]; then
        echo "[PASS] $description"
        passCount=$((passCount + 1))
    else
        echo "[FAIL] $description - expected [$expected] but got [$actual]"
        failCount=$((failCount + 1))
    fi
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
git -C "$FIXTURE" tag 27.1.0-dev.1
assertVersion "counter counts build identifiers" "27.1.0-dev.2" main 27.1
assertRefused "mainline rejects a complete version" "must be a release line" main 27.1.0
git -C "$FIXTURE" tag 27.1.0
assertRefused "mainline declaration goes stale once the line ships" "already has release tags" main 27.1
teardownFixture

echo "===== mainline staleness counts hotfix-only lines ====="
setupFixture
git -C "$FIXTURE" tag 30.1.0.1
assertRefused "a hotfix-only line still counts as shipped" "already has release tags" main 30.1
teardownFixture

echo "===== release branch ====="
setupFixture
git -C "$FIXTURE" tag 27.1.0
assertVersion "infers the next patch" "27.1.1-dev.1" release/27.1 27.1
git -C "$FIXTURE" tag 27.1.1
git -C "$FIXTURE" tag 27.1.1.1
assertVersion "hotfix tags do not perturb patch inference" "27.1.2-dev.1" release/27.1 27.1
assertRefused "branch and declaration must agree" "disagrees with the declaration" release/27.2 27.1
teardownFixture

echo "===== release branch, shallow clone guard ====="
setupFixture
assertRefused "no visible line tags is a broken checkout" "shallow clone or unfetched tags" release/29.9 29.9
teardownFixture

echo "===== complete-version override ====="
setupFixture
git -C "$FIXTURE" tag 27.1.2
assertVersion "override is taken verbatim" "27.1.2.1-dev.1" release/27.1 27.1.2.1
git -C "$FIXTURE" tag 27.1.2.1
assertRefused "override cannot name a shipped version" "already released" release/27.1 27.1.2.1
assertRefused "override must be on the branch's line" "not on this branch's line" release/27.1 28.9.1
teardownFixture

echo "===== hotfix branch ====="
setupFixture
git -C "$FIXTURE" tag 27.1.7
assertVersion "first hotfix segment" "27.1.7.1-dev.1" hotfix/27.1.7 27.1
fixtureCommit "hotfix work"
git -C "$FIXTURE" tag 27.1.7.1
assertVersion "next hotfix segment" "27.1.7.2-dev.1" hotfix/27.1.7 27.1
assertRefused "malformed hotfix branch name" "named hotfix/X.Y.Z" hotfix/nonsense 27.1
assertRefused "frozen release must be visible" "is not visible" hotfix/9.9.9 27.1
teardownFixture

echo "===== hotfix wrong anchor ====="
setupFixture
git -C "$FIXTURE" tag 27.1.7
fixtureCommit "shipped hotfix"
git -C "$FIXTURE" tag 27.1.7.1
## Re-anchor at the release tag, which misses the shipped hotfix.
git -C "$FIXTURE" checkout -q 27.1.7
assertRefused "anchoring below the latest hotfix drops a shipped fix" "not in this branch's history" hotfix/27.1.7 27.1
teardownFixture

echo "===== unversioned branch ====="
setupFixture
assertRefused "feature branches are not versioned here" "not a versioned branch" feature/DSO-1234_something 27.1
teardownFixture

echo ""
echo "===== passed: $passCount, failed: $failCount ====="
[[ $failCount -eq 0 ]]
