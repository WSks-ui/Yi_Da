const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');

// 仅将无 ArkUI DSL 的真实 .ets 模型/用例/ViewModel 转译到桌面，不能代替 ArkTS 编译。
const home = process.env.YIDA_DEVECO_HOME || 'D:/DevEco Studio 2/DevEco Studio';
const ts = require(path.join(home, 'tools/hvigor/hvigor/node_modules/typescript'));
global.ObservedV2 = (value) => value;
global.Trace = () => {};
Module._extensions['.ets'] = (module, filename) => {
  const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    fileName: filename.replace(/\.ets$/, '.ts'),
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021, experimentalDecorators: true }
  });
  module._compile(result.outputText, filename);
};
const root = '../entry/src/main/ets/';
const { Garment, GarmentDraft, VersionedId, BatchChange, PreparedPhoto } = require(root + 'domain/models/Garment.ets');
const { validateDraft, validateBatch, scaledSize, mediaRelativePath } = require(root + 'domain/usecases/GarmentRules.ets');
const { AppError, errorMessage } = require(root + 'common/errors/AppError.ets');
const { WardrobeService } = require(root + 'domain/usecases/WardrobeService.ets');
const { WardrobeViewModel } = require(root + 'features/wardrobe/viewmodels/WardrobeViewModel.ets');
const { GarmentEditorViewModel } = require(root + 'features/wardrobe/viewmodels/GarmentEditorViewModel.ets');
const { ShellViewModel } = require(root + 'features/ShellViewModel.ets');

function validDraft() {
  const draft = new GarmentDraft();
  draft.name = 'Test shirt';
  return draft;
}
function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function fake() {
  const calls = [];
  const repository = {
    list: async () => [], get: async () => new Garment(), save: async () => 'saved',
    batchChange: async () => {}, deleteArchived: async () => {},
    referencedPaths: async () => { calls.push('references'); return ['media/saved.jpg']; }
  };
  const photos = {
    initialize: async () => {}, pick: async () => '', prepare: async () => new PreparedPhoto(),
    absolute: (value) => value, release: () => { calls.push('release'); },
    discard: async () => { calls.push('discard'); },
    collect: async () => { calls.push('collect'); }
  };
  return { calls, repository, photos, service: new WardrobeService(repository, photos) };
}

