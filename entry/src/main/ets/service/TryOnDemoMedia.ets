import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { findDemoScene, TryOnDemoPoseId } from './TryOnDemo';
import { exportOutfit } from './OutfitExport';

export interface DemoImages {
  person: Resource;
  garment: Resource;
  result: Resource;
}

// 只从固定场景解析打包资源，不把任意衣橱照片映射为样片。
// 持久化只存 sceneId，禁止把构建时分配的 Resource.id 写进快照。
export function demoImages(sceneId: string): DemoImages {
  if (sceneId === 'denim_skirt') {
    return { person: $r('app.media.tryon_denim_person'), garment: $r('app.media.tryon_denim_garment'),
      result: $r('app.media.tryon_denim_result') };
  }
  if (sceneId === 'navy_top') {
    return { person: $r('app.media.tryon_navy_person'), garment: $r('app.media.tryon_navy_garment'),
      result: $r('app.media.tryon_navy_result') };
  }
  if (sceneId === 'red_dress') {
    return { person: $r('app.media.tryon_red_person'), garment: $r('app.media.tryon_red_garment'),
      result: $r('app.media.tryon_red_result') };
  }
  throw new Error('这组试穿样片暂不可用');
}

// 媒体映射只返回当前确实随包提供的视角。侧面与背面先留空，
// 新素材到位后在这里按 sceneId + poseId 增加映射，页面不需要猜资源名称。
export function demoPoseResult(sceneId: string, poseId: TryOnDemoPoseId): Resource | undefined {
  if (!findDemoScene(sceneId)) { return undefined; }
  if (poseId === 'front') { return demoImages(sceneId).result; }
  return undefined;
}

// 导出原始样片而非屏幕截图，图片中自带 DEMO 与素材来源标记。
// ImageSource 和 PixelMap 均由本函数拥有，解码或写文件失败也必须释放。
export async function exportDemoResult(sceneId: string, context: common.UIAbilityContext): Promise<string> {
  if (!findDemoScene(sceneId)) { throw new Error('这组试穿样片暂不可用'); }
  const bytes: Uint8Array = await context.resourceManager.getMediaContent(demoImages(sceneId).result.id);
  const source: image.ImageSource = image.createImageSource(bytes.buffer as ArrayBuffer);
  let pixels: image.PixelMap | undefined = undefined;
  try {
    pixels = await source.createPixelMap();
    return await exportOutfit(pixels, context);
  } finally {
    if (pixels) { await pixels.release(); }
    await source.release();
  }
}
