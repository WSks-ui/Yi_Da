// 衣物识别服务的纯数据契约与离线实现。
//
// 这里故意没有引入网络库，也没有把某个云端 SDK 写死在服务层。上层只需要依赖
// GarmentRecognitionProvider，未来可以把同一份输入交给云端服务；当前演示版本使用
// 文件名/Uri 中的确定性 token 做本地规则识别，明确把 source 标成 offline-file-token。
// 这样演示时可以展示完整的“识别结果 -> 用户确认”链路，同时不会把规则命中伪装成
// 真正的视觉模型输出。

export const MIN_AUTO_RECOGNITION_CONFIDENCE: number = 0.65;
export const RECOGNITION_SOURCE_LOCAL: string = 'offline-file-token';
export const RECOGNITION_SOURCE_PIXEL_COLOR: string = 'offline-pixel-color';
export const RECOGNITION_SOURCE_UNAVAILABLE: string = 'unavailable';
export const RECOGNITION_SOURCE_USER: string = 'user-confirmed';
export const RECOGNITION_SOURCE_EXISTING: string = 'existing-draft';
export const RECOGNITION_SOURCE_MIXED: string = 'mixed';

export interface GarmentRecognition {
  category: string;
  color: string;
  material: string;
  confidence: number;
  source: string;
  userConfirmed: boolean;
  // 每个字段保留一份可解释的置信度，方便 UI 只提示低置信度字段，而不改变主契约。
  categoryConfidence?: number;
  colorConfidence?: number;
  materialConfidence?: number;
  // 总 source 只作兼容摘要；逐字段 source 才说明该值来自像素、文件名提示还是用户。
  categorySource?: string;
  colorSource?: string;
  materialSource?: string;
}

export interface GarmentRecognitionInput {
  uri: string;
  fileName?: string;
}

export interface RecognitionConfirmation {
  category?: boolean;
  color?: boolean;
  material?: boolean;
}

export interface RecognitionDraft {
  category?: string;
  color?: string;
  material?: string;
  userConfirmed?: boolean;
}

export interface GarmentRecognitionProvider {
  recognize(input: GarmentRecognitionInput): Promise<GarmentRecognition>;
}

export type RecognitionProvider = GarmentRecognitionProvider;

interface TokenRule {
  value: string;
  tokens: string[];
  priority: number;
}

interface TokenMatch {
  value: string;
  score: number;
}

// 只声明实际调用到的 Kit 成员，避免把服务层绑定到某个具体 HMS 共享包版本。
// 动态加载失败时，服务会回到文件名线索或 unavailable，不影响衣橱其余流程。
interface FileLike { fd: number; }
interface FileOpenModeLike { READ_ONLY: number; }
interface FileIoLike {
  OpenMode: FileOpenModeLike;
  open(uri: string, mode: number): Promise<FileLike>;
  close(file: FileLike): Promise<void>;
}
interface PixelMapLike {
  getPixelBytesNumber(): number;
  readPixelsToBuffer(buffer: ArrayBuffer): Promise<void>;
  release(): Promise<void>;
}
interface ImageSizeLike { width: number; height: number; }
interface ImageInfoLike { size: ImageSizeLike; }
interface ImageSourceLike {
  getImageInfo(): Promise<ImageInfoLike>;
  createPixelMap(options: object): Promise<PixelMapLike>;
  release(): Promise<void>;
}
interface PixelMapFormatLike { RGBA_8888: number; }
interface ImageModuleLike {
  PixelMapFormat: PixelMapFormatLike;
  createImageSource(fd: number): ImageSourceLike;
}
interface PixelMapDecodingOptionsLike {
  desiredSize: ImageSizeLike;
  desiredPixelFormat: number;
}

export interface ColorObservation {
  color: string;
  confidence: number;
}

const PIXEL_COLOR_NAMES: string[] = ['黑色', '白色', '灰色', '红色', '橙色', '黄色', '绿色',
  '蓝色', '藏青色', '紫色', '粉色', '棕色', '米色'];

// 将单个像素归到有限色类。这里只是像素颜色统计，不代表理解了服装主体或识别了材质。
function colorNameFromRgb(red: number, green: number, blue: number): string {
  const maximum: number = Math.max(red, green, blue);
  const minimum: number = Math.min(red, green, blue);
  const delta: number = maximum - minimum;
  const saturation: number = maximum <= 0 ? 0 : delta / maximum;
  const brightness: number = maximum / 255;
  if (brightness <= 0.14) { return '黑色'; }
  if (saturation < 0.13) {
    if (brightness >= 0.86) { return '白色'; }
    return '灰色';
  }

  let hue: number = 0;
  if (delta > 0) {
    if (maximum === red) { hue = 60 * (((green - blue) / delta) % 6); }
    else if (maximum === green) { hue = 60 * ((blue - red) / delta + 2); }
    else { hue = 60 * ((red - green) / delta + 4); }
    if (hue < 0) { hue += 360; }
  }

  if (hue < 12 || hue >= 350) {
    return saturation < 0.42 && brightness >= 0.68 ? '粉色' : '红色';
  }
  if (hue < 42) {
    if (brightness < 0.48) { return '棕色'; }
    if (red >= green && green >= blue && saturation < 0.48 && brightness >= 0.68) { return '米色'; }
    return '橙色';
  }
  if (hue < 68) { return saturation < 0.34 && brightness >= 0.68 ? '米色' : '黄色'; }
  if (hue < 165) { return '绿色'; }
  if (hue < 250) { return brightness < 0.42 ? '藏青色' : '蓝色'; }
  if (hue < 315) { return '紫色'; }
  return '粉色';
}

