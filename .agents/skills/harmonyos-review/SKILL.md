---
name: harmonyos-review
description: >-
  Review native HarmonyOS ArkTS and ArkUI repositories for concrete,
  source-evidenced defects in correctness, security, lifecycle and resource
  ownership, state management, concurrency, persistence, permissions,
  compatibility, and performance. Use for code review, bug hunting, release
  readiness, migration audits, or review of a diff, PR, module, or whole
  project. Report only findings demonstrated by reachable code and project
  configuration, with precise file and line references; use current official
  Huawei documentation for version-sensitive claims.
---

# HarmonyOS Code Review

Find real defects, not checklist-shaped speculation. Repository code and configuration establish what the application does; official Huawei documentation establishes version-sensitive platform contracts.

## 1. Fix the review scope

- Read repository instructions and inspect working-tree state before reviewing.
- Determine the requested boundary: diff/PR, files, module, subsystem, or whole repository.
- For change reviews, identify the exact base and inspect both the diff and affected call sites.
- Read `build-profile.json5`, `oh-package.json5`, `module.json5`, and related configuration to establish SDK levels, application model, devices, permissions, dependencies, and build variants.
- Do not modify code, create reports, assign grades, or estimate effort unless the user asks.

## 2. Map the relevant execution paths

Start broad, then follow evidence:

- Locate entry points, lifecycle callbacks, state owners, async boundaries, persistence operations, file operations, permissions, event subscriptions, and external inputs.
- Trace values and resources through callers and callees. Inspect cleanup, cancellation, retry, failure, and partial-success paths.
- Check tests and docs for intended behavior, but do not treat them as proof that production code is safe.
- Use focused searches to find candidates. A text match is a lead, never a finding.

Example reconnaissance commands:

```powershell
rg -n --glob '*.ets' --glob '*.ts' 'eventHub\.(on|off)|emitter\.(on|off)|setInterval|setTimeout'
rg -n --glob '*.ets' 'ResultSet|relationalStore|executeSql|beginTransaction|commit|rollBack'
rg -n --glob '*.ets' 'requestPermissionsFromUser|checkAccessToken|canIUse'
rg -n --glob '*.ets' --glob '*.json5' '(password|secret|token|api[_-]?key)'
rg -n --glob '*.json5' 'compileSdkVersion|compatibleSdkVersion|targetSdkVersion|requestPermissions'
```

Adapt patterns to the repository. Exclude generated, dependency, build-output, fixture, and test-data directories when they create noise.

## 3. Analyze only applicable categories

Load [references/checklist.md](references/checklist.md) and select categories supported by the scope:

- Correctness and error propagation
- Security, privacy, and sensitive data
- Lifecycle, resource ownership, and cancellation
- V1/V2 state management and concurrent updates
- RDB, Preferences, files, migration, and atomicity
- Permissions, SysCaps, devices, and API compatibility
- Network and external-input handling
- Performance issues with a concrete expensive path
- Tests covering changed or high-risk behavior

For platform-dependent claims, consult [references/official-docs.md](references/official-docs.md) and verify against current official Huawei documentation. Do not hard-code “current” API versions or infer a requirement from another framework.

## 4. Prove each finding

A reportable finding needs all of the following:

1. A precise source location.
2. A reachable trigger or execution path.
3. The incorrect behavior or violated project/platform contract.
4. A concrete user, data, security, compatibility, or operational impact.
5. Evidence that existing guards, cleanup, or callers do not already prevent it.

Before reporting, try to disprove the candidate:

- Read the complete function and relevant callers/callees.
- Check every success, error, cancellation, and teardown path.
- Search for compensating validation or cleanup elsewhere.
- Confirm the API/decorator/permission behavior for the project's actual SDK range.
- Distinguish production code from examples, generated code, dead code, and test fixtures.

Do not report style preferences, arbitrary size limits, generic “could be” risks, or scanner matches without demonstrated impact.

## 5. Assign severity from impact

- **Critical**: Exploitable security issue, irreversible data loss, or release-blocking failure on a core path.
- **High**: Likely crash, corruption, security/privacy breach, or core-feature failure.
- **Medium**: Real defect with narrower conditions, recoverable impact, or significant degradation.
- **Low**: Minor concrete defect with limited impact; omit pure polish unless requested.

Severity reflects impact and likelihood, not fix difficulty.

## 6. Report findings first

Unless the user requests a repository document, respond in the conversation. Use [references/report-template.md](references/report-template.md) only when a full Markdown artifact is requested.

Order findings by severity. Each finding should contain:

- `[severity] concise title`
- `path/to/file.ets:line`
- Trigger and evidence
- Impact
- Focused remediation
- Official source when the finding depends on a HarmonyOS contract

If no findings meet the evidence bar, say so explicitly. Then note coverage gaps and unrun validation separately; do not inflate them into findings.

## Exit criteria

- Scope and SDK/device assumptions are explicit.
- Every finding is source-evidenced and independently actionable.
- Platform claims are checked against the project's version range.
- Findings, open questions, and unverified risks are clearly separated.
- Tests/builds run are reported accurately; unrun checks are not described as passed.
