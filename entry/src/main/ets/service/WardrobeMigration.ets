// 离线衣橱迁移包。
//
// 迁移包与网络同步不同：它把快照和应用私有图片字节打包成可分享文本，
// 由用户通过系统分享/文件选择器传到另一台设备。这里不直接访问文件系统，
// 所有读写都由调用方注入，导入也只在提交成功后发布候选快照。

import { DemoSnapshot } from '../model/Wardrobe';
import { SyncEnvelope, SyncValidationResult, createSyncEnvelope, validateSyncEnvelope } from './WardrobeSync';

export const MIGRATION_PACKAGE_FORMAT: string = 'yida-wardrobe-migration';
export const MIGRATION_PACKAGE_VERSION: number = 1;
export const MIGRATION_ASSET_PREFIX: string = 'migration-asset://';

// 默认上限防止分享文本、内存解码和导入写入一次占用过多资源；调用方可按设备能力收紧。
export const DEFAULT_MAX_PACKAGE_BYTES: number = 30 * 1024 * 1024;
export const DEFAULT_MAX_IMAGE_BYTES: number = 8 * 1024 * 1024;
export const DEFAULT_MAX_TOTAL_IMAGE_BYTES: number = 20 * 1024 * 1024;
export const DEFAULT_MAX_ASSET_COUNT: number = 100;

export interface MigrationLimits {
  maxPackageBytes?: number;
  maxImageBytes?: number;
  maxTotalImageBytes?: number;
  maxAssetCount?: number;
}

export interface NormalizedMigrationLimits {
  maxPackageBytes: number;
  maxImageBytes: number;
  maxTotalImageBytes: number;
  maxAssetCount: number;
}

// 源设备只需要读取并验证 URI；目标设备另外提供目标 URI、写入和清理能力。
export interface MigrationSourceFileAdapter {
  isPrivateUri(uri: string): boolean;
  read(uri: string): Promise<Uint8Array> | Uint8Array;
}

export interface MigrationTargetFileAdapter {
  isPrivateUri(uri: string): boolean;
  destinationUri(assetId: string, packageId: string): string;
  write(uri: string, bytes: Uint8Array): Promise<void> | void;
  remove(uri: string): Promise<void> | void;
}

export interface MigrationFileAdapter extends MigrationSourceFileAdapter, MigrationTargetFileAdapter {}

export interface MigrationAsset {
  assetId: string;
  byteLength: number;
  contentHash: string;
  bytesBase64: string;
}

// 包内 envelope 的 snapshot 使用占位 URI，避免把源设备的私有路径泄露给另一台设备。
export interface WardrobeMigrationPackage<T extends Object = DemoSnapshot> {
  format: string;
  packageVersion: number;
  exportedAt: string;
  envelope: SyncEnvelope<T>;
  assets: MigrationAsset[];
  totalImageBytes: number;
  continuationPayload: string;
}

export interface MigrationConflict {
  reason: string;
  localRevision: number;
  incomingRevision: number;
  localUpdatedAt: string;
  incomingUpdatedAt: string;
  localDeviceId: string;
  incomingDeviceId: string;
  decisionRequired: boolean;
}

export type MigrationPreparationStatus = 'ready' | 'duplicate' | 'stale' | 'conflict' | 'rejected';

export interface MigrationWriteAsset {
  assetId: string;
  targetUri: string;
  bytes: Uint8Array;
  contentHash: string;
}

export interface WardrobeMigrationCandidate<T extends Object = DemoSnapshot> {
  snapshot: T;
  envelope: SyncEnvelope<T>;
  assets: MigrationWriteAsset[];
  continuationPayload: string;
  conflict?: MigrationConflict;
}

export interface MigrationPreparationResult<T extends Object = DemoSnapshot> {
  status: MigrationPreparationStatus;
  message: string;
  candidate?: WardrobeMigrationCandidate<T>;
  conflict?: MigrationConflict;
}

