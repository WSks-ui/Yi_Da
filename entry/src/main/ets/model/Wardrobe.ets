export enum Category {
  TOP = '上装', BOTTOM = '下装', SHOES = '鞋履', OUTER = '外套', ACCESSORY = '配饰'
}

export enum GarmentStatus {
  READY = '可穿', LAUNDRY = '待洗', STORED = '收纳', HIDDEN = '季节隐藏', ARCHIVED = '已归档'
}

export const CATEGORIES: Category[] = [Category.TOP, Category.BOTTOM, Category.SHOES, Category.OUTER, Category.ACCESSORY];
export const STATUSES: GarmentStatus[] = [GarmentStatus.READY, GarmentStatus.LAUNDRY, GarmentStatus.STORED,
  GarmentStatus.HIDDEN, GarmentStatus.ARCHIVED];
export const OCCASIONS: string[] = ['上课', '课程展示', '社团', '约会'];
export const SEASONS: string[] = ['春', '夏', '秋', '冬', '四季'];

// 版型、配色和风格用于把偏好档案转成推荐顺序。演示衣物只有图片，属性是内置示例值。
export const FITS: string[] = ['宽松', '合身', '有轮廓感'];
export const PALETTES: string[] = ['基础色', '低饱和', '明亮'];
export const STYLES: string[] = ['简约', '学院', '通勤', '运动', '复古'];

// 偏好档案按维度记录，结果页展示的是可修改的多个维度，而不是唯一固定的风格结论。
export interface PreferenceProfile {
  fits: string[];
  palettes: string[];
  styles: string[];
  layering: number;
  accessories: number;
  priority: string;
  completed: boolean;
  // 体型档案作为可选上下文保留在偏好档案中，旧快照和旧调用不需要补字段。
  body?: BodyProfile;
}

export function emptyProfile(): PreferenceProfile {
  return { fits: [], palettes: [], styles: [], layering: 0, accessories: 0, priority: '', completed: false };
}

export interface Garment {
  id: string;
  name: string;
  category: Category;
  // 细类和材质由用户确认后保存；旧快照没有这两个可选字段时仍可正常读取。
  subcategory?: string;
  material?: string;
  imageKey: string;
  imageUri: string;
  color: string;
  minTemp: number;
  maxTemp: number;
  occasions: string[];
  // 季节和用户标签是可选整理字段；旧快照缺失时按空值处理。
  season?: string;
  tags?: string[];
  status: GarmentStatus;
  wearCount: number;
  // 用户对单件衣物的推荐反馈：1 多推荐，-1 少推荐，0/缺省为中性。
  // 这是软排序信号，不会绕过待洗、温度、场合等硬约束。
  recommendationBias?: number;
  isDemo: boolean;
  // 偏好匹配用的属性。导入的衣物在用户确认前保持中性值，不猜测。
  fit: string;
  palette: string;
  style: string;
  layering: boolean;
  pattern: boolean;
}

// 画布布局用 0..1 的中心坐标保存，层级由 items 顺序决定，换屏宽仍能恢复相同构图。
export interface CanvasPiece {
  garmentId: string;
  x: number;
  y: number;
  scale: number;
  rotation: number;
}

export interface OutfitLayout {
  background: string;
  items: CanvasPiece[];
}

export interface Outfit {
  id: string;
  garmentIds: string[];
  occasion: string;
  temperature: number;
  reason: string;
  // 用户自定义名称与收藏标记。手搭方案与规则推荐共用同一个结构。
  name: string;
  isCustom: boolean;
  savedAt: string;
  layout?: OutfitLayout;
}

export interface WearRecord {
  id: string;
  outfitId: string;
  garmentIds: string[];
  date: string;
  feedback: string;
}

// 穿搭日记：一天可以有多条，记录搭配、上身照片与文字。
// 佩戴日历用 date 字段归组，不做单独存储。
export interface DiaryEntry {
  id: string;
  date: string;
  garmentIds: string[];
  note: string;
  // 上身照片的应用沙箱路径，未拍摄时为空。
  photoUri: string;
  weather: string;
  temperature: number;
  occasion: string;
  feedback: string;
  // 历史日记可能未计入 wearCount；显式记录，编辑和删除时才知道应撤销哪次计数。
  wearCounted?: boolean;
}

// AI 试穿任务。没有接入生成服务时只保存"未接入"状态，不伪造进度或结果图。
export interface TryOnTask {
  id: string;
  // 固定演示样片的场景键。真实生成任务可以不填写，UI 只用它映射本地样片资源。
  demoSceneId?: string;
  outfitId: string;
  garmentIds: string[];
  pose: string;
  createdAt: string;
  status: string;
  // 生成结果图路径。未接入服务时始终为空。
  resultUris: string[];
  // 失败或未接入的原因，直接展示给用户。
  message: string;
}

// 会员体验状态。只描述真实存在的权益，不展示无法核销的承诺。
export interface Membership {
  // 体验开始日期，用于计算剩余天数。
  startDate: string;
  // 体验总天数，0 表示尚未领取。
  trialDays: number;
  // 已使用的试穿次数，用来展示真实额度消耗。
  tryOnUsed: number;
}

// 身材、尺码与色彩档案。每一项都可以单独留空，不强制填写。
export interface BodyProfile {
  height: string;
  size: string;
  fitPreference: string;
  shoulder: string;
  chest: string;
  waist: string;
  hip: string;
  skinTone: string;
  hairColor: string;
  eyeColor: string;
  updatedAt: string;
}

