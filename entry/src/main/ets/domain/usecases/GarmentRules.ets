import { AppError } from '../../common/errors/AppError';
import { BatchChange, CATEGORIES, COLORS, GarmentDraft, STATUSES, VersionedId } from '../models/Garment';

export function validateDraft(draft: GarmentDraft): void {
  if (draft.space !== 'personal' && draft.space !== 'demo') {
    throw new AppError('INVALID_SPACE', '衣橱空间无效，请返回衣橱重试。');
  }
  if (draft.name.trim().length < 1 || draft.name.trim().length > 80) {
    throw new AppError('INVALID_NAME', '请填写 1 至 80 个字符的衣物名称。');
  }
  if (!CATEGORIES.includes(draft.category) || !STATUSES.includes(draft.status) ||
    !COLORS.includes(draft.colorGroup)) {
    throw new AppError('INVALID_ATTRIBUTE', '请重新确认类别、颜色和状态。');
  }
  if (!Number.isInteger(draft.seasonMask) || draft.seasonMask < 0 || draft.seasonMask > 15) {
    throw new AppError('INVALID_SEASON', '请重新选择适用季节。');
  }
}

export function validateBatch(ids: VersionedId[], change?: BatchChange): void {
  // 单次批量上限是交互与锁占用策略，不是平台限制；修改时同步压力测试。
  if (ids.length < 1 || ids.length > 200 || new Set(ids.map((item: VersionedId) => item.id)).size !== ids.length ||
    ids.some((item: VersionedId) => !item.id || !Number.isInteger(item.version) || item.version < 1)) {
    throw new AppError('INVALID_BATCH', '请选择 1 至 200 件不同的衣物。');
  }
  if (change) {
    if ((change.status && !STATUSES.includes(change.status)) ||
      (change.category && !CATEGORIES.includes(change.category)) ||
      !Number.isInteger(change.seasonMask) || change.seasonMask < -1 || change.seasonMask > 15) {
      throw new AppError('INVALID_BATCH', '批量修改内容无效。');
    }
    if (!change.status && !change.category && change.seasonMask === -1) {
      throw new AppError('EMPTY_BATCH', '请至少选择一个要修改的属性。');
    }
  }
}

export function mediaRelativePath(path: string): string {
  // 只接收本应用随机生成的扁平文件名，禁止 URI、盘符、百分号和路径穿越。
  if (!/^media\/[0-9a-f-]{36}(-thumb)?\.jpg$/.test(path)) {
    throw new AppError('UNSAFE_PATH', '图片引用无效，可以重新选择照片。');
  }
  return path;
}

export function scaledSize(width: number, height: number, limit: number): number[] {
  if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1 ||
    width > 8192 || height > 8192 || width * height > 24000000) {
    throw new AppError('IMAGE_DIMENSIONS', '图片应不超过 2400 万像素，单边不超过 8192 像素。');
  }
  const scale = Math.min(1, limit / Math.max(width, height));
  return [Math.max(1, Math.round(width * scale)), Math.max(1, Math.round(height * scale))];
}
