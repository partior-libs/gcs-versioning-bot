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

# `target` goes in the pom. `version` becomes the git tag and the image tag.
- run: |
    echo "pom version:   ${{ steps.version.outputs.target }}"
    echo "build tag:     ${{ steps.version.outputs.version }}"
```

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `branch-name` | current ref | Branch to derive for. |
| `version-file` | `app-version.cfg` | Config declaring the release line as `MAJOR-VERSION=` and `MINOR-VERSION=`. |
| `working-directory` | `.` | Repository to inspect. |
| `dev-label` | `dev` | Pre-release label in the build identifier. |

## Outputs

| Output | Example |
|---|---|
| `target` | `27.1.8` |
| `counter` | `3` |
| `version` | `27.1.8-dev.3` |

## Derivation rules

The release line comes from `app-version.cfg`, which holds one `KEY=VALUE` per line:

```
MAJOR-VERSION=26
MINOR-VERSION=1
```

Keys are anchored, so `APP-MAJOR-VERSION` is not mistaken for `MAJOR-VERSION`, and any other
key in the file is ignored. From that line, the rest follows from tags:

| Branch | Target |
|---|---|
| `main` | the line's `.0`, because a line's first release always comes from the mainline |
| `release/X.Y` | highest **three-segment** `X.Y.Z` tag + 1 |
| `hotfix/X.Y.Z_<label>` | the branch suffix is the version prefix; next `.N` on that line |

A hotfix branch names its own line. `hotfix/27.1.7_hf` is the **general line**
for release `27.1.7` and produces `27.1.7_hf.1`, `27.1.7_hf.2`, and so on. A
label other than `hf` names a **variant line**, such as `hotfix/27.1.7_v2`
producing `27.1.7_v2.1`. Lines are independent: each counts only its own tags,
so a variant never continues the general line's numbering and is never refused
for lacking its fixes.

Separators carry meaning here. `-` means pre-release, so it is used only for
the `-dev.N` build label. `_` marks a version that comes after its release.
`+` would be the SemVer-correct way to say "same version, different build",
but container tags forbid it.

Tag matching is by exact shape, never a glob: `27.1.*` would also match
`27.1.7_hf.1` and push a release branch onto a hotfix series.

## Refusals

The script exits non-zero rather than emit a wrong number when:

- `app-version.cfg` is missing, or lacks `MAJOR-VERSION` or `MINOR-VERSION`, or either is
  not a whole number;
- the mainline config names a line that already has release tags, which is
  stale after a branch cut. A hotfix-only line counts as shipped;
- a release branch sees no tags for its line, which means a shallow clone or
  unfetched tags rather than a genuinely fresh line;
- the branch name and the declared line disagree;
- a hotfix branch name does not match `X.Y.Z_<label>`, or its label is `dev`,
  which is reserved for build candidates;
- the release a hotfix branch patches is not visible;
- a hotfix branch is anchored below the latest tag **of its own line**, which
  would silently drop a shipped fix;
- the derived target is already released.

## Tests

```bash
./unittest-derive-branch-version.sh
```

Builds disposable git repositories and drives every path and refusal above.
