const fs = require('node:fs');
const assert = require('node:assert/strict');
const Module = require('node:module');
const { test } = require('node:test');
const ts = require(process.argv[2] || 'typescript');

if (!require.extensions['.ets']) {
  require.extensions['.ets'] = (loadedModule, filename) => {
    const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    loadedModule._compile(output, filename);
  };
}

// 桌面检查只替换 Kit 导入；WeatherService 的定位请求和天气解析仍运行生产实现。
const originalLoad = Module._load;
Module._load = function(request, parent, isMain) {
  if (request === '@kit.PerformanceAnalysisKit') {
    return { hilog: { info() {}, warn() {} } };
  }
  if (request === '@kit.AbilityKit') { return { common: {} }; }
  return originalLoad.call(this, request, parent, isMain);
};
let WeatherService;
try {
  WeatherService = require('../entry/src/main/ets/service/WeatherService.ets').WeatherService;
} finally {
  Module._load = originalLoad;
}

test('真实 WeatherService：位置请求使用 Kit 枚举并把设备坐标交给天气服务', async () => {
  let locationRequest;
  let weatherRequest;
  WeatherService.setManualCity({ name: '杭州市', latitude: 30.27, longitude: 120.15 });
  WeatherService.geoModule = {
    LocationRequestPriority: { LOW_POWER: 0x202 },
    LocationRequestScenario: { DAILY_LIFE_SERVICE: 0x304 },
    isLocationEnabled: () => true,
    getCurrentLocation: async (request) => {
      locationRequest = request;
      return { latitude: 31.23, longitude: 121.47 };
    }
  };
  WeatherService.weatherModule = {
    Dataset: { CURRENT: 1, DAILY: 2 },
    getWeatherWithContext: async (_context, request) => {
      weatherRequest = request;
      return { current: { temperature: 12, condition: { description: '晴' } },
        daily: { forecast: [{ lowTemperature: 8, highTemperature: 16 }] } };
    }
  };
  const result = await WeatherService.refresh({}, true);
  assert.equal(locationRequest.priority, 0x202);
  assert.equal(locationRequest.scenario, 0x304);
  assert.deepEqual(weatherRequest.location, { latitude: 31.23, longitude: 121.47 });
  assert.equal(result.city, '当前位置');
  assert.equal(result.available, true);
  assert.equal(result.tempMin, 8);
  assert.equal(result.tempMax, 16);
});

test('真实 WeatherService：天气服务缺少温度数据时保持手动回退', async () => {
  WeatherService.weatherModule = {
    Dataset: { CURRENT: 1, DAILY: 2 },
    getWeatherWithContext: async () => ({})
  };
  const result = await WeatherService.refresh({}, false);
  assert.equal(result.available, false);
  assert.match(result.source, /天气数据异常/);
});
