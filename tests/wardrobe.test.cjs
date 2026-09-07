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
const { ImportQueueViewModel } = require(root + 'features/wardrobe/viewmodels/ImportQueueViewModel.ets');
const { validatePickLimit, toggleSeason } = require(root + 'domain/usecases/ImportPolicy.ets');

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
    hasImageHash: async () => false,
    batchChange: async () => {}, deleteArchived: async () => {},
    referencedPaths: async () => { calls.push('references'); return ['media/saved.jpg']; }
  };
  const photos = {
    initialize: async () => {}, pick: async () => '', pickMany: async () => [], prepare: async () => new PreparedPhoto(),
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
  const choosing = vm.pick(); await Promise.resolve(); const closing = vm.dispose();
  pending.resolve(new PreparedPhoto()); await Promise.all([choosing, closing]);
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

function prepared(hash = 'a') {
  const photo = new PreparedPhoto();
  photo.original.sha256 = hash.repeat(64);
  photo.original.relativePath = `media/${hash}.jpg`;
  photo.thumbnail.relativePath = `media/${hash}-thumb.jpg`;
  return photo;
}
function queueFixture(uris = ['one']) {
  const f = fake();
  f.photos.pickMany = async () => uris;
  let count = 0;
  f.photos.prepare = async () => prepared(String(++count));
  const vm = new ImportQueueViewModel(); vm.connect(f.service);
  return { ...f, vm };
}
function confirm(item, name = 'My shirt') {
  item.name = name; item.category = 'top'; item.confirmed = true;
}

test('picker limits are explicit and include all sixteen season combinations', () => {
  for (const limit of [1, 20]) { validatePickLimit(limit); }
  for (const limit of [0, 21, 1.5, NaN]) { assert.throws(() => validatePickLimit(limit)); }
  for (let mask = 0; mask < 16; mask++) {
    for (let index = 0; index < 4; index++) {
      assert.equal(toggleSeason(mask, index, true), mask | (1 << index));
      assert.equal(toggleSeason(mask, index, false), mask & ~(1 << index));
    }
  }
  assert.throws(() => toggleSeason(16, 0, true));
});
test('five selected photos with one corrupt input retain four independently savable items', async () => {
  const f = queueFixture(['a', 'b', 'bad', 'c', 'd']);
  let counter = 0;
  f.photos.prepare = async (uri) => { if (uri === 'bad') throw new Error('decode'); return prepared(String(++counter)); };
  let saved = 0; f.repository.save = async () => 'saved-' + ++saved;
  await f.vm.pick();
  assert.deepEqual(f.vm.items.map(item => item.phase), ['ready', 'ready', 'failed', 'ready', 'ready']);
  f.vm.items.filter(item => item.phase === 'ready').forEach(item => confirm(item));
  await f.vm.saveConfirmed();
  assert.equal(saved, 4); assert.equal(f.vm.savedCount(), 4);
  assert.equal(f.vm.items[2].phase, 'failed');
});
test('failed import can retry only the affected item', async () => {
  const f = queueFixture(['bad', 'good']); let attempts = 0;
  f.photos.prepare = async uri => { if (uri === 'bad' && ++attempts === 1) throw new Error('gone'); return prepared(uri[0]); };
  await f.vm.pick(); const good = f.vm.items[1].photo;
  await f.vm.retry(f.vm.items[0]);
  assert.equal(f.vm.items[0].phase, 'ready'); assert.equal(f.vm.items[1].photo, good);
});
test('picker cancel while paused does not restart pending work', async () => {
  const f = queueFixture(['a', 'b']); const pending = deferred();
  f.photos.prepare = async () => pending.promise;
  const loading = f.vm.pick(); await Promise.resolve(); await Promise.resolve();
  f.vm.pause(); pending.resolve(prepared()); await loading;
  assert.equal(f.vm.items[1].phase, 'pending');
  f.photos.pickMany = async () => [];
  await f.vm.pick();
  assert.equal(f.vm.paused, true); assert.equal(f.vm.items[1].phase, 'pending');
});
test('late picker result after disposal never starts image decoding', async () => {
  const f = queueFixture(); const pending = deferred(); let decoded = 0;
  f.photos.pickMany = () => pending.promise;
  f.photos.prepare = async () => { decoded++; return prepared(); };
  const selecting = f.vm.pick(); await f.vm.dispose(); pending.resolve(['one']); await selecting;
  assert.equal(decoded, 0); assert.equal(f.vm.items.length, 0);
});
test('disposal during decode waits then removes uncommitted image exactly once', async () => {
  const f = queueFixture(); const pending = deferred();
  f.photos.prepare = () => pending.promise;
  const selecting = f.vm.pick(); await Promise.resolve(); await Promise.resolve();
  const close = f.vm.dispose(); pending.resolve(prepared()); await Promise.all([selecting, close]);
  assert.equal(f.calls.filter(value => value === 'discard').length, 1);
  assert.equal(f.vm.items[0].photo, undefined);
});
test('disposal during save preserves committed photo and does not submit later items', async () => {
  const f = queueFixture(['a', 'b']); await f.vm.pick(); f.vm.items.forEach(item => confirm(item));
  const pending = deferred(); let saves = 0;
  f.repository.save = async () => { saves++; return pending.promise; };
  const saving = f.vm.saveConfirmed(); await Promise.resolve(); await Promise.resolve();
  const closing = f.vm.dispose(); pending.resolve('saved');
  await Promise.all([saving, closing]);
  assert.equal(saves, 1); assert.equal(f.vm.savedCount(), 1);
  assert.equal(f.calls.filter(value => value === 'discard').length, 1);
  assert.equal(f.vm.items[0].photo, undefined);
});
test('failed save retains photo and successful items are never submitted again', async () => {
  const f = queueFixture(['a', 'b']); await f.vm.pick(); f.vm.items.forEach(item => confirm(item));
  let count = 0; f.repository.save = async () => { if (++count === 2) throw new Error('full'); return String(count); };
  await f.vm.saveConfirmed();
  assert.equal(f.vm.items[0].phase, 'saved'); assert.equal(f.vm.items[1].phase, 'ready');
  assert.ok(f.vm.items[1].photo); assert.equal(f.vm.items[0].photo, undefined);
  await f.vm.saveConfirmed(); assert.equal(count, 3); assert.equal(f.vm.savedCount(), 2);
});
test('missing name or category cannot save even when confirmed', async () => {
  const f = queueFixture(); await f.vm.pick();
  const item = f.vm.items[0]; item.confirmed = true; item.name = 'shirt';
  await f.vm.saveConfirmed();
  assert.equal(item.phase, 'ready'); assert.ok(item.error); assert.equal(f.vm.savedCount(), 0);
});
test('unconfirmed valid items cannot be silently saved', async () => {
  const f = queueFixture(); await f.vm.pick();
  f.vm.items[0].name = 'shirt'; f.vm.items[0].category = 'top';
  await f.vm.saveConfirmed(); assert.equal(f.vm.savedCount(), 0); assert.ok(f.vm.error);
});
test('duplicate selection URI is de-duplicated and oversize result is rejected', async () => {
  const f = queueFixture(['a', 'a']); await f.vm.pick();
  assert.equal(f.vm.items.length, 1);
  f.photos.pickMany = async () => Array.from({ length: 20 }, (_, i) => String(i));
  await f.vm.pick(); assert.equal(f.vm.items.length, 1); assert.ok(f.vm.error);
});
test('same photo in queue requires explicit duplicate acknowledgement', async () => {
  const f = queueFixture(['a', 'b']); f.photos.prepare = async () => prepared();
  await f.vm.pick();
  assert.equal(f.vm.items[1].duplicate, true);
  f.vm.items.forEach(item => confirm(item));
  await f.vm.saveConfirmed();
  assert.equal(f.vm.items[0].phase, 'saved'); assert.equal(f.vm.items[1].phase, 'ready');
  f.vm.items[1].allowDuplicate = true; await f.vm.saveConfirmed();
  assert.equal(f.vm.savedCount(), 2);
});
test('duplicate check is repeated in serialized save, not only before confirmation', async () => {
  const f = fake(); let saved = false; let count = 0;
  f.repository.hasImageHash = async () => saved;
  f.repository.save = async () => { saved = true; count++; return 'saved'; };
  const first = f.service.save(validDraft(), prepared());
  const second = f.service.save(validDraft(), prepared());
  await first; await assert.rejects(second, { code: 'DUPLICATE_PHOTO' });
  assert.equal(count, 1);
});
test('existing duplicate rejection keeps editor photo for explicit confirmed retry', async () => {
  const f = fake(); f.photos.pick = async () => 'one'; f.photos.prepare = async () => prepared();
  f.repository.hasImageHash = async () => true;
  const vm = new GarmentEditorViewModel(); await vm.open(f.service, '', 'personal'); await vm.pick(); vm.name = 'shirt';
  assert.equal(await vm.save(), false); assert.equal(vm.duplicate, true);
  vm.allowDuplicate = true; assert.equal(await vm.save(), true);
  assert.equal(f.calls.includes('discard'), false);
});
test('single editor disposal during commit cannot delete committed media', async () => {
  const f = fake(); const pending = deferred();
  f.photos.pick = async () => 'one'; f.photos.prepare = async () => prepared();
  const vm = new GarmentEditorViewModel(); await vm.open(f.service, '', 'personal'); await vm.pick(); vm.name = 'shirt';
  f.repository.save = async () => pending.promise;
  const saving = vm.save(); const closing = vm.dispose(); pending.resolve('id'); await Promise.all([saving, closing]);
  assert.equal(f.calls.includes('discard'), false); assert.equal(vm.dirty, false);
});
test('single editor cancellation reports cleanup failure instead of silently losing retry state', async () => {
  const f = fake();
  f.photos.pick = async () => 'one'; f.photos.prepare = async () => prepared();
  f.photos.discard = async () => { throw new Error('private-path'); };
  const vm = new GarmentEditorViewModel(); await vm.open(f.service, '', 'personal'); await vm.pick();
  await vm.dispose();
  assert.equal(f.service.cleanupPending, true); assert.ok(vm.notice.includes('清理'));
  assert.ok(!vm.notice.includes('private-path'));
});
test('late editor photo cleanup failure remains actionable after page disposal', async () => {
  const f = fake(); const pending = deferred();
  f.photos.pick = async () => 'one'; f.photos.prepare = () => pending.promise;
  f.photos.discard = async () => { throw new Error('disk'); };
  const vm = new GarmentEditorViewModel(); await vm.open(f.service, '', 'personal');
  const picking = vm.pick(); await Promise.resolve(); const closing = vm.dispose();
  pending.resolve(prepared()); await Promise.all([picking, closing]);
  assert.equal(f.service.cleanupPending, true); assert.equal(vm.imagePath, '');
});
test('editor close waits for cleanup so the outer page can refresh the actual result', async () => {
  const f = fake(); const pending = deferred();
  f.photos.pick = async () => 'one'; f.photos.prepare = async () => prepared();
  f.photos.discard = () => pending.promise;
  const vm = new GarmentEditorViewModel(); await vm.open(f.service, '', 'personal'); await vm.pick();
  let closed = false; const closing = vm.dispose().then(() => { closed = true; });
  await Promise.resolve(); assert.equal(closed, false);
  pending.reject(new Error('disk')); await closing;
  assert.equal(closed, true); assert.equal(f.service.cleanupPending, true);
});
test('cleanup failure while skipping remains reported and does not resave skipped item', async () => {
  const f = queueFixture(); await f.vm.pick();
  f.photos.discard = async () => { throw new Error('full'); };
  await f.vm.skip(f.vm.items[0]); await f.vm.saveConfirmed();
  assert.equal(f.service.cleanupPending, true); assert.equal(f.vm.items[0].phase, 'skipped');
  assert.equal(f.vm.items[0].photo, undefined);
});
test('unknown IDs and selection overflow cannot enter batch selection', () => {
  const vm = new WardrobeViewModel();
  vm.items = Array.from({ length: 201 }, (_, index) => ({ id: String(index), version: 1 }));
  vm.toggle('missing'); assert.equal(vm.selected.length, 0);
  vm.items.forEach(item => vm.toggle(item.id));
  assert.equal(vm.selected.length, 200); assert.ok(vm.error);
});
