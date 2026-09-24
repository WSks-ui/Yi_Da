const fs = require('node:fs');
const assert = require('node:assert/strict');
const { test } = require('node:test');

// 桌面纯逻辑检查加载真实 .ets 迁移服务，不模拟系统文件 Kit 或设备分享能力。
const ts = require(process.argv[2] || 'typescript');
require.extensions['.ets'] = (loadedModule, filename) => {
  const source = fs.readFileSync(filename, 'utf8');
  const output = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  loadedModule._compile(output, filename);
};

const migration = require('../entry/src/main/ets/service/WardrobeMigration.ets');
const sync = require('../entry/src/main/ets/service/WardrobeSync.ets');

const sourceBytes = new Map([
  ['private://shirt.png', Uint8Array.from([1, 2, 3, 4])],
  ['private://diary.png', Uint8Array.from([8, 7, 6])]
]);

const source = {
  isPrivateUri(uri) { return uri.startsWith('private://'); },
  read(uri) {
    const bytes = sourceBytes.get(uri);
    if (!bytes) throw new Error('source missing');
    return bytes;
  }
};

function snapshot() {
  return {
    version: 1,
    garments: [{ id: 'g1', imageUri: 'private://shirt.png' }],
    diary: [{ id: 'd1', photoUri: 'private://diary.png' }],
    tryOnTasks: [{ id: 't1', resultUris: ['private://shirt.png'] }]
  };
}

function makeTarget(options = {}) {
  const files = new Map();
  const writes = [];
  const removals = [];
  return {
    files,
    writes,
    removals,
    isPrivateUri(uri) { return uri.startsWith('target://'); },
    destinationUri(assetId, packageId) {
      if (options.badPath) return 'target://../escape/' + assetId;
      return 'target://' + packageId + '/' + assetId + '.bin';
    },
    write(uri, bytes) {
      writes.push(uri);
      if (options.failOnWrite && writes.length === options.failOnWrite) {
        files.set(uri, Uint8Array.from(bytes));
        throw new Error('写入失败');
      }
      files.set(uri, Uint8Array.from(bytes));
    },
    remove(uri) {
      removals.push(uri);
      files.delete(uri);
    }
  };
}

test('导出包含私有图片字节、hash 和占位 URI，不泄露源路径', async () => {
  const payload = await migration.exportWardrobeMigration(snapshot(), source, 'phone-a', 3,
    '2026-09-24T00:00:00.000Z', '{"schemaVersion":1,"tasks":[]}', undefined,
    '2026-09-24T01:00:00.000Z');
  assert.equal(payload.includes('private://'), false);
  const data = JSON.parse(payload);
  assert.equal(data.assets.length, 2);
  assert.equal(data.totalImageBytes, 7);
  assert.equal(data.envelope.snapshot.garments[0].imageUri, 'migration-asset://asset-0');
  assert.equal(data.envelope.snapshot.tryOnTasks[0].resultUris[0], 'migration-asset://asset-0');
  assert.equal(data.assets[0].contentHash, migration.computeByteHash(sourceBytes.get('private://shirt.png')));
});

test('导出拒绝外部 URI 和容量超限，避免把不可迁移引用写入包', async () => {
  await assert.rejects(
    migration.exportWardrobeMigration({ ...snapshot(), garments: [{ id: 'g1', imageUri: 'content://external' }] }, source,
      'phone-a', 1, '2026-09-24T00:00:00.000Z'),
    /私有图片 URI/
  );
  await assert.rejects(
    migration.exportWardrobeMigration(snapshot(), source, 'phone-a', 1, '2026-09-24T00:00:00.000Z', '',
      { maxImageBytes: 2, maxTotalImageBytes: 4 }),
    /单张迁移图片/
  );
});

