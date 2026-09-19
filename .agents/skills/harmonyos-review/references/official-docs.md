# Official Huawei documentation routing

Official documentation changes independently of this skill. Open the current page and verify the project's API range before using a platform claim in a finding.

## Primary entry points

- [HarmonyOS documentation center](https://developer.huawei.com/consumer/cn/doc/)
- [HarmonyOS version and release notes](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/overview-allversion)
- [Application development guide](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/application-dev-guide)
- [API reference introduction](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/development-intro-api)
- [Application development best practices](https://developer.huawei.com/consumer/cn/best-practices/)

Do not encode a “current recommended API” in the review. Read the repository configuration first, then use release notes only to explain support or migration consequences.

## What to verify in an API reference

For every platform-dependent finding, check the exact symbol and note:

- API level introduced, changed, or deprecated.
- Supported devices and application forms.
- Required SysCaps and permissions.
- Stage/FA model or UI/card restrictions.
- Parameter, return, error-code, exception, and async behavior.
- Resource release or listener unregister contract.
- Replacement API and compatibility notes, when deprecated.

Link to the closest page that proves the finding. A documentation landing page is insufficient when a symbol-specific page is available.

## Topic routing

- ArkTS and state management: development guide sections for ArkTS, decorators, V1/V2 migration, and component lifecycle.
- ArkUI: component API reference, rendering control, navigation, accessibility, and multi-device layout guidance.
- Data: ArkData guides and references for Preferences, RDB, distributed data, and migration.
- Files: Core File Kit guides and references for file I/O, URI access, and picker behavior.
- Network: Network Kit and Basic Services Kit references for HTTP, WebSocket, sockets, upload, and download.
- Permissions: permission guide, permission list, and Ability Kit API reference.
- Security/privacy: HarmonyOS security, privacy, Universal Keystore Kit, and application best-practice pages.
- Performance: performance best practices and official profiling/tool documentation.

## Evidence labels

Keep these distinct in notes and reports:

- **Code fact**: directly shown by repository code/configuration.
- **Platform fact**: verified in current official documentation for the project's version.
- **Inference**: logical consequence of code and platform facts; explain the chain.
- **Unverified**: needs runtime, backend, device, account, signing, or documentation access.

Community posts may help find terminology, but do not use them as the sole support for a platform-contract finding.
