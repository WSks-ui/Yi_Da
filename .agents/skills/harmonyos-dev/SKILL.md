---
name: harmonyos-dev
description: >-
  Develop, debug, refactor, or design native HarmonyOS applications with
  ArkTS, ArkUI, Stage model, and HarmonyOS Kits. Use for HarmonyOS feature
  implementation, UI and state-management work, device adaptation, permissions,
  networking, persistence, API migration, build failures, and architecture
  decisions. Inspect an existing project before choosing APIs, derive its SDK
  and device constraints from repository configuration, and verify
  version-sensitive guidance against current official Huawei documentation.
  Use harmonyos-review instead when the primary request is a code audit.
---

# HarmonyOS Development

Implement HarmonyOS work from repository evidence and current official documentation. Prefer a small verified change over a broad speculative rewrite.

## Workflow

### 1. Establish project context

For an existing repository, inspect before asking questions:

- Read repository instructions and the files relevant to the request.
- Locate `build-profile.json5`, `oh-package.json5`, `module.json5`, `app.json5`, and module-level configuration.
- Derive the compile/compatible/target SDK, Stage or FA model, device types, state-management generation, Kits, permissions, and build commands.
- Search for nearby implementations and preserve established architecture unless the task requires changing it.

For a greenfield request, ask only for decisions that materially affect the result: target devices, minimum compatible API, application or atomic service, and required system capabilities. Do not invent a default API version or device type.

### 2. Verify version-sensitive facts

Use this source order:

1. The repository's SDK configuration, generated types, compiler diagnostics, and installed SDK.
2. Current Huawei API reference for signatures, availability, permissions, SysCaps, errors, and deprecation.
3. Current Huawei development guides, release notes, best practices, and official samples.
4. Local reference files in this skill as navigation and review checklists.

Treat local references as snapshots, not authority. Recheck any API name, signature, decorator constraint, permission, availability level, or lifecycle behavior before relying on it. If official material is unavailable, say what remains unverified and avoid presenting inference as fact.

When external research is needed, use an available documentation or browsing tool and restrict technical claims to official Huawei sources. Do not require a particular tool such as Context7.

### 3. Design the smallest coherent change

- State the compatibility and device assumptions that affect the implementation.
- Keep V1 and V2 state-management patterns consistent within a component boundary unless performing an explicit migration.
- Check API-level, device, SysCap, permission, and application-form constraints before selecting a Kit API.
- Plan ownership and cleanup for subscriptions, timers, network handles, `ResultSet` objects, files, controllers, and other resources.
- Preserve error semantics. Handle `BusinessError` and rejected promises where the API contract requires it; do not silently swallow failures.
- Prefer resources and adaptive layouts over hard-coded strings, colors, sizes, and single-device assumptions.

Load only the relevant reference:

- State and reactivity: [references/state-management.md](references/state-management.md)
- ArkUI and device adaptation: [references/ui-components.md](references/ui-components.md)
- Preferences, RDB, and files: [references/data-persistence.md](references/data-persistence.md)
- HTTP, WebSocket, sockets, and transfers: [references/network.md](references/network.md)
- Permission declaration and runtime authorization: [references/permissions.md](references/permissions.md)
- Measurement-led performance work: [references/performance.md](references/performance.md)

### 4. Implement in repository style

- Edit the existing seam rather than creating a parallel abstraction without evidence.
- Keep ArkTS types explicit and compatible with the project's compiler rules.
- Reuse project logging, error, dependency-injection, navigation, resource, and test conventions.
- For API migrations, separate mechanical compatibility edits from behavior changes.
- Do not change unrelated code or generated artifacts.

### 5. Verify

Run the narrowest relevant checks first, then broader checks when available:

- Compile or build the affected module.
- Run related unit, integration, UI, or Hvigor tests.
- Inspect diagnostics for API compatibility and ArkTS constraints.
- For UI work, verify the affected device classes, orientations, themes, font scaling, and empty/error/loading states that are in scope.
- For lifecycle work, exercise creation, background/foreground, navigation away, and teardown paths where practical.

If a required environment, SDK, device, account, or service is unavailable, report the exact unverified boundary. Never describe an unrun check as passed.

## Source and response policy

Cite official Huawei documentation for material version-sensitive claims or when the user asks for sources. Put citations next to the supported claim. Do not add decorative quotations or claim that local examples are official requirements.

For implementation tasks, finish with:

- What changed and where.
- Compatibility assumptions.
- Verification run and its result.
- Remaining unverified items or risks.

For explanation-only requests, answer directly; do not mutate the repository unless asked.
