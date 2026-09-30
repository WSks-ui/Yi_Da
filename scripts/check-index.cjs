const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const ts = require(process.argv[2] || 'typescript');

// check-domain.cjs 已注册 .ets loader；本文件也可单独运行，因此缺失时补一个最小转译器。
if (!require.extensions['.ets']) {
  require.extensions['.ets'] = (loadedModule, filename) => {
    const source = fs.readFileSync(filename, 'utf8');
    const output = ts.transpileModule(source, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    loadedModule._compile(output, filename);
  };
}

const IMPORT_MODEL = require('../entry/src/main/ets/model/GarmentImport.ets');
const { ImportFailureStep, ImportPhase } = IMPORT_MODEL;
const { ImportSession } = require('../entry/src/main/ets/service/GarmentImportRunner.ets');
const { GarmentImportController } = require('../entry/src/main/ets/service/GarmentImportController.ets');
const { SnapshotCommit } = require('../entry/src/main/ets/service/SnapshotCommit.ets');
const TRY_ON_DEMO = require('../entry/src/main/ets/service/TryOnDemo.ets');
const SYNC = require('../entry/src/main/ets/service/WardrobeSync.ets');
const MIGRATION = require('../entry/src/main/ets/service/WardrobeMigration.ets');
const GI = require('../entry/src/main/ets/service/GarmentImport.ets');
const RECOGNITION = require('../entry/src/main/ets/service/GarmentRecognition.ets');
const DADA = require('../entry/src/main/ets/service/DadaContext.ets');
const PRESENTATION = require('../entry/src/main/ets/service/TryOnPresentationController.ets');
const REPLIES = require('../entry/src/main/ets/service/AssistantReplyController.ets');
const AGENT = require('../entry/src/main/ets/service/OutfitAgent.ets');
const { replyClock } = require('./fixtures/reply-clock.cjs');

const INDEX_SOURCE_PATH = path.resolve(__dirname, '../entry/src/main/ets/pages/Index.ets');
const INDEX_SOURCE = fs.readFileSync(INDEX_SOURCE_PATH, 'utf8');
// ArkTS 的 `struct` 不是 TypeScript 关键字，TS 解析器会把它当成表达式的一部分，
// 于是找不到 Index 这个声明。这里只把 `struct X` 归一化成等长的 `class X` 再建 AST，
// 行号与列号保持不变，探针取到的成员文本仍来自同一份源码。
const INDEX_PARSABLE = INDEX_SOURCE.replace(/\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)/g,
  (match, name) => 'class ' + name);
