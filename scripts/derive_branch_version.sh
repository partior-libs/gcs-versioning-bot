#!/bin/bash +e

## Derive the Build Tag for a branch from the branch name, the declared Release
## Line, and the repository's existing tags.
##
## Deliberately git-only: no Artifactory, no Jira, no controller config. Any
## workflow that needs "what version is this commit?" can call it, whether or
## not it is releasing anything.
##
## Usage:
##   derive_branch_version.sh <branchName> <versionConfigFile> [repoDir] [devLabel]
##
##   branchName          main | release/27.1 | hotfix-base/27.1.30[_v2]
##   versionConfigFile   app-version.cfg, holding one KEY=VALUE per line:
##                           MAJOR-VERSION=27
##                           MINOR-VERSION=1
##                       Relative paths resolve against repoDir. Hotfix
##                       branches take their version from the branch name, so
##                       the file is not read there and need not exist.
##   repoDir             repository to inspect (default: current directory)
##   devLabel            label reserved for pull request builds (default: dev)
##
## Emits one key=value line on stdout:
##   version=27.1.31     the Build Tag, which is also the artifact version
##
## There is no separate target and no build label. A Build Tag numbers a
## commit; a release is a second tag (R27.1.1) added later by promotion. Pull
## request builds are the only ones carrying a label, and the workflow appends
## that itself because a pull request is never tagged.
##
## Every refusal exits 1 with [ERROR] on stderr, so a caller fails loudly
## instead of versioning an artifact with a garbage number.

## The bot's shared function library, which sources general.ini itself. Use it
## rather than repeating the lookup, so this script reads app-version.cfg
## through the same getVFileValue the rest of the bot uses.
if [[ -n "$BASH_SOURCE" ]] && [[ -f "$(dirname "$BASH_SOURCE")/bot-libs.sh" ]]; then
    source "$(dirname "$BASH_SOURCE")/bot-libs.sh"
else
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): Unable to find and source bot-libs.sh"
    exit 1
fi

branchName="$1"
versionConfigFile="${2:-app-version.cfg}"
repoDir="${3:-.}"
devLabel="${4:-dev}"

## Resolve the config relative to the repository unless given absolutely.
case "$versionConfigFile" in
    /*) versionConfigPath="$versionConfigFile" ;;
    *)  versionConfigPath="${repoDir%/}/$versionConfigFile" ;;
esac

function refuse() {
    echo "[ERROR] $BASH_SOURCE (line:$LINENO): $1" >&2
    exit 1
}

function gitInRepo() {
    git -C "$repoDir" "$@"
}

## Tags exactly one numeric segment below $1, and nothing deeper.
##
## Called with a Release Line (27.1) it returns that line's Build Tags. Called
## with a Hotfix Line prefix (27.1.30_hf) it returns that ONE line's Build
## Tags. The exact shape is what keeps the two apart: a glob on 27.1.* would
## also return 27.1.30_hf.1 and push a Release Branch onto a hotfix line, and a
## Variant Line must never see the General Line's tags.
function directChildTags() {
    gitInRepo tag -l | grep -E "^${1//./\\.}\.[0-9]+$" || true
}

function tagExists() {
    gitInRepo tag -l | grep -qxF "$1"
}

## A Release Branch for this line, local or on any remote. Its existence means
## the line has been cut, so the mainline should already have moved on.
function releaseBranchExists() {
    gitInRepo for-each-ref --format='%(refname)' \
        "refs/heads/release/$1" "refs/remotes/*/release/$1" 2>/dev/null \
        | grep -q .
}

## Highest numeric segment below $1, or empty when the line has no tags.
function highestChild() {
    local tags
    tags="$(directChildTags "$1")"
    [[ -z "$tags" ]] && return 0
    echo "$tags" | sort -V | tail -1 | sed 's/.*\.//'
}