// 纯函数供桌面检查与设备服务共用；忽略透明像素和常见纯白抠图背景，按色类票数投票。
// 白底图若没有其它有效颜色则回退到原始样本，避免把全白衣物误报成“无结果”。
export function analyzeRgbaPixels(bytes: Uint8Array): ColorObservation | undefined {
  const counts: Record<string, number> = {};
  let count: number = 0;
  let fallbackColor: string = '';
  let fallbackCount: number = 0;
  for (let index: number = 0; index + 3 < bytes.length; index += 4) {
    const red: number = bytes[index];
    const green: number = bytes[index + 1];
    const blue: number = bytes[index + 2];
    const alpha: number = bytes[index + 3];
    if (alpha < 32) { continue; }
    const color: string = colorNameFromRgb(red, green, blue);
    if (fallbackColor.length === 0 || fallbackCount === 0) { fallbackColor = color; }
    fallbackCount++;
    if (red > 245 && green > 245 && blue > 245) { continue; }
    counts[color] = (counts[color] || 0) + 1;
    count++;
  }

  if (count === 0) {
    if (fallbackCount === 0) { return undefined; }
    return { color: fallbackColor, confidence: 0.55 };
  }

  let winner: string = '';
  let winnerCount: number = 0;
  let runnerUpCount: number = 0;
  for (const color of PIXEL_COLOR_NAMES) {
    const colorCount: number = counts[color] || 0;
    if (colorCount > winnerCount) {
      runnerUpCount = winnerCount;
      winner = color;
      winnerCount = colorCount;
    } else if (colorCount > runnerUpCount) {
      runnerUpCount = colorCount;
    }
  }
  if (winner.length === 0 || count < 8) { return undefined; }
  const share: number = winnerCount / count;
  const margin: number = (winnerCount - runnerUpCount) / count;
  // 这是基于缩略图票数的提示分，不是经过数据集校准的模型概率。
  const confidence: number = Number(Math.max(0.35, Math.min(0.95, 0.35 + share * 0.45 + margin * 0.45))
    .toFixed(2));
  return { color: winner, confidence: confidence };
}

