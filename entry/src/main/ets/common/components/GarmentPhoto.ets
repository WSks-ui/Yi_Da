import { fileUri } from '@kit.CoreFileKit';
import { Palette } from './Palette';

@ComponentV2
export struct GarmentPhoto {
  @Param path: string = '';
  @Param label: string = '';
  @Local failed: boolean = false;

  @Monitor('path')
  resetFailure(): void { this.failed = false; }

  build() {
    Stack() {
      if (this.path && !this.failed) {
        // 文件 API 使用绝对路径，ArkUI Image 使用 file URI；数据库仍只保存沙箱相对路径。
        Image(fileUri.getUriFromPath(this.path)).width('100%').height('100%').objectFit(ImageFit.Contain)
          .accessibilityText(this.label).onError(() => { this.failed = true; })
      } else {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.ohos_photo')).fontSize(28).fontColor([Palette.muted])
          Text(this.failed ? '照片不可读取' : '未添加照片').fontSize(13).fontColor(Palette.muted)
        }
      }
    }.width('100%').height('100%').backgroundColor(Palette.panel).borderRadius(6).clip(true)
  }
}
