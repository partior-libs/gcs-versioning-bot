# 06 - External Integrations & API Specifications

`gcs-versioning-bot` integrates with four primary external enterprise systems: **JFrog Artifactory**, **Docker Registry**, **JIRA Cloud / Server REST API**, and the **GitHub Actions Runtime**.

This document details the exact protocols, REST payloads, query languages, authentication headers, error codes, and response handling for each integration.

---

## 1. JFrog Artifactory Integration (AQL Pagination Protocol)

### 1.1 Overview & Requirements
When querying artifact history from Artifactory, repositories with thousands of builds can cause query timeouts or exceed JSON payload response limits. `gcs-versioning-bot` solves this using **Artifactory Query Language (AQL)** with a page-based pagination loop ($500$ items per page).

### 1.2 AQL Query Payload Format
The bot dynamically writes an `aql.json` query payload file during execution:

```json
items.find(
    { 
        "name": {"$match": "<ARTIFACT_NAME>-*"}, 
        "$or": [
            { "repo": "<TARGET_REPO>" },
            { "repo": "<DEV_REPO>" },
            { "repo": "<RELEASE_REPO>" }
        ], 
        "$or": [
            { "path": {"$match" : "<GROUP_PATH>/<ARTIFACT_NAME>"}},
            { "path": {"$match" : "<GROUP_PATH>/<ARTIFACT_NAME>/*"}}
        ]
    }
).sort({"$desc" : ["created"]}).offset(<OFFSET>).limit(500)
```

### 1.3 Execution & Pagination Protocol
- **Endpoint**: `POST <ARTIFACTORY_BASE_URL>/api/search/aql`
- **Headers**:
  - `Content-Type: text/plain`
  - Authentication: Basic Auth (`-u username:password`) or JFrog Access Token via `jf rt curl`.
- **Pagination Loop Algorithm**:
  1. Initialize `offset = 0`, `pageSize = 500`.
  2. Execute query payload.
  3. Inspect JSON response field `.results`. Count items ($N = \text{len}(\text{results})$).
  4. Append items to combined temporary JSON file (`versions-test.txt.combined.tmp`).
  5. If $N < 500$, break loop (last page reached).
  6. If $N == 500$, set `offset = offset + 500` and repeat.

### 1.4 Regex Version Extraction from Artifact Names
Once artifact names are retrieved, `extractAndStoreVersionFromArtifactName()` strips known prefixes/suffixes and validates SemVer format using regex:

$$\text{Regex}: \verb|^([0-9]+\.){2}[0-9]+(((-|\+)[0-9a-zA-Z]+\.[0-9]+)*(\+[0-9a-zA-Z]+\.[0-9\.]+)*$)|$$

---

## 2. Docker Registry API v2 Integration

When Docker image tags are used as the source of truth instead of Artifactory generic artifacts:

- **Endpoint**: `GET <REGISTRY_URL>/v2/<IMAGE_NAME>/tags/list`
- **Authentication**: Basic Auth or Bearer Token header (`Authorization: Bearer <TOKEN>`).
- **Processing**:
  1. Parses JSON `.tags[]` array.
  2. Filters tags matching current prepended version label.
  3. Sorts tag list using version sorting (`sort -V`).
  4. Returns the highest matching tag for DEV, RC, or Release scopes.

---

## 3. JIRA REST API Integration

`gcs-versioning-bot` automates JIRA release management, version creation, archiving, and issue tagging.

### 3.1 Fetch Project Details
- **Endpoint**: `GET <JIRA_BASE_URL>/rest/api/latest/project/<PROJECT_KEY>`
- **Headers**: `Accept: application/json`, Basic Auth (`-u user:token`).
- **Response**: Extracts `$.id` (e.g. `10024`) required for version creation payloads.

### 3.2 Create Release Version (`createArtifactNextVersionInJira`)
- **Endpoint**: `POST <JIRA_BASE_URL>/rest/api/2/version`
- **Headers**: `Content-Type: application/json`
- **Request Payload**:
  ```json
  {
    "projectId": "10024",
    "name": "RC_service-name-1.2.0-rc.3",
    "startDate": "2026-07-24",
    "releaseDate": "2026-08-07",
    "description": "https://github.com/partior-libs/my-repo/actions/runs/123456"
  }
  ```
- **Expected Status Code**: `201 Created`.

### 3.3 Update / Archive Version Status (`updateJiraVersion`)
- **Endpoint**: `PUT <JIRA_BASE_URL>/rest/api/3/version/<JIRA_VERSION_ID>`
- **Request Payload**:
  ```json
  {
    "archived": true,
    "released": false,
    "releaseDate": "2026-07-24"
  }
  ```
- **Expected Status Code**: `200 OK`.

### 3.4 Tag FixVersion on Commit Issues (`tagFixVersionInJira`)
- **Endpoint**: `PUT <JIRA_BASE_URL>/rest/api/3/issue/<JIRA_ISSUE_KEY>` (e.g., `PROJ-1234`)
- **Request Payload**:
  ```json
  {
    "update": {
      "fixVersions": [
        {
          "add": {
            "name": "RC_service-name-1.2.0-rc.3"
          }
        }
      ]
    }
  }
  ```
- **Expected Status Code**: `204 No Content`.

---

## 4. GitHub Actions Runtime Integration

### 4.1 Input Parameters & Workspace Injection
The composite action receives workflow arguments via standard GitHub Actions `with:` steps. Inputs are set as environment variables inside the runner container.

### 4.2 Output File Exports
`gcs-versioning-bot` exposes calculated version results to downstream workflow steps using GitHub Actions environment file commands:

1. **Step Outputs (`$GITHUB_OUTPUT`)**:
   ```bash
   echo "next-version=${calculatedVersion}" >> $GITHUB_OUTPUT
   echo "dev-version=${lastDevVersion}" >> $GITHUB_OUTPUT
   echo "rc-version=${lastRcVersion}" >> $GITHUB_OUTPUT
   echo "release-version=${lastRelVersion}" >> $GITHUB_OUTPUT
   ```

2. **Environment Variable Exports (`$GITHUB_ENV`)**:
   ```bash
   echo "BUILD_GH_VERSION_NEXT=${calculatedVersion}" >> $GITHUB_ENV
   ```