// 这是候选快照的提交边界：validate/commit 成功前不发布，commit 成功后才允许 publish。
export interface CandidateSnapshotCommitter<T extends Object = DemoSnapshot> {
  validate?: (snapshot: T, envelope: SyncEnvelope<T>) => Promise<void> | void;
  commit: (snapshot: T, envelope: SyncEnvelope<T>) => Promise<void> | void;
  publish: (snapshot: T, envelope: SyncEnvelope<T>) => void;
}

export interface MigrationCommitResult {
  committed: boolean;
  published: boolean;
  writtenUris: string[];
  message: string;
}

function isObject(value: Object | null | undefined): boolean {
  return value !== null && value !== undefined && typeof value === 'object' && !Array.isArray(value);
}

function clone<T extends Object>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

// ArkTS 不允许把无索引签名的泛型直接断言为 Record；通过 JSON 边界取得显式记录，
// 同时保留快照服务只处理可序列化迁移数据的约束。
function cloneRecord(value: Object): Record<string, Object> {
  return JSON.parse(JSON.stringify(value)) as Record<string, Object>;
}

function validTimestamp(value: string): boolean {
  return typeof value === 'string' && value.length > 0 && Number.isFinite(new Date(value).getTime());
}

function normalizeLimits(limits?: MigrationLimits): NormalizedMigrationLimits {
  const result: NormalizedMigrationLimits = {
    maxPackageBytes: limits?.maxPackageBytes === undefined ? DEFAULT_MAX_PACKAGE_BYTES : limits.maxPackageBytes,
    maxImageBytes: limits?.maxImageBytes === undefined ? DEFAULT_MAX_IMAGE_BYTES : limits.maxImageBytes,
    maxTotalImageBytes: limits?.maxTotalImageBytes === undefined ? DEFAULT_MAX_TOTAL_IMAGE_BYTES : limits.maxTotalImageBytes,
    maxAssetCount: limits?.maxAssetCount === undefined ? DEFAULT_MAX_ASSET_COUNT : limits.maxAssetCount
  };
  if (!Number.isInteger(result.maxPackageBytes) || result.maxPackageBytes <= 0 ||
    !Number.isInteger(result.maxImageBytes) || result.maxImageBytes <= 0 ||
    !Number.isInteger(result.maxTotalImageBytes) || result.maxTotalImageBytes <= 0 ||
    !Number.isInteger(result.maxAssetCount) || result.maxAssetCount <= 0) {
    throw new Error('迁移容量上限必须是正整数');
  }
  if (result.maxImageBytes > result.maxTotalImageBytes) {
    throw new Error('单张图片上限不能超过图片总容量上限');
  }
  return result;
}

function utf8Length(value: string): number {
  let length: number = 0;
  for (let index: number = 0; index < value.length; index++) {
    const code: number = value.charCodeAt(index);
    if (code <= 0x7f) {
      length += 1;
    } else if (code <= 0x7ff) {
      length += 2;
    } else if (code >= 0xd800 && code <= 0xdbff && index + 1 < value.length) {
      const next: number = value.charCodeAt(index + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        length += 4;
        index++;
      } else {
        length += 3;
      }
    } else {
      length += 3;
    }
  }
  return length;
}

function isValidAssetId(value: string): boolean {
  return typeof value === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(value);
}

function assertSafeUri(uri: string, adapter: MigrationTargetFileAdapter, label: string): void {
  if (typeof uri !== 'string' || uri.length === 0 || uri.indexOf('\u0000') >= 0 || uri.indexOf('..') >= 0 ||
    !adapter.isPrivateUri(uri)) {
    throw new Error(label + '不属于允许的应用私有路径');
  }
}

function bytesToBase64(bytes: Uint8Array): string {
  const alphabet: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result: string = '';
  for (let index: number = 0; index < bytes.length; index += 3) {
    const first: number = bytes[index];
    const second: number = index + 1 < bytes.length ? bytes[index + 1] : 0;
    const third: number = index + 2 < bytes.length ? bytes[index + 2] : 0;
    const combined: number = (first << 16) | (second << 8) | third;
    result += alphabet[(combined >> 18) & 63];
    result += alphabet[(combined >> 12) & 63];
    result += index + 1 < bytes.length ? alphabet[(combined >> 6) & 63] : '=';
    result += index + 2 < bytes.length ? alphabet[combined & 63] : '=';
  }
  return result;
}