// 识别列表覆盖常见上装、外套、裙装、下装、内衣、鞋履和配饰。
// 这些是演示契约中的“细分类别”，不是现有推荐引擎使用的五个大类 Category。
export const GARMENT_CATEGORY_RULES: TokenRule[] = [
  { value: '圆领T恤', tokens: ['圆领t恤', 'crewneck', 'crew-neck'], priority: 95 },
  { value: 'V领T恤', tokens: ['v领t恤', 'v-neck', 'vneck'], priority: 95 },
  { value: 'T恤', tokens: ['t恤', 't-shirt', 'tshirt', 'tee'], priority: 90 },
  { value: 'Polo衫', tokens: ['polo', 'polo衫'], priority: 90 },
  { value: '衬衫', tokens: ['衬衫', 'shirt'], priority: 88 },
  { value: '短袖衬衫', tokens: ['短袖衬衫', 'short-sleeve-shirt'], priority: 94 },
  { value: '长袖衬衫', tokens: ['长袖衬衫', 'long-sleeve-shirt'], priority: 94 },
  { value: '休闲衬衫', tokens: ['休闲衬衫', 'casual-shirt'], priority: 92 },
  { value: '雪纺衫', tokens: ['雪纺衫', 'chiffon-top'], priority: 94 },
  { value: '吊带衫', tokens: ['吊带衫', 'camisole', 'cami'], priority: 92 },
  { value: '背心', tokens: ['背心', 'tank-top', 'tanktop'], priority: 88 },
  { value: '工字背心', tokens: ['工字背心', 'racerback'], priority: 94 },
  { value: '针织衫', tokens: ['针织衫', 'knit-top', 'knitwear'], priority: 90 },
  { value: '毛衣', tokens: ['毛衣', 'sweater', 'pullover'], priority: 90 },
  { value: '高领毛衣', tokens: ['高领毛衣', 'turtleneck'], priority: 95 },
  { value: '开衫', tokens: ['开衫', 'cardigan'], priority: 90 },
  { value: '卫衣', tokens: ['卫衣', 'sweatshirt'], priority: 90 },
  { value: '连帽卫衣', tokens: ['连帽卫衣', 'hoodie', 'hooded-sweatshirt'], priority: 95 },
  { value: '运动上衣', tokens: ['运动上衣', 'sports-top', 'activewear-top'], priority: 92 },
  { value: '打底衫', tokens: ['打底衫', 'base-layer'], priority: 90 },
  { value: '保暖内衣上衣', tokens: ['保暖内衣上衣', 'thermal-top'], priority: 96 },
  { value: '马甲', tokens: ['马甲', 'vest'], priority: 88 },
  { value: '西装马甲', tokens: ['西装马甲', 'waistcoat'], priority: 95 },
  { value: '夹克', tokens: ['夹克', 'jacket'], priority: 86 },
  { value: '牛仔夹克', tokens: ['牛仔夹克', 'denim-jacket', 'jean-jacket'], priority: 95 },
  { value: '皮夹克', tokens: ['皮夹克', 'leather-jacket'], priority: 95 },
  { value: '棒球夹克', tokens: ['棒球夹克', 'varsity-jacket', 'baseball-jacket'], priority: 95 },
  { value: '风衣', tokens: ['风衣', 'trench-coat', 'trench'], priority: 92 },
  { value: '长风衣', tokens: ['长风衣', 'long-trench'], priority: 96 },
  { value: '大衣', tokens: ['大衣', 'coat'], priority: 86 },
  { value: '羊毛大衣', tokens: ['羊毛大衣', 'wool-coat'], priority: 96 },
  { value: '羽绒服', tokens: ['羽绒服', 'down-jacket', 'down-coat'], priority: 95 },
  { value: '轻薄羽绒服', tokens: ['轻薄羽绒服', 'light-down'], priority: 98 },
  { value: '棉服', tokens: ['棉服', 'padded-jacket'], priority: 92 },
  { value: '派克大衣', tokens: ['派克大衣', 'parka'], priority: 95 },
  { value: '冲锋衣', tokens: ['冲锋衣', 'hardshell', 'shell-jacket'], priority: 94 },
  { value: '雨衣', tokens: ['雨衣', 'raincoat'], priority: 94 },
  { value: '西装外套', tokens: ['西装外套', 'blazer'], priority: 94 },
  { value: '西服', tokens: ['西服', 'suit-jacket', 'suit'], priority: 90 },
  { value: '小香风外套', tokens: ['小香风外套', 'boucle-jacket'], priority: 98 },
  { value: '针织外套', tokens: ['针织外套', 'knit-jacket'], priority: 94 },
  { value: '抓绒外套', tokens: ['抓绒外套', 'fleece-jacket', 'fleece'], priority: 94 },
  { value: '机车夹克', tokens: ['机车夹克', 'moto-jacket', 'biker-jacket'], priority: 96 },
  { value: '连衣裙', tokens: ['连衣裙', 'dress'], priority: 90 },
  { value: '吊带裙', tokens: ['吊带裙', 'slip-dress'], priority: 95 },
  { value: '衬衫裙', tokens: ['衬衫裙', 'shirt-dress'], priority: 95 },
  { value: '针织裙', tokens: ['针织裙', 'knit-dress'], priority: 95 },
  { value: '礼服', tokens: ['礼服', 'formal-dress'], priority: 92 },
  { value: '晚礼服', tokens: ['晚礼服', 'evening-gown'], priority: 96 },
  { value: '婚纱', tokens: ['婚纱', 'wedding-dress'], priority: 98 },
  { value: '旗袍', tokens: ['旗袍', 'qipao', 'cheongsam'], priority: 98 },
  { value: '汉服', tokens: ['汉服', 'hanfu'], priority: 98 },
  { value: '连体裤', tokens: ['连体裤', 'jumpsuit'], priority: 95 },
  { value: '背带裤', tokens: ['背带裤', 'dungarees', 'bib-pants'], priority: 95 },
  { value: '工装连体裤', tokens: ['工装连体裤', 'coveralls'], priority: 98 },
  { value: '牛仔裤', tokens: ['牛仔裤', 'jeans', 'denim-pants'], priority: 94 },
  { value: '直筒裤', tokens: ['直筒裤', 'straight-leg'], priority: 92 },
  { value: '阔腿裤', tokens: ['阔腿裤', 'wide-leg'], priority: 92 },
  { value: '休闲裤', tokens: ['休闲裤', 'casual-pants'], priority: 90 },
  { value: '西装裤', tokens: ['西装裤', 'dress-pants'], priority: 94 },
  { value: '卡其裤', tokens: ['卡其裤', 'chinos', 'khakis'], priority: 94 },
  { value: '工装裤', tokens: ['工装裤', 'cargo-pants'], priority: 94 },
  { value: '束脚裤', tokens: ['束脚裤', 'joggers'], priority: 92 },
  { value: '运动裤', tokens: ['运动裤', 'track-pants', 'sports-pants'], priority: 92 },
  { value: '卫裤', tokens: ['卫裤', 'sweatpants'], priority: 92 },
  { value: '打底裤', tokens: ['打底裤', 'leggings'], priority: 94 },
  { value: '紧身裤', tokens: ['紧身裤', 'skinny-pants'], priority: 92 },
  { value: '短裤', tokens: ['短裤', 'shorts'], priority: 88 },
  { value: '牛仔短裤', tokens: ['牛仔短裤', 'denim-shorts'], priority: 96 },
  { value: '运动短裤', tokens: ['运动短裤', 'sports-shorts'], priority: 96 },
  { value: '半身裙', tokens: ['半身裙', 'skirt'], priority: 90 },
  { value: '牛仔裙', tokens: ['牛仔裙', 'denim-skirt'], priority: 95 },
  { value: 'A字裙', tokens: ['a字裙', 'a-line-skirt', 'aline-skirt'], priority: 96 },
  { value: '百褶裙', tokens: ['百褶裙', 'pleated-skirt'], priority: 96 },
  { value: '包臀裙', tokens: ['包臀裙', 'bodycon-skirt'], priority: 96 },
  { value: '铅笔裙', tokens: ['铅笔裙', 'pencil-skirt'], priority: 96 },
  { value: '迷你裙', tokens: ['迷你裙', 'mini-skirt'], priority: 95 },
  { value: '中长裙', tokens: ['中长裙', 'midi-skirt'], priority: 95 },
  { value: '长裙', tokens: ['长裙', 'maxi-skirt'], priority: 94 },
  { value: '裙裤', tokens: ['裙裤', 'skort'], priority: 94 },
  { value: '背带裙', tokens: ['背带裙', 'pinafore'], priority: 95 },
  { value: '内裤', tokens: ['内裤', 'underwear', 'briefs', 'panties'], priority: 90 },
  { value: '文胸', tokens: ['文胸', 'bra', 'brassiere'], priority: 94 },
  { value: '睡衣', tokens: ['睡衣', 'pajamas', 'pyjamas'], priority: 92 },
  { value: '家居服', tokens: ['家居服', 'loungewear'], priority: 92 },
  { value: '睡裙', tokens: ['睡裙', 'nightgown'], priority: 94 },
  { value: '泳装', tokens: ['泳装', 'swimwear', 'swimsuit'], priority: 90 },
  { value: '比基尼', tokens: ['比基尼', 'bikini'], priority: 96 },
  { value: '连体泳衣', tokens: ['连体泳衣', 'one-piece-swimsuit'], priority: 98 },
  { value: '运动鞋', tokens: ['运动鞋', 'sneakers', 'trainer'], priority: 90 },
  { value: '跑鞋', tokens: ['跑鞋', 'running-shoes'], priority: 95 },
  { value: '篮球鞋', tokens: ['篮球鞋', 'basketball-shoes'], priority: 96 },
  { value: '帆布鞋', tokens: ['帆布鞋', 'canvas-shoes'], priority: 95 },
  { value: '板鞋', tokens: ['板鞋', 'skate-shoes'], priority: 94 },
  { value: '休闲鞋', tokens: ['休闲鞋', 'casual-shoes'], priority: 92 },
  { value: '皮鞋', tokens: ['皮鞋', 'leather-shoes'], priority: 92 },
  { value: '乐福鞋', tokens: ['乐福鞋', 'loafers', 'loafer'], priority: 96 },
  { value: '牛津鞋', tokens: ['牛津鞋', 'oxfords', 'oxford-shoes'], priority: 96 },
  { value: '高跟鞋', tokens: ['高跟鞋', 'high-heels', 'pumps'], priority: 96 },
  { value: '平底鞋', tokens: ['平底鞋', 'flats', 'flat-shoes'], priority: 94 },
  { value: '玛丽珍鞋', tokens: ['玛丽珍鞋', 'mary-janes'], priority: 98 },
  { value: '凉鞋', tokens: ['凉鞋', 'sandals'], priority: 90 },
  { value: '拖鞋', tokens: ['拖鞋', 'slippers', 'flip-flops'], priority: 90 },
  { value: '穆勒鞋', tokens: ['穆勒鞋', 'mules'], priority: 96 },
  { value: '短靴', tokens: ['短靴', 'ankle-boots', 'booties'], priority: 94 },
  { value: '长靴', tokens: ['长靴', 'knee-high-boots', 'long-boots'], priority: 94 },
  { value: '马丁靴', tokens: ['马丁靴', 'martens', 'combat-boots'], priority: 97 },
  { value: '雨靴', tokens: ['雨靴', 'rain-boots', 'wellies'], priority: 95 },
  { value: '登山鞋', tokens: ['登山鞋', 'hiking-shoes'], priority: 96 },
  { value: '雪地靴', tokens: ['雪地靴', 'snow-boots'], priority: 96 },
  { value: '袜子', tokens: ['袜子', 'socks'], priority: 88 },
  { value: '长袜', tokens: ['长袜', 'knee-socks'], priority: 94 },
  { value: '袜套', tokens: ['袜套', 'leg-warmers'], priority: 94 },
  { value: '围巾', tokens: ['围巾', 'scarf'], priority: 92 },
  { value: '披肩', tokens: ['披肩', 'shawl', 'wrap'], priority: 94 },
  { value: '帽子', tokens: ['帽子', 'hat'], priority: 86 },
  { value: '棒球帽', tokens: ['棒球帽', 'baseball-cap', 'baseballhat'], priority: 96 },
  { value: '针织帽', tokens: ['针织帽', 'beanie', 'knit-cap'], priority: 96 },
  { value: '贝雷帽', tokens: ['贝雷帽', 'beret'], priority: 96 },
  { value: '渔夫帽', tokens: ['渔夫帽', 'bucket-hat'], priority: 96 },
  { value: '腰带', tokens: ['腰带', 'belt'], priority: 92 },
  { value: '领带', tokens: ['领带', 'tie'], priority: 92 },
  { value: '领结', tokens: ['领结', 'bow-tie', 'bowtie'], priority: 96 },
  { value: '手套', tokens: ['手套', 'gloves'], priority: 92 },
  { value: '背包', tokens: ['背包', 'backpack'], priority: 92 },
  { value: '双肩包', tokens: ['双肩包', 'rucksack'], priority: 96 },
  { value: '手提包', tokens: ['手提包', 'handbag', 'tote'], priority: 94 },
  { value: '单肩包', tokens: ['单肩包', 'shoulder-bag'], priority: 96 },
  { value: '腰包', tokens: ['腰包', 'waist-bag', 'fanny-pack'], priority: 96 },
  { value: '斜挎包', tokens: ['斜挎包', 'crossbody-bag'], priority: 96 },
  { value: '太阳镜', tokens: ['太阳镜', 'sunglasses'], priority: 96 },
  { value: '眼镜', tokens: ['眼镜', 'glasses', 'spectacles'], priority: 90 },
  { value: '手表', tokens: ['手表', 'watch'], priority: 90 },
  { value: '项链', tokens: ['项链', 'necklace'], priority: 92 },
  { value: '手链', tokens: ['手链', 'bracelet'], priority: 92 },
  { value: '耳环', tokens: ['耳环', 'earrings', 'earring'], priority: 94 },
  { value: '胸针', tokens: ['胸针', 'brooch'], priority: 94 },
  { value: '发带', tokens: ['发带', 'hairband', 'headband'], priority: 94 },
  { value: '发箍', tokens: ['发箍', 'hair-hoop'], priority: 96 }
];