export interface OutfitRequest {
  occasion: string;
  temperature: number;
  lockedIds: string[];
  excludedIds: string[];
  profile: PreferenceProfile;
  // 推荐入口可直接传入身材档案；未传时由推荐服务保持旧排序。
  body?: BodyProfile;
}

export interface Recommendation {
  outfits: Outfit[];
  explanation: string;
}

// 城市坐标。定位不可用时用户手动选择，温度按城市典型值给出，用户仍可再调。
export interface CityOption {
  name: string;
  latitude: number;
  longitude: number;
  // 该城市的典型温度区间，手工模式下用它初始化推荐温度。
  typicalMin: number;
  typicalMax: number;
}

export const CITIES: CityOption[] = [
  { name: '湖州市', latitude: 30.8943, longitude: 120.0863, typicalMin: 15, typicalMax: 24 },
  { name: '杭州市', latitude: 30.2741, longitude: 120.1551, typicalMin: 16, typicalMax: 25 },
  { name: '上海市', latitude: 31.2304, longitude: 121.4737, typicalMin: 16, typicalMax: 24 },
  { name: '北京市', latitude: 39.9042, longitude: 116.4074, typicalMin: 8, typicalMax: 20 },
  { name: '深圳市', latitude: 22.5431, longitude: 114.0579, typicalMin: 22, typicalMax: 30 }
];

export interface DemoSnapshot {
  version: number;
  garments: Garment[];
  saved: Outfit[];
  records: WearRecord[];
  occasion: string;
  temperature: number;
  activeIds: string[];
  profile: PreferenceProfile;
  diary: DiaryEntry[];
  tryOnTasks: TryOnTask[];
  membership: Membership;
  body: BodyProfile;
  // 用户选择的城市名。空字符串表示还没选过，首页会引导选择。
  city: string;
}

export function emptyMembership(): Membership {
  return { startDate: '', trialDays: 0, tryOnUsed: 0 };
}

export function emptyBodyProfile(): BodyProfile {
  return { height: '', size: '', fitPreference: '', shoulder: '', chest: '', waist: '', hip: '',
    skinTone: '', hairColor: '', eyeColor: '', updatedAt: '' };
}

// 会员体验剩余天数。未领取时返回 0，过期返回 0，不用负数表示。
export function trialDaysLeft(membership: Membership): number {
  if (membership.trialDays <= 0 || membership.startDate.length === 0) { return 0; }
  const start = new Date(membership.startDate).getTime();
  if (!Number.isFinite(start)) { return 0; }
  const passed = Math.floor((Date.now() - start) / 86400000);
  return Math.max(0, membership.trialDays - passed);
}

// 衣橱完善度：由已录入衣物数、已确认属性数、已补尺寸数、是否完成偏好档案组成。
// 只作为参考进度，不作为使用门槛。
export interface Completeness {
  garments: number;
  attributes: number;
  sizes: number;
  profileDone: boolean;
  percent: number;
}

export function completeness(snapshot: DemoSnapshot): Completeness {
  const garments = snapshot.garments.length;
  // 每件衣物至少要有品类、颜色和温度区间，视为已确认属性。
  const attributes = snapshot.garments.filter((item: Garment) =>
    item.category.length > 0 && item.color.length > 0 && item.maxTemp > item.minTemp).length;
  const body = snapshot.body;
  let sizes = 0;
  if (body.height.length > 0) { sizes++; }
  if (body.size.length > 0) { sizes++; }
  if (body.chest.length > 0 || body.waist.length > 0 || body.hip.length > 0) { sizes++; }
  const profileDone = snapshot.profile.completed;
  // 四项目标各占 25 分，衣橱与属性按完成比例折算。
  const garmentScore = Math.min(1, garments / 10) * 25;
  const attributeScore = garments > 0 ? (attributes / garments) * 25 : 0;
  const sizeScore = (sizes / 3) * 25;
  const profileScore = profileDone ? 25 : 0;
  return { garments: garments, attributes: attributes, sizes: sizes, profileDone: profileDone,
    percent: Math.round(garmentScore + attributeScore + sizeScore + profileScore) };
}

export function copyGarment(item: Garment): Garment {
  const copy: Garment = {
    id: item.id, name: item.name, category: item.category, imageKey: item.imageKey,
    imageUri: item.imageUri, color: item.color, minTemp: item.minTemp, maxTemp: item.maxTemp,
    occasions: item.occasions.slice(), status: item.status, wearCount: item.wearCount,
    isDemo: item.isDemo,
    fit: item.fit, palette: item.palette, style: item.style, layering: item.layering, pattern: item.pattern
  };
  // Optional 字段只有在原对象确实存在时才复制，避免旧快照的 JSON 形状被
  // 无意义的 undefined 键改变，同时保留用户已确认的细类、材质和反馈。
  if (item.subcategory !== undefined) { copy.subcategory = item.subcategory; }
  if (item.material !== undefined) { copy.material = item.material; }
  if (item.season !== undefined) { copy.season = item.season; }
  if (item.tags !== undefined) { copy.tags = item.tags.slice(); }
  if (item.recommendationBias !== undefined) { copy.recommendationBias = item.recommendationBias; }
  return copy;
}

export function garmentImage(item: Garment): ResourceStr {
  if (item.imageUri.length > 0) { return item.imageUri; }
  switch (item.imageKey) {
    case 'shirt': return $r('app.media.demo_shirt');
    case 'jeans': return $r('app.media.demo_jeans');
    case 'shoes': return $r('app.media.demo_sneakers');
    case 'jacket': return $r('app.media.demo_jacket');
    case 'graphic': return $r('app.media.demo_knit');
    default: return $r('app.media.demo_tee');
  }
}
