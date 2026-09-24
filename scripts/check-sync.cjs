const fs = require('node:fs');
const assert = require('node:assert/strict');
const { test } = require('node:test');

// 桌面纯逻辑检查直接加载真实 .ets 文件；不模拟设备、网络或分布式数据 Kit。
const ts = require(process.argv[2] || 'typescript');
require.extensions['.ets'] = (loadedModule, filename) => {
  const source = fs.readFileSync(filename, 'utf8');
  const output = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  loadedModule._compile(output, filename);
};

const sync = require('../entry/src/main/ets/service/WardrobeSync.ets');
const continuation = require('../entry/src/main/ets/service/TaskContinuation.ets');

const snapshot = (name) => ({ version: 1, name, garments: [], saved: [] });

test('同步信封包含 deviceId/schemaVersion/revision/updatedAt/hash，hash 与字段顺序无关', () => {
  const first = sync.createSyncEnvelope(snapshot('初始'), 'phone-a', 3, '2026-09-24T00:00:00.000Z');
  const second = sync.createSyncEnvelope({ saved: [], garments: [], name: '初始', version: 1 },
    'phone-a', 3, '2026-09-24T00:00:00.000Z');
  assert.equal(first.deviceId, 'phone-a');
  assert.equal(first.schemaVersion, sync.SYNC_SCHEMA_VERSION);
  assert.equal(first.revision, 3);
  assert.equal(first.snapshotHash, second.snapshotHash);
  assert.equal(sync.deserializeSyncEnvelope(sync.serializeSyncEnvelope(first)).snapshotHash, first.snapshotHash);
});

test('InMemory 传输层真实保留离线消息，并对重复消息幂等', async () => {
  const transport = new sync.InMemoryLocalSyncTransport();
  const envelope = sync.createSyncEnvelope(snapshot('离线'), 'phone-a', 1, '2026-09-24T00:00:00.000Z');
  const first = await transport.enqueue(envelope);
  const duplicate = await transport.enqueue(envelope);
  assert.equal(first.accepted, true);
  assert.equal(first.queued, true);
  assert.equal(first.online, false);
  assert.equal(duplicate.message, '同步消息已在离线队列中');
  assert.equal(transport.pendingOutgoing().length, 1);
  assert.equal(transport.takeOutgoing().length, 1);
  assert.equal(transport.pendingOutgoing().length, 0);
});

test('Noop 传输层明确报告未同步，不制造已发送结果', async () => {
  const transport = new sync.NoopLocalSyncTransport();
  const result = await transport.enqueue(sync.createSyncEnvelope(snapshot('未联网'), 'phone-a', 1,
    '2026-09-24T00:00:00.000Z'));
  assert.equal(result.accepted, false);
  assert.equal(result.queued, false);
  assert.equal(result.online, false);
  assert.match(result.message, /未发送/);
});

test('同步 merge：重复消息、旧 revision、新 revision 按明确规则处理', async () => {
  const transport = new sync.InMemoryLocalSyncTransport();
  const coordinator = new sync.WardrobeSyncCoordinator('phone-a', snapshot('本地'), 2, transport,
    '2026-09-24T02:00:00.000Z');
  const newer = sync.createSyncEnvelope(snapshot('远端更新'), 'tablet-b', 3, '2026-09-24T03:00:00.000Z');
  const applied = coordinator.merge(newer);
  assert.equal(applied.status, 'applied');
  assert.equal(applied.accepted, true);
  assert.equal(applied.snapshot.name, '远端更新');
  assert.equal(coordinator.merge(newer).status, 'duplicate');

  const old = sync.createSyncEnvelope(snapshot('旧数据'), 'tablet-b', 1, '2026-09-24T04:00:00.000Z');
  assert.equal(coordinator.merge(old).status, 'stale');
  assert.equal(coordinator.currentEnvelope().snapshot.name, '远端更新');

  await coordinator.publish(snapshot('本地待发送'), 4, '2026-09-24T05:00:00.000Z');
  assert.equal(coordinator.pending().length, 1);
  assert.equal(transport.pendingOutgoing().length, 1);
});

test('同步 merge：相同 revision 的不同快照返回可解释冲突，并按 updatedAt 决策', () => {
  const coordinator = new sync.WardrobeSyncCoordinator('phone-a', snapshot('本地'), 5,
    new sync.NoopLocalSyncTransport(), '2026-09-24T05:00:00.000Z');
  const remoteNewer = sync.createSyncEnvelope(snapshot('远端较新'), 'tablet-b', 5, '2026-09-24T06:00:00.000Z');
  const conflict = coordinator.merge(remoteNewer);
  assert.equal(conflict.status, 'conflict');
  assert.equal(conflict.accepted, true);
  assert.equal(conflict.conflict.resolution, 'remote');
  assert.match(conflict.message, /updatedAt/);

  const sameTime = sync.createSyncEnvelope(snapshot('同时修改'), 'laptop-c', 5, '2026-09-24T06:00:00.000Z');
  const manual = coordinator.merge(sameTime);
  assert.equal(manual.status, 'conflict');
  assert.equal(manual.accepted, false);
  assert.equal(manual.conflict.resolution, 'manual');
  assert.match(manual.message, /人工/);
});

