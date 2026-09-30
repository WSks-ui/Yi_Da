// CoreFileKit/DocumentViewPicker 宿主适配器。
//
// WardrobeMigration 只处理包格式、候选快照和提交契约；本文件负责把它接到
// 当前设备的 filesDir 与系统文件选择器。源图片只允许读取应用 filesDir 下的
// 文件，目标图片使用本模块生成的唯一文件名，写入失败会清理半成品。

import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import {
  DEFAULT_MAX_IMAGE_BYTES,
  DEFAULT_MAX_PACKAGE_BYTES,
  MigrationLimits,
  MigrationSourceFileAdapter,
  MigrationTargetFileAdapter,
  exportWardrobeMigration
} from './WardrobeMigration';
import { IMPORT_BATCH_PREFIX } from './GarmentImport';

export const DEFAULT_MIGRATION_FILE_NAME: string = '艺搭_衣橱迁移';
export const MIGRATION_FILE_SUFFIX: string = '.yida';
// 复用现有导入批次前缀，使 DemoRepository.sweepOrphans 能按同一受限规则清理
// 未被快照引用的迁移图片；已写入快照的 URI 会被 referencedImages 保留。
export const MIGRATION_ASSET_FILE_PREFIX: string = IMPORT_BATCH_PREFIX + 'migration_';
export const MIGRATION_ASSET_FILE_SUFFIX: string = '.png';
const READ_CHUNK_BYTES: number = 64 * 1024;
const PNG_SIGNATURE: number[] = [137, 80, 78, 71, 13, 10, 26, 10];

export interface CoreFileMigrationLimits extends MigrationLimits {
  // Picker 选择的同步包没有图片拆分限制，只受整个包大小限制。
  maxPickerPackageBytes?: number;
}

export interface CoreFileMigrationAdapters {
  source: MigrationSourceFileAdapter;
  target: MigrationTargetFileAdapter;
}

export type MigrationPickerStatus = 'saved' | 'selected' | 'cancelled' | 'failed';

export interface MigrationPickerResult<T> {
  status: MigrationPickerStatus;
  message: string;
  uri?: string;
  value?: T;
}

function normalizedRoot(root: string): string {
  if (typeof root !== 'string' || root.length === 0 || root.indexOf('\u0000') >= 0) {
    throw new Error('应用 filesDir 无效');
  }
  let result: string = root.replace(/[\\/]+$/, '');
  if (result.length === 0 || result.split(/[\\/]/).indexOf('..') >= 0) {
    throw new Error('应用 filesDir 路径不安全');
  }
  return result;
}

function pathFromUri(uri: string): string {
  if (typeof uri !== 'string' || uri.length === 0 || uri.indexOf('\u0000') >= 0) {
    throw new Error('文件 URI 为空或包含非法字符');
  }
  let path: string = '';
  try {
    path = new fileUri.FileUri(uri).path;
  } catch (error) {
    throw new Error('文件 URI 无法解析');
  }
  if (typeof path !== 'string' || path.length === 0 || path.split(/[\\/]/).indexOf('..') >= 0) {
    throw new Error('文件 URI 路径不安全');
  }
  return path;
}

function isWithinRoot(path: string, root: string): boolean {
  return path === root || path.indexOf(root + '/') === 0 || path.indexOf(root + '\\') === 0;
}

function safePrivatePath(uri: string, root: string, label: string): string {
  const path: string = pathFromUri(uri);
  if (!isWithinRoot(path, root)) { throw new Error(label + '不属于应用 filesDir'); }
  return path;
}

function imageLimit(limits?: CoreFileMigrationLimits): number {
  const value: number = limits?.maxImageBytes === undefined ? DEFAULT_MAX_IMAGE_BYTES : limits.maxImageBytes;
  if (!Number.isInteger(value) || value <= 0) { throw new Error('图片大小上限必须是正整数'); }
  return value;
}

function packageLimit(limits?: CoreFileMigrationLimits): number {
  const value: number = limits?.maxPickerPackageBytes === undefined ?
    (limits?.maxPackageBytes === undefined ? DEFAULT_MAX_PACKAGE_BYTES : limits.maxPackageBytes) :
    limits.maxPickerPackageBytes;
  if (!Number.isInteger(value) || value <= 0) { throw new Error('迁移包大小上限必须是正整数'); }
  return value;
}

function byteLength(text: string): number {
  return new util.TextEncoder().encodeInto(text).byteLength;
}

