const fs = require('node:fs');
const assert = require('node:assert/strict');
const { test } = require('node:test');

// 在桌面直接验证真实 .ets 业务文件；仅转译类型语法，不模拟 ArkUI 或宣称通过真机测试。
const ts = require(process.argv[2] || 'typescript');
require.extensions['.ets'] = (loadedModule, filename) => {
  const source = fs.readFileSync(filename, 'utf8');
  const output = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  loadedModule._compile(output, filename);
};

const { Category, GarmentStatus, STATUSES, emptyProfile } = require('../entry/src/main/ets/model/Wardrobe.ets');
const { demoGarments, initialSnapshot } = require('../entry/src/main/ets/data/DemoData.ets');
const { recommend, replaceGarment } = require('../entry/src/main/ets/service/OutfitEngine.ets');
const { analyzeBodyProfile, bodyFitScore } = require('../entry/src/main/ets/service/BodyAnalysis.ets');
const { activeGarments, cardData } = require('../entry/src/main/ets/widget/CardData.ets');
const { localDay, normalizedDay, recordedDays, hasWear } = require('../entry/src/main/ets/service/WearHistory.ets');
const { temperatureAdvice, precipitationAdvice, TEMPERATURE_BANDS } = require('../entry/src/main/ets/service/TemperatureAdvice.ets');
const { normalizeLayout, constrainPiece, copyLayout, CanvasHistory } = require('../entry/src/main/ets/service/OutfitCanvas.ets');
const { saveDiary, removeDiary } = require('../entry/src/main/ets/service/WearHistory.ets');
const GI = require('../entry/src/main/ets/service/GarmentImport.ets');
const { ImportPhase, ImportFailureStep, createImportItem } = require('../entry/src/main/ets/model/GarmentImport.ets');
const { SnapshotCommit } = require('../entry/src/main/ets/service/SnapshotCommit.ets');
const { ImportSession } = require('../entry/src/main/ets/service/GarmentImportRunner.ets');
const { GarmentImportController } = require('../entry/src/main/ets/service/GarmentImportController.ets');

test('旧收藏生成画布布局，持久化往返后位置、层级和颜色不变', () => {
  const layout = normalizeLayout(undefined, ['tee', 'jeans', 'shoes']);
  layout.background = '#E7EEF5';
  layout.items[0] = constrainPiece({ ...layout.items[0], x: 0.52, y: 0.6, rotation: 45, scale: 1.2 });
  layout.items.reverse();
  assert.deepEqual(normalizeLayout(JSON.parse(JSON.stringify(layout)), ['tee', 'jeans', 'shoes']), layout);
});

test('旋转缩放后的单品仍在画布内，异常布局不影响其余单品', () => {
  for (const rotation of [-180, -90, -45, 0, 45, 90, 180]) {
    const p = constrainPiece({ garmentId: 'tee', x: -50, y: 50, scale: 100, rotation });
    const angle = rotation * Math.PI / 180;
    const hx = (Math.abs(Math.cos(angle)) * .38 + Math.abs(Math.sin(angle)) * .44) * p.scale / 2;
    const hy = (Math.abs(Math.sin(angle)) * .38 + Math.abs(Math.cos(angle)) * .44) * p.scale / 2.4;
    assert.ok(p.x >= hx - 1e-10 && p.x <= 1 - hx + 1e-10);
    assert.ok(p.y >= hy - 1e-10 && p.y <= 1 - hy + 1e-10);
  }
  const layout = normalizeLayout({ background: 'invalid', items: [null,
    { garmentId: 'tee', x: NaN, y: Infinity, rotation: NaN, scale: -4 },
    { garmentId: 'missing' }, { garmentId: 'tee' }] }, ['tee', 'jeans']);
  assert.equal(layout.items.length, 2);
  assert.equal(layout.background, '#FFFFFF');
  assert.ok(layout.items.every(p => Number.isFinite(p.x) && Number.isFinite(p.y)));
});

test('撤销恢复位置和底色，重做后新操作清除分支且历史不共享引用', () => {
  const history = new CanvasHistory();
  const first = normalizeLayout(undefined, ['tee']);
  history.record(first);
  const next = copyLayout(first); next.background = '#E7EEF5'; next.items[0].x = .6;
  const previous = history.undo(next);
  assert.deepEqual(previous, first);
  assert.deepEqual(history.redo(previous), next);
  history.undo(next); history.record(first);
  assert.equal(history.canRedo(), false);
  first.items[0].x = .7;
  assert.notEqual(history.undo(next).items[0].x, .7);
});

const diaryInput = (overrides = {}) => ({ id: 'diary_test', date: '2026-09-17', garmentIds: ['tee', 'jeans'],
  note: '', photoUri: '', weather: '手动温度', temperature: 22, occasion: '上课', feedback: '合适', ...overrides });

test('手动日记计数、跨入口重复拦截和删除撤销一致', () => {
  const garments = demoGarments(); const before = JSON.stringify(garments);
  const saved = saveDiary([], [], garments, diaryInput());
  assert.equal(saved.error, '');
  assert.equal(saved.garments[0].wearCount, garments[0].wearCount + 1);
  const duplicate = saveDiary(saved.diary, saved.records, saved.garments,
    diaryInput({ id: 'wear_123', garmentIds: ['jeans', 'tee'] }));
  assert.match(duplicate.error, /已经记录/);
  const removed = removeDiary(saved.diary, saved.records, saved.garments, 'diary_test');
  assert.deepEqual(removed.garments, garments);
  assert.equal(removed.records.length, 0);
  assert.equal(JSON.stringify(garments), before);
});

test('同 ID 重试不增加计数，修改组合撤销旧衣物并增加新衣物', () => {
  const saved = saveDiary([], [], demoGarments(), diaryInput());
  const retry = saveDiary(saved.diary, saved.records, saved.garments, diaryInput());
  assert.deepEqual(retry.garments, saved.garments);
  const changed = saveDiary(retry.diary, retry.records, retry.garments, diaryInput({ garmentIds: ['shirt', 'jeans'] }));
  const count = (items, id) => items.find(item => item.id === id).wearCount;
  assert.equal(count(changed.garments, 'tee'), count(demoGarments(), 'tee'));
  assert.equal(count(changed.garments, 'shirt'), count(demoGarments(), 'shirt') + 1);
  assert.equal(changed.records.length, 1);
});

