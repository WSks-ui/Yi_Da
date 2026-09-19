// 温度带 → 穿搭提示。
//
// 首页天气卡原本在副标题位置写「手动温度」，那只是数据来源标签，对用户没有信息量。
// 这里把温度翻译成一句可执行的提示：穿什么、要不要带伞。
//
// 边界取常见的体感分界（20℃ 以下加外套、10℃ 以下要保暖、28℃ 以上要透气），
// 每带一句文案加一个图标键，避免同一句话在相邻温度重复得太频繁。
//
// 图标只存字符串键、不在这里调用 $r()：这个模块要能在 Node 里跑测试，
// 而 $r() 是 ArkUI 的资源函数，脱离运行时会得到 undefined。
//
// 降水优先于温度：下雨下雪时「带伞」比「穿什么」更紧急。

export interface TemperatureBand {
  // 该温度带的上界（含）。温度带按 maxTemp 升序排列，取第一个满足 temp <= maxTemp 的。
  maxTemp: number;
  // 仅作标识，实际资源由 iconKeyToResource 转换。
  iconKey: string;
  text: string;
}

export const TEMPERATURE_BANDS: TemperatureBand[] = [
  { maxTemp: -50, iconKey: 'snow', text: '严寒，务必厚羽绒与保暖内层' },
  { maxTemp: 0, iconKey: 'snow', text: '冰冻，羽绒服加围巾手套' },
  { maxTemp: 5, iconKey: 'snow', text: '很冷，厚外套配毛衣' },
  { maxTemp: 10, iconKey: 'cloud', text: '冷，需要保暖外套' },
  { maxTemp: 15, iconKey: 'cloud', text: '偏冷，加一件薄外套' },
  { maxTemp: 20, iconKey: 'cloud', text: '凉爽，长袖正合适' },
  { maxTemp: 25, iconKey: 'mild', text: '微凉，适合薄外套' },
  { maxTemp: 28, iconKey: 'mild', text: '舒适，单穿长袖或薄衬衫' },
  { maxTemp: 32, iconKey: 'sun', text: '偏热，短袖透气为主' },
  { maxTemp: 100, iconKey: 'sun', text: '炎热，选轻薄速干面料' }
];

// 取温度对应的提示。温度是必填项，所以这里总能给出一个结果，不需要可空处理。
export function temperatureAdvice(temp: number): TemperatureBand {
  for (const band of TEMPERATURE_BANDS) {
    if (temp <= band.maxTemp) { return band; }
  }
  return TEMPERATURE_BANDS[TEMPERATURE_BANDS.length - 1];
}

// 降水提示：有雨雪时优先说明，因为带伞比穿什么更影响当天出门。
// 传入条件文本（可能为空），命中则返回该句，否则返回空串表示"没有额外提示"。
export function precipitationAdvice(condition: string): string {
  if (condition.indexOf('雪') >= 0) { return '有雪，注意防滑与保暖'; }
  if (condition.indexOf('雨') >= 0) { return '有雨，记得带伞'; }
  return '';
}
