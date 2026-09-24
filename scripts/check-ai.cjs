const fs = require('node:fs');
const assert = require('node:assert/strict');
const Module = require('node:module');
const { test } = require('node:test');

// 只转译服务层的类型语法，在桌面 Node 中验证纯逻辑契约；不模拟设备、不宣称模型或真机能力。
const ts = require(process.argv[2] || 'typescript');
require.extensions['.ets'] = (loadedModule, filename) => {
  const source = fs.readFileSync(filename, 'utf8');
  const output = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  loadedModule._compile(output, filename);
};

const recognition = require('../entry/src/main/ets/service/GarmentRecognition.ets');
const inference = require('../entry/src/main/ets/service/NeuralInference.ets');
const clothing = require('../entry/src/main/ets/service/OpenImageClothing.ets');

test('端侧 Open Images 只建议可映射衣物，弱命中、非衣物及尺寸不符时放弃', () => {
  const scores = new Float32Array(clothing.OPEN_IMAGE_OUTPUT_SIZE);
  scores[91] = 0.88;
  const jeans = clothing.chooseClothingCandidate(scores);
  assert.equal(jeans.subcategory, '牛仔裤');
  assert.equal(jeans.category, '下装');
  scores[91] = 0.1;
  assert.equal(clothing.chooseClothingCandidate(scores), undefined);
  scores[91] = 0.5;
  scores[22] = 0.95;
  assert.equal(clothing.chooseClothingCandidate(scores), undefined);
  assert.equal(clothing.chooseClothingCandidate(new Float32Array(1000)), undefined);
});

test('模型 RGBA 预处理只读真实像素并核对输入尺寸', () => {
  const bytes = new Uint8Array(224 * 224 * 4);
  bytes[0] = 255;
  bytes[1] = 0;
  bytes[2] = 0;
  bytes[3] = 255;
  const result = clothing.normalizeOpenImagePixels(bytes);
  assert.equal(result.length, 224 * 224 * 3);
  assert.ok(result[0] > 2);
  assert.ok(result[1] < -1);
  assert.throws(() => clothing.normalizeOpenImagePixels(new Uint8Array(4)), /尺寸/);
});

test('类别和材质文件名提示覆盖代表性 token，并明确低于自动采用阈值', () => {
  assert.ok(recognition.GARMENT_CATEGORIES.length >= 70);
  assert.equal(new Set(recognition.GARMENT_CATEGORIES).size, recognition.GARMENT_CATEGORIES.length);
  const samples = [
    ['hoodie_red_cotton.png', '连帽卫衣'],
    ['denim-jeans-blue.png', '牛仔裤'],
    ['wool-coat-black.png', '羊毛大衣'],
    ['mary-janes_black.png', '玛丽珍鞋'],
    ['crossbody-bag_brown.png', '斜挎包']
  ];
  for (const [fileName, expected] of samples) {
    const result = recognition.recognizeGarmentSync(fileName);
    assert.equal(result.category, expected);
    assert.ok(result.confidence < recognition.MIN_AUTO_RECOGNITION_CONFIDENCE);
    assert.equal(result.source, recognition.RECOGNITION_SOURCE_LOCAL);
    assert.equal(result.categorySource, recognition.RECOGNITION_SOURCE_LOCAL);
    assert.equal(result.categoryConfidence, result.confidence);
  }
  const material = recognition.recognizeGarmentSync('hoodie_red_cotton.png');
  assert.equal(material.color, '红色');
  assert.equal(material.colorSource, recognition.RECOGNITION_SOURCE_LOCAL);
  assert.equal(material.material, '棉');
  assert.equal(material.materialSource, recognition.RECOGNITION_SOURCE_LOCAL);
});

