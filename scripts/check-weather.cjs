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
let openMeteoResponse = null;
let requestedForecastUrl = '';
Module._load = function(request, parent, isMain) {
  if (request === '@kit.PerformanceAnalysisKit') {
    return { hilog: { info() {}, warn() {} } };
  }
  if (request === '@kit.AbilityKit') { return { common: {} }; }
  if (request === '@kit.NetworkKit') {
    return { http: {
      RequestMethod: { GET: 'GET' },
      createHttp: () => ({
        request: async (url) => {
          requestedForecastUrl = url;
          if (openMeteoResponse === null) { throw new Error('offline'); }
          return { responseCode: 200, result: JSON.stringify(openMeteoResponse) };
        },
        destroy() {}
      })
    } };
  }
  return originalLoad.call(this, request, parent, isMain);
};
let WeatherService;
let OpenMeteoWeather;
try {
  WeatherService = require('../entry/src/main/ets/service/WeatherService.ets').WeatherService;
  OpenMeteoWeather = require('../entry/src/main/ets/service/OpenMeteoWeather.ets');
} finally {
  Module._load = originalLoad;
}

test('Open-Meteo 解析真实结构、天气码、错误与城市级坐标', () => {
  const parsed = OpenMeteoWeather.parseOpenMeteo(JSON.stringify({
    current: { temperature_2m: 12.5, weather_code: 61 },
    daily: { temperature_2m_min: [8.2], temperature_2m_max: [16.4] }
  }));
  assert.deepEqual(parsed, { min: 8, max: 16, condition: '雨' });
  assert.equal(OpenMeteoWeather.parseOpenMeteo('{bad'), undefined);
  assert.equal(OpenMeteoWeather.parseOpenMeteo('{"daily":{}}'), undefined);
  assert.match(OpenMeteoWeather.forecastUrl(30.27123, 120.15234), /latitude=30.27&longitude=120.15/);
  assert.throws(() => OpenMeteoWeather.forecastUrl(91, 120), /无效/);
});

test('天气 Kit 不可用时使用城市坐标获取实际预报，断网时返回手动温度', async () => {
  WeatherService.setManualCity({ name: '杭州市', latitude: 30.27, longitude: 120.15 });
  WeatherService.weatherModule = null;
  openMeteoResponse = {
    current: { temperature_2m: 22, weather_code: 1 },
    daily: { temperature_2m_min: [18], temperature_2m_max: [26] }
  };
  const live = await WeatherService.refresh({});
  assert.equal(live.available, true);
  assert.equal(live.source, 'Open-Meteo 预报');
  assert.equal(live.city, '杭州市');
  assert.equal(live.tempMin, 18);
  assert.match(requestedForecastUrl, /api\.open-meteo\.com/);
  openMeteoResponse = null;
  const fallback = await WeatherService.refresh({});
  assert.equal(fallback.available, false);
  assert.match(fallback.source, /手动温度/);
});

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
