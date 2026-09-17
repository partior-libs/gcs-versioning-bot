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
##   branchName          e.g. main | release/27.1 | hotfix/27.1.7_hf
##   versionDeclaration  the VERSION file's content: a release line (27.1).
##                       Hotfix branches take their version from the branch
##                       name, so the declaration is not read there.
##   repoDir             repository to inspect (default: current directory)
##   devLabel            pre-release label for the build identifier (default: dev)
##
## Emits key=value lines on stdout:
##   target=27.1.8        the version being built toward; this goes in the pom
##   counter=3            successful builds so far for that target
##   version=27.1.8-dev.3 the build identifier; this becomes the git tag and
##                        the candidate container tag
##
## target and version are deliberately different. '-' means pre-release, so it
## is correct on a candidate but must never reach an artifact version: Maven
## orders 27.1.1-dev.2 ABOVE 27.1.1_hf.1, which would be wrong.
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

## Tags exactly one numeric segment below $1, and nothing deeper.
##
## Called with a release line (27.1) it returns that line's plain releases.
## Called with a Hotfix Line prefix (27.1.7_hf) it returns that ONE line's
## releases. The exact shape is what keeps the two apart: a glob on 27.1.*
## would also return 27.1.7_hf.1 and push a release branch onto a hotfix line,
## and a Variant Line must never see the General Line's tags.
function directChildTags() {
    gitInRepo tag -l | grep -E "^${1//./\\.}\.[0-9]+$" || true
}

## Anything released on a line, plain or hotfix. Used only to decide whether a
## mainline declaration has gone stale, where a hotfix counts as a shipment
## just as much as a patch does.
function anyReleaseTagsOfLine() {
    gitInRepo tag -l \
        | grep -E "^${1//./\\.}\.[0-9]+(_[a-z][a-z0-9]*\.[0-9]+)?$" || true
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
        ## A release branch only ever produces the line's next patch. Hotfixes
        ## come from a hotfix branch, so there is no override here: the
        ## declaration has exactly one meaning.
        line="${branchName#release/}"
        [[ "$versionDeclaration" =~ ^[0-9]+\.[0-9]+$ ]] \
            || refuse "on $branchName the declaration must be a release line (X.Y); got '$versionDeclaration'"
        [[ "$versionDeclaration" == "$line" ]] \
            || refuse "branch $branchName disagrees with the declaration '$versionDeclaration'"
        existing="$(directChildTags "$line")"
        [[ -n "$existing" ]] \
            || refuse "no release tags visible for line $line — the branch is cut at ${line}.0, so zero tags proves a shallow clone or unfetched tags"
        max="$(echo "$existing" | sort -V | tail -1)"
        target="${line}.$(( ${max##*.} + 1 ))"
        ;;
    hotfix/*)
        ## The branch suffix IS the version prefix, so there is no special case
        ## to get wrong: read the line id off the branch, count its own tags,
        ## take the next number.
        linePrefix="${branchName#hotfix/}"
        [[ "$linePrefix" =~ ^([0-9]+\.[0-9]+\.[0-9]+)_([a-z][a-z0-9]*)$ ]] \
            || refuse "hotfix branches are named hotfix/X.Y.Z_<label>, where <label> is 'hf' for the general line or a variant code matching [a-z][a-z0-9]*; got $branchName"
        frozen="${BASH_REMATCH[1]}"
        lineLabel="${BASH_REMATCH[2]}"

        ## 'dev' marks a candidate and lives on the other separator. Letting a
        ## line take it would produce strings nobody could read back.
        [[ "$lineLabel" == "$devLabel" ]] \
            && refuse "'$devLabel' is reserved for build candidates and cannot name a Hotfix Line"

        tagExists "$frozen" \
            || refuse "release tag $frozen is not visible — a hotfix branch is cut from the release it patches"

        hotfixTags="$(directChildTags "$linePrefix")"
        if [[ -n "$hotfixTags" ]]; then
            ## Wrong-anchor guard, per line: every shipped release of THIS line
            ## must be in this branch's history. Other lines are deliberately
            ## ignored, because a Variant Line is not expected to contain the
            ## General Line's fixes.
            while IFS= read -r shipped; do
                [[ -z "$shipped" ]] && continue
                gitInRepo merge-base --is-ancestor "$shipped" HEAD \
                    || refuse "shipped release $shipped is not in this branch's history — cut hotfix/$linePrefix from that line's LATEST tag"
            done <<< "$hotfixTags"
            max="$(echo "$hotfixTags" | sort -V | tail -1)"
            target="${linePrefix}.$(( ${max##*.} + 1 ))"
        else
            target="${linePrefix}.1"
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