## NOTE: refuse() inside this function exits only the SUBSHELL that $( )
## creates, and this script deliberately runs without `set -e`. Every caller
## must therefore write `x="$(readReleaseLine)" || exit 1`, or a refusal turns
## into an empty string and the run continues.
##
## Read the Release Line from app-version.cfg, which holds one KEY=VALUE per
## line:
##
##     MAJOR-VERSION=27
##     MINOR-VERSION=1
##
## The reading itself is getVFileValue from bot-libs.sh, so this script and
## get_latest_version.sh agree on what the file means. Its first two arguments
## are the bot's rule switches; both are true here, because a caller that asked
## for a release line has already decided it wants one. Read lazily, because a
## hotfix branch takes its version from the branch name and never needs this.
function readReleaseLine() {
    local major minor
    [[ -f "$versionConfigPath" ]] \
        || refuse "version config not found: $versionConfigPath"
    major="$(getVFileValue true true "$versionConfigPath" "MAJOR-VERSION")"
    minor="$(getVFileValue true true "$versionConfigPath" "MINOR-VERSION")"
    [[ -n "$major" && "$major" != "$VBOT_NIL" ]] \
        || refuse "MAJOR-VERSION is missing from $versionConfigPath"
    [[ -n "$minor" && "$minor" != "$VBOT_NIL" ]] \
        || refuse "MINOR-VERSION is missing from $versionConfigPath"
    [[ "$major" =~ ^[0-9]+$ ]] \
        || refuse "MAJOR-VERSION must be a whole number; got '$major'"
    [[ "$minor" =~ ^[0-9]+$ ]] \
        || refuse "MINOR-VERSION must be a whole number; got '$minor'"
    echo "${major}.${minor}"
}

[[ -n "$branchName" ]] || refuse "no branch name given"

case "$branchName" in
    main|master|develop)
        line="$(readReleaseLine)" || exit 1
        ## Once the Release Branch exists it owns this line's numbering, and
        ## the mainline should have been moved on automatically when the branch
        ## was cut. Both minting into one namespace is the failure this catches.
        if releaseBranchExists "$line"; then
            refuse "$versionConfigFile names line $line but release/$line already exists — the mainline should have moved to the next line when that branch was cut"
        fi
        highest="$(highestChild "$line")"
        ## A line's first build is .0. Every later commit takes the next
        ## number, whether or not the previous one produced an artifact.
        if [[ -z "$highest" ]]; then
            version="${line}.0"
        else
            version="${line}.$(( highest + 1 ))"
        fi
        ;;
    release/*)
        ## A Release Branch continues its line's numbering where the mainline
        ## stopped. The declaration must agree with the branch name, so a
        ## mis-cut branch cannot quietly mint into another line.
        line="${branchName#release/}"
        [[ "$line" =~ ^[0-9]+\.[0-9]+$ ]] \
            || refuse "release branches are named release/X.Y; got $branchName"
        declaredLine="$(readReleaseLine)" || exit 1
        [[ "$declaredLine" == "$line" ]] \
            || refuse "branch $branchName disagrees with the declaration '$declaredLine' in $versionConfigFile"
        highest="$(highestChild "$line")"
        [[ -n "$highest" ]] \
            || refuse "no build tags visible for line $line — the branch is cut at one, so zero proves a shallow clone or unfetched tags"
        version="${line}.$(( highest + 1 ))"
        ;;
    hotfix-base/*)
        ## The branch suffix is the anchor Build Tag plus an optional line
        ## label. No label means the General Hotfix Line, 'hf'. The anchor is
        ## fixed for the life of the branch, because a hotfix-base branch is
        ## cut once and then reused.
        suffix="${branchName#hotfix-base/}"
        [[ "$suffix" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(_([a-z][a-z0-9]*))?$ ]] \
            || refuse "hotfix branches are named hotfix-base/X.Y.Z for the general line or hotfix-base/X.Y.Z_<label> for a variant, where <label> matches [a-z][a-z0-9]*; got $branchName"
        anchor="${BASH_REMATCH[1]}"
        lineLabel="${BASH_REMATCH[3]:-hf}"

        ## 'dev' marks a pull request build. Letting a line take it would
        ## produce strings nobody could read back.
        [[ "$lineLabel" == "$devLabel" ]] \
            && refuse "'$devLabel' is reserved for pull request builds and cannot name a Hotfix Line"

        tagExists "$anchor" \
            || refuse "build tag $anchor is not visible — a hotfix branch is cut from the build it patches"

        linePrefix="${anchor}_${lineLabel}"
        highest="$(highestChild "$linePrefix")"
        if [[ -z "$highest" ]]; then
            version="${linePrefix}.1"
        else
            version="${linePrefix}.$(( highest + 1 ))"
        fi
        ;;
    *)
        refuse "branch '$branchName' is not a versioned branch (main, release/*, hotfix-base/*)"
        ;;
esac

tagExists "$version" && refuse "derived build tag $version already exists"

echo "version=${version}"
