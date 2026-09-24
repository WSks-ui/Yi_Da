# 离线同步与任务续接

`entry/src/main/ets/service/WardrobeSync.ets` 和 `TaskContinuation.ets` 只提供纯数据状态机，不直接访问应用私有目录，也不假设网络或分布式数据 Kit 已接入。当前应用的“离线迁移”页面使用下方的 `WardrobeMigration` 文件包；它不是 `WardrobeSync` 后台同步。

衣橱快照通过 `createSyncEnvelope(snapshot, deviceId, revision, updatedAt)` 生成同步信封。信封包含 `deviceId`、`schemaVersion`、`revision`、`updatedAt`、`snapshotHash` 和 `snapshot`。接收方调用 `validateSyncEnvelope`、`WardrobeSyncCoordinator.merge`，按 `revision` 优先、`updatedAt` 解决同 revision 冲突；revision 与时间都相同但 hash 不同会返回 `manual` 冲突，保留本地快照并给出原因。

`InMemoryLocalSyncTransport` 会真实保存离线待发送消息并对重复消息幂等；`NoopLocalSyncTransport` 明确返回 `queued: false` 和“未发送”，所以不能把离线状态显示为已同步。后续接入分布式数据 Kit 时实现 `LocalSyncTransport` 即可替换传输层。

`exportSyncPackage` / `importSyncPackage` 是协议层的通用文本封装，用于不含设备私有文件引用的数据。它们不会复制图片，也不会把快照中的 `file://` URI 改写成目标设备 URI，因此不能直接迁移包含本地图片的 `DemoSnapshot`。真正搬运衣物、日记和试穿结果图片时，必须使用下方 `WardrobeMigration`。

`TaskContinuationQueue` 支持 `try-on`、`import`、`task` 三类任务，任务通过 `taskId` 幂等。`pause`、`resume`、`cancel`、`update`、`complete` 和 `fail` 都是可解释的状态转换；`serialize`/`restore` 只恢复任务记录，不会重新启动原任务的文件操作、抠图或试穿生成。当前应用没有把该队列持久化，也没有将任务内容接入迁移页面，因此不能宣称重启后或跨设备继续执行在途任务。需要持久化时注入实现 `ContinuationStore` 的适配器，不在队列内拼接文件路径。

## 图片迁移包

`WardrobeMigration.ets` 提供不依赖网络的跨设备迁移路径。`exportWardrobeMigration` 通过 `MigrationSourceFileAdapter.isPrivateUri/read` 读取衣物、日记和试穿结果引用的应用私有图片，写入 Base64 字节、大小和内容 hash；源 URI 会被 `migration-asset://asset-N` 占位符替换，不会写入包。默认单图上限为 8 MiB、图片总量 20 MiB、包大小 30 MiB、资产数量 100，可通过 `MigrationLimits` 收紧。

目标设备先调用 `prepareWardrobeMigration`。它只校验包、容量、Base64/hash、占位符和目标私有 URI，并返回重建 URI 后的候选快照，不提前写文件。UI 根据 `ready`、`stale`、`duplicate` 或 `conflict` 展示结果；`conflict` 必须向用户确认覆盖。随后调用 `commitWardrobeMigrationCandidate`，注入 `MigrationTargetFileAdapter` 与 `CandidateSnapshotCommitter`，按 `validate -> 写图片 -> commit -> publish` 执行。写入或快照提交失败会清理本次已写入 URI，`publish` 不会在 `commit` 前调用。

在真实设备上，`WardrobeMigrationHost.ets` 提供 CoreFileKit 与
DocumentViewPicker 适配：用 `createCoreFileMigrationAdapters(context.filesDir, limits)`
创建源/目标文件适配器；导出可调用
`exportWardrobeMigrationWithPicker(context, snapshot, deviceId, revision)`，导入可调用
`selectMigrationPackageWithPicker(context)`。Picker 结果通过 `status` 区分
`saved`、`selected`、`cancelled` 和 `failed`，用户取消会明确返回 `cancelled`，不会被当作失败或已完成。

迁移文件是未加密、未签名的 JSON 文本，图片以 Base64 保存。内容 hash 用于发现传输损坏，不提供来源认证或防篡改；文件可能包含用户衣物照片、日记和身材档案，应只保存到用户信任的位置。迁移图片只接受包含 PNG 签名的字节，目标文件使用 `.png` 扩展名和现有
`garment_batch_` 前缀，以便沿用孤儿图片清理规则；写入成功后文件会保留，失败时才清理半成品。
Picker 导出/导入受 UTF-8 字节大小限制。该流程仍是用户主动导出文件、在另一台设备选择文件并确认导入，不能显示为自动同步。