// 对外暴露类别名数组，测试和未来 provider 可以用它校验输出是否属于演示契约。
export const GARMENT_CATEGORIES: string[] = GARMENT_CATEGORY_RULES.map((rule: TokenRule) => rule.value);

const COLOR_RULES: TokenRule[] = [
  { value: '藏青色', tokens: ['藏青', '海军蓝', 'navy'], priority: 98 },
  { value: '浅蓝色', tokens: ['浅蓝', '天蓝', 'sky-blue', 'light-blue'], priority: 96 },
  { value: '米色', tokens: ['米色', '杏色', 'beige', 'cream'], priority: 94 },
  { value: '棕色', tokens: ['棕色', '棕', '咖啡', 'brown', 'coffee'], priority: 92 },
  { value: '黑色', tokens: ['黑色', '黑', 'black'], priority: 90 },
  { value: '白色', tokens: ['白色', '白', 'white'], priority: 90 },
  { value: '灰色', tokens: ['灰色', '灰', 'gray', 'grey'], priority: 90 },
  { value: '红色', tokens: ['红色', '红', 'red'], priority: 90 },
  { value: '粉色', tokens: ['粉色', '粉', 'pink'], priority: 90 },
  { value: '橙色', tokens: ['橙色', '橙', 'orange'], priority: 90 },
  { value: '黄色', tokens: ['黄色', '黄', 'yellow'], priority: 90 },
  { value: '绿色', tokens: ['绿色', '绿', 'green'], priority: 90 },
  { value: '蓝色', tokens: ['蓝色', '蓝', 'blue'], priority: 90 },
  { value: '紫色', tokens: ['紫色', '紫', 'purple'], priority: 90 },
  { value: '银色', tokens: ['银色', '银', 'silver'], priority: 90 },
  { value: '金色', tokens: ['金色', '金', 'gold'], priority: 90 },
  { value: '多彩色', tokens: ['多彩', '彩色', '彩虹', 'multicolor', 'rainbow'], priority: 92 }
];