test('拉丁文件名 token 必须完整匹配，避免从普通词片段误判衣物属性', () => {
  const result = recognition.recognizeGarmentSync('hoodieish_redesign_bluebird_cottony.png');
  assert.equal(result.category, '');
  assert.equal(result.color, '');
  assert.equal(result.material, '');
  assert.equal(result.source, recognition.RECOGNITION_SOURCE_UNAVAILABLE);
});

test('文件名线索识别是确定性的，随机沙箱 URI 不会被包装成视觉模型结果', async () => {
  const uri = 'file://sandbox/garment_batch_s123_t0_orig.png';
  const first = recognition.recognizeGarmentSync(uri);
  const second = recognition.recognizeGarmentSync(uri);
  assert.deepEqual(first, second);
  assert.equal(first.category, '');
  assert.equal(first.color, '');
  assert.equal(first.material, '');
  assert.equal(first.confidence, 0);
  assert.equal(first.source, recognition.RECOGNITION_SOURCE_UNAVAILABLE);
  assert.match(recognition.recognitionSummary(first), /请手动填写/);

  const asyncResult = await recognition.recognizeGarment('hoodie_red_cotton.png');
  // 默认入口尝试读取真实像素；桌面 Node 没有 HarmonyOS ImageKit，因此明确降级。
  assert.equal(asyncResult.category, '');
  assert.equal(asyncResult.material, '');
  assert.equal(asyncResult.color, '');
  assert.equal(asyncResult.source, recognition.RECOGNITION_SOURCE_UNAVAILABLE);
  assert.equal(asyncResult.categorySource, recognition.RECOGNITION_SOURCE_UNAVAILABLE);
  assert.equal(asyncResult.colorSource, recognition.RECOGNITION_SOURCE_UNAVAILABLE);
  assert.equal(asyncResult.materialSource, recognition.RECOGNITION_SOURCE_UNAVAILABLE);
  const filenameResult = await recognition.recognizeGarmentFromFileName('hoodie_red_cotton.png');
  assert.deepEqual(filenameResult, recognition.recognizeGarmentSync('hoodie_red_cotton.png'));
  const filenameProvider = await new recognition.FilenameTokenRecognitionProvider().recognize({
    uri: 'file://sandbox/random-import-id.png', fileName: 'hoodie_red_cotton.png'
  });
  assert.equal(filenameProvider.category, '连帽卫衣');
  assert.equal(filenameProvider.color, '红色');
  assert.equal(filenameProvider.material, '棉');
  assert.match(recognition.recognitionSummary(filenameProvider), /文件名线索/);
  assert.match(recognition.recognitionSummary(filenameProvider), /请核对/);
});

test('RGBA 主色统计按色类多数投票，透明像素和白底不会压过有效颜色', () => {
  const rgba = [];
  for (let i = 0; i < 12; i++) rgba.push(25, 75, 210, 255);
  for (let i = 0; i < 4; i++) rgba.push(220, 35, 35, 255);
  let result = recognition.analyzeRgbaPixels(Uint8Array.from(rgba));
  assert.equal(result.color, '蓝色');
  assert.ok(result.confidence > 0.65);

  const withBackground = [];
  for (let i = 0; i < 8; i++) withBackground.push(20, 175, 90, 255);
  for (let i = 0; i < 8; i++) withBackground.push(255, 255, 255, 255);
  for (let i = 0; i < 12; i++) withBackground.push(230, 20, 20, 0);
  result = recognition.analyzeRgbaPixels(Uint8Array.from(withBackground));
  assert.equal(result.color, '绿色');

  const white = [];
  for (let i = 0; i < 12; i++) white.push(255, 255, 255, 255);
  assert.equal(recognition.analyzeRgbaPixels(Uint8Array.from(white)).color, '白色');
  assert.equal(recognition.analyzeRgbaPixels(new Uint8Array(32)), undefined);
});

