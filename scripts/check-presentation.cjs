const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const ts = require(process.argv[2] || 'typescript');
if (!require.extensions['.ets']) {
  require.extensions['.ets'] = (module, filename) => module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, filename);
}
const flow = require('../entry/src/main/ets/service/TryOnPresentationController.ets');
const scenes = require('../entry/src/main/ets/service/TryOnDemo.ets');
// 媒体映射和导出同样运行生产方法；仅替代 ImageKit 解码/文件写入等平台边界。
const mediaPlatform = { resources: [], exported: [], sourceReleased: 0, pixelsReleased: 0, albums: [], shares: [] };
const media = {};
new Function('require', '$r', 'exports', ts.transpileModule(fs.readFileSync(
  path.resolve(__dirname, '../entry/src/main/ets/service/TryOnDemoMedia.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText)(name => {
  if (name === './TryOnDemo') return scenes;
  if (name === '@kit.ImageKit') return { image: { createImageSource: () => ({
    createPixelMap: async () => ({ release: async () => { mediaPlatform.pixelsReleased++; } }),
    release: async () => { mediaPlatform.sourceReleased++; }
  }) } };
  if (name === './OutfitExport') return { exportOutfit: async () => {
    mediaPlatform.exported.push('file://demo.png'); return 'file://demo.png';
  } };
  throw new Error('未替代的平台依赖：' + name);
}, name => ({ id: name }), media);

function clock() {
  let sequence = 0;
  const pending = new Map(), all = new Map(), delays = [];
  return {
    scheduler: {
      schedule(fn, milliseconds) { const id = ++sequence; delays.push(milliseconds); pending.set(id, fn); all.set(id, fn); return id; },
      clear(id) { pending.delete(id); }
    },
    tick() { const [id, fn] = pending.entries().next().value; pending.delete(id); fn(); return id; },
    stale(id) { all.get(id)(); },
    count: () => pending.size,
    delays
  };
}

test('真实演示控制器：三场景阶段顺序一致，1.8/1.8/1.8/0.6 秒后完成', () => {
  for (const scene of scenes.DEMO_SCENES) {
    const time = clock(), controller = new flow.TryOnPresentationController(time.scheduler), states = [];
    controller.subscribe(state => states.push(state));
    controller.start(scene.id);
    for (let i = 0; i < 4; i++) time.tick();
    assert.deepEqual(states.map(x => x.stage), ['idle', 'preparing', 'interacting', 'presenting', 'revealing', 'complete']);
    assert.deepEqual(time.delays, [1800, 1800, 1800, 600]);
    assert.equal(states.at(-1).sceneId, scene.id);
    assert.equal(time.count(), 0);
    controller.dispose();
  }
});
test('真实演示控制器：未知场景和销毁后启动被拒绝，连点不会创建第二计时器', () => {
  const time = clock(), controller = new flow.TryOnPresentationController(time.scheduler);
  assert.throws(() => controller.start('invalid'), /未知/);
  assert.equal(time.count(), 0);
  const id = controller.start('navy_top');
  assert.equal(controller.start('red_dress'), id);
  assert.equal(controller.snapshot().sceneId, 'navy_top');
  assert.equal(time.count(), 1);
  controller.dispose();
  assert.equal(time.count(), 0);
  assert.throws(() => controller.start('navy_top'), /关闭/);
});
test('真实演示控制器：每个阶段取消或销毁后，已入队旧回调不能产生结果', () => {
  for (let stage = 0; stage < 4; stage++) {
    for (const stop of ['cancel', 'dispose']) {
      const time = clock(), controller = new flow.TryOnPresentationController(time.scheduler), observed = [];
      controller.subscribe(state => observed.push(state));
      controller.start('denim_skirt');
      for (let i = 0; i < stage; i++) time.tick();
      controller[stop]();
      const count = observed.length;
      time.stale(stage + 1);
      assert.equal(time.count(), 0);
      assert.equal(observed.length, count);
      assert.equal(controller.snapshot().stage, 'idle');
    }
  }
});
test('真实演示控制器：重播取得新 runId，旧回调不能抢占新场景；订阅可释放', () => {
  const time = clock(), controller = new flow.TryOnPresentationController(time.scheduler), states = [];
  const unsubscribe = controller.subscribe(state => states.push(state));
  const first = controller.start('denim_skirt'); controller.cancel();
  const second = controller.start('red_dress'); time.stale(1);
  assert.ok(second > first);
  assert.equal(controller.snapshot().sceneId, 'red_dress');
  assert.equal(controller.snapshot().stage, 'preparing');
  unsubscribe(); const count = states.length; time.tick();
  assert.equal(states.length, count); controller.dispose();
});
test('真实演示控制器：订阅回调中取消不会重新建立计时器', () => {
  const time = clock(), controller = new flow.TryOnPresentationController(time.scheduler);
  controller.subscribe(state => { if (state.stage === 'preparing') controller.cancel(); });
  controller.start('navy_top'); assert.equal(time.count(), 0); controller.dispose();
});

// 提取页面的真实非 Builder 方法和字段；仅用虚拟时钟替代平台 setTimeout，不复制页面状态机。
function makePage(time) {
  const filename = path.resolve(__dirname, '../entry/src/main/ets/pages/TryOnPage.ets');
  const text = fs.readFileSync(filename, 'utf8').replace(/\bstruct\s+(\w+)/g, 'class $1');
  const source = ts.createSourceFile(filename, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
  const component = source.statements.find(x => x.name?.text === 'TryOnPage');
  const members = component.members.filter(x => {
    if (ts.isPropertyDeclaration(x)) return true;
    if (!ts.isMethodDeclaration(x) || x.name.getText(source) === 'build') return false;
    return !(ts.getDecorators(x) || []).some(d => ['Builder', 'Styles'].includes(d.expression.getText(source)));
  }).map(x => {
    const decorators = ts.getDecorators(x) || [];
    const raw = x.getText(source);
    return decorators.length ? raw.slice(decorators.at(-1).end - x.getStart(source)) : raw;
  });
  const deps = { ...flow, ...scenes, ...media,
    saveOutfitToAlbum: async uri => { mediaPlatform.albums.push(uri); return true; },
    shareOutfitImage: async uri => { mediaPlatform.shares.push(uri); },
    TryOnPresentationController: class extends flow.TryOnPresentationController { constructor() { super(time.scheduler); } }
  };
  const output = ts.transpileModule('class Probe {' + members.join('\n') + '}', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const page = new (new Function(...Object.keys(deps), output + ';return Probe')(...Object.values(deps)))();
  page.getUIContext = () => ({ getHostContext: () => ({ resourceManager: {
    getMediaContent: async id => { mediaPlatform.resources.push(id); return new Uint8Array([1, 2, 3]); }
  } }) });
  return page;
}
test('真实试穿页：挂载和 Watch 同一命令只启动一次，取消不写业务记录', () => {
  const time = clock(), page = makePage(time), consumed = [];
  page.command = { id: 1, sceneId: 'navy_top', action: 'start' };
  page.onCommandConsumed = id => consumed.push(id);
  page.aboutToAppear(); page.consumeCommand();
  assert.deepEqual(consumed, [1]); assert.equal(time.count(), 1);
  assert.equal(page.selectedId, 'navy_top'); assert.equal(page.generating, true);
  page.cancelPresentation(); time.stale(1);
  assert.equal(page.generatedSceneId, ''); assert.deepEqual(page.tasks, []);
  page.aboutToDisappear(); assert.equal(time.count(), 0);
});
test('真实试穿页：后台取消，回前台不自动恢复；离页后旧回调不改状态', () => {
  const time = clock(), page = makePage(time); page.aboutToAppear(); page.generatePreview();
  page.foreground = false; page.onForegroundChanged();
  page.foreground = true; page.onForegroundChanged();
  time.stale(1); assert.equal(page.generating, false); assert.equal(page.generatedSceneId, '');
  page.generatePreview(); page.aboutToDisappear(); time.stale(2);
  assert.equal(page.generating, false); assert.equal(time.count(), 0);
});
test('真实试穿页：完成后显示同组正面结果，保存只由显式保存入口调用', async () => {
  const time = clock(), page = makePage(time), saved = [];
  page.onSubmit = async scene => saved.push(scene);
  page.command = { id: 1, sceneId: 'red_dress', action: 'start' }; page.aboutToAppear();
  for (let i = 0; i < 4; i++) time.tick();
  assert.equal(page.generatedSceneId, 'red_dress'); assert.equal(page.busy, false);
  assert.deepEqual(saved, []);
  assert.equal(page.isGenerated(), true);
  assert.equal(page.currentResult().id, 'app.media.tryon_red_result');
  await page.saveRecord(); assert.deepEqual(saved, ['red_dress']); page.aboutToDisappear();
});

test('真实试穿页：运行禁止切换与连点，三组结果均同源，侧背面不伪造素材', () => {
  for (const scene of scenes.DEMO_SCENES) {
    const time = clock(), page = makePage(time); page.initialSceneId = scene.id; page.aboutToAppear();
    page.generatePreview(); page.select('red_dress'); page.generatePreview();
    assert.equal(page.selectedId, scene.id); assert.equal(time.count(), 1);
    for (let i = 0; i < 4; i++) time.tick();
    assert.equal(page.currentResult().id, media.demoImages(scene.id).result.id);
    assert.equal(page.poseAvailable(scenes.DEMO_POSES[1]), false);
    assert.equal(page.poseAvailable(scenes.DEMO_POSES[2]), false);
    page.aboutToDisappear();
  }
});

test('真实试穿页：未知命令被拒绝，已保存记录直接打开结果且不强制等待', () => {
  const time = clock(), page = makePage(time);
  page.command = { id: 1, sceneId: 'invalid', action: 'start' }; page.aboutToAppear();
  assert.equal(time.count(), 0); assert.equal(page.generatedSceneId, '');
  page.tasks = [scenes.createDemoTask('navy_top')]; page.openRecord(page.tasks[0]);
  assert.equal(time.count(), 0); assert.equal(page.generatedSceneId, 'navy_top');
  page.command = { id: 2, sceneId: 'navy_top', action: 'compare' }; page.consumeCommand();
  assert.equal(page.mode, '对比'); assert.equal(time.count(), 0); page.aboutToDisappear();
});

test('真实试穿页：相册导出和分享仍读取同组带 DEMO 标记的原始资源，并释放解码对象', async () => {
  mediaPlatform.resources = []; mediaPlatform.sourceReleased = 0; mediaPlatform.pixelsReleased = 0;
  const time = clock(), page = makePage(time); page.initialSceneId = 'denim_skirt'; page.aboutToAppear();
  page.generatePreview(); for (let i = 0; i < 4; i++) time.tick();
  await page.deliver(true); await page.deliver(false);
  assert.deepEqual(mediaPlatform.resources, ['app.media.tryon_denim_result', 'app.media.tryon_denim_result']);
  assert.equal(mediaPlatform.sourceReleased, 2); assert.equal(mediaPlatform.pixelsReleased, 2);
  assert.deepEqual(mediaPlatform.albums, ['file://demo.png']); assert.deepEqual(mediaPlatform.shares, ['file://demo.png']);
  assert.equal(page.busy, false); page.aboutToDisappear();
});
