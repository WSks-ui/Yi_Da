import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { AppError } from '../../common/errors/AppError';
import { MediaAsset, PreparedPhoto } from '../../domain/models/Garment';
import { MediaRepository } from '../../domain/repositories/MediaRepository';
import { mediaRelativePath, scaledSize } from '../../domain/usecases/GarmentRules';

const MAX_BYTES: number = 10 * 1024 * 1024;
const ORIGINAL_EDGE: number = 2048;
const THUMBNAIL_EDGE: number = 384;

export class PhotoStorage implements MediaRepository {
  private root: string;
  private active: Set<string> = new Set();
  private context: common.Context;

  constructor(context: common.Context, testNamespace: string = '') {
    this.context = context;
    if (testNamespace && !/^test-[0-9a-f-]{36}$/.test(testNamespace)) {
      throw new AppError('INVALID_TEST_NAMESPACE', '测试存储目录无效。');
    }
    this.root = testNamespace ? `${context.filesDir}/${testNamespace}` : context.filesDir;
  }

  async initialize(): Promise<void> {
    if (!await fs.access(`${this.root}/media`)) { await fs.mkdir(`${this.root}/media`, true); }
    if (!await fs.access(`${this.root}/staging`)) { await fs.mkdir(`${this.root}/staging`, true); }
  }

  async pick(): Promise<string> {
    const result = await new photoAccessHelper.PhotoViewPicker().select({
      MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 1
    });
    // 用户取消返回空结果，不作为权限错误，也不清掉编辑中的已有图片。
    return result.photoUris.length > 0 ? result.photoUris[0] : '';
  }

  absolute(relativePath: string): string {
    return relativePath ? `${this.root}/${mediaRelativePath(relativePath)}` : '';
  }