const MATERIAL_RULES: TokenRule[] = [
  { value: '全棉', tokens: ['全棉', '纯棉', '100cotton'], priority: 98 },
  { value: '棉', tokens: ['棉', 'cotton'], priority: 90 },
  { value: '亚麻', tokens: ['亚麻', 'linen', '麻'], priority: 92 },
  { value: '羊毛', tokens: ['羊毛', 'wool'], priority: 92 },
  { value: '羊绒', tokens: ['羊绒', 'cashmere'], priority: 96 },
  { value: '牛仔布', tokens: ['牛仔布', '牛仔', '丹宁', 'denim'], priority: 95 },
  { value: '皮革', tokens: ['皮革', '真皮', 'leather'], priority: 94 },
  { value: '人造革', tokens: ['人造革', 'pu皮', 'synthetic-leather'], priority: 96 },
  { value: '针织', tokens: ['针织', 'knit'], priority: 90 },
  { value: '涤纶', tokens: ['涤纶', '聚酯', 'polyester'], priority: 92 },
  { value: '尼龙', tokens: ['尼龙', 'nylon'], priority: 92 },
  { value: '氨纶', tokens: ['氨纶', '莱卡', 'spandex', 'lycra'], priority: 92 },
  { value: '莫代尔', tokens: ['莫代尔', 'modal'], priority: 94 },
  { value: '粘纤', tokens: ['粘纤', '人造棉', 'viscose', 'rayon'], priority: 94 },
  { value: '雪纺', tokens: ['雪纺', 'chiffon'], priority: 94 },
  { value: '丝绸', tokens: ['丝绸', '真丝', 'silk'], priority: 94 },
  { value: '蕾丝', tokens: ['蕾丝', 'lace'], priority: 94 },
  { value: '灯芯绒', tokens: ['灯芯绒', 'corduroy'], priority: 94 },
  { value: '天鹅绒', tokens: ['天鹅绒', 'velvet'], priority: 94 },
  { value: '羽绒', tokens: ['羽绒', 'down'], priority: 92 },
  { value: '抓绒', tokens: ['抓绒', 'fleece'], priority: 92 },
  { value: '防水面料', tokens: ['防水', 'waterproof', 'hardshell'], priority: 94 },
  { value: '混纺', tokens: ['混纺', 'blend'], priority: 90 },
  { value: '绒面革', tokens: ['绒面', '麂皮', 'suede'], priority: 96 },
  { value: '竹纤维', tokens: ['竹纤维', 'bamboo-fiber'], priority: 94 }
];

