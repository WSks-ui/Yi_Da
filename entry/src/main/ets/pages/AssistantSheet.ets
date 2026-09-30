import { Garment, Outfit, garmentImage } from '../model/Wardrobe';
import { Theme, Type } from '../components/Theme';
import { MaterialPanel } from '../components/MaterialKit';
import { DadaOrb } from '../components/DadaOrb';
import { DadaAction, DadaContext, DadaPage, DadaShortcut, DadaState, TRY_ON_BOUNDARY, dadaGuide, dadaShortcuts } from '../service/DadaContext';

export enum AssistantMessageRole {
  USER = 'user',
  ASSISTANT = 'assistant'
}

export interface AssistantMessage {
  id: string;
  role: AssistantMessageRole;
  text: string;
}

@Component
export struct AssistantSheet {
  @Prop messages: AssistantMessage[] = [];
  @Prop outfits: Outfit[] = [];
  @Prop garments: Garment[] = [];
  @Prop context: DadaContext = { page: DadaPage.TODAY, key: 'today', objectId: '' };
  @Prop state: DadaState = DadaState.IDLE;
  @Prop feedback: string = '';
  @Prop recognitionMessage: string = '';
  @Prop recognitionColor: string = '';
  @Prop recognitionCategory: string = '';
  @Prop busy: boolean = false;
  @State draft: string = '';
  onSubmit: (input: string) => void = () => {};
  onApply: (outfit: Outfit) => void = () => {};
  onQuick: (input: string) => void = () => {};
  onAction: (action: DadaAction, input: string) => void = () => {};

  private imageOf(id: string): ResourceStr {
    const item: Garment | undefined = this.garments.find((entry: Garment) => entry.id === id);
    return item === undefined ? $r('app.media.demo_shirt') : garmentImage(item);
  }

  private send(): void {
    const input: string = this.draft.trim();
    if (input.length === 0 || this.busy) { return; }
    this.draft = '';
    this.onSubmit(input);
  }

  @Builder
  private messageRow(message: AssistantMessage) {
    Row() {
      if (message.role === AssistantMessageRole.ASSISTANT) { Blank().layoutWeight(0.12) }
      Column({ space: Theme.spaceXs }) {
        Text(message.role === AssistantMessageRole.USER ? '你' : '搭搭')
          .fontSize(Type.caption).fontColor(message.role === AssistantMessageRole.USER ? Theme.accent : Theme.secondary)
        Text(message.text).fontSize(Type.bodySmall).fontColor(Theme.text).lineHeight(22).width('100%')
      }.padding(Theme.spaceM).backgroundColor(message.role === AssistantMessageRole.USER
        ? Theme.accentSoft : Theme.surface).borderRadius(Theme.radiusCard)
        .layoutWeight(0.88)
      if (message.role === AssistantMessageRole.USER) { Blank().layoutWeight(0.12) }
    }.width('100%').justifyContent(message.role === AssistantMessageRole.USER ? FlexAlign.End : FlexAlign.Start)
  }

  @Builder
  private outfitCard(outfit: Outfit) {
    MaterialPanel({ contentPadding: Theme.spaceM }) {
      Column({ space: Theme.spaceS }) {
        Row({ space: Theme.spaceS }) {
          Text(`${outfit.occasion} · ${outfit.temperature}℃`).fontSize(Type.cardTitle)
            .fontWeight(FontWeight.Medium).fontColor(Theme.text).layoutWeight(1)
          Text(`${outfit.garmentIds.length} 件`).fontSize(Type.caption).fontColor(Theme.secondary)
        }.width('100%')
        Row({ space: 8 }) {
          ForEach(outfit.garmentIds, (id: string) => {
            Image(this.imageOf(id))
              .height(76).layoutWeight(1).objectFit(ImageFit.Contain).borderRadius(8)
              .backgroundColor(Theme.surfaceSoft)
          }, (id: string) => id)
        }.width('100%')
        Text(outfit.reason).fontSize(Type.caption).fontColor(Theme.secondary).lineHeight(20)
          .maxLines(4).width('100%')
        Text('采用后更新为 ' + outfit.occasion + ' · ' + outfit.temperature + '℃')
          .fontSize(Type.caption).fontColor(Theme.secondary).width('100%')
        Button('采用这套', { type: ButtonType.Normal }).width('100%').height(Theme.buttonHeight)
          .borderRadius(Theme.radiusPill).backgroundColor(Theme.accent).fontColor(Theme.onAccent)
          .enabled(!this.busy).onClick(() => this.onApply(outfit))
      }.width('100%')
    }
  }

