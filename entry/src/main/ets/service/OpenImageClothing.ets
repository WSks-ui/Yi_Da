import { Category } from '../model/Wardrobe';

// MindSpore 官方 Open Images MobileNetV2 输出的标签索引。
// 这是通用多标签模型，仅映射与现有衣橱五大类直接对应的少数标签；
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
  { index: 40, category: Category.BOTTOM, subcategory: '打底裤', label: 'Tights' },
  { index: 53, category: Category.ACCESSORY, subcategory: '手提包', label: 'Handbag' },
  { index: 91, category: Category.BOTTOM, subcategory: '牛仔裤', label: 'Jeans' },
  { index: 131, category: Category.OUTER, subcategory: '夹克', label: 'Jacket' },
  { index: 210, category: Category.OUTER, subcategory: '西装外套', label: 'Blazer' },
  { index: 241, category: Category.OUTER, subcategory: '外套', label: 'Outerwear' },
  { index: 315, category: Category.SHOES, subcategory: '鞋', label: 'Shoe' },
  { index: 317, category: Category.SHOES, subcategory: '运动鞋', label: 'Sneakers' },
  { index: 333, category: Category.ACCESSORY, subcategory: '帽子', label: 'Hat' },
  { index: 359, category: Category.BOTTOM, subcategory: '短裤', label: 'Shorts' },
  { index: 362, category: Category.BOTTOM, subcategory: '打底裤', label: 'Leggings' },
  { index: 384, category: Category.ACCESSORY, subcategory: '围巾', label: 'Scarf' },
  { index: 387, category: Category.ACCESSORY, subcategory: '包', label: 'Bag' },
  { index: 397, category: Category.TOP, subcategory: '运动上衣', label: 'Jersey' }
];

export const OPEN_IMAGE_OUTPUT_SIZE: number = 410;

export function chooseClothingCandidate(scores: Float32Array): ClothingCandidate | undefined {
  if (scores.length !== OPEN_IMAGE_OUTPUT_SIZE) { return undefined; }
  let bestGlobal: number = 0;
  for (const score of scores) {
    if (Number.isFinite(score) && score > bestGlobal) { bestGlobal = score; }
  }
  let winner: ClothingLabel | undefined = undefined;
  let winnerScore: number = 0;
  for (const label of LABELS) {
    const value: number = scores[label.index];
    if (Number.isFinite(value) && value > winnerScore) {
      winner = label;
      winnerScore = value;
    }
  }
  // Open Images 是通用场景标签；对非衣物照片和弱命中保持空结果。
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
