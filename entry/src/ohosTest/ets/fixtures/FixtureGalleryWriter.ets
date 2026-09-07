import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

export class FixtureGalleryWriter {
  private context: common.UIAbilityContext;
  private path: string;
  private counter: number = 0;
  private runId: number = Date.now();
  lastTitle: string = '';

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.path = `${context.cacheDir}/yida-licensed-picker-fixture.jpg`;
  }

  async prepare(): Promise<string> {
    const bytes = await this.context.createModuleContext('entry').resourceManager.getRawFileContent('demo/tshirt.jpg');
    const file = await fs.open(this.path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    try {
      let offset = 0;
      while (offset < bytes.byteLength) {
        const written = await fs.write(file.fd, bytes.buffer.slice(bytes.byteOffset + offset, bytes.byteOffset + bytes.byteLength));
        if (written < 1) { throw new Error('Fixture write incomplete'); }
        offset += written;
      }
    } finally { await fs.close(file); }
    return fileUri.getUriFromPath(this.path);
  }

  async saveOne(): Promise<void> {
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    try {
      // 必须由 SaveButton SUCCESS 回调触发，仅创建明确命名的授权测试照片。
      // 不请求 READ_IMAGEVIDEO/WRITE_IMAGEVIDEO，不枚举或修改现有相册照片。
      this.lastTitle = `YiDa_QA_${this.runId}_${++this.counter}`;
      const uri = await helper.createPhotoAsset(photoAccessHelper.PhotoType.IMAGE, 'jpg', this.lastTitle);
      const input = await fs.open(this.path, fs.OpenMode.READ_ONLY);
      try {
        const output = await fs.open(uri, fs.OpenMode.WRITE_ONLY);
        try { await fs.copyFile(input.fd, output.fd); } finally { await fs.close(output); }
      } finally { await fs.close(input); }
    } finally { await helper.release(); }
  }
}
