import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { MAX_EDGE, MAX_SOURCE_BYTES, MAX_SOURCE_PIXELS } from './GarmentImport';

export interface BundledGarmentPhoto {
  id: string;
  label: string;
  resource: Resource;
}

// 列表只收录随应用打包、适合单件录入的衣物照片；资源名不会由外部输入拼接。
export const BUNDLED_GARMENT_PHOTOS: BundledGarmentPhoto[] = [
  { id: 'demo_shirt', label: '示例衬衫', resource: $r('app.media.demo_shirt') },
  { id: 'demo_jacket', label: '示例外套', resource: $r('app.media.demo_jacket') },
  { id: 'demo_sneakers', label: '示例运动鞋', resource: $r('app.media.demo_sneakers') }
];

// marker 只在当前录入会话中标识所选样片；保存衣物时必须使用复制进沙箱后返回的文件 URI。
const BUNDLED_PHOTO_SOURCE_PREFIX: string = 'bundled-garment-photo:';

function findBundledGarmentPhoto(id: string): BundledGarmentPhoto | undefined {
  for (const photo of BUNDLED_GARMENT_PHOTOS) {
    if (photo.id === id) { return photo; }
  }
  return undefined;
}

export function bundledPhotoSource(id: string): string {
  if (!findBundledGarmentPhoto(id)) { return ''; }
  return BUNDLED_PHOTO_SOURCE_PREFIX + id;
}

export function bundledPhotoId(source: string): string {
  if (source.indexOf(BUNDLED_PHOTO_SOURCE_PREFIX) !== 0) { return ''; }
  const id: string = source.slice(BUNDLED_PHOTO_SOURCE_PREFIX.length);
  return findBundledGarmentPhoto(id) ? id : '';
}

// 将白名单中的打包照片解码并复制到调用方为本次录入生成的沙箱路径。
// marker 与构建资源 ID 都不作为衣物的持久图片地址，持久化只使用本函数返回的文件 URI。
export async function importBundledGarmentPhoto(context: common.UIAbilityContext, id: string,
  targetPath: string): Promise<string> {
  const photo: BundledGarmentPhoto | undefined = findBundledGarmentPhoto(id);
  if (!photo) { throw new Error('这张示例衣物照片暂不可用'); }

  let imageSource: image.ImageSource | undefined = undefined;
  let pixelMap: image.PixelMap | undefined = undefined;
  let packer: image.ImagePacker | undefined = undefined;
  let created: boolean = false;
  try {
    const bytes: Uint8Array = await context.resourceManager.getMediaContent(photo.resource.id);
    if (bytes.byteLength > MAX_SOURCE_BYTES) { throw new Error('示例衣物照片超过导入大小限制'); }

    imageSource = image.createImageSource(bytes.buffer as ArrayBuffer);
    const info: image.ImageInfo = await imageSource.getImageInfo();
    if (!info || !info.size || info.size.width <= 0 || info.size.height <= 0) {
      throw new Error('这张示例衣物照片无法识别');
    }
    if (info.size.width * info.size.height > MAX_SOURCE_PIXELS) {
      throw new Error('示例衣物照片分辨率超过导入限制');
    }

    // 与普通衣物照片使用相同的像素预算：只缩小长边超过上限的图片，小图保持原尺寸。
    const longest: number = Math.max(info.size.width, info.size.height);
    const ratio: number = longest > MAX_EDGE ? MAX_EDGE / longest : 1;
    const width: number = Math.max(1, Math.round(info.size.width * ratio));
    const height: number = Math.max(1, Math.round(info.size.height * ratio));
    pixelMap = await imageSource.createPixelMap({ desiredSize: { width: width, height: height },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
    if (!pixelMap) { throw new Error('这张示例衣物照片无法解码'); }

    packer = image.createImagePacker();
    const output: fs.File = await fs.open(targetPath,
      fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    created = true;
    try {
      await packer.packToFile(pixelMap, output.fd, { format: 'image/png', quality: 100 });
    } finally {
      await fs.close(output);
    }
    return fileUri.getUriFromPath(targetPath);
  } catch (error) {
    // 创建或截断目标文件后若编码失败，移除半成品，避免后续录入误用不完整图片。
    if (created) { await fs.unlink(targetPath).catch(() => {}); }
    throw new Error((error as Error).message || '未能导入这张示例衣物照片');
  } finally {
    // 每种原生图像对象分别释放，单项释放失败也不能阻断其他资源的清理。
    if (packer) { await packer.release().catch(() => {}); }
    if (pixelMap) { await pixelMap.release().catch(() => {}); }
    if (imageSource) { await imageSource.release().catch(() => {}); }
  }
}
