# HarmonyOS evidence checklist

Use this as a routing guide, not a requirement to manufacture a finding in every category. Mark a category `N/A` when the reviewed path cannot exercise it.

## Project and compatibility

- Derive `compileSdkVersion`, `compatibleSdkVersion`, `targetSdkVersion`, device types, application model, and build variants from project files.
- Confirm that used APIs exist across the actual compatible SDK range.
- Check API-level, SysCap, device, application/atomic-service, and ArkTS-card restrictions where applicable.
- Check deprecated APIs only when the project still calls them; identify the supported replacement and migration impact.
- Check that fallback or gating behavior exists when an optional capability is unavailable.

## Correctness and error handling

- Trace input, mutation, output, and error paths across function boundaries.
- Confirm synchronous exceptions and promise rejections preserve actionable error information.
- Look for swallowed failures, false success results, incomplete rollback, and state updated before work succeeds.
- Check indexing, null/undefined handling, type assertions, serialization, parsing, and boundary values against reachable inputs.
- Check retry and duplicate invocation behavior for idempotency where mutations occur.

## Security and privacy

- Treat credential-like text as a lead. Confirm that it is a live secret rather than a key name, placeholder, fixture, or public identifier.
- Check signing configuration, tokens, credentials, private keys, and sensitive endpoints for accidental source control exposure.
- Trace untrusted input into SQL, file paths, URLs, Web components, commands, deserialization, and logs.
- Check TLS use, certificate validation, secret storage, cryptographic key ownership, and data-at-rest requirements against the threat model.
- Check logs and error messages for personal, authentication, business-sensitive, or file-content leakage.
- Check collection, storage, sharing, and deletion of personal data against declared behavior.

## Lifecycle and resource ownership

- Identify the owner and terminal cleanup path for each subscription, callback, timer, task, controller, file descriptor, `ResultSet`, database handle, socket, HTTP object, media object, and worker.
- Match registration and release using the same callback or handle identity.
- Check navigation away, component recreation, foreground/background transitions, ability termination, cancellation, and exception paths.
- Look for callbacks mutating destroyed UI state or stale task results overwriting newer state.
- Confirm cleanup APIs are called in lifecycle hooks where their contract permits the needed work.

## State management and concurrency

- Determine whether each component uses V1 or V2 semantics; do not assume mixing is invalid without checking the exact decorator combination and SDK.
- Confirm observed fields match the mutations that must refresh UI.
- Trace parent-child ownership, one-way/two-way update contracts, provider/consumer scope, and persistence bridges.
- Check overlapping saves, loads, requests, navigation events, and callbacks for lost updates or out-of-order completion.
- Check shared singleton, storage, event bus, and global state for initialization and teardown races.

## Persistence and files

- Ensure every `ResultSet` and file handle closes on success and failure.
- Check transaction begin/commit/rollback behavior, error propagation, and partial mutations.
- Check schema versioning and migration for existing user data; do not assume fresh-install behavior is sufficient.
- Validate security level and encryption choices against data sensitivity rather than requiring encryption universally.
- Check file paths, sandbox boundaries, URI handling, atomic replacement, overwrite behavior, and partial-write recovery.
- Check Preferences flush/persistence semantics only where durability timing affects behavior.

## Permissions and capabilities

- Compare declared permissions with reachable feature use.
- Verify permission type and request flow for the project's API range; not every declared permission is runtime-requestable.
- Check denial, cancellation, restricted-policy, and settings-revocation behavior.
- Request sensitive permissions in user context and only when the feature needs them.
- Verify access-token and context usage against the official API contract.
- Check that the app does not request unrelated permissions.

## Network and external services

- Check request-object lifecycle, cancellation, timeout, retry, duplicate submission, and response-size handling.
- Validate status codes, response types, JSON structure, redirects, and server-provided file names/paths.
- Check secure protocols and whether sensitive data appears in URLs or logs.
- Check WebSocket/socket listener cleanup and reconnect state.
- Check upload/download URI access, destination ownership, progress listener cleanup, and partial-file behavior.
- Separate platform defects from backend assumptions that cannot be verified locally.

## Performance

Report performance findings only when code evidence identifies avoidable work on a relevant path.

- Look for blocking I/O or expensive computation on UI-sensitive paths.
- Check unbounded lists, repeated parsing/allocation, excessive state updates, duplicate requests, and retained resources.
- Check lazy rendering/data-source contracts where large collections are reachable.
- Prefer profiler or benchmark evidence. If measurement is unavailable, state why the code path is predictably expensive.
- Do not use arbitrary file length, function length, nesting, coverage, frame-rate, or memory thresholds as defects.

## Tests and validation

- Check whether tests cover the changed or high-risk behavior, including failure and teardown paths.
- A missing test is usually coverage risk, not proof of a production defect.
- Run the narrowest relevant build/test commands when authorized and available.
- Record tools and paths not exercised, such as real devices, restricted accounts, network services, upgrades from old data, or release signing.