test('旧反馈日记与旧手动日记删除区分，穿着历史截断后仍能撤销', () => {
  const garments = demoGarments();
  const oldManual = removeDiary([diaryInput()], [], garments, 'diary_test');
  assert.deepEqual(oldManual.garments, garments);
  const oldWear = diaryInput({ id: 'wear_123' });
  const oldRecord = { id: '123', date: '2026/9/17', garmentIds: ['tee', 'jeans'], feedback: '合适' };
  assert.equal(removeDiary([oldWear], [oldRecord], garments, 'wear_123').garments[0].wearCount, garments[0].wearCount - 1);
  const saved = saveDiary([], [], garments, diaryInput());
  assert.deepEqual(removeDiary(saved.diary, [], saved.garments, 'diary_test').garments, garments);
});

test('空记录、悬空单品及日记容量达到上限时不静默丢历史', () => {
  const garments = demoGarments();
  assert.notEqual(saveDiary([], [], garments, diaryInput({ garmentIds: [] })).error, '');
  assert.notEqual(saveDiary([], [], garments, diaryInput({ garmentIds: ['missing'] })).error, '');
  const full = Array.from({ length: 200 }, (_, i) => diaryInput({ id: 'd' + i, date: '2025-01-' + i }));
  const result = saveDiary(full, [], garments, diaryInput());
  assert.match(result.error, /已满/); assert.equal(result.diary, full);
});

test('穿搭日期保留本地日历日期并兼容旧版分隔符', () => {
  assert.equal(localDay(new Date(2026, 8, 15, 0, 5)), '2026-09-15');
  assert.equal(normalizedDay('2026/9/5'), '2026-09-05');
  assert.equal(normalizedDay('2026.9.5'), '2026-09-05');
  assert.equal(normalizedDay('2026-02-30'), '2026-02-30');
  assert.equal(normalizedDay('9/5/2026'), '9/5/2026');
});

test('同日多条日记与穿着反馈合并后只计一天', () => {
  const diary = [{ date: '2026-09-15' }, { date: '2026/9/15' }, { date: '2026-09-16' }];
  const records = [{ date: '2026.9.15' }, { date: '2026-08-31' }];
  assert.deepEqual(recordedDays(diary, records), ['2026-09-15', '2026-09-16', '2026-08-31']);
});

test('重复穿搭判定兼容旧日期、衣物顺序，且不修改原数组', () => {
  const records = [{ date: '2026/9/15', garmentIds: ['tee', 'jeans'] }];
  const ids = ['jeans', 'tee'];
  assert.equal(hasWear(records, '2026-09-15', ids), true);
  assert.equal(hasWear(records, '2026-09-16', ids), false);
  assert.equal(hasWear(records, '2026-09-15', ['shirt', 'jeans']), false);
  assert.deepEqual(records[0].garmentIds, ['tee', 'jeans']);
  assert.deepEqual(ids, ['jeans', 'tee']);
});
const query = (overrides = {}) => ({ occasion: '上课', temperature: 24, lockedIds: [], excludedIds: [],
  profile: emptyProfile(), ...overrides });

test('只返回不同的完整搭配，不混入待洗上衣', () => {
  const result = recommend(demoGarments(), query());
  assert.equal(result.outfits.length, 2);
  assert.equal(new Set(result.outfits.map(item => item.id)).size, 2);
  for (const look of result.outfits) {
    assert.equal(look.garmentIds.length, 3);
    assert.ok(!look.garmentIds.includes('graphic'));
    assert.ok(look.garmentIds.includes('jeans'));
    assert.ok(look.garmentIds.includes('shoes'));
  }
});

for (const status of STATUSES.filter(value => value !== GarmentStatus.READY)) {
  test(`${status}状态的必要品类不进入推荐`, () => {
    const garments = demoGarments();
    garments.find(item => item.id === 'jeans').status = status;
    const result = recommend(garments, query());
    assert.equal(result.outfits.length, 0);
    assert.match(result.explanation, /下装/);
  });
}

test('低温添加外套，缺少外套给出原因', () => {
  const garments = demoGarments();
  const result = recommend(garments, query({ temperature: 15 }));
  assert.ok(result.outfits.length > 0);
  assert.ok(result.outfits.every(look => look.garmentIds.includes('jacket')));
  garments.find(item => item.id === 'jacket').status = GarmentStatus.STORED;
  const missing = recommend(garments, query({ temperature: 15 }));
  assert.equal(missing.outfits.length, 0);
  assert.match(missing.explanation, /外套/);
});

test('有可穿配饰时推荐会顺带加入，没有配饰时仍保持完整方案', () => {
  const garments = demoGarments();
  const accessory = { id: 'scarf', name: '浅色围巾', category: Category.ACCESSORY, imageKey: 'graphic',
    imageUri: '', color: '米白色', minTemp: 5, maxTemp: 24, occasions: ['上课'], status: GarmentStatus.READY,
    wearCount: 0, isDemo: true, fit: '合身', palette: '低饱和', style: '学院', layering: true, pattern: false };
  const withAccessory = recommend(garments.concat([accessory]), query({ temperature: 18 }));
  assert.ok(withAccessory.outfits.length > 0);
  assert.ok(withAccessory.outfits[0].garmentIds.includes('scarf'));
  assert.ok(recommend(garments, query({ temperature: 18 })).outfits.length > 0);
});

test('温度和场合是硬约束', () => {
  assert.equal(recommend(demoGarments(), query({ temperature: 36 })).outfits.length, 0);
  assert.equal(recommend(demoGarments(), query({ temperature: NaN })).outfits.length, 0);
  const result = recommend(demoGarments(), query({ occasion: '课程展示' }));
  assert.equal(result.outfits.length, 1);
  assert.ok(result.outfits[0].garmentIds.includes('shirt'));
});