test('非法同步 payload 被拒绝：坏 JSON、坏 schema 和篡改 hash', () => {
  assert.throws(() => sync.deserializeSyncEnvelope('{bad json'), /合法 JSON/);
  const envelope = sync.createSyncEnvelope(snapshot('合法'), 'phone-a', 1, '2026-09-24T00:00:00.000Z');
  assert.throws(() => sync.deserializeSyncEnvelope(JSON.stringify({ ...envelope, schemaVersion: 999 })), /schemaVersion/);
  assert.throws(() => sync.deserializeSyncEnvelope(JSON.stringify({ ...envelope, snapshotHash: '00000000' })), /snapshotHash/);
  const coordinator = new sync.WardrobeSyncCoordinator('phone-a', snapshot('本地'));
  const rejected = coordinator.merge({ ...envelope, snapshotHash: '00000000' });
  assert.equal(rejected.status, 'rejected');
});

test('同步包可离线导出/导入，任务内容随包携带但不宣称已跨设备同步', () => {
  const envelope = sync.createSyncEnvelope(snapshot('可分享'), 'phone-a', 2, '2026-09-24T00:00:00.000Z');
  const packagePayload = sync.exportSyncPackage(envelope, '{"schemaVersion":1,"tasks":[]} ',
    '2026-09-24T01:00:00.000Z');
  const imported = sync.importSyncPackage(packagePayload);
  assert.equal(imported.format, sync.SYNC_PACKAGE_FORMAT);
  assert.equal(imported.envelope.snapshot.name, '可分享');
  assert.match(imported.continuationPayload, /tasks/);
  assert.throws(() => sync.importSyncPackage(JSON.stringify({ ...imported, format: 'other' })), /格式或版本/);
});

test('任务续接：try-on/import/task 都支持幂等入队、暂停恢复和取消', () => {
  const queue = new continuation.TaskContinuationQueue();
  const payload = { source: 'offline', scene: 'denim_skirt' };
  const created = queue.createTask('task-tryon-1', 'try-on', payload, '2026-09-24T00:00:00.000Z');
  assert.equal(created.changed, true);
  assert.equal(queue.createTask('task-tryon-1', 'try-on', payload).changed, false);
  assert.equal(queue.createTask('task-import-1', 'import').task.status, 'pending');
  assert.equal(queue.createTask('task-generic-1', 'task').task.status, 'pending');
  assert.equal(queue.start('task-tryon-1').task.status, 'running');
  assert.equal(queue.pause('task-tryon-1', '暂时离开页面').task.status, 'paused');
  assert.equal(queue.resume('task-tryon-1').task.status, 'running');
  assert.equal(queue.cancel('task-tryon-1', '用户取消').task.status, 'cancelled');
  assert.equal(queue.cancel('task-tryon-1').changed, false);
  assert.throws(() => queue.createTask('task-tryon-1', 'try-on', { scene: 'other' }), /其他任务内容/);
});

test('任务续接：序列化恢复保留状态，非法 payload 和重复 taskId 被拒绝', () => {
  const queue = new continuation.TaskContinuationQueue();
  queue.createTask('task-import-2', 'import', { uri: 'content://image' }, '2026-09-24T00:00:00.000Z');
  queue.start('task-import-2');
  queue.update('task-import-2', 0.5, '复制完成');
  const serialized = queue.serialize();
  const restored = continuation.deserializeContinuationQueue(serialized);
  assert.equal(restored.get('task-import-2').status, 'running');
  assert.equal(restored.get('task-import-2').progress, 0.5);
  restored.cancel('task-import-2', '恢复后取消');
  assert.equal(restored.get('task-import-2').cancelReason, '恢复后取消');

  assert.throws(() => continuation.deserializeContinuationQueue('{bad json'), /合法 JSON/);
  const bad = JSON.parse(serialized);
  bad.tasks.push({ ...bad.tasks[0] });
  assert.throws(() => continuation.deserializeContinuationQueue(JSON.stringify(bad)), /重复 taskId/);
  const invalid = JSON.parse(serialized);
  invalid.tasks[0].status = 'unknown';
  assert.throws(() => continuation.deserializeContinuationQueue(JSON.stringify(invalid)), /状态不支持/);
});