function base64Index(value: string, index: number): number {
  const code: number = value.charCodeAt(index);
  if (code >= 65 && code <= 90) { return code - 65; }
  if (code >= 97 && code <= 122) { return code - 71; }
  if (code >= 48 && code <= 57) { return code + 4; }
  if (value[index] === '+') { return 62; }
  if (value[index] === '/') { return 63; }
  return -1;
}

function base64ToBytes(value: string): Uint8Array {
  if (typeof value !== 'string' || value.length === 0 || value.length % 4 !== 0 || /[^A-Za-z0-9+/=]/.test(value)) {
    throw new Error('图片字节不是合法 Base64');
  }
  const outputLength: number = value.length / 4 * 3 - (value.endsWith('==') ? 2 : (value.endsWith('=') ? 1 : 0));
  const output: Uint8Array = new Uint8Array(outputLength);
  let offset: number = 0;
  for (let index: number = 0; index < value.length; index += 4) {
    const first: number = base64Index(value, index);
    const second: number = base64Index(value, index + 1);
    const third: number = value[index + 2] === '=' ? 0 : base64Index(value, index + 2);
    const fourth: number = value[index + 3] === '=' ? 0 : base64Index(value, index + 3);
    if (first < 0 || second < 0 || third < 0 || fourth < 0 ||
      (value[index + 2] === '=' && value[index + 3] !== '=') ||
      ((value[index + 2] === '=' || value[index + 3] === '=') && index + 4 < value.length)) {
      throw new Error('图片字节不是合法 Base64');
    }
    const combined: number = (first << 18) | (second << 12) | (third << 6) | fourth;
    if (offset < output.length) { output[offset++] = (combined >> 16) & 255; }
    if (offset < output.length) { output[offset++] = (combined >> 8) & 255; }
    if (offset < output.length) { output[offset++] = combined & 255; }
  }
  return output;
}

// FNV-1a 用于检测迁移包中的字节损坏；它不是签名，也不能承担鉴权。
export function computeByteHash(bytes: Uint8Array): string {
  let hash: number = 2166136261;
  for (let index: number = 0; index < bytes.length; index++) {
    hash ^= bytes[index];
    hash = Math.imul(hash, 16777619) >>> 0;
  }
  return hash.toString(16).padStart(8, '0');
}

function placeholder(assetId: string): string { return MIGRATION_ASSET_PREFIX + assetId; }

function packageId<T extends Object>(envelope: SyncEnvelope<T>): string {
  return envelope.deviceId + '-' + String(envelope.revision) + '-' + envelope.snapshotHash;
}

function mapAssetId(uris: string[], uri: string): string {
  const existing: number = uris.indexOf(uri);
  return existing >= 0 ? 'asset-' + String(existing) : 'asset-' + String(uris.length);
}

function replacePrivateUri(uri: string, source: MigrationSourceFileAdapter, uris: string[], field: string): string {
  if (uri.length === 0) { return ''; }
  if (!source.isPrivateUri(uri)) { throw new Error(field + '不是允许的应用私有图片 URI'); }
  const assetId: string = mapAssetId(uris, uri);
  if (uris.indexOf(uri) < 0) { uris.push(uri); }
  return placeholder(assetId);
}