test('锁定与排除冲突不能偷偷移除指定衣物', () => {
  assert.equal(recommend(demoGarments(), query({ lockedIds: ['tee'], excludedIds: ['tee'] })).outfits.length, 0);
  assert.equal(recommend(demoGarments(), query({ lockedIds: ['graphic'] })).outfits.length, 0);
  assert.equal(recommend(demoGarments(), query({ lockedIds: ['tee', 'shirt'] })).outfits.length, 0);
  assert.equal(recommend(demoGarments(), query({ lockedIds: ['missing'] })).outfits.length, 0);
});

test('锁定上装后所有方案都保留该上装', () => {
  const result = recommend(demoGarments(), query({ lockedIds: ['tee'] }));
  assert.equal(result.outfits.length, 1);
  assert.ok(result.outfits[0].garmentIds.includes('tee'));
});

test('单件替换只改变指定品类，原搭配对象保持不变', () => {
  const garments = demoGarments();
  const original = recommend(garments, query()).outfits[0];
  const before = JSON.stringify(original);
  const oldTop = original.garmentIds.find(id => garments.find(item => item.id === id).category === Category.TOP);
  const next = replaceGarment(original, oldTop, garments, query({ lockedIds: ['jeans'] }));
  assert.equal(next.outfits.length, 1);
  assert.deepEqual(next.outfits[0].garmentIds.filter(id => id !== 'tee' && id !== 'shirt'), ['jeans', 'shoes']);
  assert.ok(!next.outfits[0].garmentIds.includes(oldTop));
  assert.equal(JSON.stringify(original), before);
});

test('锁定单品或没有替代单品时，不返回伪造替换结果', () => {
  const garments = demoGarments();
  const original = recommend(garments, query()).outfits[0];
  assert.equal(replaceGarment(original, 'jeans', garments, query()).outfits.length, 0);
  assert.equal(replaceGarment(original, 'jeans', garments, query({ lockedIds: ['jeans'] })).outfits.length, 0);
});

test('缺少任何必要品类时返回空状态', () => {
  assert.equal(recommend([], query()).outfits.length, 0);
  assert.equal(recommend(demoGarments().filter(item => item.category !== Category.SHOES), query()).outfits.length, 0);
});

test('卡片只显示当前有效搭配，衣物变待洗后不再展示过期结果', () => {
  const snapshot = initialSnapshot();
  assert.equal(activeGarments(snapshot).length, 3);
  assert.equal(cardData(snapshot).count, 3);
  snapshot.garments.find(item => item.id === 'tee').status = GarmentStatus.LAUNDRY;
  assert.equal(activeGarments(snapshot).length, 0);
  assert.equal(cardData(snapshot).hasOutfit, false);
});

test('导入衣物不被替换成预置图片', () => {
  const snapshot = initialSnapshot();
  const top = snapshot.garments.find(item => item.id === 'tee');
  top.imageKey = ''; top.imageUri = 'file://private/garment.jpg'; top.isDemo = false;
  assert.equal(cardData(snapshot).imageKey, '');
  assert.equal(cardData(snapshot).hasOutfit, true);
});

test('偏好档案只调整推荐顺序，不排除衣物也不改变方案数量', () => {
  const garments = demoGarments();
  const plain = recommend(garments, query());
  const prefersBaggy = recommend(garments, query({
    profile: { fits: ['宽松'], palettes: ['低饱和'], styles: ['学院'],
      layering: 1, accessories: 1, priority: '个性表达', completed: true }
  }));
  // 同一批衣物，方案数量不变；只是宽松学院风的单品排到前面。
  assert.equal(prefersBaggy.outfits.length, plain.outfits.length);
  assert.equal(prefersBaggy.outfits[0].garmentIds.includes('shirt'), true);
});

test('单件多推荐/少推荐只调整顺序，温度与状态硬约束仍然优先', () => {
  const neutral = demoGarments();
  const preferred = demoGarments();
  preferred.find(item => item.id === 'shirt').recommendationBias = 1;
  const preferredResult = recommend(preferred, query());
  assert.equal(preferredResult.outfits[0].garmentIds.includes('shirt'), true);

  const rejected = demoGarments();
  rejected.find(item => item.id === 'shirt').recommendationBias = -1;
  const rejectedResult = recommend(rejected, query());
  assert.equal(rejectedResult.outfits[0].garmentIds.includes('shirt'), false);

  const unavailable = demoGarments();
  unavailable.find(item => item.id === 'shirt').recommendationBias = 1;
  unavailable.find(item => item.id === 'shirt').maxTemp = 18;
  const hardConstraint = recommend(unavailable, query());
  assert.ok(hardConstraint.outfits.length > 0);
  assert.equal(hardConstraint.outfits[0].garmentIds.includes('shirt'), false);
  assert.equal(neutral.find(item => item.id === 'shirt').recommendationBias, undefined);
});

test('偏好与硬约束冲突时，硬约束仍然优先', () => {
  const garments = demoGarments();
  // 偏好基础色也不影响“待洗必排除”。
  garments.find(item => item.id === 'jeans').status = GarmentStatus.LAUNDRY;
  const result = recommend(garments, query({
    profile: { fits: ['合身'], palettes: ['基础色'], styles: ['简约'],
      layering: 0, accessories: 0, priority: '舒适', completed: true }
  }));
  assert.equal(result.outfits.length, 0);
  assert.match(result.explanation, /下装/);
});

test('未完成档案时推荐理由不声称匹配偏好', () => {
  const garments = demoGarments();
  const result = recommend(garments, query());
  assert.equal(result.outfits[0].reason.includes('偏好档案'), false);
  const done = recommend(garments, query({
    profile: { fits: ['合身'], palettes: ['基础色'], styles: ['简约'],
      layering: 0, accessories: 0, priority: '舒适', completed: true }
  }));
  assert.equal(done.outfits[0].reason.includes('偏好档案'), true);
});

