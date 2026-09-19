import { image } from '@kit.ImageKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';

// HMS 共享模块仅在用户请求时动态加载；没有能力的模拟器仍可导入和使用原图。
interface SegmentedSubject { foregroundImage: image.PixelMap; }
interface SegmentationResult { subjectCount: number; fullSubject: SegmentedSubject; }
interface SegmentationInput { pixelMap: image.PixelMap; }
interface SegmentationOptions { maxCount: number; enableSubjectDetails: boolean; enableSubjectForegroundImage: boolean; }
interface SegmentationService {
  init(): Promise<boolean>;
  doSegmentation(input: SegmentationInput, options: SegmentationOptions): Promise<SegmentationResult>;
  release(): Promise<void>;
}

export function cutoutSupported(): boolean { return canIUse('SystemCapability.AI.Vision.SubjectSegmentation'); }

// 全局最多同时一个原生抠图任务。
// 说明：这里只做"同一时刻只跑一个"的互斥，不假装能取消已经下发的原生任务——
// 底层服务没有取消接口，把标记当成真的终止会写出错误的并发假设。
// 占用从请求进入的同步时刻开始，因此单件编辑与批量录入不会重叠占用同一服务。
let cutoutBusy: boolean = false;

export function cutoutInFlight(): boolean { return cutoutBusy; }

// 返回新 PNG，不覆盖原图；调用方在确认保存前同时持有原图和结果，取消时清理临时文件。
// target 由调用方（仓储）生成并拥有，服务本身不再自行拼文件名。
export async function cutoutGarment(uri: string, target: string): Promise<string> {
  if (!cutoutSupported()) { throw new Error('当前设备不支持主体抠图，可继续使用原图'); }
  if (cutoutBusy) { throw new Error('已有一个抠图任务在进行，请等它结束再试'); }
  cutoutBusy = true;
  let service: SegmentationService | undefined = undefined;
  let input: image.PixelMap | undefined = undefined;
  let foreground: image.PixelMap | undefined = undefined;
  let initialized: boolean = false;
  let file: fs.File | undefined = undefined;
  let source: image.ImageSource | undefined = undefined;
  let created: boolean = false;
  try {
    try {
      const kit: Record<string, object> = await import('@kit.CoreVisionKit') as Record<string, object>;
      service = kit['subjectSegmentation'] as SegmentationService;
    } catch (error) { throw new Error('当前设备未提供抠图服务，可继续使用原图'); }
    file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    source = image.createImageSource(file.fd);
    const info: image.ImageInfo = await source.getImageInfo();
    const ratio: number = Math.min(1, 1600 / Math.max(info.size.width, info.size.height));
    input = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      desiredSize: { width: Math.max(1, Math.round(info.size.width * ratio)), height: Math.max(1, Math.round(info.size.height * ratio)) } });
    initialized = await service.init();
    if (!initialized) { throw new Error('抠图服务尚不可用，请重试或保留原图'); }
    const result: SegmentationResult = await service.doSegmentation({ pixelMap: input },
      { maxCount: 1, enableSubjectDetails: false, enableSubjectForegroundImage: true });
    if (result.fullSubject) { foreground = result.fullSubject.foregroundImage; }
    if (result.subjectCount === 0 || !foreground) { throw new Error('没有找到清晰主体，请换一张照片或保留原图'); }
    const packer: image.ImagePacker = image.createImagePacker();
    try {
      const output: fs.File = await fs.open(target, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      created = true;
      try { await packer.packToFile(foreground, output.fd, { format: 'image/png', quality: 100 }); }
      finally { await fs.close(output); }
    } finally { await packer.release().catch(() => {}); }
    return fileUri.getUriFromPath(target);
  } catch (error) {
    // 打包中断时不能把半张 PNG 留给下一次录入；保留原错误供界面解释失败原因。
    if (created) { await fs.unlink(target).catch(() => {}); }
    throw new Error((error as Error).message || '主体抠图失败，请重试或保留原图');
  } finally {
    // 清理彼此独立，一个对象释放失败也必须继续释放其余图像、文件与原生服务。
    if (foreground && foreground !== input) { await foreground.release().catch(() => {}); }
    if (input) { await input.release().catch(() => {}); }
    if (source) { await source.release().catch(() => {}); }
    if (file) { await fs.close(file).catch(() => {}); }
    if (initialized && service) { await service.release().catch(() => {}); }
    cutoutBusy = false;
  }
}
