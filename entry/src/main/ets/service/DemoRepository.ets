import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { DemoSnapshot, CATEGORIES, STATUSES, OCCASIONS, emptyProfile, emptyMembership,
  emptyBodyProfile } from '../model/Wardrobe';
import { initialSnapshot } from '../data/DemoData';
import { normalizeLayout } from './OutfitCanvas';
import { IMPORT_BATCH_PREFIX, IMPORT_SUFFIX_CUTOUT, IMPORT_SUFFIX_ORIGINAL, MAX_EDGE,
  MAX_SOURCE_BYTES, MAX_SOURCE_PIXELS } from './GarmentImport';

const FILE_NAME: string = '/wardrobe_demo_v1.json';
// 批量导入的临时文件前缀。启动时的遗留清理只认这个前缀，不扫空整个目录。
const BATCH_PREFIX: string = '/' + IMPORT_BATCH_PREFIX;
// 上一版单件导入用的前缀。仍然属于本应用生成的文件，参与同一套受限清理。
const LEGACY_PREFIXES: string[] = ['/garment_', '/garment_cutout_'];

// 旧快照可能缺少后来加入的字段，补默认值而不是丢弃用户数据。
function withDefaults(snapshot: DemoSnapshot): DemoSnapshot {
  if (!snapshot.profile) { snapshot.profile = emptyProfile(); }
  if (!Array.isArray(snapshot.diary)) { snapshot.diary = []; }
  if (!Array.isArray(snapshot.tryOnTasks)) { snapshot.tryOnTasks = []; }
  if (!snapshot.membership) { snapshot.membership = emptyMembership(); }
  if (!snapshot.body) { snapshot.body = emptyBodyProfile(); }
  if (typeof snapshot.city !== 'string') { snapshot.city = ''; }
  for (const item of snapshot.garments) {
    if (typeof item.fit !== 'string') { item.fit = '合身'; }
    if (typeof item.palette !== 'string') { item.palette = '基础色'; }
    if (typeof item.style !== 'string') { item.style = '简约'; }
    if (typeof item.layering !== 'boolean') { item.layering = false; }
    if (typeof item.pattern !== 'boolean') { item.pattern = false; }
  }
  for (const outfit of snapshot.saved) {
    if (typeof outfit.name !== 'string') { outfit.name = ''; }
    if (typeof outfit.isCustom !== 'boolean') { outfit.isCustom = false; }
    if (typeof outfit.savedAt !== 'string') { outfit.savedAt = ''; }
    if (outfit.layout) { outfit.layout = normalizeLayout(outfit.layout, outfit.garmentIds); }
  }
  return snapshot;
}

export function readSnapshot(filesDir: string): DemoSnapshot {
  const path: string = filesDir + FILE_NAME;
  if (!fs.accessSync(path)) { return initialSnapshot(); }
  if (fs.statSync(path).size > 2 * 1024 * 1024) { throw new Error('衣橱数据超过本地容量限制'); }
  const snapshot: DemoSnapshot = JSON.parse(fs.readTextSync(path)) as DemoSnapshot;
  return validateSnapshot(snapshot);
}

// 手动迁移与正常启动共用同一份结构校验。导入侧会先校验候选，
// 成功后才写图片与快照；这里不能依赖文件读取来判断一个尚未落盘的候选。
export function validateSnapshot(snapshot: DemoSnapshot): DemoSnapshot {
  if (snapshot.version !== 1 || !Array.isArray(snapshot.garments) || !Array.isArray(snapshot.saved) ||
    !Array.isArray(snapshot.records) || !Array.isArray(snapshot.activeIds) ||
    !Number.isFinite(snapshot.temperature) || snapshot.temperature < -20 || snapshot.temperature > 45 ||
    OCCASIONS.indexOf(snapshot.occasion) < 0) { throw new Error('衣橱数据格式不正确'); }
  const knownIds: string[] = [];
  for (const item of snapshot.garments) {
    if (typeof item.id !== 'string' || knownIds.indexOf(item.id) >= 0 || typeof item.name !== 'string' ||
      typeof item.imageKey !== 'string' || typeof item.imageUri !== 'string' || typeof item.color !== 'string' ||
      (item.subcategory !== undefined && typeof item.subcategory !== 'string') ||
      (item.material !== undefined && typeof item.material !== 'string') ||
      (typeof item.subcategory === 'string' && item.subcategory.length > 24) ||
      (typeof item.material === 'string' && item.material.length > 24) ||
      CATEGORIES.indexOf(item.category) < 0 || STATUSES.indexOf(item.status) < 0 || !Array.isArray(item.occasions) ||
      !Number.isFinite(item.minTemp) || !Number.isFinite(item.maxTemp) || item.minTemp > item.maxTemp ||
      !Number.isFinite(item.wearCount) || item.wearCount < 0) { throw new Error('衣物数据格式不正确'); }
    knownIds.push(item.id);
  }
  for (const outfit of snapshot.saved) {
    if (typeof outfit.id !== 'string' || !Array.isArray(outfit.garmentIds) || typeof outfit.reason !== 'string' ||
      typeof outfit.occasion !== 'string' || !Number.isFinite(outfit.temperature)) { throw new Error('收藏数据格式不正确'); }
  }
  for (const record of snapshot.records) {
    if (typeof record.id !== 'string' || !Array.isArray(record.garmentIds) || typeof record.date !== 'string' ||
      typeof record.feedback !== 'string') { throw new Error('穿着记录格式不正确'); }
  }
  return withDefaults(snapshot);
}