const INDEX_FILE = ts.createSourceFile(INDEX_SOURCE_PATH, INDEX_PARSABLE, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
const IMPORT_PAGE_SOURCE_PATH = path.resolve(__dirname, '../entry/src/main/ets/pages/GarmentImportPage.ets');
const IMPORT_PAGE_SOURCE = fs.readFileSync(IMPORT_PAGE_SOURCE_PATH, 'utf8');

function decoratorName(decorator) {
  const expression = decorator.expression;
  if (ts.isIdentifier(expression)) { return expression.text; }
  if (expression && expression.name) { return expression.name.text; }
  if (expression && expression.expression && expression.expression.name) { return expression.expression.name.text; }
  return '';
}

function withoutDecorators(member) {
  let text = member.getText(INDEX_FILE);
  const decorators = ts.canHaveDecorators(member) ? (ts.getDecorators(member) || []) : [];
  if (decorators.length > 0) {
    text = text.slice(decorators[decorators.length - 1].end - member.getStart(INDEX_FILE)).trimStart();
  }
  return text;
}

function makeIndexProbe() {
  const struct = INDEX_FILE.statements.find((statement) => statement.name && statement.name.text === 'Index');
  assert.ok(struct, 'Index.ets 必须包含 Index struct');
  const members = struct.members.filter((member) => {
    if (member.kind === ts.SyntaxKind.PropertyDeclaration) { return true; }
    if (member.kind !== ts.SyntaxKind.MethodDeclaration || !member.name) { return false; }
    if (member.name.getText(INDEX_FILE) === 'build') { return false; }
    const decorators = ts.canHaveDecorators(member) ? (ts.getDecorators(member) || []) : [];
    return !decorators.some((decorator) => ['Builder', 'Styles'].indexOf(decoratorName(decorator)) >= 0);
  }).map(withoutDecorators);
  const probeSource = 'class Probe {\n' + members.join('\n') + '\n}';
  const output = ts.transpileModule(probeSource, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;

  class ProbeScroller { scrollTo() {} }
  class ProbeTabsController {}
  class ProbeRepository {}
  const platform = {
    cutout: () => Promise.reject(new Error('当前设备不支持主体抠图')),
    cutoutSupported: () => false,
    cutoutInFlight: () => false,
    bundledCopies: [],
    bundledImport(context, id, targetPath) {
      this.bundledCopies.push({ id, targetPath });
      return Promise.resolve('file://sandbox/' + id + '.png');
    },
    recognize: () => Promise.resolve({ category: '', color: '', material: '', confidence: 0,
      source: 'unavailable', userConfirmed: false }),
    migrationExport: () => Promise.resolve({ status: 'saved', message: '已保存' }),
    migrationPick: () => Promise.resolve({ status: 'cancelled', message: '已取消导入' })
  };
  const wardrobe = require('../entry/src/main/ets/model/Wardrobe.ets');
  const data = require('../entry/src/main/ets/data/DemoData.ets');
  const wearHistory = require('../entry/src/main/ets/service/WearHistory.ets');
  const outfitEngine = require('../entry/src/main/ets/service/OutfitEngine.ets');
  const cardData = require('../entry/src/main/ets/widget/CardData.ets');
  const deps = {
    ...wardrobe,
    ...data,
    ...wearHistory,
    ...outfitEngine,
    ...cardData,
    ...GI,
    ImportFailureStep,
    ImportPhase,
    ImportSession,
    GarmentImportController,
    SnapshotCommit,
    ...TRY_ON_DEMO,
    ...SYNC,
    ...MIGRATION,
    ...DADA,
    ...PRESENTATION,
    ...REPLIES,
    ...AGENT,
    AssistantMessageRole: { USER: 'user', ASSISTANT: 'assistant' },
    recognitionSummary: RECOGNITION.recognitionSummary,
    RECOGNITION_SOURCE_PIXEL_COLOR: RECOGNITION.RECOGNITION_SOURCE_PIXEL_COLOR,
    garmentModel: { classify: async () => undefined },
    activeImportImage: GI.activeImageUri,
    DemoRepository: ProbeRepository,
    readSnapshot: () => data.initialSnapshot(),
    validateSnapshot: (snapshot) => snapshot,
    exportWardrobeMigrationWithPicker: (...args) => platform.migrationExport(...args),
    selectMigrationPackageWithPicker: (...args) => platform.migrationPick(...args),
    createCoreFileMigrationTargetAdapter: () => ({
      isPrivateUri: (uri) => uri.startsWith('file://sandbox/'),
      destinationUri: (assetId) => 'file://sandbox/' + assetId + '.bin',
      write: async () => {}, remove: async () => {}
    }),
    util: { TextEncoder: class { encodeInto(value) { return Buffer.from(value, 'utf8'); } } },
    WeatherService: {
      setManualCity() {},
      clearManualCity() {},
      refresh: () => Promise.resolve({ available: false, city: '', condition: '', tempMin: 0, tempMax: 0, source: '手动温度' })
    },
    formProvider: {
      getPublishedRunningFormInfos: async () => [],
      updateForm: async () => {},
      openFormManager: () => {}
    },
    formBindingData: { createFormBindingData: () => ({}) },
    systemShare: {},
    uniformTypeDescriptor: {},
    hilog: { error() {}, warn() {}, info() {} },
    common: {},
    ConfigurationConstant: { ColorMode: { COLOR_MODE_DARK: 1 } },
    HdsTabsController: ProbeTabsController,
    Scroller: ProbeScroller,
    emptyDraft: () => ({ uri: '', name: '', categoryIndex: -1, color: '', minTemp: 12,
      maxTemp: 30, occasions: [], error: '' }),
    cutoutGarment: (...args) => platform.cutout(...args),
    cutoutSupported: () => platform.cutoutSupported(),
    cutoutInFlight: () => platform.cutoutInFlight(),
    bundledPhotoSource: (id) => ['demo_shirt', 'demo_jacket', 'demo_sneakers'].includes(id)
      ? 'bundled-garment-photo:' + id : '',
    bundledPhotoId: (source) => source.startsWith('bundled-garment-photo:')
      ? source.slice('bundled-garment-photo:'.length) : '',
    importBundledGarmentPhoto: (...args) => platform.bundledImport(...args),
    recognizeGarment: (uri) => platform.recognize(uri),
    $r: (value) => value,
    animateTo: (options, action) => action(),
    Curve: { FastOutSlowIn: 0 }
  };
  const names = Object.keys(deps);
  const Probe = new Function(...names, output + '\nreturn Probe;')(...names.map((name) => deps[name]));
  return { Probe, platform };
}

const INDEX_PROBE = makeIndexProbe();

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}

async function waitMs(milliseconds) {
  await new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function flushMicrotasks(times = 8) {
  for (let i = 0; i < times; i++) { await Promise.resolve(); }
}

function makeIndexRepository(options = {}) {
  return {
    uris: (options.uris || []).slice(),
    copyActions: (options.copyActions || []).slice(),
    cutoutCalls: [],
    discarded: [],
    chooseCalls: [],
    copyCalls: [],
    saveCalls: [],
    disk: [],
    saveHandler: options.saveHandler || (() => Promise.resolve()),
    chooseImages(limit) { this.chooseCalls.push(limit); return Promise.resolve(this.uris.slice(0, limit)); },
    importImage(sourceUri, targetPath) {
      this.copyCalls.push({ sourceUri, targetPath });
      const action = this.copyActions.length > 0 ? this.copyActions.shift() :
        Promise.resolve('file://sandbox/' + sourceUri + '.png');
      return action && action.promise ? action.promise : Promise.resolve(action);
    },
    originalPathFor(taskId) { return '/sandbox/' + taskId + '_orig.png'; },
    cutoutPathFor(taskId) { return '/sandbox/' + taskId + '_cut.png'; },
    savePayload(payload) {
      this.saveCalls.push(payload);
      return Promise.resolve().then(() => this.saveHandler(payload)).then(() => {
        this.disk.push(JSON.parse(payload));
      });
    },
    save(snapshot) { return this.savePayload(JSON.stringify(snapshot)); },
    discardImage(uri) { this.discarded.push(uri); return Promise.resolve(); },
    sweepOrphans() { return Promise.resolve(0); }
  };
}

function makeIndexPage(options = {}) {
  const page = new INDEX_PROBE.Probe();
  const repository = makeIndexRepository(options);
  const ui = { toasts: [], dialogs: [], dialog: () => Promise.resolve({ index: 1 }) };
  page.repository = repository;
  page.alive = true;
  page.mainRoute = options.mainRoute || 'garmentImport';
  page.sweepDone = true;
  page.readBlocked = false;
  page.getUIContext = () => ({
    getHostContext: () => ({ filesDir: '/sandbox', config: { colorMode: 0 } }),
    getPromptAction: () => ({
      showToast: ({ message }) => { ui.toasts.push(message); },
      showDialog: (dialog) => { ui.dialogs.push(dialog); return ui.dialog(); }
    })
  });
  return { page, repository, ui, platform: INDEX_PROBE.platform };
}

async function prepareIndexImport(page, repository, uris, copyActions) {
  repository.uris = uris.slice();
  repository.copyActions = (copyActions || []).slice();
  await page.pickImportPhotos();
  await flushMicrotasks();
  return page.importSessionRef();
}

function fillIndexDraft(page, index, name) {
  page.importName(index, name);
  page.importColor(index, '白色');
  page.importCategory(index, 0);
  page.importOccasions(index, ['上课']);
}

function findNoticeClickBody() {
  const struct = INDEX_FILE.statements.find((statement) => statement.name && statement.name.text === 'Index');
  const build = struct.members.find((member) => member.name && member.name.getText(INDEX_FILE) === 'build');
  let body = '';
  function visit(node, inNotice) {
    let notice = inNotice;
    if (node.kind === ts.SyntaxKind.IfStatement && node.expression &&
      node.expression.getText(INDEX_FILE).indexOf('this.notice.length') >= 0) { notice = true; }
    if (notice && node.kind === ts.SyntaxKind.CallExpression && node.expression &&
      node.expression.name && node.expression.name.text === 'onClick' && node.arguments.length > 0) {
      body = node.arguments[0].getText(INDEX_FILE);
    }
    ts.forEachChild(node, (child) => visit(child, notice));
  }
  visit(build, false);
  return body;
}

test('真实 UI 顶部保存提示点击 retryPersist，而不是重新构造普通 persist', () => {
  const handler = findNoticeClickBody();
  assert.ok(handler.length > 0, 'build 中必须有 notice 的 onClick');
  assert.match(handler, /retryPersist\s*\(/, '顶部提示必须接真实重试方法');
  assert.doesNotMatch(handler, /\.persist\s*\(/, '顶部提示不能绕过 pendingRetry 重新保存当前状态');
});

test('真实 UI：COPY 失败项显示重试导入并接回当前项 onRetry', () => {
  const copyBranch = IMPORT_PAGE_SOURCE.match(/else if \(this\.currentFailureStep\(\) === ImportFailureStep\.COPY\)[\s\S]*?\n      } else if/);
  assert.ok(copyBranch, 'GarmentImportPage 必须为 COPY 失败提供独立操作区');
  assert.match(copyBranch[0], /Button\('重试导入'/);
  assert.match(copyBranch[0], /enabled\(this\.currentCanEdit\(\)\)/,
    '重试导入必须沿用当前项的 busy/readBlocked/终态门禁');
  assert.match(copyBranch[0], /onRetry\(this\.currentIndex\)/);
});

test('真实 Index：订阅收到异步 READY，两个导入项字段独立且复制串行', async () => {
  const first = deferred();
  const second = deferred();
  const { page, repository } = makeIndexPage();
  const session = await prepareIndexImport(page, repository, ['u1', 'u2'], [first, second]);
  assert.equal(page.importItems.length, 2);
  assert.equal(page.importItems[0].phase, ImportPhase.COPYING);
  assert.equal(repository.copyCalls.length, 1, '首项未完成前只能启动一次复制');
  assert.equal(page.importItems[0].originalUri, '');
  first.resolve('file://sandbox/u1.png');
  await flushMicrotasks();
  assert.equal(session.find(page.importItems[0].id).phase, ImportPhase.READY);
  assert.equal(page.importItems[1].phase, ImportPhase.COPYING);
  assert.equal(repository.copyCalls.length, 2, '首项完成后才启动第二项复制');
  second.resolve('file://sandbox/u2.png');
  await flushMicrotasks();
  assert.equal(page.importItems[1].phase, ImportPhase.READY);
  page.importName(0, '第一件');
  page.importName(1, '第二件');
  assert.equal(page.importItems[0].draft.name, '第一件');
  assert.equal(page.importItems[1].draft.name, '第二件');
});

test('真实 Index：随包照片进入同一导入会话，确认后保存独立沙箱图片', async () => {
  const { page, repository, platform } = makeIndexPage();
  await page.pickImportSample('demo_shirt');
  await flushMicrotasks();
  assert.equal(page.importItems.length, 1);
  assert.equal(page.importItems[0].phase, ImportPhase.READY);
  assert.equal(page.importItems[0].sourceUri, 'bundled-garment-photo:demo_shirt');
  assert.equal(page.importItems[0].originalUri, 'file://sandbox/demo_shirt.png');
  assert.equal(platform.bundledCopies.length, 1);
  assert.equal(repository.copyCalls.length, 0, '随包资源不能误送系统相册 URI 读取路径');

  fillIndexDraft(page, 0, '新录入的衬衫');
  await page.importConfirm(0);
  await flushMicrotasks();
  assert.equal(repository.disk.length, 1);
  assert.equal(repository.disk[0].garments.length, 1);
  assert.equal(repository.disk[0].garments[0].imageUri, 'file://sandbox/demo_shirt.png');
  assert.equal(repository.disk[0].garments[0].isDemo, true);
  assert.equal(page.importItems[0].phase, ImportPhase.SAVED);
});

test('真实 Index：COPY 失败后重试导入复用任务并保留已填写字段', async () => {
  const { page, repository } = makeIndexPage();
  const session = await prepareIndexImport(page, repository, ['u1'],
    [Promise.reject(new Error('第一次导入失败')), Promise.resolve('file://sandbox/retry.png')]);
  await flushMicrotasks();
  assert.equal(session.items[0].phase, ImportPhase.ERROR);
  assert.equal(session.items[0].failureStep, ImportFailureStep.COPY);
  page.importName(0, '复制失败后重试');
  page.importColor(0, '白色');
  page.importCategory(0, 0);
  page.importOccasions(0, ['上课']);
  const callsBeforeRetry = repository.copyCalls.length;
  page.importRetry(0);
  await flushMicrotasks();
  assert.equal(repository.copyCalls.length, callsBeforeRetry + 1, '重试必须再次发起一次导入');
  assert.equal(session.items[0].phase, ImportPhase.READY);
  assert.equal(session.items[0].failureStep, ImportFailureStep.NONE);
  assert.equal(session.items[0].draft.name, '复制失败后重试');
  assert.equal(session.items[0].draft.categoryIndex, 0);
  assert.deepEqual(session.items[0].draft.occasions, ['上课']);
});

test('真实 Index：单件编辑失败后同会话可重试，切换衣物后旧重试失效', async () => {
  const data = require('../entry/src/main/ets/data/DemoData.ets');
  let shouldFail = true;
  const { page, repository } = makeIndexPage({ saveHandler: () => {
    if (shouldFail) { return Promise.reject(new Error('磁盘不可写')); }
    return Promise.resolve();
  }});
  page.garments = data.demoGarments();
  page.selectedItem = page.garments[0];
  page.showSheet = true;
  page.openEdit();
  page.draft.name = '同会话重试';
  await page.addGarment();
  await flushMicrotasks();
  assert.equal(repository.saveCalls.length, 1);
  assert.equal(typeof page.pendingRetry, 'function');
  shouldFail = false;
  page.retryPersist();
  await flushMicrotasks();
  assert.equal(repository.saveCalls.length, 2, '同一编辑会话的失败保存应可重试');
  assert.equal(page.garments[0].name, '同会话重试');

  shouldFail = true;
  page.selectedItem = page.garments[1];
  page.openEdit();
  page.draft.name = '新衣物草稿';
  await page.addGarment();
  await flushMicrotasks();
  assert.equal(typeof page.pendingRetry, 'function');
  const savesBeforeSwitchRetry = repository.saveCalls.length;
  page.selectedItem = page.garments[2];
  page.openEdit();
  page.retryPersist();
  await flushMicrotasks();
  assert.equal(repository.saveCalls.length, savesBeforeSwitchRetry,
    '切换编辑对象后旧失败重试不得提交新对象草稿');
});

test('真实 Index：importConfirm 落盘成功后标记 SAVED，退出保留已用图片', async () => {
  const copy = deferred();
  const { page, repository } = makeIndexPage();
  const session = await prepareIndexImport(page, repository, ['u1'], [copy]);
  copy.resolve('file://sandbox/u1.png');
  await flushMicrotasks();
  fillIndexDraft(page, 0, '第一件');
  await page.importConfirm(0);
  await flushMicrotasks();
  const item = session.find(page.importItems[0].id);
  assert.equal(item.phase, ImportPhase.SAVED);
  assert.equal(page.garments.length, 1);
  assert.equal(repository.disk.length, 1);
  const used = item.originalUri;
  page.importExit();
  await flushMicrotasks();
  assert.equal(page.mainRoute, 'tabs');
  assert.equal(repository.discarded.indexOf(used), -1, '已保存项引用的图片必须保留');
});

test('真实 Index：跳过第一张后不能选回并保存已删除 URI，SAVED/SKIPPED 不能被编辑或复活', async () => {
  const first = deferred();
  const second = deferred();
  const { page, repository, ui } = makeIndexPage();
  const session = await prepareIndexImport(page, repository, ['u1', 'u2'], [first, second]);
  first.resolve('file://sandbox/u1.png');
  await flushMicrotasks();
  second.resolve('file://sandbox/u2.png');
  await flushMicrotasks();
  fillIndexDraft(page, 0, '待跳过');
  ui.dialog = () => Promise.resolve({ index: 1 });
  page.importSkip(0);
  await flushMicrotasks();
  const skipped = session.items[0];
  assert.equal(skipped.phase, ImportPhase.SKIPPED);
  assert.notEqual(GI.canSave(skipped, 0), '', 'SKIPPED 项必须始终不可保存');
  const skippedBefore = JSON.stringify(skipped);
  page.importMove(0);
  page.importName(0, '不应复活');
  page.importCategory(0, 1);
  page.importCutout(0);
  page.importRetry(0);
  await flushMicrotasks();
  assert.equal(JSON.stringify(session.items[0]), skippedBefore);
  const savesBefore = repository.saveCalls.length;
  await page.importConfirm(0);
  assert.equal(repository.saveCalls.length, savesBefore, '已删除项不得写入旧 URI');

  fillIndexDraft(page, 1, '可保存');
  await page.importConfirm(1);
  await flushMicrotasks();
  const saved = session.items[1];
  assert.equal(saved.phase, ImportPhase.SAVED);
  const savedBefore = JSON.stringify(saved);
  page.importName(1, '不应编辑');
  page.importCutout(1);
  page.importRetry(1);
  await flushMicrotasks();
  assert.equal(JSON.stringify(session.items[1]), savedBefore, 'SAVED 项不得被编辑、抠图或重试复活');
});

test('真实 Index：onCardOpen 在 COPYING、CUTTING、未保存和全部完成场景都经过 importExit', async () => {
  const copy = deferred();
  const { page, repository, platform, ui } = makeIndexPage();
  await prepareIndexImport(page, repository, ['u1'], [copy]);
  page.onCardOpen();
  assert.equal(page.mainRoute, 'garmentImport', 'COPYING 时卡片入口不能直接切回 tabs');
  copy.resolve('file://sandbox/u1.png');
  await flushMicrotasks();
  const cutout = deferred();
  platform.cutoutSupported = () => true;
  platform.cutout = () => cutout.promise;
  page.importCutout(0);
  assert.equal(page.importItems[0].phase, ImportPhase.CUTTING);
  page.onCardOpen();
  assert.equal(page.mainRoute, 'garmentImport', 'CUTTING 时卡片入口不能直接切回 tabs');
  cutout.resolve('file://sandbox/u1_cut.png');
  await flushMicrotasks();
  fillIndexDraft(page, 0, '未保存');
  ui.dialog = () => Promise.resolve({ index: 0 });
  page.onCardOpen();
  await flushMicrotasks();
  assert.equal(page.mainRoute, 'garmentImport', '未保存项必须先经过退出确认');
  ui.dialog = () => Promise.resolve({ index: 1 });
  page.onCardOpen();
  await flushMicrotasks();
  assert.equal(page.mainRoute, 'tabs');

  const complete = makeIndexPage();
  const doneCopy = deferred();
  const doneSession = await prepareIndexImport(complete.page, complete.repository, ['u2'], [doneCopy]);
  doneCopy.resolve('file://sandbox/u2.png');
  await flushMicrotasks();
  fillIndexDraft(complete.page, 0, '已完成');
  await complete.page.importConfirm(0);
  await flushMicrotasks();
  assert.equal(doneSession.items[0].phase, ImportPhase.SAVED);
  complete.page.onCardOpen();
  await flushMicrotasks();
  assert.equal(complete.page.mainRoute, 'tabs', '全部完成时也必须走统一退出清理');
});

test('真实 Index：卡片退出取消后等待与订阅重发都不重复弹框，确认后页签回到今日', async () => {
  const copy = deferred();
  const { page, repository, ui } = makeIndexPage();
  const session = await prepareIndexImport(page, repository, ['u1'], [copy]);
  // 先在复制进行中请求卡片入口，复制结束后由订阅回调安排退出确认。
  ui.dialog = () => Promise.resolve({ index: 0 });
  page.onCardOpen();
  copy.resolve('file://sandbox/u1.png');
  await flushMicrotasks();
  await waitMs(20);
  assert.equal(ui.dialogs.length, 1, '导入稳定后只应显示一次退出确认');
  await flushMicrotasks();
  assert.equal(page.mainRoute, 'garmentImport');

  // 取消后再发布一次会话快照，不能因旧的卡片请求再次拉起对话框。
  page.importName(0, '取消后继续编辑');
  await flushMicrotasks();
  await waitMs(140);
  assert.equal(ui.dialogs.length, 1, '取消卡片退出后等待与订阅重发都不得再次弹框');
  assert.equal(session.items[0].phase, ImportPhase.READY);

  // 确认退出后等待程序化切页签的 140ms 动画，最终必须停在今日页。
  page.tab = 2;
  ui.dialog = () => Promise.resolve({ index: 1 });
  page.onCardOpen();
  await flushMicrotasks();
  assert.equal(ui.dialogs.length, 2, '再次请求卡片入口才允许重新显示退出确认');
  await waitMs(180);
  assert.equal(page.mainRoute, 'tabs');
  assert.equal(page.tab, 0, '卡片确认退出后的页签必须回到今日');
});

test('真实 Index：普通返回确认期间收到卡片请求，取消后编辑不会再次弹框', async () => {
  const { page, repository, ui } = makeIndexPage();
  const session = await prepareIndexImport(page, repository, ['u1'], [Promise.resolve('file://sandbox/u1.png')]);
  const dialogResult = deferred();
  ui.dialog = () => dialogResult.promise;
  page.importExit();
  assert.equal(ui.dialogs.length, 1);
  page.onCardOpen();
  assert.equal(page.pendingImportCardOpen, true, '对话框打开期间卡片请求应暂存到当前会话');
  dialogResult.resolve({ index: 0 });
  await flushMicrotasks();
  assert.equal(page.pendingImportCardOpen, false, '普通返回取消必须清掉当前会话的卡片请求');
  page.importName(0, '取消后继续编辑');
  await flushMicrotasks();
  await waitMs(20);
  assert.equal(ui.dialogs.length, 1, '后续编辑不得被旧卡片请求再次弹框');
  assert.equal(session.items[0].draft.name, '取消后继续编辑');
});

test('真实 Index：importCutout 成功后切回原图，再次抠图复用已有结果', async () => {
  const copy = deferred();
  const cutout = deferred();
  const { page, repository, platform } = makeIndexPage();
  await prepareIndexImport(page, repository, ['u1'], [copy]);
  copy.resolve('file://sandbox/u1.png');
  await flushMicrotasks();
  platform.cutoutSupported = () => true;
  platform.cutout = () => {
    repository.cutoutCalls.push('cutout');
    return cutout.promise;
  };
  page.importCutout(0);
  assert.equal(repository.cutoutCalls.length, 1);
  cutout.resolve('file://sandbox/u1_cut.png');
  await flushMicrotasks();
  assert.equal(page.importItems[0].useCutout, true);
  page.importUseOriginal(0);
  assert.equal(page.importItems[0].useCutout, false);
  page.importCutout(0);
  await flushMicrotasks();
  assert.equal(repository.cutoutCalls.length, 1, '已有抠图结果时不得重复调用抠图服务');
  assert.equal(page.importItems[0].useCutout, true, '已有抠图结果再次选择时必须切回抠图版本');
  assert.equal(GI.activeImageUri(page.importItems[0]), 'file://sandbox/u1_cut.png',
    '再次选择抠图后保存/展示 URI 必须指向已有结果');
});

test('真实 Index：ERROR(SAVE) 保留原图并允许继续抠图', async () => {
  const copy = Promise.resolve('file://sandbox/u1.png');
  const { page, repository, platform } = makeIndexPage({
    copyActions: [copy],
    saveHandler: () => Promise.reject(new Error('磁盘不可写'))
  });
  const session = await prepareIndexImport(page, repository, ['u1'], [copy]);
  fillIndexDraft(page, 0, '保存失败后抠图');
  await page.importConfirm(0);
  await flushMicrotasks();
  assert.equal(session.items[0].phase, ImportPhase.ERROR);
  assert.equal(session.items[0].failureStep, ImportFailureStep.SAVE);
  assert.equal(session.items[0].originalUri, 'file://sandbox/u1.png');

  const cutout = deferred();
  platform.cutoutSupported = () => true;
  platform.cutout = () => {
    repository.cutoutCalls.push('cutout');
    return cutout.promise;
  };
  page.importCutout(0);
  assert.equal(session.items[0].phase, ImportPhase.CUTTING, '保存失败项仍应允许使用原图进入抠图');
  assert.equal(repository.cutoutCalls.length, 1);
  cutout.resolve('file://sandbox/u1_cut.png');
  await flushMicrotasks();
  assert.equal(session.items[0].phase, ImportPhase.READY);
  assert.equal(session.items[0].useCutout, true);
  assert.equal(GI.activeImageUri(session.items[0]), 'file://sandbox/u1_cut.png');
});

test('真实 Index：启动遗留清理未完成时单件 pickPhoto 不打开 Picker 也不创建文件', async () => {
  const { page, repository, ui } = makeIndexPage({ uris: ['u1'] });
  page.sweepDone = false;
  page.sheet = 'add';
  page.showSheet = true;
  await page.pickPhoto();
  assert.equal(repository.chooseCalls.length, 0, '清理未完成时不应打开系统 Picker');
  assert.equal(repository.copyCalls.length, 0, '清理未完成时不应创建单件导入文件');
  assert.equal(page.draft.uri, '');
  assert.equal(ui.toasts.length, 1);
});

test('真实 Index：延迟 persist 时 upsertOutfit 不假成功，最终磁盘与内存一致', async () => {
  const save = deferred();
  const { page, repository } = makeIndexPage({ saveHandler: () => save.promise });
  page.mainRoute = 'tabs';
  const look = { id: 'diy_new', garmentIds: [], occasion: '上课', temperature: 24, reason: '',
    name: '我的搭配', isCustom: true, savedAt: '' };
  page.persist();
  const second = page.upsertOutfit(look);
  await assert.rejects(second, /保存|忙|进行/);
  assert.equal(page.saved.length, 0);
  assert.equal(repository.disk.length, 0);
  save.resolve();
  await flushMicrotasks();
  assert.equal(repository.disk.length, 1);
  assert.deepEqual(repository.disk[0].saved, []);
});

test('真实 Index：DIY 保存失败后顶部重试保存对应候选，persist 失败也有重试入口', async () => {
  let fail = true;
  const { page, repository } = makeIndexPage({ saveHandler: () => {
    if (fail) { fail = false; return Promise.reject(new Error('磁盘不可写')); }
    return Promise.resolve();
  }});
  page.mainRoute = 'tabs';
  const look = { id: 'diy_retry', garmentIds: [], occasion: '上课', temperature: 24, reason: '',
    name: '重试方案', isCustom: true, savedAt: '' };
  await assert.rejects(page.upsertOutfit(look));
  assert.equal(page.saved.length, 0);
  assert.equal(typeof page.pendingRetry, 'function');
  page.retryPersist();
  await flushMicrotasks();
  assert.deepEqual(page.saved.map((item) => item.id), ['diy_retry']);

  fail = true;
  page.temperature = 23;
  page.persist();
  await flushMicrotasks();
  assert.equal(typeof page.pendingRetry, 'function', '普通 persist 失败也必须保留重试闭包');
  page.retryPersist();
  await flushMicrotasks();
  assert.equal(repository.disk[repository.disk.length - 1].temperature, 23);
});

test('真实 Index：成功的普通 persist 不清除已有 DIY pendingRetry', async () => {
  let fail = true;
  const { page } = makeIndexPage({ saveHandler: () => {
    if (fail) { fail = false; return Promise.reject(new Error('磁盘不可写')); }
    return Promise.resolve();
  }});
  page.mainRoute = 'tabs';
  const look = { id: 'diy_keep_retry', garmentIds: [], occasion: '上课', temperature: 24, reason: '',
    name: '保留重试', isCustom: true, savedAt: '' };
  await assert.rejects(page.upsertOutfit(look));
  const retry = page.pendingRetry;
  assert.equal(typeof retry, 'function');
  page.persist();
  await flushMicrotasks();
  assert.equal(page.pendingRetry, retry, '普通成功持久化不得吞掉未完成的 DIY 重试');
  page.retryPersist();
  await flushMicrotasks();
  assert.deepEqual(page.saved.map((item) => item.id), ['diy_keep_retry']);
});

test('真实 Index：天气触发的成功 persist 不清除已有导入 pendingRetry', async () => {
  let fail = true;
  const { page, repository } = makeIndexPage({ saveHandler: () => {
    if (fail) { fail = false; return Promise.reject(new Error('磁盘不可写')); }
    return Promise.resolve();
  }});
  const copy = Promise.resolve('file://sandbox/weather_retry.png');
  const session = await prepareIndexImport(page, repository, ['weather_retry'], [copy]);
  fillIndexDraft(page, 0, '天气重试衣物');
  await page.importConfirm(0);
  await flushMicrotasks();
  assert.equal(session.items[0].failureStep, ImportFailureStep.SAVE);
  const retry = page.pendingRetry;
  assert.equal(typeof retry, 'function');
  page.applyTemperature(18);
  await flushMicrotasks();
  assert.equal(page.temperature, 18);
  assert.equal(page.pendingRetry, retry, '天气成功持久化不得吞掉未完成的导入重试');
  page.retryPersist();
  await flushMicrotasks();
  assert.equal(session.items[0].phase, ImportPhase.SAVED);
});

test('真实 Index：日记保存失败不发布候选，后续 DIY 保存不夹带失败日记与衣物', async () => {
  let fail = true;
  const { page, repository } = makeIndexPage({ saveHandler: () => {
    if (fail) { fail = false; return Promise.reject(new Error('磁盘不可写')); }
    return Promise.resolve();
  }});
  page.mainRoute = 'tabs';
  page.garments = ['现有衣物'];
  page.diary = [{ id: 'd1' }];
  const change = { diary: [{ id: 'd1' }, { id: 'd2' }], records: [], garments: ['草稿衣物'], error: '' };
  // 生产入口接收变更工厂，以便重试时基于最新已发布状态重新构造候选。
  await assert.rejects(page.commitDiary(() => change));
  assert.deepEqual(page.garments, ['现有衣物']);
  assert.deepEqual(page.diary, [{ id: 'd1' }]);
  const look = { id: 'diy_after_diary', garmentIds: [], occasion: '上课', temperature: 24, reason: '',
    name: '后续方案', isCustom: true, savedAt: '' };
  await page.upsertOutfit(look);
  await flushMicrotasks();
  const written = repository.disk[repository.disk.length - 1];
  assert.deepEqual(written.garments, ['现有衣物']);
  assert.deepEqual(written.diary, [{ id: 'd1' }]);
  assert.deepEqual(written.saved.map((item) => item.id), ['diy_after_diary']);
});

test('真实 Index：resetDemo 延迟落盘期间天气只延后应用，补存后磁盘与内存一致', async () => {
  const resetSave = deferred();
  const weatherSave = deferred();
  const saves = [resetSave, weatherSave];
  const { page, repository, ui } = makeIndexPage({ saveHandler: () => {
    const next = saves.shift();
    return next ? next.promise : Promise.resolve();
  }});
  page.mainRoute = 'tabs';
  // resetDemo 的清理逻辑按真实 Garment 读取 imageUri，这里使用最小合法衣物对象，
  // 避免测试替身触发与业务场景无关的异步 TypeError。
  page.garments = [{ id: 'old', imageUri: 'file://sandbox/old.png' }];
  page.temperature = 24;
  ui.dialog = () => Promise.resolve({ index: 1 });
  page.resetDemo();
  await flushMicrotasks();
  assert.equal(repository.saveCalls.length, 1);
  page.applyTemperature(18);
  assert.equal(page.temperature, 24, '提交进行中天气不得改写正在落盘的快照');
  assert.equal(page.garments[0].id, 'old', '发布前不得先显示重置候选');
  resetSave.resolve();
  await flushMicrotasks();
  assert.equal(page.temperature, 18);
  assert.deepEqual(page.garments, require('../entry/src/main/ets/data/DemoData.ets').initialSnapshot().garments);
  weatherSave.resolve();
  await flushMicrotasks();
  const last = repository.disk[repository.disk.length - 1];
  assert.deepEqual(last.garments, page.garments);
  assert.equal(last.temperature, page.temperature);
});

test('真实 Index：旧导入会话退出后 pendingRetry 失效，新会话索引 0 不会重试旧保存', async () => {
  let fail = true;
  const { page, repository, ui, platform } = makeIndexPage({ saveHandler: () => {
    if (fail) { fail = false; return Promise.reject(new Error('磁盘不可写')); }
    return Promise.resolve();
  }});
  const copy = deferred();
  const session = await prepareIndexImport(page, repository, ['u1'], [copy]);
  copy.resolve('file://sandbox/u1.png');
  await flushMicrotasks();
  fillIndexDraft(page, 0, '旧项');
  await page.importConfirm(0);
  await flushMicrotasks();
  assert.equal(session.items[0].phase, ImportPhase.ERROR);
  assert.equal(typeof page.pendingRetry, 'function');
  ui.dialog = () => Promise.resolve({ index: 1 });
  page.importExit();
  await flushMicrotasks();
  assert.equal(page.pendingRetry, undefined);
  page.mainRoute = 'garmentImport';
  const nextCopy = deferred();
  await prepareIndexImport(page, repository, ['u2'], [nextCopy]);
  nextCopy.resolve('file://sandbox/u2.png');
  await flushMicrotasks();
  page.retryPersist();
  await flushMicrotasks();
  assert.equal(page.importItems[0].phase, ImportPhase.READY);
  assert.equal(repository.disk.length, 0, '新会话不得被旧保存闭包误提交');
});

test('真实 Index：试穿提交先落盘再发布，且不消耗会员额度', async () => {
  const save = deferred();
  const { page, repository } = makeIndexPage({ saveHandler: () => save.promise });
  page.mainRoute = 'tabs';
  page.membership = { startDate: '2026-09-01T00:00:00.000Z', trialDays: 7, tryOnUsed: 3 };
  const pending = page.submitTryOn('denim_skirt');
  await flushMicrotasks();
  assert.equal(page.tryOnTasks.length, 0, '落盘完成前不能发布试穿任务');
  assert.equal(repository.disk.length, 0);
  assert.equal(page.membership.tryOnUsed, 3, '演示样片不能消耗会员额度');
  save.resolve();
  await pending;
  assert.equal(page.tryOnTasks.length, 1);
  assert.equal(page.tryOnTasks[0].demoSceneId, 'denim_skirt');
  assert.equal(page.tryOnTasks[0].status, '演示样片');
  assert.equal(page.tryOnTasks[0].resultUris.length, 0);
  assert.equal(page.membership.tryOnUsed, 3);
  assert.equal(repository.disk[0].membership.tryOnUsed, 3);
});

test('真实 Index：试穿提交失败不发布，顶部重试按当前快照重新构造候选', async () => {
  let fail = true;
  const { page, repository } = makeIndexPage({ saveHandler: () => {
    if (fail) { fail = false; return Promise.reject(new Error('磁盘不可写')); }
    return Promise.resolve();
  }});
  page.mainRoute = 'tabs';
  await assert.rejects(page.submitTryOn('navy_top'), /保存/);
  assert.equal(page.tryOnTasks.length, 0, '保存失败时内存不能提前出现任务');
  assert.equal(repository.disk.length, 0);
  assert.equal(typeof page.pendingRetry, 'function');
  page.retryPersist();
  await flushMicrotasks();
  assert.deepEqual(page.tryOnTasks.map((task) => task.demoSceneId), ['navy_top']);
  assert.deepEqual(repository.disk[0].tryOnTasks.map((task) => task.demoSceneId), ['navy_top']);
});

test('真实 Index：删除试穿任务失败时保留内存与磁盘记录', async () => {
  const original = TRY_ON_DEMO.createDemoTask('red_dress', new Date('2026-09-18T01:02:03.000Z'));
  const { page, repository } = makeIndexPage({ saveHandler: () => Promise.reject(new Error('磁盘不可写')) });
  page.mainRoute = 'tabs';
  page.tryOnTasks = [original];
  await assert.rejects(page.deleteTryOnTask(original.id), /删除|保存/);
  assert.deepEqual(page.tryOnTasks.map((task) => task.id), [original.id]);
  assert.equal(repository.disk.length, 0);
  assert.equal(typeof page.pendingRetry, 'function');
});

test('真实 Index：重启恢复的同一场景再次提交幂等，不新增任务也不重复落盘', async () => {
  const first = makeIndexPage();
  first.page.mainRoute = 'tabs';
  await first.page.submitTryOn('denim_skirt');
  assert.equal(first.page.tryOnTasks.length, 1);
  const restored = first.repository.disk[0].tryOnTasks;
  const second = makeIndexPage();
  second.page.mainRoute = 'tabs';
  second.page.tryOnTasks = restored;
  await second.page.submitTryOn('denim_skirt');
  assert.equal(second.page.tryOnTasks.length, 1);
  assert.equal(second.repository.saveCalls.length, 0, '幂等重复提交不应生成第二份快照');
});

test('真实 Index：容量只拒绝新增场景，满额时已有场景仍可幂等返回', async () => {
  const fullTasks = [TRY_ON_DEMO.createDemoTask('denim_skirt', new Date('2026-09-18T01:02:03.000Z'))];
  for (let index = 1; index < 50; index++) {
    fullTasks.push({ id: 'task_' + index, outfitId: '', garmentIds: [], pose: '正面站姿',
      createdAt: '2026-09-18T01:02:03.000Z', status: '演示样片', resultUris: [], message: '测试记录' });
  }
  const { page, repository } = makeIndexPage();
  page.mainRoute = 'tabs';
  page.tryOnTasks = fullTasks;
  await assert.rejects(page.submitTryOn('navy_top'), /已满/);
  assert.equal(page.tryOnTasks.length, 50);
  await page.submitTryOn('denim_skirt');
  assert.equal(page.tryOnTasks.length, 50);
  assert.equal(repository.saveCalls.length, 0);
});

test('真实 Index：未知试穿场景被拒绝，不能写入任意样片任务', async () => {
  const { page, repository } = makeIndexPage();
  page.mainRoute = 'tabs';
  await assert.rejects(page.submitTryOn('not_a_demo_scene'), /未知/);
  assert.equal(page.tryOnTasks.length, 0);
  assert.equal(repository.saveCalls.length, 0);
});

test('试穿日期格式化按本地时区转换，并兼容旧格式与非法历史值', () => {
  const iso = '2026-09-18T01:02:03.000Z';
  const date = new Date(iso);
  const pad = (value) => String(value).padStart(2, '0');
  const expected = date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate()) + ' ' +
    pad(date.getHours()) + ':' + pad(date.getMinutes());
  assert.equal(TRY_ON_DEMO.formatTryOnDate(iso), expected);
  assert.equal(TRY_ON_DEMO.formatTryOnDate('2026-09-18 09:02'), '2026-09-18 09:02');
  assert.equal(TRY_ON_DEMO.formatTryOnDate('旧版未知时间'), '旧版未知时间');
});

test('真实 Index：试穿入口保存场景选择，未知场景回落牛仔半裙', () => {
  const { page } = makeIndexPage();
  page.mainRoute = 'tabs';
  page.openTryOn('navy_top');
  assert.equal(page.mainRoute, 'tryOn');
  assert.equal(page.tryOnSceneId, 'navy_top');
  page.mainRoute = 'tabs';
  page.openTryOn('not_a_demo_scene');
  assert.equal(page.tryOnSceneId, 'denim_skirt');
  assert.equal(page.mainRoute, 'tryOn');
  page.mainRoute = 'tabs';
  page.openTryOn();
  assert.equal(page.tryOnSceneId, 'denim_skirt');
});

test('真实 Index：各试穿入口统一走 openTryOn，并向页面传递 initialSceneId', () => {
  assert.match(INDEX_SOURCE, /onOpenTryOn: \(\) => \{ this\.openTryOn\(\); \}/);
  assert.match(INDEX_SOURCE, /onTryOn: \(look: Outfit\) => \{ this\.selectedLook = look; this\.openTryOn\(\); \}/);
  assert.match(INDEX_SOURCE, /onOpenTryOn: \(sceneId\?: string\) => \{ this\.openTryOn\(sceneId\); \}/);
  assert.match(INDEX_SOURCE, /initialSceneId: this\.tryOnSceneId/);
});

test('试穿演示：三姿势资源契约只声明已有正面素材，不混用其他样片', () => {
  assert.deepEqual(TRY_ON_DEMO.DEMO_POSES.map((pose) => pose.id), ['front', 'side', 'back']);
  const mediaSource = fs.readFileSync(
    path.resolve(__dirname, '../entry/src/main/ets/service/TryOnDemoMedia.ets'), 'utf8');
  assert.match(mediaSource, /if \(poseId === 'front'\) \{ return demoImages\(sceneId\)\.result; \}/);
  assert.match(mediaSource, /return undefined;/,
    '侧面和背面缺少同组素材时必须保持不可用');
});

test('真实 Index：图片主色分析迟到不覆盖手动颜色，采用后只更新对应任务', async () => {
  const { page, repository, platform } = makeIndexPage();
  await prepareIndexImport(page, repository, ['photo-a', 'photo-b']);
  const gate = deferred();
  platform.recognize = () => gate.promise;
  page.importColor(0, '黑色');
  const pending = page.recognizeImportColor(0);
  page.importMove(1);
  gate.resolve({ category: '', color: '红色', material: '', confidence: 0.78,
    source: 'offline-pixel-color', colorSource: 'offline-pixel-color', colorConfidence: 0.78,
    userConfirmed: false });
  await pending;
  assert.equal(page.importItems[0].draft.color, '黑色');
  assert.equal(page.importItems[1].draft.color, '');
  assert.equal(page.importRecognitionHints[0].taskId, page.importItems[0].id);
  page.useRecognizedColor(0);
  assert.equal(page.importItems[0].draft.color, '红色');
  assert.equal(page.importItems[1].draft.color, '');
});

test('真实 Index：用户选择的细类和材质逐项保存，不从图片猜测', async () => {
  const { page, repository } = makeIndexPage();
  await prepareIndexImport(page, repository, ['photo-a', 'photo-b']);
  fillIndexDraft(page, 0, '连帽衫');
  page.importSubcategory(0, '连帽衫');
  page.importMaterial(0, '棉');
  fillIndexDraft(page, 1, '黑裤');
  assert.equal(page.importItems[1].draft.subcategory, '');
  assert.equal(page.importItems[1].draft.material, '');
  await page.importConfirm(0);
  assert.equal(repository.disk[0].garments.at(-1).subcategory, '连帽衫');
  assert.equal(repository.disk[0].garments.at(-1).material, '棉');
});

test('真实 Index：身材档案先落盘再发布，并把新推荐选择写入同一快照', async () => {
  const gate = deferred();
  const { page, repository } = makeIndexPage({ saveHandler: () => gate.promise });
  const data = require('../entry/src/main/ets/data/DemoData.ets');
  page.mainRoute = 'tabs';
  page.restore(data.initialSnapshot());
  const originalHeight = page.body.height;
  const next = { height: '168', size: 'M', fitPreference: '合身', shoulder: '40',
    chest: '88', waist: '70', hip: '90', skinTone: '', hairColor: '', eyeColor: '', updatedAt: '2026-09-24' };
  const pending = page.saveBodyProfile(next);
  await flushMicrotasks();
  assert.equal(page.body.height, originalHeight, '落盘期间不能先发布身材档案');
  gate.resolve();
  await pending;
  assert.equal(page.body.height, '168');
  assert.deepEqual(repository.disk[0].body, page.body);
  assert.deepEqual(repository.disk[0].activeIds, page.activeIds);
  assert.match(page.plans[0].reason, /体型建议/);
});

test('真实 Index：手动迁移导入先落盘再发布，覆盖确认后恢复候选快照', async () => {
  const gate = deferred();
  const { page, repository, platform } = makeIndexPage({ saveHandler: () => gate.promise });
  const source = require('../entry/src/main/ets/data/DemoData.ets').initialSnapshot();
  source.temperature = 18;
  source.city = '北京';
  const payload = await MIGRATION.exportWardrobeMigration(source,
    { isPrivateUri: () => false, read: async () => { throw new Error('无图片'); } }, 'phone-a', 0);
  platform.migrationPick = async () => ({ status: 'selected', value: payload, message: '已选择' });
  page.mainRoute = 'tabs';
  page.restore(require('../entry/src/main/ets/data/DemoData.ets').initialSnapshot());
  page.commitLock.deferTemperature(31);
  const oldTemperature = page.temperature;
  const pending = page.importMigration();
  await flushMicrotasks(20);
  assert.equal(page.temperature, oldTemperature, '快照保存完成前不能发布导入温度');
  gate.resolve();
  await pending;
  assert.equal(page.temperature, 18);
  assert.equal(repository.disk[0].temperature, 18);
  assert.equal(repository.disk[0].city, '北京');
  assert.equal(page.commitLock.hasPendingTemperature(), false,
    '导入不应把旧城市的待处理天气应用到恢复后的快照');
});

test('真实 Index：迁移快照落盘失败保留当前衣橱', async () => {
  const { page, repository, platform } = makeIndexPage({
    saveHandler: () => Promise.reject(new Error('磁盘不可写'))
  });
  const source = require('../entry/src/main/ets/data/DemoData.ets').initialSnapshot();
  source.temperature = 18;
  const payload = await MIGRATION.exportWardrobeMigration(source,
    { isPrivateUri: () => false, read: async () => { throw new Error('无图片'); } }, 'phone-b', 0);
  platform.migrationPick = async () => ({ status: 'selected', value: payload, message: '已选择' });
  page.mainRoute = 'tabs';
  page.restore(require('../entry/src/main/ets/data/DemoData.ets').initialSnapshot());
  const before = page.temperature;
  await assert.rejects(page.importMigration(), /磁盘不可写/);
  assert.equal(page.temperature, before);
  assert.equal(repository.disk.length, 0);
});

test('真实 Index：负温天气用于推荐，极端温度只在推荐值上限幅', async () => {
  const cold = makeIndexPage();
  cold.page.applyTemperature(-5);
  await flushMicrotasks(20);
  assert.equal(cold.page.temperature, -5);
  assert.equal(cold.repository.disk[0].temperature, -5);

  const extreme = makeIndexPage();
  extreme.page.applyTemperature(-30);
  await flushMicrotasks(20);
  assert.equal(extreme.page.temperature, -20);
  assert.equal(extreme.repository.disk[0].temperature, -20);
});

test('真实 Index：手动切城保存失败时不发布城市、温度和推荐', async () => {
  const { page, repository } = makeIndexPage({
    saveHandler: () => Promise.reject(new Error('磁盘不可写'))
  });
  const city = require('../entry/src/main/ets/model/Wardrobe.ets').CITIES[0];
  const before = { city: page.city, temperature: page.temperature, activeIds: page.activeIds.slice() };
  await page.applyCity(city, -5);
  assert.equal(page.city, before.city);
  assert.equal(page.temperature, before.temperature);
  assert.deepEqual(page.activeIds, before.activeIds);
  assert.equal(repository.disk.length, 0);
  assert.ok(page.pendingRetry, '失败的手动切城应保留明确的重试入口');
});

test('真实 Index：迁移清理完成前一直阻止新图片导入', async () => {
  const { page, repository, platform } = makeIndexPage();
  const source = require('../entry/src/main/ets/data/DemoData.ets').initialSnapshot();
  const payload = await MIGRATION.exportWardrobeMigration(source,
    { isPrivateUri: () => false, read: async () => { throw new Error('无图片'); } }, 'phone-c', 0);
  platform.migrationPick = async () => ({ status: 'selected', value: payload, message: '已选择' });
  const sweep = deferred();
  repository.sweepOrphans = () => sweep.promise;
  const pending = page.importMigration();
  await flushMicrotasks(20);
  assert.equal(repository.disk.length, 1, '迁移快照应已落盘');
  assert.equal(page.migrationBusy, true, '清理仍在途时迁移忙碌态必须保持');
  assert.equal(page.navigating(), true, '新文件入口必须继续受迁移门禁阻挡');
  sweep.resolve(0);
  await pending;
  assert.equal(page.migrationBusy, false);
});

test('真实 Index：只读恢复导入后完成一次清理并解除新导入门禁', async () => {
  const { page, repository, platform } = makeIndexPage();
  const source = require('../entry/src/main/ets/data/DemoData.ets').initialSnapshot();
  const payload = await MIGRATION.exportWardrobeMigration(source,
    { isPrivateUri: () => false, read: async () => { throw new Error('无图片'); } }, 'phone-d', 0);
  platform.migrationPick = async () => ({ status: 'selected', value: payload, message: '已选择' });
  page.readBlocked = true;
  page.sweepDone = false;
  page.orphanSwept = false;
  let sweepCount = 0;
  repository.sweepOrphans = async () => { sweepCount++; return 0; };
  await page.importMigration();
  assert.equal(page.readBlocked, false);
  assert.equal(page.sweepDone, true);
  assert.equal(page.orphanSwept, true);
  assert.equal(sweepCount, 1, '恢复导入后不应再次启动异步清理');
});

function makeDadaPage(options = {}) {
  const harness = makeIndexPage({ ...options, mainRoute: 'tabs' });
  harness.page.restore(require('../entry/src/main/ets/data/DemoData.ets').initialSnapshot());
  harness.page.openAssistant();
  return harness;
}

test('真实搭搭呈现接线：等待期间不重复发送或采用，逐字完成后仍由落盘链采用', async () => {
  const { page, repository } = makeDadaPage(); const clock = replyClock();
  page.setupAssistantReplies(clock.scheduler); const before = JSON.stringify(page.snapshot());
  page.submitAssistant('上课，24度'); const count = page.agentMessages.length;
  const look = page.agentOutfits[0]; assert.equal(page.assistantReply.stage, 'waiting');
  page.submitAssistant('正式一点'); await page.applyAgentOutfit(look);
  assert.equal(page.agentMessages.length, count); assert.equal(repository.saveCalls.length, 0);
  assert.equal(JSON.stringify(page.snapshot()), before); clock.advance(1000);
  assert.equal(page.assistantReply.stage, 'typing'); assert.ok(page.agentMessages.at(-1).text.startsWith(page.assistantReply.text));
  clock.drain(); assert.equal(page.assistantReply.stage, 'complete'); await page.applyAgentOutfit(look);
  assert.equal(repository.saveCalls.length, 1); assert.equal(page.showSheet, false); page.aboutToDisappear();
});
test('真实搭搭呈现接线：关闭、后台和销毁使旧回复失效，保留完整历史与草稿', () => {
  const { page, repository } = makeDadaPage(); const clock = replyClock(); page.setupAssistantReplies(clock.scheduler);
  page.draftImages = ['file://sandbox/form.png']; page.submitAssistant('今天怎么穿');
  const history = JSON.stringify(page.agentMessages), old = clock.ids()[0];
  page.showSheet = false; page.onSheetClosed(); clock.stale(old);
  assert.equal(page.assistantReply.stage, 'idle'); assert.equal(JSON.stringify(page.agentMessages), history);
  assert.deepEqual(page.draftImages, ['file://sandbox/form.png']); assert.equal(repository.discarded.length, 0);
  page.openAssistant(); page.submitAssistant('正式一点'); const background = clock.ids()[0];
  page.foreground = false; page.onDadaForegroundChanged(); clock.stale(background);
  assert.equal(page.assistantReply.stage, 'idle'); assert.equal(clock.count(), 0);
  page.foreground = true; page.submitAssistant('今天怎么穿'); const disposed = clock.ids()[0];
  page.aboutToDisappear(); clock.stale(disposed); assert.equal(clock.count(), 0);
  assert.equal(repository.saveCalls.length, 0);
});
test('真实搭搭呈现接线：多轮回复完成后，追问仍沿用候选条件且不写业务快照', () => {
  const { page, repository } = makeDadaPage(); const clock = replyClock(); page.setupAssistantReplies(clock.scheduler);
  const before = JSON.stringify(page.snapshot()); page.submitAssistant('课程展示，26度'); clock.drain();
  page.submitAssistant('再来一套'); assert.equal(page.assistantReply.stage, 'waiting'); clock.drain();
  assert.equal(page.assistantProposal.occasion, '课程展示'); assert.equal(page.assistantProposal.temperature, 26);
  assert.equal(JSON.stringify(page.snapshot()), before); assert.equal(repository.saveCalls.length, 0);
  page.aboutToDisappear();
});

test('真实搭搭接线：发送指令只发布聊天候选，连续追问沿用候选场合与温度', () => {
  const { page, repository } = makeDadaPage();
  // 正式场合的默认衣橱只有一件可用上装；补入第二件真实可选项，验证实际替换而非无替代品分支。
  const model = require('../entry/src/main/ets/model/Wardrobe.ets');
  const top = page.garments.find(x => x.category === model.Category.TOP && x.occasions.includes('课程展示') && x.maxTemp >= 26);
  page.garments = page.garments.concat([{ ...top, id: 'formal_alternative' }]);
  const before = JSON.stringify(page.snapshot());
  page.submitAssistant('课程展示，26度');
  assert.equal(page.assistantProposal.occasion, '课程展示');
  assert.equal(page.assistantProposal.temperature, 26);
  assert.ok(page.agentOutfits.length > 0);
  const previous = page.agentLatestOutfit;
  page.submitAssistant('换一件上装');
  assert.equal(page.assistantProposal.occasion, '课程展示');
  assert.equal(page.assistantProposal.temperature, 26);
  const garments = require('../entry/src/main/ets/model/Wardrobe.ets');
  const oldTop = previous.garmentIds.find(id => page.garments.find(x => x.id === id).category === garments.Category.TOP);
  assert.ok(!page.agentLatestOutfit.garmentIds.includes(oldTop), '换上装确实使用上轮候选');
  page.submitAssistant('再来一套');
  assert.equal(page.assistantProposal.temperature, 26);
  assert.equal(JSON.stringify(page.snapshot()), before);
  assert.equal(repository.saveCalls.length, 0);
  assert.ok(page.agentMessages.some(x => x.text === DADA.DADA_WELCOME));
});

test('真实搭搭接线：采用先落盘后发布和刷新卡片，连点只提交一次且保留天气来源', async () => {
  const gate = deferred();
  const { page, repository } = makeDadaPage({ saveHandler: () => gate.promise });
  const before = JSON.stringify(page.snapshot());
  const weather = { available: true, city: '上海', condition: '晴', tempMin: 21, tempMax: 25, source: '真实天气' };
  page.weather = weather;
  let cardCount = 0;
  page.refreshCard = () => { cardCount++; assert.equal(repository.disk.length, 1); };
  page.submitAssistant('课程展示，26度');
  const look = page.agentOutfits[0];
  const pending = page.applyAgentOutfit(look);
  await page.applyAgentOutfit(look); await flushMicrotasks();
  assert.equal(JSON.stringify(page.snapshot()), before);
  assert.equal(repository.saveCalls.length, 1); assert.equal(cardCount, 0);
  gate.resolve(); await pending;
  assert.equal(page.occasion, '课程展示'); assert.equal(page.temperature, 26);
  assert.deepEqual(page.activeIds, look.garmentIds);
  assert.deepEqual(repository.disk[0].activeIds, page.activeIds);
  assert.equal(page.showSheet, false); assert.equal(cardCount, 1);
  assert.deepEqual(page.weather, weather); assert.equal(repository.disk[0].city, JSON.parse(before).city);
});

test('真实搭搭接线：采用失败不发布，候选保留且原入口重试使用最新快照', async () => {
  let fail = true;
  const { page, repository } = makeDadaPage({ saveHandler: () => {
    if (fail) { fail = false; throw new Error('空间不足'); }
  } });
  const before = JSON.stringify(page.snapshot());
  page.submitAssistant('课程展示，26度'); const proposal = page.assistantProposal;
  await page.applyAgentOutfit(page.agentOutfits[0]);
  assert.equal(JSON.stringify(page.snapshot()), before); assert.equal(repository.disk.length, 0);
  assert.equal(page.assistantProposal, proposal); assert.equal(page.showSheet, true);
  assert.equal(page.dadaState, DADA.DadaState.ERROR); assert.equal(typeof page.pendingRetry, 'function');
  page.retryPersist(); await flushMicrotasks(30);
  assert.equal(page.temperature, 26); assert.equal(repository.disk.length, 1);
  assert.equal(page.showSheet, false);
});

test('真实搭搭接线：采用落盘期间天气延后应用，补存与内存一致且不丢衣橱', async () => {
  const gate = deferred(); let calls = 0;
  const { page, repository } = makeDadaPage({ saveHandler: () => ++calls === 1 ? gate.promise : Promise.resolve() });
  page.submitAssistant('课程展示，26度'); const look = page.agentOutfits[0];
  const pending = page.applyAgentOutfit(look); await flushMicrotasks(); page.applyTemperature(18);
  assert.notEqual(page.temperature, 18); gate.resolve(); await pending; await flushMicrotasks(30);
  assert.equal(repository.disk[0].temperature, 26);
  assert.deepEqual(repository.disk[0].activeIds, look.garmentIds);
  assert.equal(repository.disk.at(-1).temperature, 18);
  assert.deepEqual(repository.disk.at(-1), page.snapshot());
  assert.equal(repository.disk.at(-1).garments.length, page.garments.length);
});

test('真实搭搭接线：建议必须属于本轮且符合最新衣物状态，过期重试不得跨页执行', async () => {
  const { page, repository } = makeDadaPage();
  page.submitAssistant('课程展示，26度'); const look = page.agentOutfits[0];
  await page.applyAgentOutfit({ ...look, id: '伪造方案' }); assert.equal(repository.saveCalls.length, 0);
  page.garments = page.garments.map(item => item.id === look.garmentIds[0] ? { ...item, status: '待洗' } : item);
  await page.applyAgentOutfit(look); assert.equal(repository.saveCalls.length, 0);
  page.mainRoute = 'diary'; await page.applyAgentOutfit(look);
  assert.equal(repository.saveCalls.length, 0);

  const failed = makeDadaPage({ saveHandler: () => Promise.reject(new Error('空间不足')) });
  failed.page.submitAssistant('课程展示，26度'); await failed.page.applyAgentOutfit(failed.page.agentOutfits[0]);
  failed.page.mainRoute = 'diary'; failed.page.retryPersist(); await flushMicrotasks();
  assert.equal(failed.repository.saveCalls.length, 1);
});

test('真实搭搭接线：采用确切合法组合而非调用参数中的替换衣物', async () => {
  const { page, repository } = makeDadaPage(); page.submitAssistant('课程展示，26度');
  const look = page.agentOutfits[0];
  await page.applyAgentOutfit({ ...look, garmentIds: ['不存在的衣物'] });
  assert.deepEqual(repository.disk[0].activeIds, look.garmentIds);
});

test('真实搭搭接线：推荐前三名之外的合法组合采用和重启后仍为同一套', async () => {
  const { page, repository } = makeDadaPage();
  const engine = require('../entry/src/main/ets/service/OutfitEngine.ets');
  const model = require('../entry/src/main/ets/model/Wardrobe.ets');
  const request = page.request(); request.temperature = 26;
  const top = page.garments.find(x => x.category === model.Category.TOP && engine.eligible(x, request));
  page.garments = page.garments.concat([1, 2, 3, 4].map(index =>
    ({ ...top, id: 'top_alternative_' + index, wearCount: 100 + index })));
  const items = [model.Category.TOP, model.Category.BOTTOM, model.Category.SHOES].map(category =>
    page.garments.filter(item => item.category === category && engine.eligible(item, request)).at(-1));
  const look = engine.makeOutfit(items, request, page.profile);
  assert.ok(!engine.recommend(page.garments, request).outfits.some(x => x.id === look.id));
  page.assistantProposal = { id: 1, contextKey: page.dadaContext().key, occasion: look.occasion,
    temperature: look.temperature, outfits: [look] };
  await page.applyAgentOutfit(look);
  assert.deepEqual(page.activeIds, look.garmentIds); assert.deepEqual(page.plans[0].garmentIds, look.garmentIds);
  const restarted = makeDadaPage(); restarted.page.restore(repository.disk[0]);
  assert.deepEqual(restarted.page.activeIds, look.garmentIds);
  assert.deepEqual(restarted.page.plans[0].garmentIds, look.garmentIds);
});

test('真实搭搭接线：系统弹窗和其它表单打开时不再打开助手，关闭助手不回收草稿图片', () => {
  const { page, repository } = makeDadaPage();
  page.draftImages = ['file://sandbox/form.png']; page.draft.uri = 'file://sandbox/form.png';
  page.onSheetClosed(); assert.deepEqual(page.draftImages, ['file://sandbox/form.png']);
  assert.deepEqual(repository.discarded, []);
  page.sheet = 'add'; page.showSheet = true; page.openAssistant(); assert.equal(page.sheet, 'add');
  page.showSheet = false; page.importExitDialogOpen = true; page.openAssistant(); assert.equal(page.showSheet, false);
  page.importExitDialogOpen = false; page.importing = true; page.openAssistant(); assert.equal(page.showSheet, false);
});

test('真实搭搭接线：试穿请求在面板消失后分派一次，后台或上下文变化使未启动请求失效', () => {
  const { page } = makeDadaPage(); page.showSheet = false; page.openTryOn(); page.openAssistant();
  page.dadaAction(DADA.DadaAction.TRY_ON, 'red_dress');
  assert.equal(page.showSheet, false); assert.equal(page.tryOnCommand.id, 0);
  page.onSheetClosed(); const command = { ...page.tryOnCommand }; page.onSheetClosed();
  assert.deepEqual(page.tryOnCommand, command); assert.equal(command.id, 1); assert.equal(command.sceneId, 'red_dress');
  page.openAssistant(); page.dadaAction(DADA.DadaAction.TRY_ON, 'navy_top');
  page.foreground = false; page.onDadaForegroundChanged(); page.onSheetClosed();
  assert.equal(page.tryOnCommand.id, 0); assert.equal(page.tryOnCommandSequence, 1);
  page.foreground = true; page.openAssistant(); page.dadaAction(DADA.DadaAction.TRY_ON, 'navy_top');
  page.mainRoute = 'diary'; page.onSheetClosed(); assert.equal(page.tryOnCommand.id, 0);
});

test('真实搭搭接线：录入期间拒绝跨页指令，颜色与品类分别确认且保存仍由原按钮触发', async () => {
  const { page, repository } = makeIndexPage(); await prepareIndexImport(page, repository, ['photo-a', 'photo-b']);
  page.openAssistant(); const item = page.importItems[0];
  page.importRecognitionHints = [{ taskId: item.id, revision: item.revision, originalUri: item.originalUri,
    color: '红色', categoryIndex: 0, subcategory: 'T恤', message: '请确认建议' }];
  page.dadaAction(DADA.DadaAction.TRY_ON, 'navy_top'); assert.equal(page.mainRoute, 'garmentImport');
  assert.equal(page.pendingDadaAction, undefined);
  page.dadaAction(DADA.DadaAction.USE_COLOR, '');
  assert.equal(page.importItems[0].draft.color, '红色'); assert.equal(page.importItems[0].draft.categoryIndex, -1);
  page.dadaAction(DADA.DadaAction.USE_CATEGORY, '');
  assert.equal(page.importItems[0].draft.categoryIndex, 0); assert.equal(page.importItems[0].draft.subcategory, 'T恤');
  assert.equal(repository.saveCalls.length, 0); assert.equal(page.importItems[1].draft.color, '');
  page.importMove(1); page.dadaAction(DADA.DadaAction.USE_COLOR, '');
  assert.equal(page.importItems[1].draft.color, '');
});

test('真实搭搭接线：建议绑定 taskId/原图/revision，失效、终态和只读状态均不能采用', async () => {
  const { page, repository } = makeIndexPage(); const session = await prepareIndexImport(page, repository, ['photo-a']);
  page.openAssistant(); const item = page.importItems[0];
  const hint = { taskId: item.id, revision: item.revision, originalUri: item.originalUri,
    color: '红色', categoryIndex: 0, subcategory: 'T恤', message: '请确认建议' };
  for (const stale of [{ ...hint, taskId: 'old' }, { ...hint, originalUri: 'old' }, { ...hint, revision: hint.revision - 1 }]) {
    page.importRecognitionHints = [stale]; page.useRecognizedColor(0); page.useRecognizedCategory(0);
    assert.equal(page.importItems[0].draft.color, ''); assert.equal(page.importItems[0].draft.categoryIndex, -1);
  }
  page.importRecognitionHints = [hint]; page.readBlocked = true; page.dadaAction(DADA.DadaAction.USE_COLOR, '');
  assert.equal(page.importItems[0].draft.color, ''); page.readBlocked = false;
  session.skip(page.importHost(), item.id); page.useRecognizedColor(0);
  assert.equal(page.importItems[0].phase, ImportPhase.SKIPPED); assert.equal(repository.saveCalls.length, 0);
});

test('真实搭搭接线：分析失败可重试，退出后迟到结果不进入新会话', async () => {
  const { page, repository, platform } = makeIndexPage(); await prepareIndexImport(page, repository, ['photo-a']);
  page.openAssistant(); platform.recognize = async () => { throw new Error('读取失败'); };
  await page.dadaAnalyzeCurrent(); assert.equal(page.dadaState, DADA.DadaState.ERROR);
  assert.equal(page.recognizingImportTaskId, '');
  const gate = deferred(); platform.recognize = () => gate.promise;
  const pending = page.dadaAnalyzeCurrent(); page.showSheet = false; page.finishImport();
  page.mainRoute = 'garmentImport'; await prepareIndexImport(page, repository, ['photo-b']);
  gate.resolve({ category: '', color: '红色', material: '', confidence: 0.8,
    colorSource: RECOGNITION.RECOGNITION_SOURCE_PIXEL_COLOR, source: RECOGNITION.RECOGNITION_SOURCE_PIXEL_COLOR });
  await pending; assert.deepEqual(page.importRecognitionHints, []); assert.equal(page.importItems[0].draft.color, '');
  assert.equal(page.dadaVisualState(), DADA.DadaState.IDLE);
});
