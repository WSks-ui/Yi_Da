import { Outfit } from '../model/Wardrobe';
import { Theme, Type } from '../components/Theme';
import { MaterialPanel } from '../components/MaterialKit';

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
  @Prop busy: boolean = false;
  @State draft: string = '';
  onSubmit: (input: string) => void = () => {};
  onApply: (outfit: Outfit) => void = () => {};
  onQuick: (input: string) => void = () => {};

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
        Text(message.role === AssistantMessageRole.USER ? '你' : '易搭助手')
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
        Text(outfit.reason).fontSize(Type.caption).fontColor(Theme.secondary).lineHeight(20)
          .maxLines(4).width('100%')
        Button('采用这套', { type: ButtonType.Normal }).width('100%').height(Theme.buttonCompact)
          .borderRadius(Theme.radiusPill).backgroundColor(Theme.accent).fontColor(Theme.onAccent)
          .enabled(!this.busy).onClick(() => this.onApply(outfit))
      }.width('100%')
    }
  }

  build() {
    Column({ space: Theme.spaceM }) {
      Row() {
        Column({ space: Theme.spaceXs }) {
          Text('易搭助手').fontSize(Type.title).fontWeight(FontWeight.Bold).fontColor(Theme.text)
          Text('离线运行，调用你的衣橱和推荐规则').fontSize(Type.caption).fontColor(Theme.secondary)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text('可解释').fontSize(Type.caption).fontColor(Theme.accent)
      }.width('100%')

      if (this.messages.length <= 1) {
        Text('你可以直接说“明天上课怎么穿”“约会，22度”或“换一件上装”。')
          .fontSize(Type.bodySmall).fontColor(Theme.secondary).lineHeight(22).width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(['明天上课怎么穿', '约会，22度', '换一件上装', '帮助'], (prompt: string) => {
            Button(prompt, { type: ButtonType.Normal }).fontSize(Type.buttonSmall).height(36)
              .margin(Theme.spaceXs).borderRadius(Theme.radiusPill).backgroundColor(Theme.accentSoft)
              .fontColor(Theme.accent).onClick(() => this.onQuick(prompt))
          }, (prompt: string) => prompt)
        }.width('100%')
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
          .onSubmit(() => this.send())
        Button('发送', { type: ButtonType.Normal }).height(Theme.buttonHeight).width(72)
          .borderRadius(Theme.radiusPill).backgroundColor(Theme.accent).fontColor(Theme.onAccent)
          .enabled(!this.busy).onClick(() => this.send())
      }.width('100%')
    }.width('100%').padding({ left: Theme.spaceXl, right: Theme.spaceXl, top: Theme.spaceXl, bottom: Theme.spaceXxl })
  }
}
