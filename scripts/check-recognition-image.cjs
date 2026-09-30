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
const recognition = require('../entry/src/main/ets/service/GarmentRecognition.ets');

// 执行真正的 SDK 宿主适配器，只注入文件系统/解码器边界，不复制图片读取和结果组合流程。
function reader(failAt = '') {
  const calls = { opened: [], options: [], closed: 0, sourceReleased: 0, pixelsReleased: 0 };
  const fail = stage => { if (failAt === stage) throw new Error(stage); };
  const sdk = {
    '@kit.CoreFileKit': { fileIo: { OpenMode: { READ_ONLY: 1 },
      open: async uri => { calls.opened.push(uri); fail('open'); return { fd: 42 }; },
      close: async () => { calls.closed++; fail('close'); }
    } },
    '@kit.ImageKit': { image: { PixelMapFormat: { RGBA_8888: 1 }, createImageSource: fd => {
      assert.equal(fd, 42); return {
        getImageInfo: async () => { fail('info'); return { size: { width: 100, height: 200 } }; },
        createPixelMap: async options => { calls.options.push(options); fail('decode'); return {
          getPixelBytesNumber: () => 48,
          readPixelsToBuffer: async buffer => {
            fail('read'); const rgba = new Uint8Array(buffer);
            for (let i = 0; i < rgba.length; i += 4) rgba.set([27, 78, 220, 255], i);
          },
          release: async () => { calls.pixelsReleased++; fail('pixelsRelease'); }
        }; },
        release: async () => { calls.sourceReleased++; fail('sourceRelease'); }
      };
    } } },
    '@kit.PerformanceAnalysisKit': { hilog: { warn() {} } },
    './GarmentRecognition': recognition
  };
  const filename = path.resolve(__dirname, '../entry/src/main/ets/service/GarmentRecognitionImage.ets');
  const exports = {};
  new Function('require', 'exports', ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText)(name => {
    assert.ok(sdk[name], '必须显式替代平台依赖：' + name); return sdk[name];
  }, exports);
  return { ...exports, calls };
}

test('真实图片颜色接线：静态 Kit 解码像素，按比例限幅，不从文件名推断属性', async () => {
  const host = reader(); const result = await host.recognizeGarmentPhoto('file://red-dress-silk.png');
  assert.deepEqual(host.calls.opened, ['file://red-dress-silk.png']);
  assert.deepEqual(host.calls.options, [{ desiredSize: { width: 24, height: 48 }, desiredPixelFormat: 1 }]);
  assert.equal(result.color, '蓝色'); assert.equal(result.colorSource, recognition.RECOGNITION_SOURCE_PIXEL_COLOR);
  assert.equal(result.category, ''); assert.equal(result.material, ''); assert.equal(result.userConfirmed, false);
  assert.equal(host.calls.closed, 1); assert.equal(host.calls.sourceReleased, 1); assert.equal(host.calls.pixelsReleased, 1);
  const index = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/Index.ets'), 'utf8');
  assert.match(index, /recognizeGarmentPhoto as recognizeGarment/);
});

test('真实图片颜色接线：打开、读元信息、解码或像素读取失败均明确降级，已创建对象全部释放', async () => {
  for (const stage of ['open', 'info', 'decode', 'read']) {
    const host = reader(stage), result = await host.recognizeGarmentPhoto('file://blue-shirt.png');
    assert.equal(result.source, recognition.RECOGNITION_SOURCE_UNAVAILABLE); assert.equal(result.color, '');
    assert.equal(host.calls.closed, stage === 'open' ? 0 : 1);
    assert.equal(host.calls.sourceReleased, stage === 'open' ? 0 : 1);
    assert.equal(host.calls.pixelsReleased, stage === 'read' ? 1 : 0);
  }
});

test('真实图片颜色接线：单个释放异常不影响其它释放或成功得到的颜色建议', async () => {
  for (const stage of ['pixelsRelease', 'sourceRelease', 'close']) {
    const host = reader(stage), result = await host.recognizeGarmentPhoto('file://photo.png');
    assert.equal(result.color, '蓝色'); assert.equal(host.calls.closed, 1);
    assert.equal(host.calls.sourceReleased, 1); assert.equal(host.calls.pixelsReleased, 1);
  }
});