function isPng(bytes: Uint8Array): boolean {
  if (bytes.length < PNG_SIGNATURE.length) { return false; }
  for (let index: number = 0; index < PNG_SIGNATURE.length; index++) {
    if (bytes[index] !== PNG_SIGNATURE[index]) { return false; }
  }
  return true;
}

async function readBytesFromFile(uriOrPath: string, maxBytes: number, label: string,
  root?: string, requirePng: boolean = false): Promise<Uint8Array> {
  if (root !== undefined) { safePrivatePath(uriOrPath, root, label); }
  let file: fs.File | undefined = undefined;
  try {
    file = await fs.open(uriOrPath, fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW);
    if (root !== undefined && !isWithinRoot(file.path, root)) {
      throw new Error(label + '打开后的真实路径不属于应用 filesDir');
    }
    const before: fs.Stat = await fs.stat(file.fd);
    const size: number = Number(before.size);
    if (!Number.isInteger(size) || size <= 0 || size > maxBytes) {
      throw new Error(label + '大小无效或超过上限');
    }
    const bytes: Uint8Array = new Uint8Array(size);
    let offset: number = 0;
    while (offset < size) {
      const length: number = Math.min(READ_CHUNK_BYTES, size - offset);
      const chunkBuffer: ArrayBuffer = new ArrayBuffer(length);
      const count: number = await fs.read(file.fd, chunkBuffer, { length: length });
      if (!Number.isInteger(count) || count <= 0 || count > length) {
        throw new Error(label + '读取未完成');
      }
      bytes.set(new Uint8Array(chunkBuffer, 0, count), offset);
      offset += count;
    }
    const after: fs.Stat = await fs.stat(file.fd);
    if (Number(after.size) !== size || offset !== size) { throw new Error(label + '读取字节数不完整'); }
    if (requirePng && !isPng(bytes)) { throw new Error(label + '不是受支持的 PNG 图片'); }
    return bytes;
  } finally {
    if (file !== undefined) { await fs.close(file).catch(() => {}); }
  }
}

async function writeBytesToNewFile(path: string, bytes: Uint8Array, root: string,
  maxBytes: number, requirePng: boolean = false): Promise<void> {
  if (!isWithinRoot(path, root) || path.split(/[\\/]/).indexOf('..') >= 0) {
    throw new Error('目标图片路径不属于应用 filesDir');
  }
  if (bytes.length <= 0 || bytes.length > maxBytes) { throw new Error('目标图片大小无效或超过上限'); }
  if (requirePng && !isPng(bytes)) { throw new Error('目标图片不是受支持的 PNG 图片'); }
  if (fs.accessSync(path)) { throw new Error('目标图片已存在，拒绝覆盖'); }
  let file: fs.File | undefined = undefined;
  let opened: boolean = false;
  let completed: boolean = false;
  try {
    file = await fs.open(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.NOFOLLOW);
    if (!isWithinRoot(file.path, root)) { throw new Error('目标图片打开后的路径不安全'); }
    const existing: fs.Stat = await fs.stat(file.fd);
    if (Number(existing.size) !== 0) { throw new Error('目标图片已存在，拒绝覆盖'); }
    // 只有确认这是一个本次新建的空文件后才允许失败清理，避免误删并发创建的文件。
    opened = true;
    let written: number = 0;
    while (written < bytes.length) {
      const count: number = await fs.write(file.fd, bytes.buffer.slice(written));
      if (!Number.isInteger(count) || count <= 0) { throw new Error('目标图片写入未完成'); }
      written += count;
    }
    await fs.fsync(file.fd);
    const finalStat: fs.Stat = await fs.stat(file.fd);
    if (written !== bytes.length || Number(finalStat.size) !== bytes.length) {
      throw new Error('目标图片字节数不完整');
    }
    completed = true;
  } catch (error) {
    throw new Error((error as Error).message || '目标图片写入失败');
  } finally {
    if (file !== undefined) { await fs.close(file).catch(() => {}); }
    // 只有打开后本次写入未完成才清理，成功写入的图片必须保留给候选快照引用。
    if (opened && !completed) { await fs.unlink(path).catch(() => {}); }
  }
}

class CoreFileMigrationSource implements MigrationSourceFileAdapter {
  private readonly root: string;
  private readonly maxBytes: number;

  constructor(filesDir: string, limits?: CoreFileMigrationLimits) {
    this.root = normalizedRoot(filesDir);
    this.maxBytes = imageLimit(limits);
  }

