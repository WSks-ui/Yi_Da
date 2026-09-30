import { Garment, Outfit, garmentImage } from '../model/Wardrobe';
import { Theme, Type } from '../components/Theme';
import { DadaOrb } from '../components/DadaOrb';
import { DadaAction, DadaContext, DadaPage, DadaShortcut, DadaState, TRY_ON_BOUNDARY, dadaShortcuts } from '../service/DadaContext';
import { AssistantReplyStage, AssistantReplyView, assistantReplyActive, emptyAssistantReply } from '../service/AssistantReplyController';

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
  @Prop @Watch('onMessagesChanged') messages: AssistantMessage[] = [];
  @Prop @Watch('onReplyChanged') reply: AssistantReplyView = emptyAssistantReply();
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
  @State expandedReasonId: string = '';
  private chatScroller: Scroller = new Scroller();
  private scrollTimer: number = -1;
  private alive: boolean = false;
  private followLatest: boolean = true;
  onClose: () => void = () => {};
  onSubmit: (input: string) => void = () => {};
  onApply: (outfit: Outfit) => void = () => {};
  onQuick: (input: string) => void = () => {};
  onAction: (action: DadaAction, input: string) => void = () => {};

  aboutToAppear(): void { this.alive = true; this.queueScroll(true); }
  aboutToDisappear(): void {
    this.alive = false;
    if (this.scrollTimer >= 0) { clearTimeout(this.scrollTimer); this.scrollTimer = -1; }
  }
  onMessagesChanged(): void { this.queueScroll(true); }
  onReplyChanged(): void { this.queueScroll(false); }
  // 输入区不参与滚动。用户翻看旧消息时停止自动跟随，回到末尾或发送新问题后恢复。
  private queueScroll(force: boolean): void {
    if (force) { this.followLatest = true; }
    if (this.scrollTimer >= 0) { clearTimeout(this.scrollTimer); }
    if (!this.alive) { return; }
    this.scrollTimer = setTimeout(() => {
      this.scrollTimer = -1;
      if (this.alive && this.followLatest) { this.chatScroller.scrollEdge(Edge.Bottom); }
    }, 26);
  }
  private displayedText(message: AssistantMessage): string {
    return message.id === this.reply.messageId && assistantReplyActive(this.reply) ? this.reply.text : message.text;
  }
  private quick(shortcut: DadaShortcut): void {
    if (this.busy || assistantReplyActive(this.reply)) { return; }
    if (shortcut.action === DadaAction.GUIDE) { this.onSubmit(shortcut.label); }
    else { this.onAction(shortcut.action, shortcut.input); }
  }

  private imageOf(id: string): ResourceStr {
    const item: Garment | undefined = this.garments.find((entry: Garment) => entry.id === id);
    return item === undefined ? $r('app.media.demo_shirt') : garmentImage(item);
  }

  private send(): void {
    const input: string = this.draft.trim();
    if (input.length === 0 || this.busy || assistantReplyActive(this.reply)) { return; }
    this.draft = '';
    this.onSubmit(input);
  }

  @Builder
  private messageRow(message: AssistantMessage) {
    Row() {
      if (message.role === AssistantMessageRole.USER) { Blank().layoutWeight(1) }
      Column() {
        if (message.id === this.reply.messageId && this.reply.stage === AssistantReplyStage.WAITING) {
          Row({ space: 5 }) {
            Circle().width(5).height(5).fill(Theme.secondary).opacity(0.4)
            Circle().width(5).height(5).fill(Theme.secondary).opacity(0.7)
            Circle().width(5).height(5).fill(Theme.secondary)
          }.height(24).accessibilityText('搭搭正在回复')
        } else {
          Text(this.displayedText(message)).fontSize(Type.body).fontColor(Theme.text).textAlign(TextAlign.Start)
        }
      }.constraintSize({ maxWidth: '86%' }).alignItems(HorizontalAlign.Start)
        .padding(message.role === AssistantMessageRole.USER ? 12 : { top: 8, bottom: 8 })
        .backgroundColor(message.role === AssistantMessageRole.USER ? Theme.surfaceSoft : Color.Transparent)
        .borderRadius({ topLeft: 10, topRight: 10, bottomLeft: 10, bottomRight: 4 })
      if (message.role === AssistantMessageRole.ASSISTANT) { Blank().layoutWeight(1) }
    }.width('100%').alignItems(VerticalAlign.Top)
  }

  @Builder
  private outfitCard(outfit: Outfit) {
    Column({ space: 10 }) {
      Row() {
        Text(outfit.occasion).fontSize(Type.bodySmall).fontWeight(FontWeight.Medium).fontColor(Theme.text)
        Blank()
        Text(`${outfit.temperature}℃`).fontSize(Type.bodySmall).fontColor(Theme.secondary)
      }.width('100%')
        Row({ space: 8 }) {
          ForEach(outfit.garmentIds, (id: string) => {
            Image(this.imageOf(id))
              .height(72).layoutWeight(1).objectFit(ImageFit.Contain).borderRadius(6)
              .backgroundColor(Theme.surfaceSoft)
          }, (id: string) => id)
        }.width('100%')
      if (this.expandedReasonId === outfit.id) {
        Text(outfit.reason).fontSize(Type.bodySmall).fontColor(Theme.secondary).width('100%')
      }
      Row() {
        Button(this.expandedReasonId === outfit.id ? '收起理由' : '搭配理由', { type: ButtonType.Normal })
          .fontSize(Type.caption).height(40).backgroundColor(Color.Transparent).fontColor(Theme.secondary)
          .onClick(() => { this.expandedReasonId = this.expandedReasonId === outfit.id ? '' : outfit.id; })
        Blank()
        Button('采用这套', { type: ButtonType.Normal }).width(112).height(40).fontSize(Type.buttonSmall)
          .borderRadius(6).backgroundColor(Theme.accent).fontColor(Theme.onAccent)
          .enabled(!this.busy && !assistantReplyActive(this.reply)).onClick(() => this.onApply(outfit))
      }.width('100%')
    }.width('100%').padding(12).backgroundColor(Theme.surface)
      .border({ width: 1, color: Theme.line }).borderRadius(10)
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        DadaOrb({ diameter: 24, state: assistantReplyActive(this.reply) ? DadaState.IDLE : this.state, pulseKey: this.context.key })
        Text('搭搭').fontSize(Type.title).fontWeight(FontWeight.Medium).fontColor(Theme.text)
        Blank()
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([Theme.secondary])
        }.width(48).height(48).borderRadius(8).backgroundColor(Color.Transparent)
          .accessibilityText('关闭搭搭').onClick(() => this.onClose())
      }.width('100%').height(48)
      if (this.context.page === DadaPage.TRY_ON) {
        Text(TRY_ON_BOUNDARY).fontSize(Type.caption).fontColor(Theme.secondary).width('100%')
      }
      Scroll(this.chatScroller) {
        Column({ space: 12 }) {
          ForEach(this.messages, (message: AssistantMessage) => this.messageRow(message),
            (message: AssistantMessage) => message.id)
          if (!assistantReplyActive(this.reply)) {
            ForEach(this.outfits.slice(0, 3), (outfit: Outfit) => this.outfitCard(outfit),
              (outfit: Outfit) => outfit.id)
            if (this.context.page === DadaPage.IMPORT && this.recognitionMessage.length > 0) {
              Column({ space: 8 }) {
                Text(this.recognitionMessage).fontSize(Type.bodySmall).fontColor(Theme.secondary)
                if (this.recognitionColor.length > 0) {
                  Text('颜色 · ' + this.recognitionColor).fontSize(Type.body).fontColor(Theme.text)
                }
                if (this.recognitionCategory.length > 0) {
                  Text('品类 · ' + this.recognitionCategory).fontSize(Type.body).fontColor(Theme.text)
                }
              }.width('100%').alignItems(HorizontalAlign.Start).padding(12)
                .border({ width: 1, color: Theme.line }).borderRadius(10)
            }
          }
        }.width('100%').padding({ top: 8, bottom: 12 })
          .onAreaChange(() => this.queueScroll(false))
      }.width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Off)
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) { this.followLatest = false; }
          if (event.type === TouchType.Up) { this.followLatest = this.chatScroller.isAtEnd(); }
        })

      // 快捷提问与反馈紧邻输入区；聊天滚动时这两项保持可达。
      Column({ space: 8 }) {
        if (this.state === DadaState.ERROR && this.feedback.length > 0) {
          Text(this.feedback).fontSize(Type.bodySmall).fontColor(Theme.warning).width('100%')
        }
        Scroll() {
          Row({ space: 8 }) {
            ForEach(dadaShortcuts(this.context.page), (shortcut: DadaShortcut) => {
              Button(shortcut.label, { type: ButtonType.Normal }).height(36).fontSize(Type.bodySmall)
                .padding({ left: 12, right: 12 }).backgroundColor(Color.Transparent)
                .border({ width: 1, color: Theme.line }).borderRadius(6).fontColor(Theme.secondary)
                .enabled(!this.busy && !assistantReplyActive(this.reply)).onClick(() => this.quick(shortcut))
            }, (shortcut: DadaShortcut) => shortcut.label)
          }.padding({ top: 4, bottom: 4 })
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(44)
        Row({ space: 8 }) {
          TextInput({ text: this.draft, placeholder: '问问今天怎么穿…' }).layoutWeight(1)
            .height(44).fontSize(Type.body).backgroundColor(Theme.surfaceSoft)
            .borderRadius(8).onChange((value: string) => this.draft = value)
            .enabled(!this.busy).enterKeyType(EnterKeyType.Send).onSubmit(() => this.send())
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(20).fontColor([Theme.onAccent])
          }.height(44).width(44).borderRadius(8).backgroundColor(Theme.accent)
            .accessibilityText('发送').enabled(!this.busy && !assistantReplyActive(this.reply) && this.draft.trim().length > 0)
            .onClick(() => this.send())
        }.width('100%')
      }.width('100%').padding({ top: 8 }).border({ width: { top: 1 }, color: Theme.line })
    }.width('100%').height('100%').padding({ left: 16, right: 16, top: 12, bottom: 20 })
      .backgroundColor(Theme.surface)
  }
}
