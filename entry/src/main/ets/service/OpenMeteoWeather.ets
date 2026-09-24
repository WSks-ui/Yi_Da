import { http } from '@kit.NetworkKit';

// 只向天气服务发送约两位小数的城市级坐标。此服务是比赛版的联网备选来源；
// 结果是预报，不是设备温度或定位精度声明。
export interface OpenMeteoReading {
  min: number;
  max: number;
  condition: string;
}

interface CurrentForecast {
  temperature_2m?: number;
  weather_code?: number;
}

interface DailyForecast {
  temperature_2m_min?: number[];
  temperature_2m_max?: number[];
}

interface ForecastResponse {
  current?: CurrentForecast;
  daily?: DailyForecast;
}

function boundedCoordinate(value: number, limit: number): number {
  if (!Number.isFinite(value) || Math.abs(value) > limit) { throw new Error('天气坐标无效'); }
  return Math.round(value * 100) / 100;
}

export function forecastUrl(latitude: number, longitude: number): string {
  const lat: number = boundedCoordinate(latitude, 90);
  const lon: number = boundedCoordinate(longitude, 180);
  return `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}` +
    '&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min' +
    '&timezone=auto&forecast_days=1';
}

function weatherDescription(code: number | undefined): string {
  if (code === 0) { return '晴'; }
  if (code === 1 || code === 2) { return '多云'; }
  if (code === 3) { return '阴'; }
  if (code === 45 || code === 48) { return '雾'; }
  if (code !== undefined && ((code >= 51 && code <= 67) || (code >= 80 && code <= 82))) { return '雨'; }
  if (code !== undefined && ((code >= 71 && code <= 77) || code === 85 || code === 86)) { return '雪'; }
  if (code !== undefined && code >= 95 && code <= 99) { return '雷雨'; }
  return '';
}

export function parseOpenMeteo(text: string): OpenMeteoReading | undefined {
  let data: ForecastResponse;
  try { data = JSON.parse(text) as ForecastResponse; } catch (_) { return undefined; }
  const daily: DailyForecast | undefined = data.daily;
  const lows: number[] = daily?.temperature_2m_min || [];
  const highs: number[] = daily?.temperature_2m_max || [];
  const low: number | undefined = lows[0];
  const high: number | undefined = highs[0];
  const current: number | undefined = data.current?.temperature_2m;
  let min: number;
  let max: number;
  if (low !== undefined && high !== undefined && Number.isFinite(low) && Number.isFinite(high)) {
    min = Math.round(low);
    max = Math.round(high);
  } else if (current !== undefined && Number.isFinite(current)) {
    min = Math.round(current);
    max = min;
  } else { return undefined; }
  if (min > max || min < -90 || max > 65) { return undefined; }
  return { min: min, max: max, condition: weatherDescription(data.current?.weather_code) };
}

export async function fetchOpenMeteo(latitude: number, longitude: number): Promise<OpenMeteoReading | undefined> {
  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await request.request(forecastUrl(latitude, longitude), {
      method: http.RequestMethod.GET, connectTimeout: 5000, readTimeout: 5000
    });
    if (response.responseCode !== 200 || typeof response.result !== 'string') { return undefined; }
    return parseOpenMeteo(response.result);
  } finally { request.destroy(); }
}
