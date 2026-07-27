# 04 - Domain Data Model & State Machine

This document defines the formal domain entities, data schemas, algebraic version precedence rules, state transition truth tables, and core state machines for the Greenfield Automated Versioning Engine.

---

## 1. Domain Entity Model & Schema Definitions

```
                     +---------------------------+
                     |       Configuration       |
                     +---------------------------+
                                   |
         +-------------------------+-------------------------+
         |                                                   |
         v                                                   v
+------------------+                               +------------------+
|   VersionScope   |                               | ArtifactRegistry |
| (MAJOR, MINOR,   |                               | (AQL / Docker /  |
|  PATCH, RC, DEV) |                               |  JIRA Source)    |
+------------------+                               +------------------+
         |                                                   |
         v                                                   v
+------------------+                               +------------------+
|    ScopeRule     |                               | ArtifactHistory  |
| (Branch, Tag,    |                               | (lastDev, lastRc,|
|  MsgTag, File)   |                               |  lastRel, base)  |
+------------------+                               +------------------+
         |                                                   |
         +-------------------------+-------------------------+
                                   |
                                   v
                         +-------------------+
                         |   VersionResult   |
                         |  (nextVersion)    |
                         +-------------------+
```

### 1.1 Data Schema Specifications

#### Entity: `Version`
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "raw_string": { "type": "string", "example": "1.2.3-rc.1+bld.103.1" },
    "major": { "type": "integer", "minimum": 0 },
    "minor": { "type": "integer", "minimum": 0 },
    "patch": { "type": "integer", "minimum": 0 },
    "prerelease": {
      "type": "object",
      "properties": {
        "identifier": { "type": "string", "enum": ["dev", "rc", "hf"] },
        "number": { "type": "integer", "minimum": 0 }
      }
    },
    "build_metadata": {
      "type": "object",
      "properties": {
        "identifier": { "type": "string" },
        "run_number": { "type": "integer" },
        "run_attempt": { "type": "integer" }
      }
    }
  },
  "required": ["raw_string", "major", "minor", "patch"]
}
```

#### Entity: `ArtifactHistory`
```json
{
  "type": "object",
  "properties": {
    "last_dev_version": { "type": "string", "nullable": true },
    "last_rc_version": { "type": "string", "nullable": true },
    "last_release_version": { "type": "string", "nullable": true },
    "last_base_version": { "type": "string", "nullable": true },
    "is_initial_version": { "type": "boolean", "default": false }
  }
}
```

---

## 2. SemVer 2.0.0 Precedence & Comparison Algebra

When comparing two version objects $V_A$ and $V_B$ to establish "highest existing version":

1. **Core Part Comparison**: Compare $MAJOR$, $MINOR$, $PATCH$ numerically in order:
   - If $V_A.major \neq V_B.major$, return $\text{max}(V_A.major, V_B.major)$.
   - If $V_A.minor \neq V_B.minor$, return $\text{max}(V_A.minor, V_B.minor)$.
   - If $V_A.patch \neq V_B.patch$, return $\text{max}(V_A.patch, V_B.patch)$.

2. **Pre-Release vs Release Precedence**:
   - A normal release version ($1.2.0$) has **higher precedence** than a pre-release version ($1.2.0-rc.1$) with identical $MAJOR.MINOR.PATCH$.
   $$\text{"1.2.0"} > \text{"1.2.0-rc.5"} > \text{"1.2.0-dev.12"}$$

3. **Numeric Pre-Release Comparison**:
   - Compare pre-release numeric suffixes as integers, **not as raw strings**:
   $$\text{"1.2.0-rc.10"} > \text{"1.2.0-rc.9"}$$

4. **Build Metadata Ignored in Precedence**:
   - Build metadata (`+bld.103.1`) MUST BE IGNORED when determining version precedence:
   $$\text{"1.2.0-rc.1+bld.103.1"} \equiv \text{"1.2.0-rc.1+bld.104.1"}$$

---

## 3. Core State Machine & Transition Rules Matrix

The state engine follows a deterministic finite state machine (FSM) during execution:

```
    [ UNINITIALIZED ]
            |
            v
  ( Query Registries )
            |
            +-----------------------> [ INITIAL_VERSION_STATE ]
            |                         ( Set is_initial = true, default 1.0.0 )
            v
  [ HISTORICAL_STATE_LOADED ]
  ( lastDev, lastRc, lastRel )
            |
            v
  ( Select Base X.Y.Z )
            |
            v
  [ BASE_CORE_SELECTED ]
            |
            +---> ( Core File Rule Enabled? ) ----> [ FILE_OVERRIDE_APPLIED ]
            |                                               |
            +---> ( Auto Core Triggered? ) ------> [ CORE_INCREMENTED ]
            |                                               |
            v                                               v
  [ BASE_CORE_FINALIZED ] <----------------------------------+
            |
            v
  ( Active Branch Scope? )
            |
            +---> ( Branch matches DEV ) --------> [ DEV_PRERELEASE_STATE ]
            |                                      ( Format: X.Y.Z-dev.N )
            |
            +---> ( Branch matches RC ) ---------> [ RC_PRERELEASE_STATE ]
            |                                      ( Format: X.Y.Z-rc.N )
            |
            +---> ( Branch matches Release ) ----> [ FULL_RELEASE_STATE ]
                                                   ( Format: X.Y.Z )
            |
            v
  [ OUTPUT_EXPORTED ]
```

---

## 4. Evaluation Truth Table for Scope Triggers

The following matrix governs state transitions during version generation:

| Current Branch | Scope Rules Enabled | Feature Flag Active? | Last Dev | Last RC | Last Rel | Trigger Msg Tag | Output Version Result |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| `feature/abc` | `DEV` active | Yes | `1.2.0-dev.2` | `1.2.0-rc.1` | `1.2.0` | None | `1.2.0-dev.3` |
| `feature/abc` | `DEV` + `MINOR` | Yes | `1.2.0-dev.2` | `1.2.0-rc.1` | `1.2.0` | `#minor` | `1.3.0-dev.1` |
| `release/1.2.0`| `RC` active | Yes | `1.2.0-dev.5` | `1.2.0-rc.1` | `1.2.0` | None | `1.2.0-rc.2` |
| `release/1.3.0`| `RC` active | Yes | `1.3.0-dev.10`| `None` | `1.2.0` | None | `1.3.0-rc.1` |
| `main` | `PATCH` active| Yes | `1.2.0-dev.5` | `1.2.0-rc.2` | `1.2.0` | None | `1.2.1` |
| `main` | `MAJOR` active| Yes | `1.2.0-dev.5` | `1.2.0-rc.2` | `1.2.0` | `#major,#major`| `3.0.0` |
| `hotfix/v1.2` | `HOTFIX` active| Yes | `1.2.0-dev.1` | `None` | `1.2.0` | None (`rebase=1.2.0`)| `1.2.0-hf.1` |