function rewriteSnapshotUris<T extends Object>(snapshot: T, source: MigrationSourceFileAdapter, uris: string[]): T {
  const root: Record<string, Object> = cloneRecord(snapshot);
  if (Array.isArray(root.garments)) {
    for (const garment of root.garments as Record<string, Object>[]) {
      if (typeof garment.imageUri !== 'string') { throw new Error('衣物 imageUri 字段无效'); }
      garment.imageUri = replacePrivateUri(garment.imageUri as string, source, uris, '衣物图片');
    }
  }
  if (Array.isArray(root.diary)) {
    for (const entry of root.diary as Record<string, Object>[]) {
      if (typeof entry.photoUri !== 'string') { throw new Error('日记 photoUri 字段无效'); }
      entry.photoUri = replacePrivateUri(entry.photoUri as string, source, uris, '日记图片');
    }
  }
  if (Array.isArray(root.tryOnTasks)) {
    for (const task of root.tryOnTasks as Record<string, Object>[]) {
      if (!Array.isArray(task.resultUris)) { throw new Error('试穿 resultUris 字段无效'); }
      task.resultUris = (task.resultUris as Object[]).map((uri: Object) => {
        if (typeof uri !== 'string') { throw new Error('试穿结果 URI 无效'); }
        return replacePrivateUri(uri as string, source, uris, '试穿结果图片');
      });
    }
  }
  return JSON.parse(JSON.stringify(root)) as T;
}

function assetIdForUri(uris: string[], uri: string): string {
  const index: number = uris.indexOf(uri);
  if (index < 0) { throw new Error('迁移图片引用不存在'); }
  return 'asset-' + String(index);
}

function validatePackageShape<T extends Object>(value: Object, limits: NormalizedMigrationLimits): string {
  if (!isObject(value)) { return '迁移包必须是对象'; }
  const data: Record<string, Object> = value as Record<string, Object>;
  if (data.format !== MIGRATION_PACKAGE_FORMAT || data.packageVersion !== MIGRATION_PACKAGE_VERSION) {
    return '迁移包格式或版本不支持';
  }
  if (!validTimestamp(data.exportedAt as string)) { return '迁移包 exportedAt 无效'; }
  if (!Array.isArray(data.assets)) { return '迁移包缺少 assets'; }
  if (data.assets.length > limits.maxAssetCount) { return '迁移图片数量超过上限'; }
  if (typeof data.totalImageBytes !== 'number' || !Number.isInteger(data.totalImageBytes) || data.totalImageBytes < 0 ||
    data.totalImageBytes > limits.maxTotalImageBytes) { return '迁移图片总大小超过上限'; }
  if (typeof data.continuationPayload !== 'string') { return '迁移包缺少任务续接内容'; }
  const checked: SyncValidationResult<T> = validateSyncEnvelope(data.envelope);
  if (!checked.valid) { return checked.error; }
  return '';
}

function parsePackage<T extends Object = DemoSnapshot>(payload: string,
  limits: NormalizedMigrationLimits): WardrobeMigrationPackage<T> {
  if (typeof payload !== 'string' || payload.length === 0) { throw new Error('迁移包内容为空'); }
  if (utf8Length(payload) > limits.maxPackageBytes) { throw new Error('迁移包超过容量上限'); }
  let parsed: Object;
  try {
    parsed = JSON.parse(payload) as Object;
  } catch (error) {
    throw new Error('迁移包不是合法 JSON');
  }
  const shapeError: string = validatePackageShape<T>(parsed, limits);
  if (shapeError.length > 0) { throw new Error(shapeError); }
  const data: Record<string, Object> = parsed as Record<string, Object>;
  const assets: MigrationAsset[] = [];
  const ids: string[] = [];
  let total: number = 0;
  for (const value of data.assets as Object[]) {
    if (!isObject(value)) { throw new Error('迁移 asset 必须是对象'); }
    const item: Record<string, Object> = value as Record<string, Object>;
    const assetId: string = item.assetId as string;
    const byteLength: number = item.byteLength as number;
    const contentHash: string = item.contentHash as string;
    const bytesBase64: string = item.bytesBase64 as string;
    if (!isValidAssetId(assetId) || ids.indexOf(assetId) >= 0) { throw new Error('迁移 assetId 无效或重复'); }
    if (typeof byteLength !== 'number' || !Number.isInteger(byteLength) || byteLength <= 0 ||
      byteLength > limits.maxImageBytes) { throw new Error('单张迁移图片超过上限'); }
    if (typeof contentHash !== 'string' || contentHash.length === 0 || typeof bytesBase64 !== 'string') {
      throw new Error('迁移 asset 字段无效');
    }
    const bytes: Uint8Array = base64ToBytes(bytesBase64);
    if (bytes.length !== byteLength || computeByteHash(bytes) !== contentHash) {
      throw new Error('迁移图片字节校验失败');
    }
    total += bytes.length;
    if (total > limits.maxTotalImageBytes) { throw new Error('迁移图片总大小超过上限'); }
    ids.push(assetId);
    assets.push({ assetId: assetId, byteLength: byteLength, contentHash: contentHash, bytesBase64: bytesBase64 });
  }
  if (total !== data.totalImageBytes) { throw new Error('迁移图片总大小字段不一致'); }
  return {
    format: MIGRATION_PACKAGE_FORMAT,
    packageVersion: MIGRATION_PACKAGE_VERSION,
    exportedAt: data.exportedAt as string,
    envelope: data.envelope as SyncEnvelope<T>,
    assets: assets,
    totalImageBytes: total,
    continuationPayload: data.continuationPayload as string
  };
}