test('导入默认分析只回传图片像素颜色，不从 URI 自动填类别或材质', () => {
  const pixelOnly = {
    category: '', color: '蓝色', material: '', confidence: 0.84,
    source: recognition.RECOGNITION_SOURCE_PIXEL_COLOR, userConfirmed: false,
    categoryConfidence: 0, colorConfidence: 0.84, materialConfidence: 0,
    categorySource: recognition.RECOGNITION_SOURCE_UNAVAILABLE,
    colorSource: recognition.RECOGNITION_SOURCE_PIXEL_COLOR,
    materialSource: recognition.RECOGNITION_SOURCE_UNAVAILABLE
  };
  assert.equal(pixelOnly.category, '');
  assert.equal(pixelOnly.material, '');
  assert.match(recognition.recognitionSummary(pixelOnly), /图片像素统计/);
});

test('默认 provider 从 ImageKit 像素取色，并忽略 URI 与文件名中的类别和材质 token', async () => {
  const originalLoad = Module._load;
  const rgba = [];
  for (let i = 0; i < 12; i++) rgba.push(25, 75, 210, 255);
  let imageReleased = false;
  let sourceReleased = false;
  let fileClosed = false;
  Module._load = function (request, parent, isMain) {
    if (request === '@kit.CoreFileKit') {
      return { fileIo: {
        OpenMode: { READ_ONLY: 0 },
        open: async () => ({ fd: 1 }),
        close: async () => { fileClosed = true; }
      } };
    }
    if (request === '@kit.ImageKit') {
      return { image: {
        PixelMapFormat: { RGBA_8888: 0 },
        createImageSource: () => ({
          getImageInfo: async () => ({ size: { width: 4, height: 3 } }),
          createPixelMap: async () => ({
            getPixelBytesNumber: () => rgba.length,
            readPixelsToBuffer: async (buffer) => new Uint8Array(buffer).set(rgba),
            release: async () => { imageReleased = true; }
          }),
          release: async () => { sourceReleased = true; }
        })
      } };
    }
    return originalLoad.call(this, request, parent, isMain);
  };
  try {
    const result = await new recognition.LocalGarmentRecognitionProvider().recognize({
      uri: 'file://sandbox/hoodie_red_cotton.png', fileName: 'hoodie_red_cotton.png'
    });
    assert.equal(result.category, '');
    assert.equal(result.color, '蓝色');
    assert.equal(result.material, '');
    assert.equal(result.source, recognition.RECOGNITION_SOURCE_PIXEL_COLOR);
    assert.equal(result.categorySource, recognition.RECOGNITION_SOURCE_UNAVAILABLE);
    assert.equal(result.colorSource, recognition.RECOGNITION_SOURCE_PIXEL_COLOR);
    assert.equal(result.materialSource, recognition.RECOGNITION_SOURCE_UNAVAILABLE);
  } finally {
    Module._load = originalLoad;
  }
  assert.equal(imageReleased, true);
  assert.equal(sourceReleased, true);
  assert.equal(fileClosed, true);
});

test('低置信度结果不覆盖用户已经确认的属性，高置信度结果只更新未确认字段', () => {
  const draft = { category: '衬衫', color: '白色', material: '棉', userConfirmed: true };
  const low = recognition.recognizeGarmentSync('file://sandbox/garment_batch_s1_t0_orig.png');
  const protectedResult = recognition.applyRecognition(draft, low);
  assert.equal(protectedResult.category, '衬衫');
  assert.equal(protectedResult.color, '白色');
  assert.equal(protectedResult.material, '棉');

  const inferred = recognition.recognizeGarmentSync('hoodie_red_cotton.png');
  const partiallyConfirmed = recognition.applyRecognition(
    { category: '上装', color: '黑色', material: '' }, inferred, { category: true });
  assert.equal(partiallyConfirmed.category, '上装');
  assert.equal(partiallyConfirmed.color, '黑色', '文件名提示和未识别字段都不能静默替换草稿');
  assert.equal(partiallyConfirmed.material, '');
  assert.equal(partiallyConfirmed.userConfirmed, true);

  const modelResult = {
    category: 'Polo衫', color: '蓝色', material: '棉', confidence: 0.91,
    source: 'vision-model-provider', userConfirmed: false,
    categoryConfidence: 0.9, colorConfidence: 0.91, materialConfidence: 0.86,
    categorySource: 'vision-model-provider', colorSource: 'vision-model-provider',
    materialSource: 'vision-model-provider'
  };
  const merged = recognition.applyRecognition({ category: '上装', color: '黑色', material: '' },
    modelResult, { category: true });
  assert.equal(merged.category, '上装');
  assert.equal(merged.color, '蓝色');
  assert.equal(merged.material, '棉');
  assert.equal(merged.categorySource, recognition.RECOGNITION_SOURCE_USER);
  assert.equal(merged.colorSource, 'vision-model-provider');
});

