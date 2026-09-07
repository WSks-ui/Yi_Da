import { AppError } from '../../common/errors/AppError';

// 工程限额，不是 Picker 平台上限。串行解码避免 20 张大图同时占用 PixelMap。
export const MAX_IMPORT_PHOTOS: number = 20;

export function validatePickLimit(limit: number): void {
  if (!Number.isInteger(limit) || limit < 1 || limit > MAX_IMPORT_PHOTOS) {
    throw new AppError('IMPORT_LIMIT', '每次最多选择 20 张照片。');
  }
}

export function toggleSeason(mask: number, index: number, selected: boolean): number {
  if (!Number.isInteger(mask) || mask < 0 || mask > 15 ||
    !Number.isInteger(index) || index < 0 || index > 3) {
    throw new AppError('INVALID_SEASON', '请重新选择适用季节。');
  }
  return selected ? mask | (1 << index) : mask & ~(1 << index);
}