test('manual garment accepts unknown season/color and no photograph', () => {
  const draft = validDraft();
  assert.doesNotThrow(() => validateDraft(draft));
});
test('required name rejects whitespace and overlong input', () => {
  for (const name of ['', '  \t ', 'x'.repeat(81)]) {
    const draft = validDraft(); draft.name = name;
    assert.throws(() => validateDraft(draft), { code: 'INVALID_NAME' });
  }
});
test('all five statuses and six categories accepted, unknown values rejected', () => {
  const draft = validDraft();
  for (const status of ['wearable', 'laundry', 'stored', 'season_hidden', 'archived']) {
    draft.status = status; validateDraft(draft);
  }
  for (const category of ['top', 'outerwear', 'bottom', 'dress', 'shoes', 'accessory']) {
    draft.category = category; validateDraft(draft);
  }
  draft.category = "top';DELETE FROM garment";
  assert.throws(() => validateDraft(draft), { code: 'INVALID_ATTRIBUTE' });
});
test('season masks reject floats, negative, overflow and NaN', () => {
  for (const mask of [-1, 16, 1.5, NaN]) {
    const draft = validDraft(); draft.seasonMask = mask;
    assert.throws(() => validateDraft(draft), { code: 'INVALID_SEASON' });
  }
});
test('spaces cannot escape personal/demo', () => {
  const draft = validDraft(); draft.space = 'shared';
  assert.throws(() => validateDraft(draft), { code: 'INVALID_SPACE' });
});
test('batch rejects duplicate IDs and optimistic versions below one', () => {
  assert.throws(() => validateBatch([new VersionedId('a', 1), new VersionedId('a', 2)]));
  assert.throws(() => validateBatch([new VersionedId('a', 0)]));
  assert.throws(() => validateBatch([]));
});
test('batch separates unchanged season from explicit unknown', () => {
  const change = new BatchChange();
  assert.throws(() => validateBatch([new VersionedId('a', 1)], change), { code: 'EMPTY_BATCH' });
  change.seasonMask = 0;
  validateBatch([new VersionedId('a', 1)], change);
});
test('media paths reject traversal, encoded names, URIs, absolute paths and extra suffix', () => {
  for (const value of ['../secret', '/media/a.jpg', 'file://a', 'media/%2e%2e.jpg', 'media/a.jpg', 'C:/a',
    'media/00000000-0000-0000-0000-000000000000.jpg/../../a']) {
    assert.throws(() => mediaRelativePath(value), { code: 'UNSAFE_PATH' });
  }
  assert.equal(mediaRelativePath('media/00000000-0000-0000-0000-000000000000-thumb.jpg'),
    'media/00000000-0000-0000-0000-000000000000-thumb.jpg');
});
test('image scaling preserves aspect ratio and never enlarges tiny input', () => {
  assert.deepEqual(scaledSize(4000, 2000, 2048), [2048, 1024]);
  assert.deepEqual(scaledSize(64, 32, 384), [64, 32]);
  assert.throws(() => scaledSize(8192, 8192, 2048), { code: 'IMAGE_DIMENSIONS' });
  assert.throws(() => scaledSize(9000, 10, 2048), { code: 'IMAGE_DIMENSIONS' });
});
test('platform errors never reveal file paths or tokens in user messages', () => {
  const value = errorMessage(new Error('/private/photo.jpg secret-token'));
  assert.ok(!value.includes('photo') && !value.includes('token'));
  assert.equal(errorMessage(new AppError('X', '已保留衣物')), '已保留衣物');
  assert.ok(errorMessage(Object.assign(new Error('private'), { code: 13900012 })).includes('权限'));
  assert.ok(errorMessage(Object.assign(new Error('private'), { code: 13900025 })).includes('存储空间不足'));
});
test('stale list response cannot replace newer filter result', async () => {
  const first = deferred(); const second = deferred(); const f = fake();
  let count = 0;
  f.repository.list = () => (++count === 1 ? first.promise : second.promise);
  const vm = new WardrobeViewModel(); vm.connect(f.service);
  const one = vm.load(); vm.search = 'new'; const two = vm.load();
  second.resolve([{ id: 'new' }]); await two;
  first.resolve([{ id: 'old' }]); await one;
  assert.equal(vm.items[0].id, 'new');
});
test('stale rejection cannot poison a newer success', async () => {
  const pending = deferred(); const f = fake(); let count = 0;
  f.repository.list = () => ++count === 1 ? pending.promise : Promise.resolve([{ id: 'new' }]);
  const vm = new WardrobeViewModel(); vm.connect(f.service);
  const first = vm.load(); await vm.load(); pending.reject(new Error('old')); await first;
  assert.equal(vm.phase, 'content'); assert.equal(vm.error, '');
});
test('cleanup failure after commit does not turn save into failure', async () => {
  const f = fake(); f.photos.collect = async () => { throw new Error('disk'); };
  assert.equal(await f.service.save(validDraft(), new PreparedPhoto()), 'saved');
  assert.equal(f.service.cleanupPending, true);
  assert.deepEqual(f.calls, ['release', 'references']);
});
test('failed database save retains prepared photo for retry', async () => {
  const f = fake(); f.repository.save = async () => { throw new Error('disk'); };
  await assert.rejects(f.service.save(validDraft(), new PreparedPhoto()));
  assert.deepEqual(f.calls, []);
});
test('one failed write does not poison subsequent serialized operation', async () => {
  const f = fake(); let count = 0;
  f.repository.save = async () => { if (++count === 1) { throw new Error('fail'); } return 'second'; };
  await assert.rejects(f.service.save(validDraft()));
  assert.equal(await f.service.save(validDraft()), 'second');
});
test('save and cleanup of another operation never overlap', async () => {
  const f = fake(); const pending = deferred(); let count = 0;
  f.repository.save = async () => { f.calls.push('save' + ++count); if (count === 1) { await pending.promise; } return 'saved'; };
  const first = f.service.save(validDraft()); const second = f.service.save(validDraft());
  await Promise.resolve(); assert.equal(count, 1);
  pending.resolve(); await Promise.all([first, second]);
  assert.deepEqual(f.calls, ['save1', 'references', 'collect', 'save2', 'references', 'collect']);
});
test('picker cancellation preserves existing image and attributes', async () => {
  const f = fake(); const vm = new GarmentEditorViewModel();
  await vm.open(f.service, '', 'personal'); vm.name = 'keep'; vm.imagePath = 'keep.jpg';
  await vm.pick();
  assert.equal(vm.name, 'keep'); assert.equal(vm.imagePath, 'keep.jpg'); assert.equal(vm.busy, false);
  assert.ok(vm.notice.includes('取消'));
});
test('late image processing result is discarded when editor is gone', async () => {
  const f = fake(); const pending = deferred();
  f.photos.pick = async () => 'chosen'; f.photos.prepare = () => pending.promise;
  const vm = new GarmentEditorViewModel(); await vm.open(f.service, '', 'personal');
  const choosing = vm.pick(); await Promise.resolve(); await vm.dispose();
  pending.resolve(new PreparedPhoto()); await choosing;
  assert.equal(vm.imagePath, ''); assert.deepEqual(f.calls, ['discard']);
});
test('double save invokes repository once while pending', async () => {
  const f = fake(); const pending = deferred(); let count = 0;
  f.repository.save = async () => { count++; return pending.promise; };
  const vm = new GarmentEditorViewModel(); await vm.open(f.service, '', 'personal'); vm.name = 'Test';
  const first = vm.save(); assert.equal(await vm.save(), false);
  pending.resolve('saved'); assert.equal(await first, true); assert.equal(count, 1);
});
test('failed editor load blocks saving an accidental new garment', async () => {
  const f = fake(); f.repository.get = async () => { throw new Error('missing'); };
  const vm = new GarmentEditorViewModel(); await vm.open(f.service, 'missing', 'personal');
  assert.equal(vm.loadFailed, true); assert.equal(await vm.save(), false);
});
test('status entry clears old filters and selection in the requested space', async () => {
  const f = fake(); const vm = new WardrobeViewModel(); vm.connect(f.service);
  vm.space = 'personal'; vm.search = 'old'; vm.category = 'shoes'; vm.seasonMask = 8;
  vm.selecting = true; vm.selected = ['old'];
  vm.resetFilters('laundry');
  assert.equal(vm.space, 'personal'); assert.equal(vm.status, 'laundry');
  assert.equal(vm.search, ''); assert.equal(vm.category, ''); assert.equal(vm.seasonMask, 0);
  assert.equal(vm.selecting, false); assert.deepEqual(vm.selected, []);
});
test('statistics failure does not strand the list in initial or fabricate counts', async () => {
  const f = fake(); let count = 0;
  f.repository.list = async () => { if (++count === 1) { throw new Error('stats fail'); } return []; };
  const vm = new ShellViewModel();
  await vm.initialize({ database: { open: async () => {} }, wardrobe: f.service });
  assert.equal(vm.phase, 'content'); assert.equal(vm.wardrobe.phase, 'empty');
  assert.equal(vm.statisticsReady, false);
});
test('cleanup initialization failure remains actionable', async () => {
  const f = fake(); const vm = new ShellViewModel();
  vm.services = { wardrobe: f.service };
  f.photos.initialize = async () => { throw new Error('disk'); };
  await vm.retryCleanup();
  assert.equal(vm.cleanupPending, true); assert.ok(vm.error);
  f.photos.initialize = async () => {};
  vm.wardrobe.connect(f.service);
  vm.wardrobe.notice = '部分无引用图片清理待重试，可前往“我的”处理。';
  await vm.retryCleanup();
  assert.equal(vm.cleanupPending, false);
  assert.equal(vm.error, '');
  assert.equal(vm.wardrobe.notice, '');
});
