import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { analyzeRgbaPixels, ColorObservation, GarmentRecognition, GarmentRecognitionInput,
  GarmentRecognitionProvider, GarmentRecognitionService, recognitionFromColor } from './GarmentRecognition';

// @kit 是 SDK 的编译期聚合入口。应用侧显式导入实际使用的成员，
// 不在运行时把整个 Kit 当作 Record 动态解析，避免能力存在却静默降级。
// 本适配器只负责本机图像解码；色类统计仍执行已有纯算法，便于注入平台边界验证。
export class ImageGarmentRecognitionProvider implements GarmentRecognitionProvider {
  async recognize(input: GarmentRecognitionInput): Promise<GarmentRecognition> {
    let file: fileIo.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    let pixels: image.PixelMap | undefined = undefined;
    let observed: ColorObservation | undefined = undefined;
    try {
      file = await fileIo.open(input.uri, fileIo.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const info: image.ImageInfo = await source.getImageInfo();
      if (info.size.width <= 0 || info.size.height <= 0) { return recognitionFromColor(); }
      const ratio: number = Math.min(1, 48 / Math.max(info.size.width, info.size.height));
      pixels = await source.createPixelMap({
        desiredSize: { width: Math.max(1, Math.round(info.size.width * ratio)),
          height: Math.max(1, Math.round(info.size.height * ratio)) },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      const byteCount: number = pixels.getPixelBytesNumber();
      if (!Number.isFinite(byteCount) || byteCount < 4 || byteCount > 4 * 1024 * 1024) {
        return recognitionFromColor();
      }
      const buffer: ArrayBuffer = new ArrayBuffer(byteCount);
      await pixels.readPixelsToBuffer(buffer);
      observed = analyzeRgbaPixels(new Uint8Array(buffer));
    } catch (error) {
      hilog.warn(0x1200, 'YiDaColor', 'Image color unavailable: %{public}s', (error as Error).message);
    } finally {
      // 依次释放本次调用拥有的对象；一个 release 失败也不能阻止其它对象回收或覆盖建议结果。
      if (pixels !== undefined) { await pixels.release().catch(() => {}); }
      if (source !== undefined) { await source.release().catch(() => {}); }
      if (file !== undefined) { await fileIo.close(file).catch(() => {}); }
    }
    return recognitionFromColor(observed);
  }
}

const photoRecognition: GarmentRecognitionService = new GarmentRecognitionService(new ImageGarmentRecognitionProvider());
export function recognizeGarmentPhoto(uri: string): Promise<GarmentRecognition> {
  return photoRecognition.recognize({ uri: uri });
}
