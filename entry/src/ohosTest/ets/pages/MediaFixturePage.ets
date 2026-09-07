import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FixtureGalleryWriter } from '../fixtures/FixtureGalleryWriter';

@Entry
@ComponentV2
struct MediaFixturePage {
  @Local imageUri: string = '';
  @Local status: string = '正在准备授权测试素材';
  @Local busy: boolean = true;
  @Local saved: number = 0;
  private writer?: FixtureGalleryWriter;

  async aboutToAppear(): Promise<void> {
    this.writer = new FixtureGalleryWriter(this.getUIContext().getHostContext() as common.UIAbilityContext);
    try {
      this.imageUri = await this.writer.prepare();
      this.status = '测试素材就绪';
    } catch (error) { this.status = `准备失败，代码 ${(error as BusinessError).code}`; }
    finally { this.busy = false; }
  }

  build() {
    Column({ space: 20 }) {
      Text('艺搭 · 图库测试夹具').fontSize(24)
      if (this.imageUri) { Image(this.imageUri).width('80%').height(280).objectFit(ImageFit.Contain) }
      Text('Lateiner / T-shirt.jpg / CC BY-SA 3.0').fontSize(14)
      Text(this.status).fontSize(15).id('fixtureStatus')
      Text(`已写入 ${this.saved} 张测试照片`).fontSize(16)
      SaveButton().id('fixtureSave').enabled(!this.busy && !!this.imageUri)
        .onClick(async (_event: ClickEvent, result: SaveButtonOnClickResult) => {
          if (result !== SaveButtonOnClickResult.SUCCESS || this.busy || !this.writer) {
            this.status = '保存已取消或未授权';
            return;
          }
          this.busy = true;
          try {
            await this.writer.saveOne();
            this.saved++;
            this.status = `已保存 ${this.writer.lastTitle}`;
          } catch (error) { this.status = `保存失败，代码 ${(error as BusinessError).code}`; }
          finally { this.busy = false; }
        })
    }.padding(24).width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#F6F7F8')
  }
}