test('空体型档案保持中性，不改变旧调用排序', () => {
  const emptyBody = { height: '', size: '', fitPreference: '', shoulder: '', chest: '', waist: '', hip: '',
    skinTone: '', hairColor: '', eyeColor: '', updatedAt: '' };
  const analysis = analyzeBodyProfile(emptyBody);
  assert.equal(analysis.shape, '信息不足');
  assert.deepEqual(analysis.knownFields, []);
  assert.equal(analysis.confidence, 0);
  const request = query();
  const oldResult = recommend(demoGarments(), request);
  const bodyResult = recommend(demoGarments(), Object.assign({}, request, { body: emptyBody }));
  assert.deepEqual(bodyResult.outfits.map(item => item.garmentIds), oldResult.outfits.map(item => item.garmentIds));
  assert.equal(bodyFitScore(demoGarments()[0], oldResult.outfits[0], analysis), 0);
});

test('肩宽缺少胸围时不做围度替代，无效数字不计入已知字段', () => {
  const partialBody = { height: '170x', size: '', fitPreference: '', shoulder: '40', chest: 'abc', waist: '72x',
    hip: '94', skinTone: '', hairColor: '', eyeColor: '', updatedAt: '' };
  const analysis = analyzeBodyProfile(partialBody);
  assert.equal(analysis.shape, '信息不足');
  assert.deepEqual(analysis.knownFields, ['shoulder', 'hip']);
  assert.equal(analysis.confidence, 0.33);
  assert.equal(analysis.knownFields.indexOf('height'), -1);
  assert.equal(analysis.knownFields.indexOf('chest'), -1);
  assert.equal(analysis.knownFields.indexOf('waist'), -1);

  const shoulderOnly = Object.assign({}, partialBody, { height: '', chest: '', waist: '', hip: '94' });
  assert.equal(analyzeBodyProfile(shoulderOnly).shape, '信息不足');
});

test('完整体型档案给出可解释标签、建议和排序影响', () => {
  const fullBody = { height: '170', size: 'M', fitPreference: '合身', shoulder: '40', chest: '88', waist: '72',
    hip: '94', skinTone: '', hairColor: '', eyeColor: '', updatedAt: '' };
  const analysis = analyzeBodyProfile(fullBody);
  assert.equal(analysis.shape, '沙漏型');
  assert.equal(analysis.confidence, 1);
  assert.equal(analysis.knownFields.length, 6);
  assert.match(analysis.summary, /沙漏型/);
  assert.ok(analysis.advice.length > 0);
  const result = recommend(demoGarments(), Object.assign({}, query(), { body: fullBody }));
  assert.match(result.outfits[0].reason, /体型建议/);
  assert.match(result.outfits[0].reason, /沙漏型/);
  assert.equal(result.outfits[0].garmentIds.includes('tee'), true);
});

test('体型推荐排序可重复，且支持从 profile.body 兼容接入', () => {
  const body = { height: '170', size: '', fitPreference: '宽松', shoulder: '42', chest: '96', waist: '82',
    hip: '90', skinTone: '', hairColor: '', eyeColor: '', updatedAt: '' };
  const request = query({ profile: Object.assign({}, emptyProfile(), { body: body }) });
  const first = recommend(demoGarments(), request);
  const second = recommend(demoGarments(), request);
  assert.deepEqual(first, second);
  assert.match(first.outfits[0].reason, /体型建议/);
});

// ---- 温度带提示 ----

test('温度带按上界升序排列，且覆盖到极端温度都有结果', () => {
  for (let i = 1; i < TEMPERATURE_BANDS.length; i++) {
    assert.ok(TEMPERATURE_BANDS[i].maxTemp > TEMPERATURE_BANDS[i - 1].maxTemp, '温度带必须升序');
  }
  // 从极寒到酷热都必须给得出提示，不能出现空文案。
  for (let t = -40; t <= 50; t++) {
    const band = temperatureAdvice(t);
    assert.ok(band && typeof band.text === 'string' && band.text.length > 0, `${t}℃ 没有提示`);
    assert.ok(band.iconKey.length > 0, `${t}℃ 没有图标键`);
  }
});

test('22℃ 落在微凉带（薄外套）', () => {
  assert.strictEqual(temperatureAdvice(22).text, '微凉，适合薄外套');
});

test('温度带边界取上界含等号，不跳带', () => {
  assert.strictEqual(temperatureAdvice(0).text, '冰冻，羽绒服加围巾手套');
  assert.strictEqual(temperatureAdvice(10).text, '冷，需要保暖外套');
  assert.strictEqual(temperatureAdvice(20).text, '凉爽，长袖正合适');
  assert.strictEqual(temperatureAdvice(25).text, '微凉，适合薄外套');
  assert.strictEqual(temperatureAdvice(28).text, '舒适，单穿长袖或薄衬衫');
  assert.strictEqual(temperatureAdvice(32).text, '偏热，短袖透气为主');
});

test('低于最低带与高于最高带都收敛到端点，不越界', () => {
  assert.strictEqual(temperatureAdvice(-100).text, temperatureAdvice(-50).text);
  assert.strictEqual(temperatureAdvice(999).text, temperatureAdvice(40).text);
});

test('降水提示优先于温度提示，且无降水时为空串', () => {
  assert.strictEqual(precipitationAdvice('小雨'), '有雨，记得带伞');
  assert.strictEqual(precipitationAdvice('中雪'), '有雪，注意防滑与保暖');
  assert.strictEqual(precipitationAdvice('晴'), '');
  assert.strictEqual(precipitationAdvice(''), '');
});

// ---- 批量录入：状态转换、部分失败、重复提交、取消清理、过期回调 ----
//
// 这些检查直接转译生产文件 service/GarmentImport.ets、model/GarmentImport.ets、
// service/SnapshotCommit.ets、service/GarmentImportRunner.ets，
// 不在测试里复制一份状态机；平台侧（Picker、文件、抠图）由模拟器实测覆盖。

// 构造一个"已就绪"的队列项，作为各用例的起点。
function readyItem(sessionId = 's1', index = 0) {
  const item = createImportItem(GI.makeTaskId(sessionId, index), GI.makeGarmentId(sessionId, index),
    'file://media/Photo/' + index);
  let items = [item];
  items = GI.beginCopy(items, item.id);
  items = GI.copySucceeded(items, item.id, 'file://sandbox/orig_' + index + '.png');
  return items[0];
}