// 只读取一张小缩略图的 RGBA 像素，提供“真实图片主色”这一项可验证能力。
// 这不是服装分类模型：类别和材质仍然只能来自显式 provider 或文件名线索，不能由主色推断。
async function dominantColorFromImage(uri: string): Promise<ColorObservation | undefined> {
  let file: FileLike | undefined = undefined;
  let source: ImageSourceLike | undefined = undefined;
  let pixels: PixelMapLike | undefined = undefined;
  try {
    const coreKit: Record<string, object> = await import('@kit.CoreFileKit') as Record<string, object>;
    const imageKit: Record<string, object> = await import('@kit.ImageKit') as Record<string, object>;
    const fs: FileIoLike = coreKit['fileIo'] as FileIoLike;
    const image: ImageModuleLike = imageKit['image'] as ImageModuleLike;
    if (!fs || !image || !fs.OpenMode || !image.PixelMapFormat) { return undefined; }
    file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    source = image.createImageSource(file.fd);
    const info: ImageInfoLike = await source.getImageInfo();
    if (!info || !info.size || info.size.width <= 0 || info.size.height <= 0) { return undefined; }
    const longest: number = Math.max(info.size.width, info.size.height);
    const ratio: number = Math.min(1, 48 / longest);
    const options: PixelMapDecodingOptionsLike = {
      desiredSize: { width: Math.max(1, Math.round(info.size.width * ratio)),
        height: Math.max(1, Math.round(info.size.height * ratio)) },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    };
    pixels = await source.createPixelMap(options);
    const byteCount: number = pixels.getPixelBytesNumber();
    if (!Number.isFinite(byteCount) || byteCount < 4 || byteCount > 4 * 1024 * 1024) { return undefined; }
    const buffer: ArrayBuffer = new ArrayBuffer(byteCount);
    await pixels.readPixelsToBuffer(buffer);
    const bytes: Uint8Array = new Uint8Array(buffer);
    return analyzeRgbaPixels(bytes);
  } catch (error) {
    // 设备没有文件或图像能力时明确降级，调用方仍能看到 unavailable/文件名线索状态。
    return undefined;
  } finally {
    if (pixels) { await pixels.release().catch(() => {}); }
    if (source) { await source.release().catch(() => {}); }
    if (file) {
      try {
        const coreKit: Record<string, object> = await import('@kit.CoreFileKit') as Record<string, object>;
        const fs: FileIoLike = coreKit['fileIo'] as FileIoLike;
        if (fs) { await fs.close(file).catch(() => {}); }
      } catch (error) { /* 动态清理失败不应覆盖原识别结果 */ }
    }
  }
}

