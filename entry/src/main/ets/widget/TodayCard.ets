import { cardImage } from './CardData';

let cardStorage: LocalStorage = new LocalStorage();

@Entry(cardStorage)
@Component
struct TodayCard {
  @LocalStorageProp('caption') caption: string = '上课 · 24℃';
  @LocalStorageProp('garmentName') garmentName: string = '今日穿搭';
  @LocalStorageProp('imageKey') imageKey: string = '';
  @LocalStorageProp('count') count: number = 0;
  @LocalStorageProp('hasOutfit') hasOutfit: boolean = false;

  build() {
    Column({ space: 6 }) {
      Text('艺搭').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#202027').width('100%')
      if (this.imageKey.length > 0) {
        Image(cardImage(this.imageKey)).layoutWeight(1).width('100%').objectFit(ImageFit.Contain)
          .onClick(() => postCardAction(this, { action: 'message', params: { message: 'expand' } }))
      } else {
        Text(this.hasOutfit ? this.garmentName : '暂无可用搭配').fontSize(14).fontColor('#6F5CF4')
          .layoutWeight(1).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => postCardAction(this, { action: 'message', params: { message: 'expand' } }))
      }
      Text(this.caption).fontSize(12).fontColor('#686874').maxLines(1)
      Row() {
        Text(this.count + ' 件单品').fontSize(10).fontColor('#686874').layoutWeight(1)
        Text('查看搭配').fontSize(12).fontColor('#6F5CF4').padding({ top: 6, bottom: 6 })
          .onClick(() => postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { fromCard: true } }))
      }.width('100%')
    }.padding(12).width('100%').height('100%').backgroundColor('#FFFFFF')
  }
}