export async function buildWardrobeMigrationPackage<T extends Object = DemoSnapshot>(snapshot: T,
  source: MigrationSourceFileAdapter, deviceId: string, revision: number,
  updatedAt: string = new Date().toISOString(), continuationPayload: string = '',
  limits?: MigrationLimits, exportedAt: string = new Date().toISOString()): Promise<WardrobeMigrationPackage<T>> {
  const normalized: NormalizedMigrationLimits = normalizeLimits(limits);
  if (!validTimestamp(exportedAt)) { throw new Error('迁移包 exportedAt 无效'); }
  if (typeof continuationPayload !== 'string') { throw new Error('任务续接内容必须是字符串'); }
  const uris: string[] = [];
  const placeholderSnapshot: T = rewriteSnapshotUris(snapshot, source, uris);
  if (uris.length > normalized.maxAssetCount) { throw new Error('迁移图片数量超过上限'); }
  const assets: MigrationAsset[] = [];
  let total: number = 0;
  for (const uri of uris) {
    const raw: Uint8Array = await source.read(uri);
    const bytes: Uint8Array = new Uint8Array(raw);
    if (bytes.length <= 0 || bytes.length > normalized.maxImageBytes) { throw new Error('单张迁移图片大小无效或超过上限'); }
    total += bytes.length;
    if (total > normalized.maxTotalImageBytes) { throw new Error('迁移图片总大小超过上限'); }
    const encoded: string = bytesToBase64(bytes);
    assets.push({ assetId: assetIdForUri(uris, uri), byteLength: bytes.length,
      contentHash: computeByteHash(bytes), bytesBase64: encoded });
  }
  const envelope: SyncEnvelope<T> = createSyncEnvelope(placeholderSnapshot, deviceId, revision, updatedAt);
  const result: WardrobeMigrationPackage<T> = {
    format: MIGRATION_PACKAGE_FORMAT,
    packageVersion: MIGRATION_PACKAGE_VERSION,
    exportedAt: exportedAt,
    envelope: envelope,
    assets: assets,
    totalImageBytes: total,
    continuationPayload: continuationPayload
  };
  if (utf8Length(JSON.stringify(result)) > normalized.maxPackageBytes) { throw new Error('迁移包超过容量上限'); }
  return result;
}

export async function exportWardrobeMigration<T extends Object = DemoSnapshot>(snapshot: T,
  source: MigrationSourceFileAdapter, deviceId: string, revision: number,
  updatedAt?: string, continuationPayload: string = '', limits?: MigrationLimits,
  exportedAt?: string): Promise<string> {
  const result: WardrobeMigrationPackage<T> = await buildWardrobeMigrationPackage(snapshot, source, deviceId, revision,
    updatedAt === undefined ? new Date().toISOString() : updatedAt, continuationPayload, limits,
    exportedAt === undefined ? new Date().toISOString() : exportedAt);
  return JSON.stringify(result);
}

