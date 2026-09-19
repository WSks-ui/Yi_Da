import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';

// 调用方拥有 PixelMap，本函数只拥有打包器与文件句柄，所有路径都由沙箱生成。
export async function exportOutfit(pixelMap: image.PixelMap, context: common.UIAbilityContext): Promise<string> {
  const path: string = context.cacheDir + '/outfit_' + Date.now() + '.png';
  const packer: image.ImagePacker = image.createImagePacker();
  try {
    const file: fs.File = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try { await packer.packToFile(pixelMap, file.fd, { format: 'image/png', quality: 100 }); }
    finally { await fs.close(file); }
  } catch (error) {
    await fs.unlink(path).catch(() => {});
    throw new Error('搭配图片写入失败');
  } finally { await packer.release().catch(() => {}); }
  // 缓存只保留最近十张，当前导出使用独立文件名，不覆盖仍被分享面板读取的图片。
  const files: string[] = (await fs.listFile(context.cacheDir).catch((): string[] => []))
    .filter((name: string) => /^outfit_\d+\.png$/.test(name)).sort();
  for (const name of files.slice(0, Math.max(0, files.length - 10))) {
    await fs.unlink(context.cacheDir + '/' + name).catch(() => {});
  }
  return fileUri.getUriFromPath(path);
}

export async function shareOutfitImage(uri: string, context: common.UIAbilityContext,
  title: string = '艺起搭 · 我的搭配'): Promise<void> {
  const data: systemShare.SharedData = new systemShare.SharedData({
    utd: uniformTypeDescriptor.UniformDataType.PNG, uri: uri, title: title
  });
  await new systemShare.ShareController(data).show(context, { previewMode: systemShare.SharePreviewMode.DEFAULT });
}

export async function saveOutfitToAlbum(uri: string, context: common.UIAbilityContext): Promise<boolean> {
  const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
  try {
    const targets: string[] = await helper.showAssetsCreationDialog([uri], [{
      title: '艺起搭_' + Date.now(), fileNameExtension: 'png', photoType: photoAccessHelper.PhotoType.IMAGE
    }]);
    if (targets.length === 0) { return false; }
    const source: fs.File = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      const target: fs.File = await fs.open(targets[0], fs.OpenMode.WRITE_ONLY);
      try { await fs.copyFile(source.fd, target.fd); }
      finally { await fs.close(target); }
    } finally { await fs.close(source); }
    return true;
  } finally { await helper.release(); }
}