test('导入只构造候选快照，提交成功后按 commit 再 publish，并重建目标 URI', async () => {
  const payload = await migration.exportWardrobeMigration(snapshot(), source, 'phone-a', 3,
    '2026-09-24T00:00:00.000Z');
  const target = makeTarget();
  const prepared = await migration.prepareWardrobeMigration(payload, target);
  assert.equal(prepared.status, 'ready');
  assert.equal(target.writes.length, 0, '准备阶段不能提前写目标文件');
  assert.match(prepared.candidate.snapshot.garments[0].imageUri, /^target:\/\//);
  assert.equal(prepared.candidate.snapshot.tryOnTasks[0].resultUris[0], prepared.candidate.snapshot.garments[0].imageUri);

  const events = [];
  const result = await migration.commitWardrobeMigrationCandidate(prepared.candidate, target, {
    validate() { events.push('validate'); },
    commit() { events.push('commit'); },
    publish() { events.push('publish'); }
  });
  assert.deepEqual(events, ['validate', 'commit', 'publish']);
  assert.equal(result.committed, true);
  assert.equal(result.published, true);
  assert.equal(target.files.size, 2);
});

test('迁移到新设备后仍可再次导出，衣物、日记和试穿图片字节保持一致', async () => {
  const firstPayload = await migration.exportWardrobeMigration(snapshot(), source, 'phone-a', 3,
    '2026-09-24T00:00:00.000Z');
  const firstTarget = makeTarget();
  const firstPrepared = await migration.prepareWardrobeMigration(firstPayload, firstTarget);
  assert.equal(firstPrepared.status, 'ready');
  let firstSaved = undefined;
  await migration.commitWardrobeMigrationCandidate(firstPrepared.candidate, firstTarget, {
    commit(value) { firstSaved = value; },
    publish() {}
  });
  assert.deepEqual(firstSaved, firstPrepared.candidate.snapshot);

  // 把第一次恢复后的文件当作平板本机 filesDir，再走一遍生产导出/导入服务。
  const restoredSource = {
    isPrivateUri(uri) { return firstTarget.files.has(uri); },
    read(uri) {
      const bytes = firstTarget.files.get(uri);
      if (!bytes) throw new Error('restored image missing');
      return bytes;
    }
  };
  const secondPayload = await migration.exportWardrobeMigration(firstSaved, restoredSource, 'tablet-b', 4,
    '2026-09-24T02:00:00.000Z');
  const secondTarget = makeTarget();
  const secondPrepared = await migration.prepareWardrobeMigration(secondPayload, secondTarget);
  assert.equal(secondPrepared.status, 'ready');
  let secondSaved = undefined;
  await migration.commitWardrobeMigrationCandidate(secondPrepared.candidate, secondTarget, {
    commit(value) { secondSaved = value; },
    publish() {}
  });

  assert.equal(secondSaved.garments[0].id, 'g1');
  assert.equal(secondSaved.diary[0].id, 'd1');
  assert.equal(secondSaved.tryOnTasks[0].id, 't1');
  assert.equal(secondSaved.tryOnTasks[0].resultUris[0], secondSaved.garments[0].imageUri);
  assert.deepEqual(Array.from(secondTarget.files.get(secondSaved.garments[0].imageUri)),
    Array.from(sourceBytes.get('private://shirt.png')));
  assert.deepEqual(Array.from(secondTarget.files.get(secondSaved.diary[0].photoUri)),
    Array.from(sourceBytes.get('private://diary.png')));
  assert.equal(secondTarget.files.size, 2, '重复引用的试穿结果应复用衣物图片资产');
});

test('提交失败会清理已写入和部分写入 URI，且不会 publish', async () => {
  const payload = await migration.exportWardrobeMigration(snapshot(), source, 'phone-a', 3,
    '2026-09-24T00:00:00.000Z');
  const target = makeTarget({ failOnWrite: 2 });
  const prepared = await migration.prepareWardrobeMigration(payload, target);
  let published = false;
  await assert.rejects(
    migration.commitWardrobeMigrationCandidate(prepared.candidate, target, {
      commit() { throw new Error('快照落盘失败'); },
      publish() { published = true; }
    }),
    /写入失败/
  );
  assert.equal(published, false);
  assert.equal(target.files.size, 0);
  assert.equal(target.removals.length, 2, '包括抛错的部分写入 URI 也必须清理');
});

test('目标路径校验、旧 revision 和冲突提示均在写入前返回', async () => {
  const payload = await migration.exportWardrobeMigration(snapshot(), source, 'phone-a', 3,
    '2026-09-24T00:00:00.000Z');
  const badPath = await migration.prepareWardrobeMigration(payload, makeTarget({ badPath: true }));
  assert.equal(badPath.status, 'rejected');
  assert.match(badPath.message, /私有路径/);

  const current = sync.createSyncEnvelope({ value: 'local' }, 'tablet-b', 4, '2026-09-24T04:00:00.000Z');
  const stale = await migration.prepareWardrobeMigration(payload, makeTarget(), current);
  assert.equal(stale.status, 'stale');
  assert.equal(stale.candidate !== undefined, true);

  const conflictCurrent = sync.createSyncEnvelope({ value: 'local' }, 'tablet-b', 3, '2026-09-24T04:00:00.000Z');
  const conflict = await migration.prepareWardrobeMigration(payload, makeTarget(), conflictCurrent);
  assert.equal(conflict.status, 'conflict');
  assert.equal(conflict.conflict.decisionRequired, true);
  await assert.rejects(
    migration.commitWardrobeMigrationCandidate(conflict.candidate, makeTarget(), {
      commit() {}, publish() {}
    }),
    /必须先取得用户确认/
  );
});

test('非法图片字节、非法占位和篡改 hash 被拒绝', async () => {
  const payload = await migration.exportWardrobeMigration(snapshot(), source, 'phone-a', 3,
    '2026-09-24T00:00:00.000Z');
  const data = JSON.parse(payload);
  data.assets[0].bytesBase64 = '!!!!';
  const invalidBytes = await migration.prepareWardrobeMigration(JSON.stringify(data), makeTarget());
  assert.equal(invalidBytes.status, 'rejected');
  assert.match(invalidBytes.message, /Base64|校验/);

  const badPath = JSON.parse(payload);
  badPath.envelope.snapshot.garments[0].imageUri = 'migration-asset://../../escape';
  const invalidPlaceholder = await migration.prepareWardrobeMigration(JSON.stringify(badPath), makeTarget());
  assert.equal(invalidPlaceholder.status, 'rejected');

  const badHash = JSON.parse(payload);
  badHash.assets[0].contentHash = '00000000';
  const invalidHash = await migration.prepareWardrobeMigration(JSON.stringify(badHash), makeTarget());
  assert.equal(invalidHash.status, 'rejected');
  assert.match(invalidHash.message, /校验/);
});
