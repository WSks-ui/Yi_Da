const fs = require('node:fs');
const assert = require('node:assert/strict');
const { test } = require('node:test');

const ts = require(process.argv[2] || 'typescript');
require.extensions['.ets'] = (loadedModule, filename) => {
  const source = fs.readFileSync(filename, 'utf8');
  const output = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  loadedModule._compile(output, filename);
};

const wardrobe = require('../entry/src/main/ets/model/Wardrobe.ets');
const data = require('../entry/src/main/ets/data/DemoData.ets');
const agent = require('../entry/src/main/ets/service/OutfitAgent.ets');

const context = (overrides = {}) => ({
  garments: data.demoGarments(), profile: wardrobe.emptyProfile(), body: wardrobe.emptyBodyProfile(),
  occasion: '上课', temperature: 24, lockedIds: [], excludedIds: [], ...overrides
});

test('助手能从自然语言提取场合和温度，并调用真实推荐引擎', () => {
  const result = agent.runOutfitAgent('明天课程展示，18度怎么穿', context());
  assert.equal(result.intent, agent.OutfitAgentIntent.RECOMMEND);
  assert.equal(result.occasion, '课程展示');
  assert.equal(result.temperature, 18);
  assert.ok(result.reply.includes('课程展示'));
  assert.ok(result.recommendation.outfits.length > 0);
});

test('助手支持冷一点/热一点和帮助指令，不伪造云端能力', () => {
  const colder = agent.runOutfitAgent('今天冷一点', context({ temperature: 24 }));
  assert.equal(colder.temperature, 19);
  const help = agent.runOutfitAgent('你能做什么', context());
  assert.equal(help.intent, agent.OutfitAgentIntent.HELP);
  assert.match(help.reply, /离线|推荐/);
});

test('助手可以在上一套方案上替换上装，并保留温度与场合约束', () => {
  const base = agent.runOutfitAgent('上课，24度', context());
  assert.ok(base.latestOutfit);
  const replaced = agent.runOutfitAgent('换一件上装', context(), { latestOutfit: base.latestOutfit });
  assert.equal(replaced.intent, agent.OutfitAgentIntent.REPLACE_TOP);
  assert.ok(replaced.recommendation.outfits.length > 0);
  assert.equal(replaced.temperature, 24);
  assert.equal(replaced.occasion, '上课');
  assert.ok(replaced.reply.includes('换一件上装'));
});

test('助手支持多轮换鞋和下一套，并在无方案时给出下一步澄清', () => {
  const base = agent.runOutfitAgent('上课，24度', context());
  const shoes = agent.runOutfitAgent('换一双鞋', context(), { latestOutfit: base.latestOutfit });
  assert.equal(shoes.intent, agent.OutfitAgentIntent.REPLACE_SHOES);
  const next = agent.runOutfitAgent('再来一套', context(), { latestOutfit: base.latestOutfit });
  assert.equal(next.intent, agent.OutfitAgentIntent.NEXT);
  const missing = agent.runOutfitAgent('课程展示，36度', context());
  assert.equal(missing.intent, agent.OutfitAgentIntent.CLARIFY);
  assert.match(missing.reply, /调整温度|补充/);
});