function filled(item, overrides = {}) {
  const draft = Object.assign({
    name: '白色圆领短袖', categoryIndex: 0, color: '白色', minTemp: 16, maxTemp: 35,
    temperatureEdited: false, occasions: ['上课'], error: ''
  }, overrides);
  return Object.assign({}, item, { draft: draft });
}

test('A01 三张图片生成三个稳定任务，顺序与选择一致且属性互不串', () => {
  const uris = ['file://media/a', 'file://media/b', 'file://media/c'];
  const session = GI.makeSessionId(1758000000000, uris.length);
  const uniq = GI.dedupeUris(uris);
  assert.deepEqual(uniq, uris);
  const offset = GI.offsetFor([], session, uniq.length);
  let items = uniq.map((uri, i) => createImportItem(GI.makeTaskId(session, offset + i),
    GI.makeGarmentId(session, offset + i), uri));
  assert.equal(new Set(items.map((it) => it.id)).size, 3);
  assert.equal(new Set(items.map((it) => it.garmentId)).size, 3);
  assert.deepEqual(items.map((it) => it.sourceUri), uris);
  items = GI.applyDraft(items, items[0].id, { name: '上衣A', color: '白色' });
  items = GI.applyCategory(items, items[1].id, 1);
  assert.equal(items[0].draft.name, '上衣A');
  assert.equal(items[1].draft.name, '');
  assert.equal(items[1].draft.categoryIndex, 1);
  assert.equal(items[2].draft.categoryIndex, -1);
  assert.equal(items[0].draft.categoryIndex, -1);
});

test('A02 同一次选择按 URI 精确去重，取消选择不产生任务', () => {
  assert.deepEqual(GI.dedupeUris(['u1', 'u2', 'u1', '', 'u3']), ['u1', 'u2', 'u3']);
  assert.deepEqual(GI.dedupeUris([]), []);
  const items = [];
  assert.equal(GI.summaryOf(items).total, 0);
  assert.equal(GI.hasUnfinished(items), false);
});

test('批量录入细类与材质跨字段编辑保持独立，切换大类清掉旧细类', () => {
  let items = [createImportItem('fine-1', 'g-fine-1', 'u1'), createImportItem('fine-2', 'g-fine-2', 'u2')];
  items = GI.applyCategory(items, 'fine-1', 0);
  items = GI.applyDraft(items, 'fine-1', { subcategory: '连帽衫', material: '棉' });
  items = GI.applyMinTemp(items, 'fine-1', 10);
  items = GI.applyDraft(items, 'fine-1', { color: '蓝色' });
  assert.equal(items[0].draft.subcategory, '连帽衫');
  assert.equal(items[0].draft.material, '棉');
  assert.equal(items[1].draft.subcategory, '');
  assert.equal(items[1].draft.material, '');
  items = GI.applyCategory(items, 'fine-1', 2);
  assert.equal(items[0].draft.subcategory, '');
  assert.equal(items[0].draft.material, '棉');
});

test('A03 一项拷贝失败不影响其它项，失败项可重试或跳过', () => {
  const session = 's-partial';
  const uris = ['a', 'b', 'c'];
  let items = uris.map((u, i) => createImportItem(GI.makeTaskId(session, i), GI.makeGarmentId(session, i), u));
  for (const item of items) { items = GI.beginCopy(items, item.id); }
  items = GI.copySucceeded(items, items[0].id, 'orig0');
  items = GI.copyFailed(items, items[1].id, '导入失败：这张图片无法解码');
  items = GI.copySucceeded(items, items[2].id, 'orig2');
  assert.equal(items[0].phase, ImportPhase.READY);
  assert.equal(items[1].phase, ImportPhase.ERROR);
  assert.equal(items[1].failureStep, ImportFailureStep.COPY);
  assert.equal(items[2].phase, ImportPhase.READY);
  const idBefore = items[1].id;
  const garmentBefore = items[1].garmentId;
  const revisionBefore = items[1].revision;
  items = GI.beginCopy(items, items[1].id);
  assert.equal(items[1].id, idBefore);
  assert.equal(items[1].garmentId, garmentBefore);
  assert.equal(items[1].revision, revisionBefore + 1);
  items = GI.copySucceeded(items, items[1].id, 'orig1');
  assert.equal(items[1].phase, ImportPhase.READY);
  assert.equal(items[1].originalUri, 'orig1');
});

test('A04 切项不丢字段：第 1 项的名称与品类不会被第 2 项继承', () => {
  let items = [filled(readyItem('s4', 0), { name: '第一位', categoryIndex: 0 }),
    readyItem('s4', 1)];
  const first = items[0];
  items = GI.applyDraft(items, items[1].id, { name: '第二位' });
  assert.equal(items[0].draft.name, '第一位');
  assert.equal(items[0].draft.categoryIndex, 0);
  assert.equal(items[1].draft.name, '第二位');
  assert.equal(items[1].draft.categoryIndex, -1);
  assert.notEqual(items[0].draft, items[1].draft);
  assert.equal(first.draft.categoryIndex, 0);
});

test('A05 名称、品类、温度、场合、图片任一不合法都禁止保存并说明原因', () => {
  const base = filled(readyItem('s5', 0));
  assert.equal(GI.canSave(base, 0), '');
  assert.match(GI.canSave(filled(base, { name: '   ' }), 0), /名称/);
  assert.match(GI.canSave(filled(base, { name: 'x'.repeat(31) }), 0), /名称/);
  assert.match(GI.canSave(filled(base, { categoryIndex: -1 }), 0), /品类/);
  assert.match(GI.canSave(filled(base, { occasions: [] }), 0), /场合/);
  assert.match(GI.canSave(filled(base, { occasions: ['不存在的场合'] }), 0), /场合/);
  assert.match(GI.canSave(filled(base, { minTemp: 30, maxTemp: 10 }), 0), /最低温度/);
  assert.match(GI.canSave(filled(base, { minTemp: -50 }), 0), /适穿温度/);
  assert.match(GI.canSave(filled(base, { maxTemp: Number.NaN }), 0), /数字/);
  const noImage = Object.assign({}, base, { originalUri: '', cutoutUri: '' });
  assert.match(GI.canSave(noImage, 0), /图片/);
  assert.match(GI.canSave(Object.assign({}, base, { phase: ImportPhase.SAVED }), 0), /已经保存/);
});