function incomingPlaceholder<T extends Object>(snapshot: T): boolean {
  const root: Record<string, Object> = cloneRecord(snapshot);
  if (Array.isArray(root.garments)) {
    for (const garment of root.garments as Record<string, Object>[]) {
      if (typeof garment.imageUri !== 'string' || (garment.imageUri as string).length > 0 &&
        (garment.imageUri as string).indexOf(MIGRATION_ASSET_PREFIX) !== 0) { return false; }
    }
  }
  if (Array.isArray(root.diary)) {
    for (const entry of root.diary as Record<string, Object>[]) {
      if (typeof entry.photoUri !== 'string' || (entry.photoUri as string).length > 0 &&
        (entry.photoUri as string).indexOf(MIGRATION_ASSET_PREFIX) !== 0) { return false; }
    }
  }
  if (Array.isArray(root.tryOnTasks)) {
    for (const task of root.tryOnTasks as Record<string, Object>[]) {
      if (!Array.isArray(task.resultUris)) { return false; }
      for (const value of task.resultUris as Object[]) {
        if (typeof value !== 'string' || (value as string).length > 0 &&
          (value as string).indexOf(MIGRATION_ASSET_PREFIX) !== 0) { return false; }
      }
    }
  }
  return true;
}

function rewriteCandidateUris<T extends Object>(snapshot: T, assets: MigrationWriteAsset[]): T {
  const root: Record<string, Object> = cloneRecord(snapshot);
  const targetById = (value: string): string => {
    if (value.indexOf(MIGRATION_ASSET_PREFIX) !== 0) { return value; }
    const assetId: string = value.slice(MIGRATION_ASSET_PREFIX.length);
    if (!isValidAssetId(assetId)) { throw new Error('迁移占位 assetId 无效'); }
    const found: MigrationWriteAsset | undefined = assets.find((item: MigrationWriteAsset) => item.assetId === assetId);
    if (found === undefined) { throw new Error('迁移快照引用了不存在的图片'); }
    return found.targetUri;
  };
  if (Array.isArray(root.garments)) {
    for (const garment of root.garments as Record<string, Object>[]) {
      if (typeof garment.imageUri !== 'string') { throw new Error('候选衣物 imageUri 字段无效'); }
      garment.imageUri = targetById(garment.imageUri as string);
    }
  }
  if (Array.isArray(root.diary)) {
    for (const entry of root.diary as Record<string, Object>[]) {
      if (typeof entry.photoUri !== 'string') { throw new Error('候选日记 photoUri 字段无效'); }
      entry.photoUri = targetById(entry.photoUri as string);
    }
  }
  if (Array.isArray(root.tryOnTasks)) {
    for (const task of root.tryOnTasks as Record<string, Object>[]) {
      if (!Array.isArray(task.resultUris)) { throw new Error('候选试穿 resultUris 字段无效'); }
      task.resultUris = (task.resultUris as Object[]).map((value: Object) => {
        if (typeof value !== 'string') { throw new Error('候选试穿 URI 无效'); }
        return targetById(value as string);
      });
    }
  }
  return JSON.parse(JSON.stringify(root)) as T;
}