  isPrivateUri(uri: string): boolean {
    try { return isWithinRoot(pathFromUri(uri), this.root); } catch (error) { return false; }
  }

  async read(uri: string): Promise<Uint8Array> {
    return readBytesFromFile(uri, this.maxBytes, '源图片', this.root, true);
  }
}

class CoreFileMigrationTarget implements MigrationTargetFileAdapter {
  private readonly root: string;
  private readonly maxBytes: number;
  private sequence: number = 0;
  private writeQueue: Promise<void> = Promise.resolve();

  constructor(filesDir: string, limits?: CoreFileMigrationLimits) {
    this.root = normalizedRoot(filesDir);
    this.maxBytes = imageLimit(limits);
  }

  isPrivateUri(uri: string): boolean {
    try { return isWithinRoot(pathFromUri(uri), this.root); } catch (error) { return false; }
  }

  destinationUri(assetId: string, packageId: string): string {
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(assetId)) { throw new Error('迁移 assetId 无效'); }
    const packagePart: string = packageId.replace(/[^A-Za-z0-9_-]/g, '_').slice(0, 48);
    for (let attempt: number = 0; attempt < 1000; attempt++) {
      this.sequence++;
      const name: string = MIGRATION_ASSET_FILE_PREFIX + packagePart + '_' + String(Date.now()) + '_' +
        String(this.sequence) + '_' + assetId + MIGRATION_ASSET_FILE_SUFFIX;
      const path: string = this.root + '/' + name;
      if (!fs.accessSync(path)) { return fileUri.getUriFromPath(path); }
    }
    throw new Error('无法生成未占用的迁移目标文件名');
  }

  write(uri: string, bytes: Uint8Array): Promise<void> {
    let path: string = '';
    try {
      path = safePrivatePath(uri, this.root, '目标图片');
    } catch (error) {
      return Promise.reject(error);
    }
    if (path.indexOf(this.root + '/' + MIGRATION_ASSET_FILE_PREFIX) !== 0) {
      return Promise.reject(new Error('目标图片不是本次迁移生成的文件名'));
    }
    const pending: Promise<void> = this.writeQueue.catch(() => {}).then(async () => {
      await writeBytesToNewFile(path, bytes, this.root, this.maxBytes, true);
    });
    this.writeQueue = pending;
    return pending;
  }

  async remove(uri: string): Promise<void> {
    const path: string = safePrivatePath(uri, this.root, '待清理图片');
    if (path.indexOf(this.root + '/' + MIGRATION_ASSET_FILE_PREFIX) !== 0) {
      throw new Error('拒绝清理非迁移文件');
    }
    if (fs.accessSync(path)) { await fs.unlink(path); }
  }
}

export function createCoreFileMigrationSourceAdapter(filesDir: string,
  limits?: CoreFileMigrationLimits): MigrationSourceFileAdapter {
  return new CoreFileMigrationSource(filesDir, limits);
}

export function createCoreFileMigrationTargetAdapter(filesDir: string,
  limits?: CoreFileMigrationLimits): MigrationTargetFileAdapter {
  return new CoreFileMigrationTarget(filesDir, limits);
}

export function createCoreFileMigrationAdapters(filesDir: string,
  limits?: CoreFileMigrationLimits): CoreFileMigrationAdapters {
  return { source: createCoreFileMigrationSourceAdapter(filesDir, limits),
    target: createCoreFileMigrationTargetAdapter(filesDir, limits) };
}

async function writePickerFile(uri: string, bytes: Uint8Array): Promise<void> {
  let file: fs.File | undefined = undefined;
  let emptyBeforeWrite: boolean = false;
  let completed: boolean = false;
  let cleanupPath: string = '';
  try {
    file = await fs.open(uri, fs.OpenMode.WRITE_ONLY | fs.OpenMode.NOFOLLOW);
    cleanupPath = file.path;
    const before: fs.Stat = await fs.stat(file.fd);
    if (Number(before.size) !== 0) { throw new Error('Picker 返回的目标文件非空，拒绝覆盖'); }
    emptyBeforeWrite = true;
    let written: number = 0;
    while (written < bytes.length) {
      const count: number = await fs.write(file.fd, bytes.buffer.slice(written));
      if (!Number.isInteger(count) || count <= 0) { throw new Error('迁移包写入未完成'); }
      written += count;
    }
    await fs.fsync(file.fd);
    const after: fs.Stat = await fs.stat(file.fd);
    if (written !== bytes.length || Number(after.size) !== bytes.length) {
      throw new Error('迁移包字节数不完整');
    }
    completed = true;
  } finally {
    if (file !== undefined) { await fs.close(file).catch(() => {}); }
    // Picker 预创建的是本次导出的空文件；只有写入失败时才删除它，成功文件不能被 finally 清掉。
    if (emptyBeforeWrite === true && !completed && cleanupPath.length > 0) {
      await fs.unlink(cleanupPath).catch(() => {});
    }
  }
}