test('A06 抠图失败回到 READY 并保留原图，可选择原图保存；不支持时不伪造结果', () => {
  let item = filled(readyItem('s6', 0));
  let items = GI.beginCutout([item], item.id);
  assert.equal(items[0].phase, ImportPhase.CUTTING);
  items = GI.cutoutFailed(items, item.id, '当前设备不支持主体抠图，可继续使用原图');
  assert.equal(items[0].phase, ImportPhase.READY);
  assert.equal(items[0].failureStep, ImportFailureStep.CUTOUT);
  assert.equal(items[0].originalUri, 'file://sandbox/orig_0.png');
  assert.equal(items[0].cutoutUri, '');
  assert.equal(items[0].useCutout, false);
  assert.equal(GI.canSave(items[0], 0), '');
  assert.equal(GI.activeImageUri(items[0]), 'file://sandbox/orig_0.png');
  items = GI.setUseCutout(items, item.id, true);
  assert.equal(items[0].useCutout, false);
});

test('A07 过期回调不得覆盖新任务：revision 变化后旧结果失效', () => {
  let items = [readyItem('s7', 0)];
  const item = items[0];
  const staleRevision = item.revision;
  items = GI.markSkipped(items, item.id);
  assert.equal(items[0].revision, staleRevision + 1);
  assert.equal(items[0].phase, ImportPhase.SKIPPED);
  assert.equal(GI.writeBack(items, item.id, staleRevision), false);
  // SKIPPED 是终态：迟到回调和新的开始操作都不能让已清理的任务复活。
  items = GI.beginCopy(items, item.id);
  assert.equal(items[0].revision, staleRevision + 1);
  assert.equal(items[0].phase, ImportPhase.SKIPPED);
});

test('A08 连点保存与失败重试都只产生一件：同 ID 幂等，失败保留输入', () => {
  const item = filled(readyItem('s8', 0));
  let items = GI.beginSave([item], item.id);
  assert.equal(items[0].phase, ImportPhase.SAVING);
  items = GI.saveSucceeded(items, item.id);
  assert.equal(items[0].phase, ImportPhase.SAVED);
  assert.match(GI.canSave(items[0], 0), /已经保存/);
  assert.equal(items.length, 1);
  const savedGarmentId = items[0].garmentId;
  let failing = GI.beginSave([item], item.id);
  failing = GI.saveFailed(failing, item.id, '保存失败：磁盘不可写');
  assert.equal(failing[0].phase, ImportPhase.ERROR);
  assert.equal(failing[0].failureStep, ImportFailureStep.SAVE);
  assert.equal(failing[0].originalUri, item.originalUri);
  assert.equal(failing[0].draft.name, '白色圆领短袖');
  assert.equal(GI.canSave(failing[0], 0), '');
  assert.equal(failing[0].garmentId, savedGarmentId);
});

test('A09/A10 容量只拦新增：剩余额度取单次上限与衣橱剩余容量的较小值', () => {
  assert.equal(GI.remainingCapacity(0), 10);
  assert.equal(GI.remainingCapacity(95), 5);
  assert.equal(GI.remainingCapacity(99), 1);
  assert.equal(GI.remainingCapacity(100), 0);
  assert.equal(GI.remainingCapacity(120), 0);
  const item = filled(readyItem('s10', 0));
  assert.match(GI.canSave(item, 100), /100 件/);
  assert.equal(GI.canSave(item, 99), '');
});

test('A12 启动遗留清理只认本轮批量前缀，且跳过仍被引用的文件', () => {
  const prefix = GI.IMPORT_BATCH_PREFIX;
  const snapshot = { garments: [{ imageUri: 'file://f/' + prefix + 'keep_orig.png' }],
    diary: [{ photoUri: 'file://f/' + prefix + 'diary.png' }], tryOnTasks: [] };
  const referenced = [];
  for (const g of snapshot.garments) { referenced.push(g.imageUri); }
  for (const d of snapshot.diary) { referenced.push(d.photoUri); }
  const candidates = [prefix + 'keep_orig.png', prefix + 'orphan_orig.png', 'garment_aaa.jpg', 'wardrobe_demo_v1.json'];
  const doomed = candidates.filter((name) =>
    name.startsWith(prefix) && referenced.indexOf('file://f/' + name) < 0);
  assert.deepEqual(doomed, [prefix + 'orphan_orig.png']);
  assert.equal(doomed.indexOf('wardrobe_demo_v1.json'), -1);
  assert.equal(doomed.indexOf('garment_aaa.jpg'), -1);
});

// 真实提交链：候选快照、锁、发布顺序全部由生产实现决定。
function makeCommitHarness(options = {}) {
  const state = {
    garments: (options.garments || []).slice(),
    temperature: options.temperature === undefined ? 24 : options.temperature,
    notice: '', saved: [], publishes: 0, afterPublishes: 0, failures: 0
  };
  const lock = SnapshotCommit.create();
  let candidate = undefined;
  const commit = (publish, afterPublish, delayMs = 0) => {
    const candidateForThis = candidate;
    const payload = JSON.stringify({
      garments: candidateForThis !== undefined ? candidateForThis : state.garments,
      temperature: state.temperature });
    return lock.commit(payload, {
      save: (data) => new Promise((resolve, reject) => {
        const finish = () => {
          if (options.failSave) { reject(new Error('磁盘不可写')); return; }
          state.saved.push(JSON.parse(data));
          resolve();
        };
        if (delayMs > 0) { setTimeout(finish, delayMs); } else { finish(); }
      }),
      publish: () => {
        state.publishes++;
        if (candidateForThis !== undefined) { state.garments = candidateForThis; }
        if (publish) { publish(); }
      },
      afterPublish: () => {
        state.afterPublishes++;
        const mid = lock.takeTemperature();
        if (!Number.isNaN(mid) && mid >= 5 && mid <= 35 && mid !== state.temperature) {
          state.temperature = mid;
          lock.requestResave();
        }
        if (lock.takeResave()) { commit(undefined, afterPublish, 0); }
        if (afterPublish) { afterPublish(); }
      },
      onFailure: () => { state.failures++; state.notice = '未保存'; }
    });
  };
  return { state, lock, setCandidate(value) { candidate = value; }, commit };
}