export class DemoRepository {
  private filesDir: string;
  private writeQueue: Promise<void> = Promise.resolve();

  constructor(filesDir: string) { this.filesDir = filesDir; }

  // 只有主应用写入，卡片进程只读。每次将完整快照写入临时文件，再原子替换，避免卡片读到半份 JSON。
  // 决赛接入服务器时保留 model 与推荐规则，替换此仓储实现；不要将演示图片当作用户上传记录同步。
  save(snapshot: DemoSnapshot): Promise<void> {
    return this.savePayload(JSON.stringify(snapshot));
  }

  // 与 save 同一条写队列；调用方已经序列化好快照时用它，避免"序列化两次、内容还可能不同"。
  savePayload(payload: string): Promise<void> {
    const bytes: Uint8Array = new util.TextEncoder().encodeInto(payload);
    // catch 只恢复队列，使一次失败不会阻止后续重试；本次失败仍由返回的 pending 交给页面处理。
    const pending: Promise<void> = this.writeQueue.catch(() => {}).then(async () => {
      const temporary: string = this.filesDir + FILE_NAME + '.tmp';
      const file: fs.File = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        let written: number = 0;
        while (written < bytes.byteLength) {
          const count: number = await fs.write(file.fd, bytes.buffer.slice(written));
          if (count <= 0) { throw new Error('衣橱文件未能完整写入'); }
          written += count;
        }
        await fs.fsync(file.fd);
      } finally { await fs.close(file); }
      await fs.rename(temporary, this.filesDir + FILE_NAME);
    });
    this.writeQueue = pending;
    return pending;
  }

  // 单件选择：多选接口的薄封装，保持旧调用方（单件编辑表单）的接口不变。
  async chooseImage(): Promise<string> {
    const uris: string[] = await this.chooseImages(1);
    return uris.length > 0 ? uris[0] : '';
  }

  // 批量选择：一次最多 limit 张。用户取消时返回空数组，这不是异常，调用方安静返回即可。
  async chooseImages(limit: number): Promise<string[]> {
    const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
    const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = Math.max(1, limit);
    const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
    return result.photoUris ? result.photoUris.slice() : [];
  }

  // ---- 导入文件的本应用沙箱路径 ----
  //
  // 命名规则集中在仓储：页面只传任务标识，拿不到也传不进任意路径。
  // 每项的文件名都带会话 ID 与任务 ID，不会出现"一轮里所有图片共用 Date.now()"。
  // 统一编码成 PNG 且保留透明通道，所以扩展名与编码一致。

  originalPathFor(taskId: string): string {
    return this.filesDir + BATCH_PREFIX + taskId + '_' + IMPORT_SUFFIX_ORIGINAL + '.png';
  }

  cutoutPathFor(taskId: string): string {
    return this.filesDir + BATCH_PREFIX + taskId + '_' + IMPORT_SUFFIX_CUTOUT + '.png';
  }

  cutoutUriFor(taskId: string): string {
    return fileUri.getUriFromPath(this.cutoutPathFor(taskId));
  }

  // 把 Picker 给的一张相册图片读进本应用沙箱，解码时顺便缩到预算内，再以 PNG 编码写出。
  // 只使用一次性会话 URI，不做媒体库持久化授权，因此不新增任何相册权限。
  async importImage(sourceUri: string, targetPath: string): Promise<string> {
    const source: fs.File = await fs.open(sourceUri, fs.OpenMode.READ_ONLY);
    let imageSource: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    let created: boolean = false;
    try {
      const bytes: number = (await fs.stat(source.fd)).size;
      if (bytes > MAX_SOURCE_BYTES) { throw new Error('请选择小于 20MB 的衣物图片'); }
      imageSource = image.createImageSource(source.fd);
      const info: image.ImageInfo = await imageSource.getImageInfo();
      if (!info || !info.size || info.size.width <= 0 || info.size.height <= 0) {
        throw new Error('这张图片无法识别，请换一张或跳过');
      }
      if (info.size.width * info.size.height > MAX_SOURCE_PIXELS) {
        throw new Error('这张图片分辨率过大，请换一张或先裁剪');
      }
      // 只缩小不放大：长边落在 MAX_EDGE 以内，小图保持原尺寸。
      const longest: number = Math.max(info.size.width, info.size.height);
      const ratio: number = longest > MAX_EDGE ? MAX_EDGE / longest : 1;
      const width: number = Math.max(1, Math.round(info.size.width * ratio));
      const height: number = Math.max(1, Math.round(info.size.height * ratio));
      pixelMap = await imageSource.createPixelMap({ desiredSize: { width: width, height: height },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      if (!pixelMap) { throw new Error('这张图片无法解码，请换一张或跳过'); }
      packer = image.createImagePacker();
      const output: fs.File = await fs.open(targetPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      created = true;
      try {
        await packer.packToFile(pixelMap, output.fd, { format: 'image/png', quality: 100 });
      } finally { await fs.close(output); }
      return fileUri.getUriFromPath(targetPath);
    } catch (error) {
      // 失败的半成品不能留给下一次录入使用。
      if (created) { await fs.unlink(targetPath).catch(() => {}); }
      throw new Error((error as Error).message || '未能导入这张图片');
    } finally {
      // 释放彼此独立：一个失败不能跳过其余清理。
      if (packer) { await packer.release().catch(() => {}); }
      if (pixelMap) { await pixelMap.release().catch(() => {}); }
      if (imageSource) { await imageSource.release().catch(() => {}); }
      await fs.close(source).catch(() => {});
    }
  }

  // 删除本应用生成的临时图片：只认本应用的前缀，只删沙箱内的文件，绝不碰相册原始 URI。
  async discardImage(uri: string): Promise<void> {
    const path: string = this.ownedPath(uri);
    if (path.length > 0 && fs.accessSync(path)) { await fs.unlink(path); }
  }

  private ownedPath(uri: string): string {
    if (uri.length === 0) { return ''; }
    let path: string = '';
    // Picker 返回的是媒体库 URI，解析成沙箱路径后必然不落在自己目录里，会被下面的前缀判断拒绝。
    try { path = new fileUri.FileUri(uri).path; } catch (error) { return ''; }
    if (path.indexOf(this.filesDir + '/') !== 0) { return ''; }
    const name: string = path.slice(this.filesDir.length);
    for (const prefix of LEGACY_PREFIXES) {
      if (name.indexOf(prefix) === 0) { return path; }
    }
    return name.indexOf(BATCH_PREFIX) === 0 ? path : '';
  }

  // 收集快照里所有被引用的本地图片，作为清理的保留集合。
  // 覆盖 garments、diary、tryOnTasks 三处图片字段，少一处就可能删掉还在用的文件。
  referencedImages(snapshot: DemoSnapshot): string[] {
    const keep: string[] = [];
    for (const item of snapshot.garments) {
      if (item.imageUri && item.imageUri.length > 0) { keep.push(item.imageUri); }
    }
    for (const entry of snapshot.diary) {
      if (entry.photoUri && entry.photoUri.length > 0) { keep.push(entry.photoUri); }
    }
    for (const task of snapshot.tryOnTasks) {
      if (task.resultUris) {
        for (const uri of task.resultUris) {
          if (uri.length > 0) { keep.push(uri); }
        }
      }
    }
    return keep;
  }

  // 启动遗留清理：只删本应用批量前缀、且没有被任何持久化记录引用的文件。
  // 必须在快照成功读取之后调用一次；读失败时调用方不得调用本方法。
  async sweepOrphans(snapshot: DemoSnapshot): Promise<number> {
    const keep: string[] = this.referencedImages(snapshot);
    const names: string[] = await fs.listFile(this.filesDir);
    let removed: number = 0;
    for (const name of names) {
      if (name.indexOf(IMPORT_BATCH_PREFIX) !== 0) { continue; }
      const path: string = this.filesDir + '/' + name;
      if (keep.indexOf(fileUri.getUriFromPath(path)) >= 0) { continue; }
      try { await fs.unlink(path); removed++; } catch (error) { /* 单张失败不影响其余清理 */ }
    }
    return removed;
  }
}