export async function saveMigrationPackageWithPicker(context: common.UIAbilityContext,
  payload: string, fileName: string = DEFAULT_MIGRATION_FILE_NAME,
  limits?: CoreFileMigrationLimits): Promise<MigrationPickerResult<string>> {
  try {
    const maxBytes: number = packageLimit(limits);
    const bytes: Uint8Array = new util.TextEncoder().encodeInto(payload);
    if (bytes.length <= 0 || bytes.length > maxBytes) { return { status: 'failed', message: '迁移包为空或超过大小上限' }; }
    const safeName: string = fileName.replace(/[^A-Za-z0-9_\-\u4e00-\u9fff]/g, '_').slice(0, 64);
    if (safeName.length === 0) { return { status: 'failed', message: '迁移包文件名无效' }; }
    const viewPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    options.newFileNames = [safeName + MIGRATION_FILE_SUFFIX];
    options.fileSuffixChoices = ['艺搭衣橱迁移包|' + MIGRATION_FILE_SUFFIX];
    const targets: string[] = await viewPicker.save(options);
    if (!targets || targets.length === 0) { return { status: 'cancelled', message: '已取消导出迁移包' }; }
    if (targets.length !== 1 || typeof targets[0] !== 'string' || targets[0].length === 0) {
      return { status: 'failed', message: 'Picker 未返回唯一导出文件' };
    }
    await writePickerFile(targets[0], bytes);
    return { status: 'saved', uri: targets[0], value: payload, message: '迁移包已导出到所选文件' };
  } catch (error) {
    return { status: 'failed', message: (error as Error).message || '迁移包导出失败' };
  }
}

export async function readMigrationPackageUri(uri: string,
  limits?: CoreFileMigrationLimits): Promise<string> {
  const bytes: Uint8Array = await readBytesFromFile(uri, packageLimit(limits), '迁移包');
  try {
    return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes);
  } catch (error) {
    throw new Error('迁移包不是合法 UTF-8 文本');
  }
}

export async function selectMigrationPackageWithPicker(context: common.UIAbilityContext,
  limits?: CoreFileMigrationLimits): Promise<MigrationPickerResult<string>> {
  try {
    const viewPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.fileSuffixFilters = ['艺搭衣橱迁移包|' + MIGRATION_FILE_SUFFIX, 'JSON|.json'];
    options.maxSelectNumber = 1;
    const selected: string[] = await viewPicker.select(options);
    if (!selected || selected.length === 0) { return { status: 'cancelled', message: '已取消导入迁移包' }; }
    if (selected.length !== 1 || typeof selected[0] !== 'string' || selected[0].length === 0) {
      return { status: 'failed', message: 'Picker 未返回唯一导入文件' };
    }
    const payload: string = await readMigrationPackageUri(selected[0], limits);
    return { status: 'selected', uri: selected[0], value: payload, message: '已读取迁移包，可继续校验和准备导入' };
  } catch (error) {
    return { status: 'failed', message: (error as Error).message || '迁移包导入读取失败' };
  }
}

export async function exportWardrobeMigrationWithPicker<T extends Object>(context: common.UIAbilityContext,
  snapshot: T, deviceId: string, revision: number, updatedAt?: string, continuationPayload: string = '',
  limits?: CoreFileMigrationLimits, fileName: string = DEFAULT_MIGRATION_FILE_NAME): Promise<MigrationPickerResult<string>> {
  try {
    const source: MigrationSourceFileAdapter = createCoreFileMigrationSourceAdapter(context.filesDir, limits);
    const payload: string = await exportWardrobeMigration(snapshot, source, deviceId, revision,
      updatedAt, continuationPayload, limits);
    return saveMigrationPackageWithPicker(context, payload, fileName, limits);
  } catch (error) {
    return { status: 'failed', message: (error as Error).message || '迁移包导出失败' };
  }
}

// 语义别名，便于页面按“导出同步包/导入同步包”接线。
export const saveWardrobeMigrationWithPicker = saveMigrationPackageWithPicker;
export const importWardrobeMigrationWithPicker = selectMigrationPackageWithPicker;
