import { formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Garment, garmentImage } from '../model/Wardrobe';

@Entry({ useSharedStorage: true })
@Component
struct TodayLiveCard {
  @LocalStorageProp('formId') formId: string = '';
  @LocalStorageProp('rect') rect: formInfo.Rect = { left: 0, top: 0, width: 180, height: 180 };
  @LocalStorageLink('items') items: Garment[] = [];
  @LocalStorageProp('caption') caption: string = '今日穿搭';
  @State lifted: boolean = false;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 8 }) {
        Text(this.caption).fontSize(13).fontWeight(FontWeight.Bold).fontColor('#202027')
        if (this.items.length === 0) { Text('暂无可用搭配').fontSize(14).fontColor('#686874').layoutWeight(1) }
        else {
          Row({ space: 5 }) {
            ForEach(this.items, (item: Garment, index: number) => {
              Image(garmentImage(item)).layoutWeight(1).height('100%').objectFit(ImageFit.Contain)
                .translate({ y: this.lifted ? (index % 2 === 0 ? -10 : 8) : 0 })
                .rotate({ angle: this.lifted ? (index % 2 === 0 ? -5 : 5) : 0 })
                .accessibilityText(item.name)
            }, (item: Garment) => item.id)
          }.width('100%').layoutWeight(1)
        }
        Text(this.items.length + ' 件可穿单品').fontSize(11).fontColor('#287A66')
      }.width(this.rect.width).height(this.rect.height).padding(14).backgroundColor('#FFFFFF').borderRadius(8)
        .position({ x: this.rect.left, y: this.rect.top })
        .onAppear(() => this.getUIContext().animateTo({ duration: 650, curve: Curve.EaseInOut, iterations: 4,
          playMode: PlayMode.Alternate }, () => { this.lifted = true; }))
        .onClick(() => {
          formProvider.cancelOverflow(this.formId).catch(() => { hilog.warn(0x1200, 'YiDaCard', 'Close live card failed'); });
        })
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
  }
}
