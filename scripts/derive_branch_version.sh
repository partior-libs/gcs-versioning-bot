#!/bin/bash +e

## Derive a version number from the branch, its version declaration and the
## repository's existing release tags.
##
## Deliberately git-only: no Artifactory, no Jira, no controller config. Any
## workflow that needs "what version is this commit?" can call it, whether or
## not it is releasing anything.
##
## Usage:
##   derive_branch_version.sh <branchName> <versionDeclaration> [repoDir] [devLabel]
##
##   branchName          e.g. main | release/27.1 | hotfix/27.1.7
##   versionDeclaration  the VERSION file's content: a release line (27.1) or,
##                       exceptionally, a complete version (27.1.7.1)
##   repoDir             repository to inspect (default: current directory)
##   devLabel            pre-release label for the build identifier (default: dev)
##
## Emits key=value lines on stdout:
##   target=27.1.8
##   counter=3
##   version=27.1.8-dev.3
##
## Every refusal exits 1 with [ERROR] on stderr, so a caller fails loudly
## instead of versioning an artifact with a garbage number.

## Reading action's global setting
if [[ ! -z $BASH_SOURCE ]]; then
    ACTION_BASE_DIR=$(dirname $BASH_SOURCE)
    source $(find $ACTION_BASE_DIR/.. -type f -name general.ini)
elif [[ $(find . -type f -name general.ini | wc -l) > 0 ]]; then
    source $(find . -type f -name general.ini)
elif [[ $(find .. -type f -name general.ini | wc -l) > 0 ]]; then
    source $(find .. -type f -name general.ini)
else
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to find and source general.ini"
    exit 1
fi

branchName="$1"
versionDeclaration="$(echo "$2" | tr -d '[:space:]')"
repoDir="${3:-.}"
devLabel="${4:-dev}"

function refuse() {
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): $1" >&2
    exit 1
}

function gitInRepo() {
    git -C "$repoDir" "$@"
}

## Tags exactly one segment below $1 — the direct release children of a line
## (X.Y -> X.Y.Z) or of a released version (X.Y.Z -> X.Y.Z.H). Matching by
## exact segment count matters: a glob on 27.1.* also returns 27.1.7.1, which
## sorts above 27.1.7 and would push a release branch onto the hotfix series.
function childReleaseTags() {
    gitInRepo tag -l | grep -E "^${1//./\\.}\.[0-9]+$" || true
}

## Every release tag on a line, at any depth (X.Y.Z and X.Y.Z.H).
function anyReleaseTagsOfLine() {
    gitInRepo tag -l | grep -E "^${1//./\\.}\.[0-9]+(\.[0-9]+)?$" || true
}

function tagExists() {
    gitInRepo tag -l | grep -qxF "$1"
}

[[ -n "$branchName" ]] || refuse "branch name is required"
[[ -n "$versionDeclaration" ]] || refuse "version declaration is required (the VERSION file's content)"
gitInRepo rev-parse --git-dir >/dev/null 2>&1 || refuse "not a git repository: $repoDir"

target=""
case "$branchName" in
    main|master|develop)
        [[ "$versionDeclaration" =~ ^[0-9]+\.[0-9]+$ ]] \
            || refuse "on $branchName the declaration must be a release line (X.Y); got '$versionDeclaration'"
        ## A line's first release always comes from the mainline, so the target
        ## is that line's .0 — and the declaration is stale the moment the line
        ## has shipped anything at all.
        if [[ -n "$(anyReleaseTagsOfLine "$versionDeclaration")" ]]; then
            refuse "declaration names line $versionDeclaration but that line already has release tags — bump it after cutting the release branch"
        fi
        target="${versionDeclaration}.0"
        ;;
    release/*)
        line="${branchName#release/}"
        if [[ "$versionDeclaration" =~ ^[0-9]+\.[0-9]+$ ]]; then
            [[ "$versionDeclaration" == "$line" ]] \
                || refuse "branch $branchName disagrees with the declaration '$versionDeclaration'"
            existing="$(childReleaseTags "$line")"
            [[ -n "$existing" ]] \
                || refuse "no release tags visible for line $line — the branch is cut at ${line}.0, so zero tags proves a shallow clone or unfetched tags"
            max="$(echo "$existing" | sort -V | tail -1)"
            target="${line}.$(( ${max##*.} + 1 ))"
        elif [[ "$versionDeclaration" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
            ## Complete-version override: an in-place hotfix is a declared,
            ## reviewed decision, so it is taken verbatim.
            [[ "$versionDeclaration" == "$line".* ]] \
                || refuse "override '$versionDeclaration' is not on this branch's line $line"
            tagExists "$versionDeclaration" \
                && refuse "override target $versionDeclaration is already released"
            target="$versionDeclaration"
        else
            refuse "unparseable version declaration '$versionDeclaration'"
        fi
        ;;
    hotfix/*)
        frozen="${branchName#hotfix/}"
        [[ "$frozen" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
            || refuse "hotfix branches are named hotfix/X.Y.Z; got $branchName"
        tagExists "$frozen" \
            || refuse "release tag $frozen is not visible — a hotfix branch is cut from the release tag itself"
        hotfixTags="$(childReleaseTags "$frozen")"
        if [[ -n "$hotfixTags" ]]; then
            ## Wrong-anchor guard: every shipped hotfix of the frozen version
            ## must be in this branch's history, or building here would drop it.
            while IFS= read -r shipped; do
                [[ -z "$shipped" ]] && continue
                gitInRepo merge-base --is-ancestor "$shipped" HEAD \
                    || refuse "shipped hotfix $shipped is not in this branch's history — cut hotfix/$frozen from the frozen version's LATEST tag"
            done <<< "$hotfixTags"
            max="$(echo "$hotfixTags" | sort -V | tail -1)"
            target="${frozen}.$(( ${max##*.} + 1 ))"
        else
            target="${frozen}.1"
        fi
        ;;
    *)
        refuse "branch '$branchName' is not a versioned branch (main, release/*, hotfix/*)"
        ;;
esac

tagExists "$target" && refuse "derived target $target is already released"

## The counter distinguishes builds of one target, so it counts the build
## identifiers already minted for it rather than commits.
counter=$(( $(gitInRepo tag -l | grep -cE "^${target//./\\.}-${devLabel}\.[0-9]+$" || true) + 1 ))

echo "target=${target}"
echo "counter=${counter}"
echo "version=${target}-${devLabel}.${counter}"