  async prepareSample(): Promise<PreparedPhoto> {
    await this.initialize();
    const path = `${this.root}/staging/${util.generateRandomUUID(true)}.input`;
    try {
      const bytes = await this.context.resourceManager.getRawFileContent('demo/tshirt.jpg');
      const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        let offset = 0;
        while (offset < bytes.byteLength) {
          const count = await fs.write(file.fd, bytes.buffer.slice(bytes.byteOffset + offset, bytes.byteOffset + bytes.byteLength));
          if (count < 1) { throw new AppError('WRITE_FAILED', '示例素材写入失败，请重试。'); }
          offset += count;
        }
      } finally { await fs.close(file); }
      return await this.prepare(path);
    } finally { await this.removeIfPresent(path); }
  }

  async prepare(uri: string): Promise<PreparedPhoto> {
    await this.initialize();
    const id = util.generateRandomUUID(true);
    const originalPath = `media/${id}.jpg`;
    const thumbnailPath = `media/${id}-thumb.jpg`;
    const input = `${this.root}/staging/${id}.input`;
    this.active.add(originalPath);
    this.active.add(thumbnailPath);
    let source: image.ImageSource | undefined;
    let pixel: image.PixelMap | undefined;
    let thumb: image.PixelMap | undefined;
    let normalized: image.ImageSource | undefined;
    try {
      await this.copyBounded(uri, input);
      source = image.createImageSource(input);
      const info = await source.getImageInfo();
      if (info.mimeType !== 'image/jpeg' && info.mimeType !== 'image/png') {
        throw new AppError('UNSUPPORTED_IMAGE', '请选择 JPEG 或 PNG 图片。');
      }
      const size = scaledSize(info.size.width, info.size.height, ORIGINAL_EDGE);
      const orientation = await source.getImageProperty(image.PropertyKey.ORIENTATION, { index: 0, defaultValue: '1' });
      pixel = await source.createPixelMap({ editable: true, desiredSize: { width: size[0], height: size[1] } });
      await this.orient(pixel, orientation);
      // 只对像素重新编码，不将源 ImageSource 的 EXIF 复制进沙箱长期图片。
      const original = await this.persist(pixel, id, 'garment', originalPath);
      normalized = image.createImageSource(this.absolute(originalPath));
      const thumbSize = scaledSize(original.width, original.height, THUMBNAIL_EDGE);
      thumb = await normalized.createPixelMap({
        desiredSize: { width: thumbSize[0], height: thumbSize[1] }
      });
      const thumbnail = await this.persist(thumb, util.generateRandomUUID(true), 'thumbnail', thumbnailPath);
      const photo = new PreparedPhoto();
      photo.original = original;
      photo.thumbnail = thumbnail;
      return photo;
    } catch (error) {
      this.active.delete(originalPath);
      this.active.delete(thumbnailPath);
      await this.removeIfPresent(this.absolute(originalPath));
      await this.removeIfPresent(this.absolute(thumbnailPath));
      throw error as Error;
    } finally {
      if (thumb) { await thumb.release(); }
      if (pixel) { await pixel.release(); }
      if (normalized) { await normalized.release(); }
      if (source) { await source.release(); }
      await this.removeIfPresent(input);
    }
  }

  release(photo: PreparedPhoto): void {
    this.active.delete(photo.original.relativePath);
    this.active.delete(photo.thumbnail.relativePath);
  }

  async discard(photo: PreparedPhoto): Promise<void> {
    this.release(photo);
    await this.removeIfPresent(this.absolute(photo.original.relativePath));
    await this.removeIfPresent(this.absolute(photo.thumbnail.relativePath));
  }

  async collect(references: string[]): Promise<void> {
    await this.initialize();
    const keep = new Set(references);
    const files = await fs.listFile(`${this.root}/media`);
    for (const file of files) {
      const relative = `media/${file}`;
      if (!/^media\/[0-9a-f-]{36}(-thumb)?\.jpg$/.test(relative) ||
        keep.has(relative) || this.active.has(relative)) { continue; }
      const path = this.absolute(relative);
      const stat = await fs.lstat(path);
      if (stat.isFile() && !stat.isSymbolicLink()) { await fs.unlink(path); }
    }
    const staging = await fs.listFile(`${this.root}/staging`);
    for (const file of staging) {
      if (!/^[0-9a-f-]{36}(-thumb)?\.(input|part)$/.test(file)) { continue; }
      const path = `${this.root}/staging/${file}`;
      const stat = await fs.lstat(path);
      // 暂存 24 小时只是崩溃兜底，正常取消/失败在当前操作中立即清理。
      if (stat.isFile() && !stat.isSymbolicLink() && Date.now() - stat.mtime * 1000 > 86400000) {
        await fs.unlink(path);
      }
    }
  }

  private async copyBounded(uri: string, path: string): Promise<void> {
    const input = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = await fs.stat(input.fd);
      if (stat.size < 8 || stat.size > MAX_BYTES) {
        throw new AppError('IMAGE_SIZE', '图片文件应大于 8 字节且不超过 10 MiB。');
      }
      const output = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        const buffer = new ArrayBuffer(64 * 1024);
        let total = 0;
        let first = true;
        while (true) {
          const count = await fs.read(input.fd, buffer);
          if (count === 0) { break; }
          total += count;
          if (total > MAX_BYTES) { throw new AppError('IMAGE_SIZE', '图片超过 10 MiB。'); }
          if (first) {
            const bytes = new Uint8Array(buffer, 0, count);
            const jpeg = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
            const png = [137, 80, 78, 71, 13, 10, 26, 10].every((value: number, index: number) => bytes[index] === value);
            if (!jpeg && !png) { throw new AppError('INVALID_IMAGE', '文件内容不是有效的 JPEG 或 PNG。'); }
            first = false;
          }
          let written = 0;
          while (written < count) {
            const n = await fs.write(output.fd, buffer.slice(written, count));
            if (n < 1) { throw new AppError('WRITE_FAILED', '图片写入未完成，请释放存储空间后重试。'); }
            written += n;
          }
        }
        if (total !== stat.size) { throw new AppError('IMAGE_CHANGED', '选中的图片已发生变化，请重新选择。'); }
        await fs.fsync(output.fd);
      } finally { await fs.close(output); }
    } finally { await fs.close(input); }
  }

  private async orient(pixel: image.PixelMap, orientation: string): Promise<void> {
    const names = ['Top-left', 'Top-right', 'Bottom-right', 'Bottom-left', 'Left-top', 'Right-top', 'Right-bottom', 'Left-bottom'];
    let value = Number(orientation);
    if (!Number.isInteger(value)) { value = names.indexOf(orientation) + 1; }
    if (value < 1 || value > 8) {
      throw new AppError('IMAGE_ORIENTATION', '无法确认照片方向，请在相册转正后重试，或先手工录入。');
    }
    // EXIF 5/7 为转置方向，先水平翻转再旋转；不能仅处理常见的 6/8。
    if (value === 2 || value === 5 || value === 7) { await pixel.flip(true, false); }
    if (value === 4) { await pixel.flip(false, true); }
    if (value === 3) { await pixel.rotate(180); }
    if (value === 5 || value === 8) { await pixel.rotate(270); }
    if (value === 6 || value === 7) { await pixel.rotate(90); }
  }

  private async persist(pixel: image.PixelMap, id: string, kind: string, relative: string): Promise<MediaAsset> {
    const temp = `${this.root}/staging/${relative.substring(6).replace('.jpg', '.part')}`;
    const packer = image.createImagePacker();
    try {
      const file = await fs.open(temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        await packer.packToFile(pixel, file.fd, { format: 'image/jpeg', quality: 90 });
        await fs.fsync(file.fd);
      } finally { await fs.close(file); }
      const stat = await fs.stat(temp);
      if (stat.size < 1 || stat.size > MAX_BYTES) { throw new AppError('IMAGE_SIZE', '标准化后的照片过大，请选择较小图片。'); }
      const digest = cryptoFramework.createMd('SHA256');
      const fileRead = await fs.open(temp, fs.OpenMode.READ_ONLY);
      try {
        const buffer = new ArrayBuffer(64 * 1024);
        while (true) {
          const count = await fs.read(fileRead.fd, buffer);
          if (count === 0) { break; }
          await digest.update({ data: new Uint8Array(buffer.slice(0, count)) });
        }
      } finally { await fs.close(fileRead); }
      const hash = await digest.digest();
      const info = await pixel.getImageInfo();
      const asset = new MediaAsset();
      asset.id = id;
      asset.kind = kind;
      asset.relativePath = relative;
      asset.width = info.size.width;
      asset.height = info.size.height;
      asset.byteSize = stat.size;
      asset.createdAt = Date.now();
      asset.sha256 = Array.from(hash.data).map((byte: number) => byte.toString(16).padStart(2, '0')).join('');
      await fs.rename(temp, this.absolute(relative));
      return asset;
    } finally {
      await packer.release();
      await this.removeIfPresent(temp);
    }
  }

  private async removeIfPresent(path: string): Promise<void> {
    if (await fs.access(path)) { await fs.unlink(path); }
  }
}