export async function prepareWardrobeMigration<T extends Object = DemoSnapshot>(payload: string,
  target: MigrationTargetFileAdapter, currentEnvelope?: SyncEnvelope<T>, limits?: MigrationLimits): Promise<MigrationPreparationResult<T>> {
  const normalized: NormalizedMigrationLimits = normalizeLimits(limits);
  let parsed: WardrobeMigrationPackage<T>;
  try {
    parsed = parsePackage<T>(payload, normalized);
  } catch (error) {
    return { status: 'rejected', message: (error as Error).message || '迁移包无效' };
  }
  if (!incomingPlaceholder(parsed.envelope.snapshot)) {
    return { status: 'rejected', message: '迁移快照未使用受支持的图片占位 URI' };
  }
  const packageKey: string = packageId(parsed.envelope);
  const writes: MigrationWriteAsset[] = [];
  try {
    for (const asset of parsed.assets) {
      if (!isValidAssetId(asset.assetId)) { throw new Error('迁移 assetId 无效'); }
      const targetUri: string = target.destinationUri(asset.assetId, packageKey);
      assertSafeUri(targetUri, target, '目标图片 URI');
      writes.push({ assetId: asset.assetId, targetUri: targetUri,
        bytes: base64ToBytes(asset.bytesBase64), contentHash: asset.contentHash });
    }
    const candidateSnapshot: T = rewriteCandidateUris(parsed.envelope.snapshot, writes);
    const candidateEnvelope: SyncEnvelope<T> = createSyncEnvelope(candidateSnapshot, parsed.envelope.deviceId,
      parsed.envelope.revision, parsed.envelope.updatedAt);
    let conflict: MigrationConflict | undefined = undefined;
    let status: MigrationPreparationStatus = 'ready';
    let message: string = '迁移包已校验，可提交候选快照';
    if (currentEnvelope !== undefined) {
      if (parsed.envelope.deviceId === currentEnvelope.deviceId && parsed.envelope.revision === currentEnvelope.revision &&
        parsed.envelope.snapshotHash === currentEnvelope.snapshotHash) {
        status = 'duplicate';
        message = '相同设备和 revision 已存在，忽略重复迁移包';
      } else if (parsed.envelope.revision < currentEnvelope.revision) {
        status = 'stale';
        message = '迁移包 revision 较旧，保留当前衣橱';
      } else if (parsed.envelope.revision === currentEnvelope.revision) {
        status = 'conflict';
        conflict = {
          reason: '迁移包与当前衣橱 revision 相同但来源不同，需要用户确认覆盖',
          localRevision: currentEnvelope.revision,
          incomingRevision: parsed.envelope.revision,
          localUpdatedAt: currentEnvelope.updatedAt,
          incomingUpdatedAt: parsed.envelope.updatedAt,
          localDeviceId: currentEnvelope.deviceId,
          incomingDeviceId: parsed.envelope.deviceId,
          decisionRequired: true
        };
        message = conflict.reason;
      }
    }
    const candidate: WardrobeMigrationCandidate<T> = {
      snapshot: candidateSnapshot,
      envelope: candidateEnvelope,
      assets: writes,
      continuationPayload: parsed.continuationPayload,
      conflict: conflict
    };
    return { status: status, message: message, candidate: candidate, conflict: conflict };
  } catch (error) {
    return { status: 'rejected', message: (error as Error).message || '无法构造迁移候选快照' };
  }
}

export async function commitWardrobeMigrationCandidate<T extends Object = DemoSnapshot>(
  candidate: WardrobeMigrationCandidate<T>, target: MigrationTargetFileAdapter,
  committer: CandidateSnapshotCommitter<T>, allowConflict: boolean = false): Promise<MigrationCommitResult> {
  if (candidate.conflict !== undefined && !allowConflict) {
    throw new Error('迁移存在冲突，必须先取得用户确认');
  }
  const writtenUris: string[] = [];
  let committed: boolean = false;
  try {
    if (committer.validate !== undefined) { await committer.validate(candidate.snapshot, candidate.envelope); }
    for (const asset of candidate.assets) {
      assertSafeUri(asset.targetUri, target, '目标图片 URI');
      writtenUris.push(asset.targetUri);
      // 先登记再写入：适配器若在部分写入后抛错，回滚也会尝试删除当前 URI。
      await target.write(asset.targetUri, asset.bytes);
    }
    await committer.commit(candidate.snapshot, candidate.envelope);
    committed = true;
    committer.publish(candidate.snapshot, candidate.envelope);
    return { committed: true, published: true, writtenUris: writtenUris.slice(), message: '迁移候选已提交并发布' };
  } catch (error) {
    if (!committed) {
      for (let index: number = writtenUris.length - 1; index >= 0; index--) {
        try { await target.remove(writtenUris[index]); } catch (cleanupError) { /* 继续清理其余文件 */ }
      }
    }
    throw new Error((error as Error).message || '迁移候选提交失败');
  }
}

// UI 层若按“导出/准备导入/提交导入”命名，可直接使用这些语义别名。
export const exportMigrationPackage = exportWardrobeMigration;
export const prepareMigrationPackage = prepareWardrobeMigration;
export const commitMigrationCandidate = commitWardrobeMigrationCandidate;
