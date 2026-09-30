const fs = require('node:fs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const ts = require(process.argv[2] || 'typescript');
if (!require.extensions['.ets']) {
  require.extensions['.ets'] = (module, filename) => module._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, filename);
}
const { AssistantReplyController, assistantReplyActive } = require('../entry/src/main/ets/service/AssistantReplyController.ets');
const { replyClock } = require('./fixtures/reply-clock.cjs');

test('真实回复控制器：等待一秒后逐字出现，前缀递增且完整文本一致', () => {
  const clock = replyClock(), controller = new AssistantReplyController(clock.scheduler), observed = [];
  controller.subscribe(view => observed.push(view)); controller.start('reply', '搭搭给你两套搭配。');
  clock.advance(999); assert.equal(controller.snapshot().stage, 'waiting'); assert.equal(controller.snapshot().text, '');
  clock.advance(1); assert.equal(controller.snapshot().stage, 'typing'); assert.equal(controller.snapshot().text, '搭');
  assert.equal(assistantReplyActive(controller.snapshot()), true);
  clock.drain(); assert.equal(controller.snapshot().text, '搭搭给你两套搭配。');
  assert.equal(controller.snapshot().stage, 'complete'); assert.equal(clock.count(), 0);
  const frames = observed.filter(view => view.text.length > 0);
  for (let i = 1; i < frames.length; i++) assert.ok(frames[i].text.startsWith(frames[i - 1].text));
  controller.dispose();
});
test('真实回复控制器：新消息替代旧消息，已经排队的旧回调不能改写新一轮', () => {
  const clock = replyClock(), controller = new AssistantReplyController(clock.scheduler);
  controller.start('old', '旧消息'); const oldTimer = clock.ids()[0];
  controller.start('new', '新消息'); const run = controller.snapshot().runId;
  clock.stale(oldTimer); assert.equal(controller.snapshot().messageId, 'new');
  assert.equal(controller.snapshot().stage, 'waiting'); assert.equal(clock.count(), 1);
  clock.drain(); assert.equal(controller.snapshot().runId, run); assert.equal(controller.snapshot().text, '新消息');
  controller.dispose();
});
test('真实回复控制器：等待和逐字阶段取消或销毁后，旧回调不再发布且无计时器', () => {
  for (const typed of [false, true]) for (const stop of ['cancel', 'dispose']) {
    const clock = replyClock(), controller = new AssistantReplyController(clock.scheduler), frames = [];
    controller.subscribe(view => frames.push(view)); controller.start('a', '需要逐字显示的一条消息');
    if (typed) clock.advance(1000);
    const timer = clock.ids()[0]; controller[stop](); const count = frames.length;
    clock.stale(timer); assert.equal(frames.length, count); assert.equal(clock.count(), 0);
    assert.equal(controller.snapshot().stage, 'idle'); controller.dispose();
  }
});
test('真实回复控制器：订阅可释放，取消和销毁回调重入也不能留下计时器', () => {
  const clock = replyClock(), controller = new AssistantReplyController(clock.scheduler); let calls = 0;
  const off = controller.subscribe(() => calls++); off(); controller.start('a', '消息'); assert.equal(calls, 1);
  const stopOnWaiting = controller.subscribe(view => { if (view.stage === 'waiting') controller.cancel(); });
  controller.start('b', '不会继续'); assert.equal(clock.count(), 0);
  stopOnWaiting(); let disposing = false;
  controller.subscribe(view => { if (disposing && view.stage === 'idle') controller.start('c', '销毁时不能启动'); });
  disposing = true;
  controller.dispose(); assert.equal(clock.count(), 0); controller.start('d', '无效'); assert.equal(clock.count(), 0);
});
test('真实回复控制器：中文和 emoji 保持完整字符，发布快照不泄露内部可变状态', () => {
  const clock = replyClock(), controller = new AssistantReplyController(clock.scheduler), text = '👚搭搭👖选好了。';
  controller.subscribe(view => {
    assert.ok(!/[\uD800-\uDBFF]$/.test(view.text));
    view.text = '订阅方修改不回写';
  });
  controller.start('a', text); clock.drain(); assert.equal(controller.snapshot().text, text); controller.dispose();
});
test('真实回复控制器：长回复展示耗时有上限，不让操作被持续锁住', () => {
  const clock = replyClock(), controller = new AssistantReplyController(clock.scheduler), text = '搭'.repeat(500);
  controller.start('a', text); clock.drain(); assert.ok(clock.now() <= 3500);
  assert.equal(controller.snapshot().text, text); assert.equal(assistantReplyActive(controller.snapshot()), false);
  controller.dispose();
});