  build() {
    Column({ space: Theme.spaceM }) {
      Row() {
        DadaOrb({ diameter: 40, state: this.state, pulseKey: this.context.key })
        Column({ space: Theme.spaceXs }) {
          Text('搭搭').fontSize(Type.title).fontWeight(FontWeight.Bold).fontColor(Theme.text)
          Text('用已有衣物，发现新的搭配').fontSize(Type.caption).fontColor(Theme.secondary)
        }.margin({ left: 12 }).alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%')
      Text(dadaGuide(this.context.page)).fontSize(Type.bodySmall).fontColor(Theme.secondary)
        .lineHeight(22).width('100%')
      if (this.context.page === DadaPage.TRY_ON) {
        Text(TRY_ON_BOUNDARY).fontSize(Type.caption).fontColor(Theme.accent).width('100%')
          .padding(10).backgroundColor(Theme.accentSoft).borderRadius(Theme.radiusCard)
      }
      if (this.context.page === DadaPage.IMPORT && this.recognitionMessage.length > 0) {
        Column({ space: 6 }) {
          Text(this.recognitionMessage).fontSize(Type.bodySmall).fontColor(Theme.text)
          if (this.recognitionColor.length > 0) { Text('颜色建议：' + this.recognitionColor).fontSize(Type.caption).fontColor(Theme.accent) }
          if (this.recognitionCategory.length > 0) { Text('品类建议：' + this.recognitionCategory).fontSize(Type.caption).fontColor(Theme.accent) }
        }.width('100%').alignItems(HorizontalAlign.Start).padding(12)
          .backgroundColor(Theme.accentSoft).borderRadius(Theme.radiusCard)
      }
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(dadaShortcuts(this.context.page), (shortcut: DadaShortcut) => {
          Button(shortcut.label, { type: ButtonType.Normal }).fontSize(Type.buttonSmall).height(48)
            .margin(Theme.spaceXs).borderRadius(Theme.radiusPill).backgroundColor(Theme.accentSoft)
            .fontColor(Theme.accent).enabled(!this.busy)
            .onClick(() => this.onAction(shortcut.action, shortcut.input))
        }, (shortcut: DadaShortcut) => shortcut.label)
      }.width('100%')
      if (this.feedback.length > 0) {
        Text(this.feedback).fontSize(Type.bodySmall).fontColor(this.state === DadaState.ERROR ? Theme.warning : Theme.accent)
          .lineHeight(22).width('100%')
      }

      ForEach(this.messages, (message: AssistantMessage) => this.messageRow(message),
        (message: AssistantMessage) => message.id)
      if (this.outfits.length > 0) {
        Text('本轮方案').fontSize(Type.cardTitle).fontWeight(FontWeight.Medium).fontColor(Theme.text)
          .width('100%')
        ForEach(this.outfits.slice(0, 3), (outfit: Outfit) => this.outfitCard(outfit),
          (outfit: Outfit) => outfit.id)
      }

      Row({ space: Theme.spaceS }) {
        TextInput({ text: this.draft, placeholder: '例如：社团活动，18度' }).layoutWeight(1)
          .height(Theme.buttonHeight).fontSize(Type.bodySmall).backgroundColor(Theme.surfaceSoft)
          .borderRadius(Theme.radiusInput).onChange((value: string) => this.draft = value)
          .enabled(!this.busy).onSubmit(() => this.send())
        Button('发送', { type: ButtonType.Normal }).height(Theme.buttonHeight).width(72)
          .borderRadius(Theme.radiusPill).backgroundColor(Theme.accent).fontColor(Theme.onAccent)
          .enabled(!this.busy).onClick(() => this.send())
      }.width('100%')
    }.width('100%')
  }
}
