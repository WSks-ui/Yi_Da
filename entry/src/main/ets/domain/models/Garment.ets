export const CATEGORIES: string[] = ['top', 'outerwear', 'bottom', 'dress', 'shoes', 'accessory'];
export const CATEGORY_LABELS: string[] = ['上装', '外套', '下装', '连衣裙', '鞋履', '配饰'];
export const STATUSES: string[] = ['wearable', 'laundry', 'stored', 'season_hidden', 'archived'];
export const STATUS_LABELS: string[] = ['可穿', '待洗', '收纳中', '换季隐藏', '已归档'];
export const COLORS: string[] = ['unknown', 'black', 'white', 'gray', 'red', 'yellow', 'green', 'blue', 'purple', 'brown', 'multi'];
export const COLOR_LABELS: string[] = ['未知', '黑', '白', '灰', '红', '黄', '绿', '蓝', '紫', '棕', '多色'];
export const COLOR_SWATCHES: string[] =
  ['#D7DADC', '#25282A', '#FFFFFF', '#8A9197', '#B9444F', '#D2B341', '#39725E', '#3F75AA', '#8A69A7', '#8C6652', '#ABB8BA'];

export class GarmentDraft {
  id: string = '';
  space: string = 'personal';
  name: string = '';
  category: string = 'top';
  colorGroup: string = 'unknown';
  seasonMask: number = 0;
  status: string = 'wearable';
  version: number = 0;
}

export class Garment extends GarmentDraft {
  imageAssetId: string = '';
  thumbnailAssetId: string = '';
  imagePath: string = '';
  thumbnailPath: string = '';
  createdAt: number = 0;
  updatedAt: number = 0;
}

export class MediaAsset {
  id: string = '';
  kind: string = 'garment';
  relativePath: string = '';
  sha256: string = '';
  mimeType: string = 'image/jpeg';
  width: number = 0;
  height: number = 0;
  byteSize: number = 0;
  createdAt: number = 0;
}

export class PreparedPhoto {
  original: MediaAsset = new MediaAsset();
  thumbnail: MediaAsset = new MediaAsset();
}

export class WardrobeFilter {
  space: string = 'personal';
  search: string = '';
  category: string = '';
  status: string = '';
  seasonMask: number = 0;
}

export class VersionedId {
  id: string;
  version: number;

  constructor(id: string, version: number) {
    this.id = id;
    this.version = version;
  }
}

export class BatchChange {
  status: string = '';
  category: string = '';
  // -1 表示不修改，0 是用户明确选择“季节未知”，二者不能混用。
  seasonMask: number = -1;
}

export function categoryLabel(value: string): string {
  return CATEGORY_LABELS[CATEGORIES.indexOf(value)] ?? '未知类别';
}

export function statusLabel(value: string): string {
  return STATUS_LABELS[STATUSES.indexOf(value)] ?? '未知状态';
}

export function seasonLabel(mask: number): string {
  if (mask === 0) { return '季节待确认'; }
  const labels: string[] = [];
  const names: string[] = ['春', '夏', '秋', '冬'];
  for (let i = 0; i < 4; i++) {
    if ((mask & (1 << i)) !== 0) { labels.push(names[i]); }
  }
  return labels.join(' / ');
}
