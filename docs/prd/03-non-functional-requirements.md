# 03 - Non-Functional Requirements (NFRs)

This document defines the quality attributes, performance budgets, security guarantees, fault-tolerance mechanisms, and maintainability specifications for the Greenfield Automated Versioning Engine.

---

## 1. Performance & Scalability Specifications (NFR-PERF)

- **NFR-PERF-1 (Execution Latency Budget)**:
  - Total version calculation execution time (excluding external network latency) MUST NOT exceed **2.0 seconds**.
  - Total end-to-end workflow step execution time (including network API calls to Artifactory/JIRA) MUST NOT exceed **8.0 seconds** under nominal network conditions.
- **NFR-PERF-2 (Registry Pagination Scalability)**:
  - The registry discovery client MUST gracefully process repositories containing $> 50,000$ historical artifact entries without running into memory allocation limits (`OOM`) or payload size caps.
  - Page size for AQL queries MUST be fixed at $500$ items per request.
- **NFR-PERF-3 (Memory Footprint Ceiling)**:
  - The runtime memory footprint of the core versioning process MUST remain under **64 MB** during peak evaluation.

---

## 2. Security & Credential Isolation Specifications (NFR-SEC)

- **NFR-SEC-1 (Zero-Disk Persistence of Credentials)**: API tokens, registry passwords, and JIRA user secrets MUST NEVER be written to temporary disk files or committed to workspace logs.
- **NFR-SEC-2 (Log Redaction & Sanitization)**:
  - All debug output streams, HTTP curl logs, and command traces MUST automatically mask sensitive authorization headers (`Authorization: Bearer ***`, `-u user:***`).
- **NFR-SEC-3 (TLS / Transport Security)**:
  - All outbound API communication with artifact registries, Docker endpoints, and JIRA instances MUST use TLS 1.2 or higher over HTTPS.

---

## 3. Reliability, Fault Tolerance & Error Handling (NFR-REL)

- **NFR-REL-1 (Fail-Fast Execution on Error)**:
  - If a required configuration file is missing, or an API call to Artifactory/JIRA returns a fatal error status ($401, 403, 500$), the engine MUST log a clear error message with line context and exit immediately with exit code `1`.
- **NFR-REL-2 (Idempotency Guarantee)**:
  - Executing the versioning engine multiple times on the exact same commit without repository state changes MUST produce identical calculated versions and file modifications without causing file corruption.
- **NFR-REL-3 (File Backup Rollback & Clean Workspace)**:
  - If a file replacement operation fails mid-execution (e.g. `mvn versions:set` failure), the engine MUST clean up temporary working artifacts (`pom.xml.versionsBackup`, `*.tmp` files) to prevent repository contamination.

---

## 4. Maintainability, Modularity & Portability (NFR-MAINT)

- **NFR-MAINT-1 (Technology-Stack Portability)**:
  - The architecture and data contracts MUST be completely decoupled from shell-specific scripting dialects.
  - The system MUST be re-implementable in compiled languages (Go, Rust), managed languages (TypeScript, Java, Python), or native CI/CD plugins.
- **NFR-MAINT-2 (Strict Interface Separation)**:
  - Modules for **Registry Discovery**, **Decision Calculation**, **File Replacement**, and **Issue Tracker Sync** MUST be isolated behind clean programming interfaces or abstraction layers.
- **NFR-MAINT-3 (100% Test Coverage Requirement for Core Engine)**:
  - The core version calculation decision matrix MUST achieve 100% unit test statement and branch coverage across all combination permutations.

---

## 5. Developer Experience & Observability (NFR-UX)

- **NFR-UX-1 (Dry-Run / Unit-Test Execution Mode)**:
  - The engine MUST support a `--dry-run` or `isUnitTest` mode where version calculation occurs entirely in memory and outputs are logged to console without invoking external network mutation APIs or modifying source files.
- **NFR-UX-2 (Configurable Debug Verbosity)**:
  - When `is-debug` flag is enabled, the engine MUST output detailed scope state trees (`debugReleaseVersionVariables`) showing active feature flags, target branch regexes, matched commit tags, and intermediate version parts.
- **NFR-UX-3 (Human-Readable Error Classification)**:
  - Error messages MUST be prefixed with standardized severity tags:
    - `[ERROR]`: Fatal execution error forcing script exit.
    - `[ACTION_CURL_ERROR]`: Network/HTTP connection failure.
    - `[ACTION_RESPONSE_ERROR]`: HTTP response status code mismatch.
    - `[WARNING]`: Non-fatal warning condition where fallback logic is applied.