test('类别模型只返回一个字段时不会清空草稿中的其它字段', () => {
  const merged = recognition.applyRecognition({ category: '上装', color: '白色', material: '羊毛' }, {
    category: '连帽卫衣', color: '', material: '', confidence: 0.9,
    source: 'vision-model-provider', userConfirmed: false,
    categoryConfidence: 0.9, colorConfidence: 0, materialConfidence: 0,
    categorySource: 'vision-model-provider',
    colorSource: recognition.RECOGNITION_SOURCE_UNAVAILABLE,
    materialSource: recognition.RECOGNITION_SOURCE_UNAVAILABLE
  });
  assert.equal(merged.category, '连帽卫衣');
  assert.equal(merged.color, '白色');
  assert.equal(merged.material, '羊毛');
});

test('NeuralInference provider 不可用时返回 unavailable，并保留确定性的本地特征向量降级', async () => {
  const service = new inference.NeuralInference(new inference.UnavailableNeuralInferenceProvider());
  const first = await service.inference([0.1, 0.2, 0.3, 0.4]);
  const second = await service.inference([0.1, 0.2, 0.3, 0.4]);
  assert.deepEqual(first, second);
  assert.equal(first.source, inference.INFERENCE_SOURCE_UNAVAILABLE);
  assert.equal(first.status, 'unavailable');
  assert.equal(first.modelAvailable, false);
  assert.equal(first.usedFallback, true);
  assert.equal(first.method, inference.INFERENCE_SOURCE_LOCAL);
  assert.equal(first.output.length, 5);
  assert.equal(first.featureVector.length, 8);
  assert.equal(first.output[0] > 0, true, '传入的实际数值特征仍可被离线启发式计算');
});

test('NeuralInference 不会把 URI 哈希或图片尺寸当作真实视觉特征', async () => {
  const service = new inference.NeuralInference();
  const first = await service.inference('file://image-a.png');
  const second = await service.inference({ uri: 'file://image-b.png', width: 1200, height: 800, channels: 4 });
  assert.equal(first.source, inference.INFERENCE_SOURCE_UNAVAILABLE);
  assert.equal(first.confidence, 0.2);
  assert.deepEqual(first.featureVector, new Array(8).fill(0));
  assert.deepEqual(first.output, [0, 0, 0, 0, 0]);
  assert.deepEqual(second.featureVector, first.featureVector);
  assert.deepEqual(second.output, first.output);
});

test('NeuralInference 可替换 provider，provider 成功时不标记为降级', async () => {
  const provider = {
    isAvailable: () => true,
    inference: async () => ({
      output: [0.2, 0.4], featureVector: [0.1], confidence: 0.8,
      source: 'test-provider', labels: ['a', 'b']
    })
  };
  const result = await new inference.NeuralInference(provider).inference('demo://image');
  assert.equal(result.source, 'test-provider');
  assert.equal(result.status, 'available');
  assert.equal(result.modelAvailable, true);
  assert.equal(result.usedFallback, false);
  assert.deepEqual(result.scores, [0.2, 0.4]);
});
