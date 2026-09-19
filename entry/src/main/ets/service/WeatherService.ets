// 天气能力探测与加载。
//
// 重要：Weather Service Kit 与 Location Kit 是 HMS 侧的共享包，未预置的设备（例如本机模拟器）
// 上加载会直接让进程 abort —— 崩溃信息为 "load hsp failed, hsp name:com.huawei.hms.weather/
// WeatherService"。因此这里不做顶层静态 import，改为运行时 try/catch 动态加载：
// 能力不存在时返回 null，界面继续使用手动温度，基础衣橱与推荐完全不受影响。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { CityOption } from '../model/Wardrobe';

const DOMAIN: number = 0x1200;
const TAG: string = 'YiDaWeather';

export interface WeatherSnapshot {
  available: boolean;
  city: string;
  condition: string;
  tempMin: number;
  tempMax: number;
  // 数据来源说明，直接展示给用户，避免把估计值说成实测值。
  source: string;
}

// 只声明用到的成员形状，避免引用 HMS 的类型而把静态依赖带进来。
interface CurrentLike {
  temperature: number;
  condition: ConditionLike;
}

interface ConditionLike {
  description: string;
}

interface DailyLike {
  lowTemperature: number;
  highTemperature: number;
}

interface ForecastLike {
  forecast: DailyLike[];
}

interface WeatherLike {
  current?: CurrentLike;
  daily?: ForecastLike;
}

interface WeatherModuleLike {
  getWeatherWithContext(context: common.Context, request: WeatherRequestLike): Promise<WeatherLike>;
  Dataset: DatasetLike;
}

interface DatasetLike {
  CURRENT: number;
  DAILY: number;
}

interface WeatherRequestLike {
  location: LocationLike;
  limitedDatasets: number[];
}

interface LocationLike {
  latitude: number;
  longitude: number;
}

interface GeoModuleLike {
  isLocationEnabled(): boolean;
  getCurrentLocation(request: LocationRequestLike): Promise<LocationLike>;
}

interface LocationRequestLike {
  priority: number;
  scenario: number;
  timeoutMs: number;
}

export class WeatherService {
  private static manualCity: CityOption | undefined = undefined;
  private static lastResult: WeatherSnapshot | undefined = undefined;
  private static weatherModule: WeatherModuleLike | null | undefined = undefined;
  private static geoModule: GeoModuleLike | null | undefined = undefined;

  static setManualCity(city: CityOption): void {
    WeatherService.manualCity = city;
    WeatherService.lastResult = undefined;
  }

  static manualCityName(): string {
    return WeatherService.manualCity !== undefined ? WeatherService.manualCity.name : '';
  }

  static cached(): WeatherSnapshot | undefined { return WeatherService.lastResult; }

  // 动态加载 HMS 模块；设备没有该共享包时返回 null 并记录一次日志。
  private static async weather(): Promise<WeatherModuleLike | null> {
    if (WeatherService.weatherModule !== undefined) { return WeatherService.weatherModule; }
    try {
      // Kit 导出的是 { weatherService, default }，先取模块对象再取服务对象。
      const kit: Record<string, object> = await import('@kit.WeatherServiceKit') as Record<string, object>;
      const loaded: WeatherModuleLike = kit['weatherService'] as WeatherModuleLike;
      WeatherService.weatherModule = loaded;
    } catch (error) {
      hilog.info(DOMAIN, TAG, 'weather kit unavailable on this device');
      WeatherService.weatherModule = null;
    }
    return WeatherService.weatherModule;
  }

  private static async geo(): Promise<GeoModuleLike | null> {
    if (WeatherService.geoModule !== undefined) { return WeatherService.geoModule; }
    try {
      const kit: Record<string, object> = await import('@kit.LocationKit') as Record<string, object>;
      const loaded: GeoModuleLike = kit['geoLocationManager'] as GeoModuleLike;
      WeatherService.geoModule = loaded;
    } catch (error) {
      hilog.info(DOMAIN, TAG, 'location kit unavailable on this device');
      WeatherService.geoModule = null;
    }
    return WeatherService.geoModule;
  }

  // 取当前坐标：先试定位，失败后用手动城市。两者都没有则返回 undefined。
  private static async resolveLocation(): Promise<LocationLike | undefined> {
    const geo: GeoModuleLike | null = await WeatherService.geo();
    if (geo !== null) {
      try {
        if (geo.isLocationEnabled()) {
          // 枚举值取自 Location Kit：FIRST_FIX=1，DAILY_LIFE_SERVICE=0。
          const location: LocationLike = await geo.getCurrentLocation({
            priority: 1, scenario: 0, timeoutMs: 3000
          });
          return { latitude: location.latitude, longitude: location.longitude };
        }
      } catch (error) {
        hilog.info(DOMAIN, TAG, 'location read failed, falling back to manual city');
      }
    }
    if (WeatherService.manualCity !== undefined) {
      return { latitude: WeatherService.manualCity.latitude, longitude: WeatherService.manualCity.longitude };
    }
    return undefined;
  }

  // 拉取真实天气。任何失败都返回 available=false，由界面给出"手动温度"的说明。
  static async refresh(context: common.Context): Promise<WeatherSnapshot> {
    const fallback: WeatherSnapshot = { available: false, city: WeatherService.manualCityName(),
      condition: '', tempMin: 0, tempMax: 0, source: '手动温度' };
    const kit: WeatherModuleLike | null = await WeatherService.weather();
    if (kit === null) {
      fallback.source = '本机无天气服务，使用手动温度';
      return fallback;
    }
    const location: LocationLike | undefined = await WeatherService.resolveLocation();
    if (location === undefined) { return fallback; }
    try {
      const weather: WeatherLike = await kit.getWeatherWithContext(context, {
        location: location,
        limitedDatasets: [kit.Dataset.CURRENT, kit.Dataset.DAILY]
      });
      const current: CurrentLike | undefined = weather.current;
      const daily: ForecastLike | undefined = weather.daily;
      let tempMin: number = 0;
      let tempMax: number = 0;
      // Forecast 把多日数据放在 forecast 数组里，不能直接当数组用。
      const days: DailyLike[] = daily !== undefined ? daily.forecast : [];
      if (days.length > 0) {
        // 系统给的是当日最高与最低温，展示区间比单点温度更有参考价值。
        tempMin = Math.round(days[0].lowTemperature);
        tempMax = Math.round(days[0].highTemperature);
      } else if (current !== undefined) {
        tempMin = Math.round(current.temperature);
        tempMax = tempMin;
      }
      const snapshot: WeatherSnapshot = {
        available: true,
        city: WeatherService.manualCityName(),
        // 天气现象文案由系统给出，不自行映射天气码，避免映射表过期后显示错误。
        condition: current !== undefined ? current.condition.description : '',
        tempMin: tempMin, tempMax: tempMax,
        source: '来自系统天气服务'
      };
      WeatherService.lastResult = snapshot;
      return snapshot;
    } catch (error) {
      // 1011900001 表示应用未在 AGC 配置天气服务能力；如实提示，不猜测天气。
      hilog.warn(DOMAIN, TAG, 'weather request failed');
      fallback.source = '天气获取失败，使用手动温度';
      return fallback;
    }
  }
}