function normalizeText(value: string): string {
  let decoded: string = value;
  try { decoded = decodeURIComponent(value); } catch (error) { decoded = value; }
  return decoded.toLowerCase().replace(/[\\/_.:?=&%#-]+/g, ' ').replace(/\s+/g, ' ').trim();
}

function normalizeToken(value: string): string {
  return value.toLowerCase().replace(/[\\/_.:?=&%#-]+/g, ' ').replace(/\s+/g, ' ').trim();
}

function containsToken(text: string, token: string): boolean {
  // 拉丁词必须完整匹配，避免把 “red” 命中 “redesign”、把 “black” 命中 “blacklisted”。
  if (/^[a-z0-9 ]+$/.test(token)) { return (' ' + text + ' ').indexOf(' ' + token + ' ') >= 0; }
  // 中文服饰词通常没有空格分词，保留子串匹配，但仍只作为文件名提示。
  return text.indexOf(token) >= 0;
}

function findToken(text: string, rules: TokenRule[]): TokenMatch {
  let best: TokenMatch = { value: '', score: 0 };
  for (const rule of rules) {
    for (const token of rule.tokens) {
      const normalizedToken: string = normalizeToken(token);
      if (normalizedToken.length === 0 || !containsToken(text, normalizedToken)) { continue; }
      // 长 token 优先，避免“蓝”覆盖“藏青”；priority 再用于同长度的语义细分。
      const score: number = rule.priority * 100 + normalizedToken.length;
      if (score > best.score) { best = { value: rule.value, score: score }; }
    }
  }
  return best;
}

function bounded(value: number, minimum: number, maximum: number): number {
  return Math.max(minimum, Math.min(maximum, value));
}

// 文件名 token 是可解释的演示线索，但不是视觉分类置信度，也不会自动写入草稿。
const FILE_TOKEN_HINT_CONFIDENCE: number = 0.55;

function sourceForToken(value: string): string {
  return value.length > 0 ? RECOGNITION_SOURCE_LOCAL : RECOGNITION_SOURCE_UNAVAILABLE;
}

function combinedSource(categorySource: string, colorSource: string, materialSource: string): string {
  const sources: string[] = [];
  for (const source of [categorySource, colorSource, materialSource]) {
    if (source !== RECOGNITION_SOURCE_UNAVAILABLE && sources.indexOf(source) < 0) { sources.push(source); }
  }
  if (sources.length === 0) { return RECOGNITION_SOURCE_UNAVAILABLE; }
  return sources.length === 1 ? sources[0] : RECOGNITION_SOURCE_MIXED;
}

export function recognizeGarmentSync(uri: string, fileName: string = ''): GarmentRecognition {
  const text: string = normalizeText(uri + ' ' + fileName);
  const category: TokenMatch = findToken(text, GARMENT_CATEGORY_RULES);
  const color: TokenMatch = findToken(text, COLOR_RULES);
  const material: TokenMatch = findToken(text, MATERIAL_RULES);
  const hasToken: boolean = category.value.length > 0 || color.value.length > 0 || material.value.length > 0;
  // 批量导入生成的沙箱 URI 通常只有随机任务 ID。没有可读 token 时返回 unavailable，
  // 不把随机文件名当成图像证据，也不让页面误以为已经运行了视觉模型。
  const categorySource: string = sourceForToken(category.value);
  const colorSource: string = sourceForToken(color.value);
  const materialSource: string = sourceForToken(material.value);
  const confidence: number = hasToken ? FILE_TOKEN_HINT_CONFIDENCE : 0;
  return {
    category: category.value,
    color: color.value,
    material: material.value,
    confidence: confidence,
    source: combinedSource(categorySource, colorSource, materialSource),
    userConfirmed: false,
    categoryConfidence: category.value.length > 0 ? FILE_TOKEN_HINT_CONFIDENCE : 0,
    colorConfidence: color.value.length > 0 ? FILE_TOKEN_HINT_CONFIDENCE : 0,
    materialConfidence: material.value.length > 0 ? FILE_TOKEN_HINT_CONFIDENCE : 0,
    categorySource: categorySource,
    colorSource: colorSource,
    materialSource: materialSource
  };
}

// 只按文件名/Uri token 运行的 provider，供桌面演示或未来云端结果的回归测试使用。
// 它的结果必须在界面上标成“文件名线索”，不能当作视觉模型分类。
export class FilenameTokenRecognitionProvider implements GarmentRecognitionProvider {
  async recognize(input: GarmentRecognitionInput): Promise<GarmentRecognition> {
    return recognizeGarmentSync(input.uri, input.fileName || '');
  }
}

// 默认 provider 额外尝试读取真实像素主色；没有 ImageKit 或 URI 无法读取时返回 unavailable。
export class LocalGarmentRecognitionProvider implements GarmentRecognitionProvider {
  async recognize(input: GarmentRecognitionInput): Promise<GarmentRecognition> {
    return recognizeGarmentFromImage(input.uri, input.fileName || '', false);
  }
}

async function recognizeGarmentFromImage(uri: string, fileName: string = '', includeFileTokenAttributes: boolean = false):
  Promise<GarmentRecognition> {
  const tokenResult: GarmentRecognition = recognizeGarmentSync(uri, fileName);
  const observed: ColorObservation | undefined = await dominantColorFromImage(uri);
  const category: string = includeFileTokenAttributes ? tokenResult.category : '';
  const material: string = includeFileTokenAttributes ? tokenResult.material : '';
  if (!observed) {
    const categorySource: string = category.length > 0 ? tokenResult.categorySource || RECOGNITION_SOURCE_LOCAL
      : RECOGNITION_SOURCE_UNAVAILABLE;
    const materialSource: string = material.length > 0 ? tokenResult.materialSource || RECOGNITION_SOURCE_LOCAL
      : RECOGNITION_SOURCE_UNAVAILABLE;
    return {
      category: category,
      color: '',
      material: material,
      confidence: Math.max(category.length > 0 ? tokenResult.categoryConfidence || 0 : 0,
        material.length > 0 ? tokenResult.materialConfidence || 0 : 0),
      source: combinedSource(categorySource, RECOGNITION_SOURCE_UNAVAILABLE, materialSource),
      userConfirmed: false,
      categoryConfidence: category.length > 0 ? tokenResult.categoryConfidence : 0,
      colorConfidence: 0,
      materialConfidence: material.length > 0 ? tokenResult.materialConfidence : 0,
      categorySource: categorySource,
      colorSource: RECOGNITION_SOURCE_UNAVAILABLE,
      materialSource: materialSource
    };
  }
  // 主色来自实际像素；类别与材质若存在，只说明显式开启了文件名演示规则，不能被描述为视觉分类。
  const categorySource: string = category.length > 0 ? tokenResult.categorySource || RECOGNITION_SOURCE_LOCAL
    : RECOGNITION_SOURCE_UNAVAILABLE;
  const materialSource: string = material.length > 0 ? tokenResult.materialSource || RECOGNITION_SOURCE_LOCAL
    : RECOGNITION_SOURCE_UNAVAILABLE;
  const source: string = combinedSource(categorySource, RECOGNITION_SOURCE_PIXEL_COLOR, materialSource);
  const confidence: number = observed.confidence;
  return {
    category: category,
    color: observed.color,
    material: material,
    confidence: Number(confidence.toFixed(2)),
    source: source,
    userConfirmed: false,
    categoryConfidence: category.length > 0 ? tokenResult.categoryConfidence : 0,
    colorConfidence: observed.confidence,
    materialConfidence: material.length > 0 ? tokenResult.materialConfidence : 0,
    categorySource: categorySource,
    colorSource: RECOGNITION_SOURCE_PIXEL_COLOR,
    materialSource: materialSource
  };
}

// 文件名规则的显式入口仅用于演示与桌面测试。调用方可以展示“文件名线索”，但不能把它当作图像模型。
export async function recognizeGarmentFromFileName(uri: string, fileName: string = ''): Promise<GarmentRecognition> {
  return recognizeGarmentSync(uri, fileName);
}

// 可替换 provider 的服务门面。默认 provider 永远离线，替换时只需注入同样的接口。
export class GarmentRecognitionService {
  private provider: GarmentRecognitionProvider;

  constructor(provider?: GarmentRecognitionProvider) {
    this.provider = provider || new LocalGarmentRecognitionProvider();
  }

  setProvider(provider: GarmentRecognitionProvider): void { this.provider = provider; }

  async recognize(input: GarmentRecognitionInput): Promise<GarmentRecognition> {
    return this.provider.recognize(input);
  }
}

const defaultGarmentRecognitionService: GarmentRecognitionService = new GarmentRecognitionService();

// 父页面接线使用的稳定入口。fileName 仅供显式文件名 provider 使用，默认像素 provider 不读取类别/材质提示。
export async function recognizeGarment(uri: string, fileName: string = ''): Promise<GarmentRecognition> {
  return defaultGarmentRecognitionService.recognize({ uri: uri, fileName: fileName });
}

export function recognitionSummary(result: GarmentRecognition): string {
  const values: string[] = [];
  const append: (label: string, value: string, source: string | undefined, confidence: number | undefined) => void =
    (label: string, value: string, source: string | undefined, confidence: number | undefined): void => {
      if (value.length === 0) { return; }
      let origin: string = '外部识别服务';
      if (source === RECOGNITION_SOURCE_PIXEL_COLOR) { origin = '图片像素统计'; }
      else if (source === RECOGNITION_SOURCE_LOCAL) { origin = '文件名线索'; }
      else if (source === RECOGNITION_SOURCE_USER) { origin = '用户确认'; }
      else if (source === RECOGNITION_SOURCE_EXISTING) { origin = '当前草稿'; }
      const score: number = Math.round(bounded(confidence === undefined ? result.confidence : confidence, 0, 1) * 100);
      values.push(label + ' ' + value + '（' + origin + '，提示分 ' + score + '%）');
    };
  append('类别', result.category, result.categorySource, result.categoryConfidence);
  append('颜色', result.color, result.colorSource, result.colorConfidence);
  append('材质', result.material, result.materialSource, result.materialConfidence);
  if (values.length === 0) { return '这张图片暂无可用建议，请手动填写。'; }
  return values.join(' · ') + '。请核对后再采用。';
}

function confirmed(confirmation: boolean | RecognitionConfirmation | undefined,
  field: string): boolean {
  if (confirmation === true) { return true; }
  if (confirmation === false || confirmation === undefined) { return false; }
  if (field === 'category') { return confirmation.category === true; }
  if (field === 'color') { return confirmation.color === true; }
  if (field === 'material') { return confirmation.material === true; }
  return false;
}

// 将推理结果写回草稿时统一走这里，防止低置信度结果覆盖用户已经确认的输入。
// 低置信度结果整体只作为提示展示，不会自动替换任何已有字段；高置信度时只更新未确认字段。
export function applyRecognition(draft: RecognitionDraft, result: GarmentRecognition,
  confirmation?: boolean | RecognitionConfirmation): GarmentRecognition {
  const keepAll: boolean = draft.userConfirmed === true || confirmation === true;
  const categorySourceFromResult: string = result.categorySource || result.source;
  const colorSourceFromResult: string = result.colorSource || result.source;
  const materialSourceFromResult: string = result.materialSource || result.source;
  const categoryScore: number = result.categoryConfidence === undefined ? result.confidence : result.categoryConfidence;
  const colorScore: number = result.colorConfidence === undefined ? result.confidence : result.colorConfidence;
  const materialScore: number = result.materialConfidence === undefined ? result.confidence : result.materialConfidence;
  const canUseCategory: boolean = result.category.length > 0 &&
    categorySourceFromResult !== RECOGNITION_SOURCE_LOCAL && categoryScore >= MIN_AUTO_RECOGNITION_CONFIDENCE;
  const canUseColor: boolean = result.color.length > 0 &&
    colorSourceFromResult !== RECOGNITION_SOURCE_LOCAL && colorScore >= MIN_AUTO_RECOGNITION_CONFIDENCE;
  const canUseMaterial: boolean = result.material.length > 0 &&
    materialSourceFromResult !== RECOGNITION_SOURCE_LOCAL && materialScore >= MIN_AUTO_RECOGNITION_CONFIDENCE;
  const keepCategory: boolean = keepAll || confirmed(confirmation, 'category') || !canUseCategory;
  const keepColor: boolean = keepAll || confirmed(confirmation, 'color') || !canUseColor;
  const keepMaterial: boolean = keepAll || confirmed(confirmation, 'material') || !canUseMaterial;
  const category: string = keepCategory ? (draft.category || '') : result.category;
  const color: string = keepColor ? (draft.color || '') : result.color;
  const material: string = keepMaterial ? (draft.material || '') : result.material;
  const anyConfirmed: boolean = keepAll || confirmed(confirmation, 'category') ||
    confirmed(confirmation, 'color') || confirmed(confirmation, 'material');
  const categorySource: string = category.length === 0 ? RECOGNITION_SOURCE_UNAVAILABLE
    : (keepCategory ? (keepAll || confirmed(confirmation, 'category')
      ? RECOGNITION_SOURCE_USER : RECOGNITION_SOURCE_EXISTING) : categorySourceFromResult);
  const colorSource: string = color.length === 0 ? RECOGNITION_SOURCE_UNAVAILABLE
    : (keepColor ? (keepAll || confirmed(confirmation, 'color')
      ? RECOGNITION_SOURCE_USER : RECOGNITION_SOURCE_EXISTING) : colorSourceFromResult);
  const materialSource: string = material.length === 0 ? RECOGNITION_SOURCE_UNAVAILABLE
    : (keepMaterial ? (keepAll || confirmed(confirmation, 'material')
      ? RECOGNITION_SOURCE_USER : RECOGNITION_SOURCE_EXISTING) : materialSourceFromResult);
  return {
    category: category,
    color: color,
    material: material,
    confidence: result.confidence,
    source: combinedSource(categorySource, colorSource, materialSource),
    userConfirmed: anyConfirmed,
    categoryConfidence: category.length > 0 && !keepCategory ? categoryScore : 0,
    colorConfidence: color.length > 0 && !keepColor ? colorScore : 0,
    materialConfidence: material.length > 0 && !keepMaterial ? materialScore : 0,
    categorySource: categorySource,
    colorSource: colorSource,
    materialSource: materialSource
  };
}

// 语义别名，方便导入流程或未来页面按“合并识别结果”表达意图。
export const applyRecognitionToDraft = applyRecognition;
export const mergeRecognitionResult = applyRecognition;