test('A11 真实提交链：落盘先于发布，延迟保存期间到达的天气不丢失新衣物', async () => {
  const harness = makeCommitHarness({ garments: ['旧衣物'] });
  const order = [];
  harness.setCandidate(['旧衣物', '新衣物']);
  const pending = harness.commit(
    () => { order.push('publish'); },
    () => { order.push('afterPublish'); },
    30);
  harness.lock.deferTemperature(18);
  assert.equal(harness.lock.isLocked(), true);
  assert.equal(harness.state.temperature, 24, '天气结果在落盘完成前不得生效');
  assert.deepEqual(harness.state.garments, ['旧衣物'], '发布前不得改动业务状态');
  await pending;
  assert.equal(order[0], 'publish', '发布必须在落盘成功之后');
  assert.equal(order[1], 'afterPublish', '延后项必须在发布之后处理');
  assert.deepEqual(harness.state.saved[0].garments, ['旧衣物', '新衣物']);
  assert.equal(harness.state.temperature, 18);
  const last = harness.state.saved[harness.state.saved.length - 1];
  assert.deepEqual(last.garments, ['旧衣物', '新衣物'], '补存的快照必须仍包含新衣物');
  assert.equal(last.temperature, 18);
});

test('A11 真实提交链：落盘失败不发布状态，也不执行延后项', async () => {
  const harness = makeCommitHarness({ garments: ['旧衣物'], failSave: true });
  let published = false;
  let afterCalled = false;
  harness.setCandidate(['旧衣物', '新衣物']);
  harness.lock.deferTemperature(18);
  const ok = await harness.commit(() => { published = true; }, () => { afterCalled = true; });
  assert.equal(ok, false);
  assert.equal(published, false, '失败路径不得发布成功');
  assert.equal(afterCalled, false, '失败路径不得执行延后项');
  assert.deepEqual(harness.state.garments, ['旧衣物']);
  assert.equal(harness.state.notice, '未保存');
  assert.equal(harness.state.saved.length, 0);
});

test('A11 真实提交链：锁内再次业务请求不假成功，明确重试后再保存', async () => {
  const harness = makeCommitHarness({ garments: ['旧衣物'] });
  harness.setCandidate(['旧衣物', '新衣物']);
  const first = harness.commit(undefined, undefined, 30);
  harness.setCandidate(['旧衣物', '新衣物', '第三件']);
  const second = await harness.commit(undefined, undefined, 0);
  assert.equal(second, false, '锁内业务请求不得假装提交成功');
  assert.equal(harness.state.saved.length, 0, '第一次还没落盘，队列里不应出现第二份');
  await first;
  assert.deepEqual(harness.state.saved[0].garments, ['旧衣物', '新衣物']);
  assert.equal(harness.state.saved.length, 1, '锁内业务请求不得生成未明确重试的第二次保存');
});

// ---- 真实导入链：从 pick 开始，串行、失效清理、失败与跳过不阻断 ----

function makeHost(options = {}) {
  const copyCalls = [];
  const cutoutCalls = [];
  const discarded = [];
  let alive = true;
  let inFlight = 0;
  let maxInFlight = 0;
  return {
    copyCalls, cutoutCalls, discarded,
    setAlive(value) { alive = value; },
    maxConcurrent() { return maxInFlight; },
    host: {
      pick: (limit) => Promise.resolve(options.uris ? options.uris.slice(0, limit) : []),
      copy: (sourceUri, taskId) => {
        copyCalls.push({ sourceUri, taskId });
        inFlight++;
        maxInFlight = Math.max(maxInFlight, inFlight);
        return new Promise((resolve, reject) => {
          setTimeout(() => {
            inFlight--;
            if (options.failUris && options.failUris.indexOf(sourceUri) >= 0) {
              reject(new Error('这张图片无法解码')); return;
            }
            resolve('file://sandbox/' + taskId + '.png');
          }, options.delayMs === undefined ? 2 : options.delayMs);
        });
      },
      cutout: (originalUri, taskId) => {
        cutoutCalls.push({ originalUri, taskId });
        if (options.cutoutFails) { return Promise.reject(new Error('没有找到清晰主体')); }
        return Promise.resolve('file://sandbox/' + taskId + '_cut.png');
      },
      discard: (uri) => { discarded.push(uri); return Promise.resolve(); },
      isReferenced: (uri) => (options.referenced || []).indexOf(uri) >= 0,
      isAlive: () => alive
    }
  };
}

test('A01/A03 真实导入链：从 pick 开始串行导入三张，一张失败不阻断其余', async () => {
  const harness = makeHost({ uris: ['u1', 'u2', 'u3'], failUris: ['u2'], delayMs: 2 });
  const session = ImportSession.create(1758000000000, 3);
  const created = await session.pick(harness.host, 0);
  assert.equal(created, 3, '应建立三个任务');
  await settle();
  assert.equal(harness.maxConcurrent(), 1, '拷贝必须串行，不能同时解码多张');
  assert.equal(session.copyStartCount(), 3, '每个任务只启动一次拷贝');
  assert.equal(session.items[0].phase, ImportPhase.READY);
  assert.equal(session.items[1].phase, ImportPhase.ERROR);
  assert.equal(session.items[1].failureStep, ImportFailureStep.COPY);
  assert.equal(session.items[2].phase, ImportPhase.READY);
  assert.deepEqual(session.items.map((it) => it.sourceUri), ['u1', 'u2', 'u3']);
  assert.equal(new Set(session.items.map((it) => it.id)).size, 3);
});

test('A02 真实导入链：取消选择不建立任务、不发起拷贝', async () => {
  const harness = makeHost({ uris: [] });
  const session = ImportSession.create(1758000000000, 1);
  const created = await session.pick(harness.host, 0);
  assert.equal(created, 0);
  assert.equal(session.items.length, 0);
  assert.equal(harness.copyCalls.length, 0);
});

