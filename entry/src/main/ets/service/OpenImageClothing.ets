import { Category } from '../model/Wardrobe';

// MindSpore 官方 MobileNetV2 ImageNet 输出的标签索引。
// 这是通用分类模型，仅映射与现有衣橱五大类直接对应的少数标签；
// 连衣裙等当前数据模型无法准确表示的品类故意不映射。
export interface ClothingCandidate {
  category: Category;
  subcategory: string;
  label: string;
  score: number;
}

interface ClothingLabel {
  index: number;
  category: Category;
  subcategory: string;
  label: string;
}

const LABELS: ClothingLabel[] = [
  { index: 400, category: Category.OUTER, subcategory: '学位服', label: 'academic gown' },
  { index: 515, category: Category.ACCESSORY, subcategory: '帽子', label: 'cowboy hat' },
  { index: 568, category: Category.OUTER, subcategory: '皮草外套', label: 'fur coat' },
  { index: 608, category: Category.BOTTOM, subcategory: '牛仔裤', label: 'jeans' },
  { index: 610, category: Category.TOP, subcategory: 'T恤', label: 'T-shirt' },
  { index: 614, category: Category.OUTER, subcategory: '和服式外套', label: 'kimono' },
  { index: 617, category: Category.OUTER, subcategory: '工作外套', label: 'lab coat' },
  { index: 630, category: Category.SHOES, subcategory: '便鞋', label: 'slip-on shoe' },
  { index: 655, category: Category.BOTTOM, subcategory: '短裙', label: 'miniskirt' },
  { index: 770, category: Category.SHOES, subcategory: '运动鞋', label: 'running shoe' },
  { index: 774, category: Category.SHOES, subcategory: '凉鞋', label: 'sandal' },
  { index: 806, category: Category.SHOES, subcategory: '袜子', label: 'sock' },
  { index: 824, category: Category.ACCESSORY, subcategory: '围巾', label: 'scarf' },
  { index: 834, category: Category.OUTER, subcategory: '西装', label: 'suit' },
  { index: 837, category: Category.ACCESSORY, subcategory: '太阳镜', label: 'sunglasses' },
  { index: 841, category: Category.TOP, subcategory: '卫衣', label: 'sweatshirt' },
  { index: 842, category: Category.TOP, subcategory: '泳装', label: 'swimsuit' },
  { index: 869, category: Category.OUTER, subcategory: '风衣', label: 'trench coat' },
  { index: 911, category: Category.TOP, subcategory: '羊毛衣物', label: 'wool' }
];

// 官方 quick_start MobileNetV2 在 API 26 模拟器上返回 1001 个值：
// 第 0 项是 background，后续 1000 项对应 ImageNet 类别。部分运行时会
// 去掉 background，因此同时兼容 1000 和 1001 两种输出形状。
export const IMAGE_NET_CLASS_COUNT: number = 1000;
export const IMAGE_NET_OUTPUT_SIZE: number = IMAGE_NET_CLASS_COUNT + 1;
// 保留旧导出名，避免已有调用方在升级时无意义地断裂。
export const OPEN_IMAGE_OUTPUT_SIZE: number = IMAGE_NET_CLASS_COUNT;

export function chooseClothingCandidate(scores: Float32Array): ClothingCandidate | undefined {
  if (scores.length !== IMAGE_NET_CLASS_COUNT && scores.length !== IMAGE_NET_OUTPUT_SIZE) {
    return undefined;
  }
  const labelOffset: number = scores.length === IMAGE_NET_OUTPUT_SIZE ? 1 : 0;
  let bestGlobal: number = 0;
  for (const score of scores) {
    if (Number.isFinite(score) && score > bestGlobal) { bestGlobal = score; }
  }
  let winner: ClothingLabel | undefined = undefined;
  let winnerScore: number = 0;
  for (const label of LABELS) {
    const value: number = scores[label.index + labelOffset];
    if (Number.isFinite(value) && value > winnerScore) {
      winner = label;
      winnerScore = value;
    }
  }
  // ImageNet 是通用场景标签；对非衣物照片和弱命中保持空结果。
  // 此阈值只是演示保守门槛，不等于服装识别准确率。
  if (winner === undefined || winnerScore < 0.35 || winnerScore < bestGlobal * 0.7) { return undefined; }
  return { category: winner.category, subcategory: winner.subcategory,
    label: winner.label, score: Number(winnerScore.toFixed(3)) };
}

export function normalizeOpenImagePixels(rgba: Uint8Array): Float32Array {
  const side: number = 224;
  if (rgba.length !== side * side * 4) { throw new Error('模型图片尺寸不正确'); }
  const mean: number[] = [0.485, 0.456, 0.406];
  const deviation: number[] = [0.229, 0.224, 0.225];
  const input: Float32Array = new Float32Array(side * side * 3);
  for (let pixel: number = 0; pixel < side * side; pixel++) {
    for (let channel: number = 0; channel < 3; channel++) {
      input[pixel * 3 + channel] = (rgba[pixel * 4 + channel] / 255 - mean[channel]) / deviation[channel];
    }
  }
  return input;
}
