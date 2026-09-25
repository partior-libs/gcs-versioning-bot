# Derive Branch Version

Derives a version number from the branch, its version declaration and the
repository's existing release tags.

Git-only by design — no Artifactory, no Jira, no controller config — so it is
usable from any workflow that needs "what version is this commit?", whether or
not that workflow is releasing anything.

## Usage

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0            # tags drive the derivation

- id: version
  uses: partior-libs/gcs-versioning-bot/derive-branch-version@feature/derive-branch-version

# `version` is the Build Tag AND the artifact version. A release is a second
# tag (R27.1.1) added later by promotion, so there is nothing else to read.
- run: |
    echo "build tag / pom version: ${{ steps.version.outputs.version }}"
```

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `branch-name` | current ref | Branch to derive for. On a pull request pass the **base** branch. |
| `version-file` | `app-version.cfg` | Config declaring the release line as `MAJOR-VERSION=` and `MINOR-VERSION=`. |
| `working-directory` | `.` | Repository to inspect. |
| `dev-label` | `dev` | Label reserved for pull request builds; a hotfix line may not take it. |

## Outputs

| Output | Example |
|---|---|
| `version` | `27.1.31`, or `27.1.30_hf.2` on a hotfix line |

## Derivation rules

The release line comes from `app-version.cfg`, which holds one `KEY=VALUE` per line:

```
MAJOR-VERSION=27
MINOR-VERSION=1
```

Keys are anchored, so `APP-MAJOR-VERSION` is not mistaken for `MAJOR-VERSION`, and any other
key in the file is ignored. From that line, the rest follows from tags:

| Branch | Build Tag |
|---|---|
| `main` | highest `X.Y.Z` on the line + 1, starting at `X.Y.0` |
| `release/X.Y` | highest `X.Y.Z` on the line + 1, continuing where the mainline stopped |
| `hotfix-base/X.Y.Z[_<label>]` | next `.N` on that one hotfix line, starting at `.1` |

Every commit takes the next number. A failed build, or a commit that produces
no artifact, still consumes one, so the number counts nothing and some Build
Tags name no artifact. That is accepted: a Build Tag identifies a commit's
build, and releases are identified by Milestone Tags instead.

A hotfix branch names its anchor and its line. `hotfix-base/27.1.30` is the
**general line** for build `27.1.30` and produces `27.1.30_hf.1`,
`27.1.30_hf.2`, and so on. A suffix names a **variant line**, such as
`hotfix-base/27.1.30_v2` producing `27.1.30_v2.1`. Lines are independent: each
counts only its own tags, so a variant never continues the general line's
numbering and is never refused for lacking its fixes. The branch is cut once
and reused, so its anchor never changes.

`_` marks a version that comes after its build. `-` means pre-release and is
used only for the pull request label, which never reaches a tag. `+` would be
the SemVer-correct way to say "same version, different build", but container
tags forbid it.

Milestone tags (`R27.1.1`) are invisible here. They never affect numbering, and
tag matching is by exact shape rather than a glob, so `27.1.*` cannot pull
`27.1.30_hf.1` into a release line's count.

## Refusals

The script exits non-zero rather than emit a wrong number when:

- `app-version.cfg` is missing, or lacks `MAJOR-VERSION` or `MINOR-VERSION`, or either is
  not a whole number;
- the mainline declares a line whose `release/X.Y` branch already exists, which
  means the mainline was not moved on when that branch was cut and both would
  mint into one namespace;
- a release branch sees no tags for its line, which means a shallow clone or
  unfetched tags rather than a genuinely fresh line;
- the branch name and the declared line disagree;
- a hotfix branch name does not match `X.Y.Z[_<label>]`, or its label is `dev`,
  which is reserved for pull request builds;
- the build a hotfix branch is anchored at is not visible;
- the derived Build Tag already exists.

## Tests

```bash
./unittest-derive-branch-version.sh
```

Builds disposable git repositories and drives every path and refusal above.