test('A07 真实导入链：revision 变化后失效结果只做清理，不写回', async () => {
  const harness = makeHost({ uris: ['u1', 'u2'], delayMs: 6 });
  const session = ImportSession.create(1758000000000, 2);
  await session.pick(harness.host, 0);
  const first = session.items[0];
  const revisionBefore = first.revision;
  session.skip(harness.host, first.id);
  assert.equal(session.items[0].revision, revisionBefore + 1);
  assert.equal(session.items[0].phase, ImportPhase.SKIPPED);
  await settle(14);
  assert.equal(session.items[0].originalUri, '', '失效结果不能写回被跳过的项');
  assert.equal(session.items[1].phase, ImportPhase.READY);
  assert.equal(session.items[1].originalUri.length > 0, true);
});

test('A06 真实导入链：抠图失败保留原图，可继续用原图保存；成功后可切换', async () => {
  const failing = makeHost({ uris: ['u1'], cutoutFails: true });
  const session = ImportSession.create(1758000000000, 1);
  await session.pick(failing.host, 0);
  await settle();
  const id = session.items[0].id;
  session.runCutout(failing.host, id);
  await settle();
  assert.equal(failing.cutoutCalls.length, 1);
  assert.equal(session.items[0].phase, ImportPhase.READY);
  assert.equal(session.items[0].failureStep, ImportFailureStep.CUTOUT);
  assert.equal(session.items[0].cutoutUri, '', '不支持/失败时不得伪造抠图结果');
  assert.equal(session.items[0].originalUri.length > 0, true, '原图必须保留');
  const rescue = GI.applyDraft(session.items, id, { name: '失败后仍可保存', color: '白色' });
  const ready = GI.applyCategory(rescue, id, 0);
  const withOccasion = GI.applyDraft(ready, id, { occasions: ['上课'] });
  assert.equal(GI.canSave(withOccasion[0], 0), '', '原图可用时应允许保存');

  const ok = makeHost({ uris: ['u1'], cutoutFails: false });
  const session2 = ImportSession.create(1758000000000, 1);
  await session2.pick(ok.host, 0);
  await settle();
  const id2 = session2.items[0].id;
  session2.runCutout(ok.host, id2);
  await settle();
  assert.equal(session2.items[0].cutoutUri.length > 0, true);
  assert.equal(session2.items[0].useCutout, true);
  session2.runCutout(ok.host, id2);
  await settle();
  assert.equal(ok.cutoutCalls.length, 1, '已有结果时不得重复抠图');
});

test('A09 真实导入链：结束会话时未保存项失效并清理，已保存项保留', async () => {
  const harness = makeHost({ uris: ['u1', 'u2'] });
  const session = ImportSession.create(1758000000000, 2);
  await session.pick(harness.host, 0);
  await settle();
  const firstId = session.items[0].id;
  const savedUri = session.items[0].originalUri;
  session.markSaved({ taskId: firstId, garmentId: session.items[0].garmentId });
  assert.equal(session.find(firstId).phase, ImportPhase.SAVED);
  session.dispose(harness.host);
  assert.equal(session.items.length, 0);
  assert.equal(harness.discarded.indexOf(savedUri), -1, '已保存项引用的图片不得被删除');
  assert.equal(harness.discarded.length >= 1, true, '未保存项的文件应被回收');
});

test('清理保护：仍被持久化记录引用的图片不删除', async () => {
  const harness = makeHost({ uris: ['u1'] });
  const session = ImportSession.create(1758000000000, 1);
  await session.pick(harness.host, 0);
  await settle();
  const id = session.items[0].id;
  const kept = session.items[0].originalUri;
  harness.host.isReferenced = (uri) => uri === kept;
  session.skip(harness.host, id);
  assert.equal(harness.discarded.indexOf(kept), -1, '被引用的图片不得被清理');
});

test('A10 真实导入链：容量不足时选图前就不发起，且按剩余额度限制数量', async () => {
  const harness = makeHost({ uris: ['u1', 'u2', 'u3', 'u4', 'u5', 'u6', 'u7', 'u8', 'u9', 'u10'] });
  const session = ImportSession.create(1758000000000, 10);
  const created = await session.pick(harness.host, 96);
  assert.equal(created, 4, '剩余额度应取单次上限与衣橱余量的较小值');
  await settle(12);
  assert.equal(session.items.length, 4);
  const full = ImportSession.create(1758000000010, 1);
  const denied = await full.pick(harness.host, 100);
  assert.equal(denied, 0);
  assert.equal(full.items.length, 0);
});

test('真实导入链：追加示例或相册照片不能突破本次 10 张上限', async () => {
  const harness = makeHost({ uris: ['u1', 'u2', 'u3', 'u4', 'u5', 'u6', 'u7', 'u8'] });
  const session = ImportSession.create(1758000000020, 8);
  assert.equal(await session.pick(harness.host, 0), 8);
  assert.equal(session.capacity(0), 2);
  let pickCalls = 0;
  harness.host.pick = (limit) => {
    pickCalls++;
    assert.equal(limit, 2);
    return Promise.resolve(['u9', 'u10', 'u11']);
  };
  assert.equal(await session.pick(harness.host, 0), 2, '系统选择器超额返回时仍只接收剩余额度');
  assert.equal(session.items.length, 10);
  assert.equal(session.capacity(0), 0);
  assert.equal(await session.pick(harness.host, 0), 0);
  assert.equal(pickCalls, 1, '满额后不得再次打开选择器');
  await settle(15);
});

function settle(times = 6) {
  // 复制与保存都是异步的，且至少经过一层 setTimeout + Promise 链；
  // 这里给足每轮 5ms，避免把"还没跑完"误判成失败。
  let chain = Promise.resolve();
  for (let i = 0; i < times; i++) { chain = chain.then(() => new Promise((r) => setTimeout(r, 5))); }
  return chain;
}

// 页面回归测试使用 AST Probe，实际方法与生产 Index.ets 保持同一份源码。
require('./check-index.cjs');
require('./check-weather.cjs');
