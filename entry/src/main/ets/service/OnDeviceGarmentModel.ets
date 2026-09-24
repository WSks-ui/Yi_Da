import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ClothingCandidate, chooseClothingCandidate, normalizeOpenImagePixels } from './OpenImageClothing';

const MODEL_FILE: string = 'mobilenetv2.ms';

// 仅在用户点“端侧分析”时加载约 14 MB 的官方模型。CPU 模式不依赖 NPU；
// 模型是 ImageNet 通用分类器，不承诺专用服装或材质识别。
export class OnDeviceGarmentModel {
  private modelPromise: Promise<mindSporeLite.Model> | undefined = undefined;

  private load(context: common.UIAbilityContext): Promise<mindSporeLite.Model> {
    if (this.modelPromise === undefined) {
      this.modelPromise = (async (): Promise<mindSporeLite.Model> => {
        const bytes: Uint8Array = await context.resourceManager.getRawFileContent(MODEL_FILE);
        const buffer: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset,
          bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
        const options: mindSporeLite.Context = { target: ['cpu'], cpu: { threadNum: 2 } };
        return mindSporeLite.loadModelFromBuffer(buffer, options);
      })();
    }
    return this.modelPromise;
  }

  async classify(uri: string, context: common.UIAbilityContext): Promise<ClothingCandidate | undefined> {
    let file: fileIo.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    let pixels: image.PixelMap | undefined = undefined;
    try {
      file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      pixels = await source.createPixelMap({
        desiredSize: { width: 224, height: 224 },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      const info: image.ImageInfo = await pixels.getImageInfo();
      if (info.size.width !== 224 || info.size.height !== 224) { return undefined; }
      const raw: ArrayBuffer = new ArrayBuffer(224 * 224 * 4);
      await pixels.readPixelsToBuffer(raw);
      const model: mindSporeLite.Model = await this.load(context);
      const inputs: mindSporeLite.MSTensor[] = model.getInputs();
      if (inputs.length !== 1 || inputs[0].dataSize !== 224 * 224 * 3 * 4) { return undefined; }
      inputs[0].setData(normalizeOpenImagePixels(new Uint8Array(raw)).buffer as ArrayBuffer);
      const outputs: mindSporeLite.MSTensor[] = await model.predict(inputs);
      if (outputs.length === 0) { return undefined; }
      const scores: Float32Array = new Float32Array(outputs[0].getData());
      let maximum: number = 0;
      for (const score of scores) { if (Number.isFinite(score) && score > maximum) { maximum = score; } }
      // hilog 的浮点占位符在部分 API 26 日志查看器中会原样显示，转成
      // 万分比整数后既能保留调试价值，也不会影响用户界面。
      const maximumX10000: number = Math.round(maximum * 10000);
      hilog.info(0x1200, 'YiDaModel', 'model output elements=%{public}d max_x10000=%{public}d',
        scores.length, maximumX10000);
      return chooseClothingCandidate(scores);
    } finally {
      if (pixels !== undefined) { await pixels.release().catch(() => {}); }
      if (source !== undefined) { await source.release().catch(() => {}); }
      if (file !== undefined) { await fileIo.close(file).catch(() => {}); }
    }
  }
}

export const garmentModel: OnDeviceGarmentModel = new OnDeviceGarmentModel();
