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

- run: echo "building ${{ steps.version.outputs.version }}"
```

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `branch-name` | current ref | Branch to derive for. |
| `version-file` | `VERSION` | File declaring the release line. |
| `version-declaration` | — | Declaration value; overrides `version-file`. |
| `working-directory` | `.` | Repository to inspect. |
| `dev-label` | `dev` | Pre-release label in the build identifier. |

## Outputs

| Output | Example |
|---|---|
| `target` | `27.1.8` |
| `counter` | `3` |
| `version` | `27.1.8-dev.3` |

## Derivation rules

The declaration names a **release line** (`27.1`); the rest follows from tags:

| Branch | Target |
|---|---|
| `main` | the line's `.0` — a line's first release always comes from the mainline |
| `release/X.Y` | highest **three-segment** `X.Y.Z` tag + 1 |
| `hotfix/X.Y.Z` | frozen version from the branch name, next fourth segment |

A release branch may exceptionally declare a **complete** version
(`27.1.7.1`) to prepare an in-place hotfix; that is taken verbatim.

Tag matching is by exact segment count, never a glob: `27.1.*` would also match
the hotfix tag `27.1.7.1`, which sorts above `27.1.7` and would push a release
branch onto the hotfix series.

## Refusals

The script exits non-zero rather than emit a wrong number when:

- the mainline declaration names a line that already has release tags (stale
  after a branch cut — at any depth, so a hotfix-only line counts);
- a release branch sees no tags for its line (a shallow clone or unfetched
  tags, not a genuinely fresh line);
- the branch name and the declaration disagree;
- an override names a shipped version, or one off the branch's line;
- a hotfix branch is anchored below the frozen version's latest hotfix tag,
  which would silently drop a shipped fix;
- the derived target is already released.

## Tests

```bash
./unittest-derive-branch-version.sh
```

Builds disposable git repositories and drives every path and refusal above.
