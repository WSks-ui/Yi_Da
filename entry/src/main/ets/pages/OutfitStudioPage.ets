import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { CanvasPiece, OutfitLayout, Category, CATEGORIES, Garment, GarmentStatus, Outfit,
  OutfitRequest, emptyProfile, garmentImage } from '../model/Wardrobe';
import { customOutfit, recommend } from '../service/OutfitEngine';
import { CanvasHistory, CANVAS_BACKGROUNDS, CANVAS_RATIO, copyLayout, copyPiece,
  normalizeLayout, constrainPiece } from '../service/OutfitCanvas';
import { exportOutfit, saveOutfitToAlbum, shareOutfitImage } from '../service/OutfitExport';
import { Theme, Type } from '../components/Theme';

@Component
export struct OutfitStudioPage {
  @Prop garments: Garment[] = [];
  @Link temperature: number;
  @Link occasion: string;
  @Prop lockedIds: string[] = [];
  @Prop excludedIds: string[] = [];
  @Prop initialOutfit: Outfit | undefined = undefined;
  onSave: (outfit: Outfit) => Promise<void> = async () => {};
  onDraftChange: (outfit: Outfit) => void = () => {};
  onOpenDetail: (outfit: Outfit) => void = () => {};

  @State layout: OutfitLayout = { background: '#FFFFFF', items: [] };
  @State selectedId: string = '';
  @State planName: string = '';
  @State categoryIndex: number = 0;
  @State canvasWidth: number = 320;
  @State canUndo: boolean = false;
  @State canRedo: boolean = false;
  @State busy: boolean = false;
  @State hint: string = '';
  @State failed: boolean = false;
  @State exportedUri: string = '';
  @State showExport: boolean = false;
  private history: CanvasHistory = new CanvasHistory();
  private workId: string = '';
  private gestureStart: CanvasPiece | undefined = undefined;
  private loadedIds: string[] = [];
  private alive: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    const source: Outfit | undefined = this.initialOutfit;
    this.workId = source?.isCustom ? source.id : 'diy_' + Date.now();
    this.planName = source?.name || '';
    if (source) {
      this.temperature = source.temperature; this.occasion = source.occasion;
    }
    const ids: string[] = (source?.garmentIds || []).filter((id: string) => this.item(id) !== undefined);
    this.layout = normalizeLayout(source?.layout, ids);
  }

  aboutToDisappear(): void { this.alive = false; }
  private item(id: string): Garment | undefined { return this.garments.find((item: Garment) => item.id === id); }
  private selected(): CanvasPiece | undefined { return this.layout.items.find((piece: CanvasPiece) => piece.garmentId === this.selectedId); }
  private piece(id: string): CanvasPiece { return this.layout.items.find((piece: CanvasPiece) => piece.garmentId === id) as CanvasPiece; }
  private pieceWidth(id: string): number { return this.canvasWidth * 0.38 * this.piece(id).scale; }
  private pieceHeight(id: string): number { return this.canvasWidth * 0.44 * this.piece(id).scale; }
  private pieceX(id: string): number { return this.canvasWidth * (this.piece(id).x - 0.19 * this.piece(id).scale); }
  private pieceY(id: string): number { return this.canvasWidth * (CANVAS_RATIO * this.piece(id).y - 0.22 * this.piece(id).scale); }
  private selectedName(): string { return this.item(this.selectedId)?.name || '未选择单品'; }
  private source(id: string): ResourceStr { return garmentImage(this.item(id) as Garment); }
  private request(): OutfitRequest {
    return { temperature: this.temperature, occasion: this.occasion, lockedIds: this.lockedIds,
      excludedIds: this.excludedIds, profile: emptyProfile() };
  }
  private outfit(): Outfit {
    const items: Garment[] = this.layout.items.map((piece: CanvasPiece) => this.item(piece.garmentId) as Garment);
    const look: Outfit = customOutfit(items, this.request(), this.planName.trim() || '我的搭配');
    look.id = this.workId; look.layout = copyLayout(this.layout);
    return look;
  }
  private draftChanged(): void { this.onDraftChange(this.outfit()); }
  private checkpoint(): void { this.history.record(this.layout); this.updateHistory(); }
  private updateHistory(): void { this.canUndo = this.history.canUndo(); this.canRedo = this.history.canRedo(); }
  private undo(redo: boolean): void {
    this.layout = redo ? this.history.redo(this.layout) : this.history.undo(this.layout);
    this.selectedId = ''; this.updateHistory(); this.draftChanged();
  }
  private updatePiece(piece: CanvasPiece): void {
    const next: OutfitLayout = copyLayout(this.layout);
    next.items = next.items.map((item: CanvasPiece) => item.garmentId === piece.garmentId ? constrainPiece(piece) : item);
    this.layout = next;
  }
  private beginGesture(piece: CanvasPiece): void {
    if (this.busy) { return; }
    this.selectedId = piece.garmentId; this.gestureStart = copyPiece(piece); this.checkpoint();
  }
  private move(event: GestureEvent): void {
    if (!this.gestureStart || this.busy) { return; }
    const piece: CanvasPiece = copyPiece(this.gestureStart);
    piece.x += event.offsetX / this.canvasWidth;
    piece.y += event.offsetY / (this.canvasWidth * CANVAS_RATIO);
    this.updatePiece(piece);
  }
  private pinch(event: GestureEvent): void {
    if (!this.gestureStart || this.busy) { return; }
    const piece: CanvasPiece = copyPiece(this.gestureStart);
    piece.scale *= event.scale; this.updatePiece(piece);
  }
  private changeScale(value: number): void {
    const selected: CanvasPiece | undefined = this.selected();
    if (!selected) { return; }
    const piece: CanvasPiece = copyPiece(selected); piece.scale = value;
    this.updatePiece(piece);
  }
  private rotateSelected(): void {
    const selected: CanvasPiece | undefined = this.selected();
    if (!selected) { return; }
    this.checkpoint(); const piece: CanvasPiece = copyPiece(selected);
    piece.rotation = piece.rotation >= 165 ? -180 : piece.rotation + 15;
    this.updatePiece(piece); this.draftChanged();
  }
  private front(): void {
    const piece: CanvasPiece | undefined = this.selected();
    if (!piece) { return; }
    this.checkpoint();
    this.layout = { background: this.layout.background,
      items: this.layout.items.filter((item: CanvasPiece) => item.garmentId !== piece.garmentId).concat([copyPiece(piece)]) };
    this.draftChanged();
  }
  private remove(): void {
    if (!this.selected()) { return; }
    this.checkpoint(); this.layout = { background: this.layout.background,
      items: this.layout.items.filter((piece: CanvasPiece) => piece.garmentId !== this.selectedId) };
    this.selectedId = ''; this.draftChanged();
  }
  private add(item: Garment): void {
    if (this.layout.items.some((piece: CanvasPiece) => piece.garmentId === item.id)) { this.selectedId = item.id; return; }
    if (this.layout.items.length >= 8) { this.hint = '一张画布最多放 8 件单品'; return; }
    this.checkpoint();
    const ids: string[] = this.layout.items.map((piece: CanvasPiece) => piece.garmentId).concat([item.id]);
    this.layout = normalizeLayout(this.layout, ids); this.selectedId = item.id; this.draftChanged();
  }
  private autoFill(): void {
    const look: Outfit | undefined = recommend(this.garments, this.request()).outfits[0];
    if (!look) { this.hint = '当前条件没有完整搭配，可从衣橱自由挑选'; return; }
    this.checkpoint(); this.layout = normalizeLayout(undefined, look.garmentIds);
    this.selectedId = ''; this.draftChanged();
  }
  private async newCanvas(): Promise<void> {
    if (this.busy) { return; }
    if (this.layout.items.length > 0) {
      const result = await this.getUIContext().getPromptAction().showDialog({ title: '新建搭配？',
        message: '当前画布会清空。请先保存需要保留的方案。',
        buttons: [{ text: '取消', color: Theme.secondary }, { text: '新建', color: Theme.accent }] });
      if (!this.alive || result.index !== 1) { return; }
    }
    // 新作品分配新 ID；日常保存复用 ID，只有显式新建才创建另一份作品。
    this.workId = 'diy_' + Date.now(); this.planName = ''; this.selectedId = '';
    this.layout = normalizeLayout(undefined, []); this.history = new CanvasHistory();
    this.loadedIds = []; this.hint = ''; this.failed = false;
    this.updateHistory(); this.draftChanged();
  }
  private async save(): Promise<void> {
    if (this.busy || this.layout.items.length === 0) { return; }
    this.busy = true; this.hint = ''; this.failed = false;
    try {
      const look: Outfit = this.outfit();
      await this.onSave(look);
      if (this.alive) { this.hint = '方案已保存'; this.onDraftChange(look); }
    } catch (error) {
      if (this.alive) { this.hint = ((error as Error).message || '保存失败') + '，草稿仍保留'; this.failed = true; }
    }
    finally { if (this.alive) { this.busy = false; } }
  }
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private async exportImage(): Promise<void> {
    if (this.busy || this.layout.items.length === 0) { return; }
    if (this.layout.items.some((piece: CanvasPiece) => this.loadedIds.indexOf(piece.garmentId) < 0)) {
      this.hint = '还有图片未加载成功，请检查衣物图片后重试'; this.failed = true; return;
    }
    this.busy = true; this.hint = ''; this.failed = false;
    let pixels: image.PixelMap | undefined = undefined;
    try {
      pixels = await this.getUIContext().getComponentSnapshot().get('outfit-artwork', { scale: 2, waitUntilRenderFinished: true });
      const uri: string = await exportOutfit(pixels, this.context());
      if (this.alive) { this.exportedUri = uri; this.showExport = true; }
    } catch (error) { if (this.alive) { this.hint = '图片导出失败，请重试'; this.failed = true; } }
    finally { if (pixels) { await pixels.release(); } if (this.alive) { this.busy = false; } }
  }
  private async deliverImage(album: boolean): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      if (album) {
        const saved: boolean = await saveOutfitToAlbum(this.exportedUri, this.context());
        if (this.alive) { this.hint = saved ? '图片已保存到相册' : '已取消保存'; }
      } else { await shareOutfitImage(this.exportedUri, this.context()); }
    } catch (error) { if (this.alive) { this.hint = album ? '相册保存失败，可重试' : '未能打开分享'; this.failed = true; } }
    finally { if (this.alive) { this.busy = false; } }
  }

  @Builder
  private tool(icon: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(icon).fontSize(21).fontColor([Theme.text])
    }.width(42).height(42).borderRadius(8).backgroundColor(Theme.surfaceSoft)
      .accessibilityText(label)
      // Builder 的值参数不会持续跟随状态；直接读取组件状态，选中后工具才能解锁。
      .enabled(this.toolEnabled(label) && !this.busy).opacity(this.toolEnabled(label) ? 1 : 0.35)
      .onClick(action)
      .onHover((hover: boolean) => { if (hover) { this.getUIContext().getPromptAction().showToast({ message: label }); } })
  }

  private toolEnabled(label: string): boolean {
    if (label === '新建搭配') { return true; }
    if (label === '撤销') { return this.canUndo; }
    if (label === '重做') { return this.canRedo; }
    return this.selected() !== undefined;
  }

  @Builder
  private artwork() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach(this.layout.items, (piece: CanvasPiece) => {
          Image(this.source(piece.garmentId)).objectFit(ImageFit.Contain)
            // ForEach 以衣物 ID 复用节点，变换值必须现取 @State，不能捕获首次构建的 piece。
            .width(this.pieceWidth(piece.garmentId)).height(this.pieceHeight(piece.garmentId))
            .position({ x: this.pieceX(piece.garmentId), y: this.pieceY(piece.garmentId) })
            .rotate({ angle: this.piece(piece.garmentId).rotation })
            .accessibilityText('画布单品 ' + (this.item(piece.garmentId)?.name || ''))
            .onComplete(() => { if (this.loadedIds.indexOf(piece.garmentId) < 0) { this.loadedIds.push(piece.garmentId); } })
            .onError(() => { this.loadedIds = this.loadedIds.filter((id: string) => id !== piece.garmentId); })
            .onClick(() => this.selectedId = piece.garmentId)
            .priorityGesture(GestureGroup(GestureMode.Exclusive,
              PinchGesture().onActionStart(() => this.beginGesture(this.piece(piece.garmentId)))
                .onActionUpdate((event: GestureEvent) => this.pinch(event)).onActionEnd(() => this.draftChanged()),
              PanGesture({ fingers: 1, distance: 3 }).onActionStart(() => this.beginGesture(this.piece(piece.garmentId)))
                .onActionUpdate((event: GestureEvent) => this.move(event)).onActionEnd(() => this.draftChanged())
            ))
        }, (piece: CanvasPiece) => piece.garmentId)
        if (this.layout.items.length === 0) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.shirt')).fontSize(44).fontColor([Theme.tertiary])
            Text('从喜欢的一件开始').fontSize(Type.bodySmall).fontColor(Theme.secondary)
          }.width('100%').height('100%').justifyContent(FlexAlign.Center).hitTestBehavior(HitTestMode.None)
        }
      }.width('100%').height(this.canvasWidth * CANVAS_RATIO).clip(true)
        .backgroundColor(this.layout.background).id('outfit-artwork')
      // 选中框是截图节点的兄弟层，导出永远不会带上编辑控件。
      ForEach(this.layout.items.filter((piece: CanvasPiece) => piece.garmentId === this.selectedId), (piece: CanvasPiece) => {
        Rect().width(this.pieceWidth(piece.garmentId)).height(this.pieceHeight(piece.garmentId))
          .fill(Color.Transparent).stroke(Theme.accent).strokeWidth(1)
          .position({ x: this.pieceX(piece.garmentId), y: this.pieceY(piece.garmentId) })
          .rotate({ angle: this.piece(piece.garmentId).rotation }).hitTestBehavior(HitTestMode.None)
      })
    }.width('100%').height(this.canvasWidth * CANVAS_RATIO).clip(true)
      .border({ width: 1, color: Theme.line }).borderRadius(8)
      .onAreaChange((_old: Area, area: Area) => this.canvasWidth = Number(area.width))
  }

  @Builder
  private exportSheet() {
    Column({ space: 16 }) {
      Text('搭配图片').fontSize(Type.title).fontColor(Theme.text).width('100%')
      Image(this.exportedUri).width('100%').layoutWeight(1).objectFit(ImageFit.Contain)
      Row({ space: 12 }) {
        Button('保存到相册').layoutWeight(1).height(44).fontSize(Type.buttonSmall)
          .enabled(!this.busy).backgroundColor(Theme.accent).onClick(() => this.deliverImage(true))
        Button('分享图片').layoutWeight(1).height(44).fontSize(Type.buttonSmall)
          .enabled(!this.busy).backgroundColor(Theme.accentSoft).fontColor(Theme.accent)
          .onClick(() => this.deliverImage(false))
      }
      Text(this.hint).fontSize(Type.caption).fontColor(this.failed ? Theme.warning : Theme.secondary)
    }.width('100%').height('100%').padding(24)
  }

  build() {
    Column({ space: 12 }) {
      TextInput({ text: this.planName, placeholder: '给搭配起个名字' }).maxLength(24)
        .fontColor(Theme.text).backgroundColor(Theme.surface).onChange((value: string) => { this.planName = value; this.draftChanged(); })
      Row({ space: 8 }) {
        this.tool($r('sys.symbol.arrow_left'), '撤销', () => this.undo(false))
        this.tool($r('sys.symbol.arrow_right'), '重做', () => this.undo(true))
        this.tool($r('sys.symbol.plus'), '新建搭配', () => {
          this.newCanvas().catch(() => {});
        })
        Blank()
        Button('一键搭配').height(42).fontSize(Type.buttonSmall).backgroundColor(Theme.accentSoft)
          .fontColor(Theme.accent).enabled(!this.busy).onClick(() => this.autoFill())
      }.width('100%')
      this.artwork()
      Row({ space: 8 }) {
        ForEach(CANVAS_BACKGROUNDS, (color: string) => {
          Button({ type: ButtonType.Circle }).width(28).height(28).backgroundColor(color)
            .border({ width: this.layout.background === color ? 2 : 1,
              color: this.layout.background === color ? Theme.accent : Theme.line })
            .accessibilityText('画布底色 ' + color).enabled(!this.busy)
            .onClick(() => { this.checkpoint(); const next: OutfitLayout = copyLayout(this.layout);
              next.background = color; this.layout = next; this.draftChanged(); })
        })
        Blank()
        Text(this.layout.items.length + ' 件单品').fontSize(Type.caption).fontColor(Theme.secondary)
      }.width('100%')
      Text(this.selectedName()).fontSize(Type.bodySmall).fontColor(Theme.text).maxLines(1).width('100%')
      Row({ space: 8 }) {
        this.tool($r('sys.symbol.arrow_clockwise'), '旋转 15 度', () => this.rotateSelected())
        this.tool($r('sys.symbol.arrow_up'), '移到最上层', () => this.front())
        this.tool($r('sys.symbol.trash'), '移除单品', () => this.remove())
        Slider({ value: this.selected()?.scale || 1, min: 0.5, max: 1.65, step: 0.05 })
          .layoutWeight(1).enabled(!!this.selected() && !this.busy).selectedColor(Theme.accent)
          .accessibilityText('单品大小').onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Click) { this.checkpoint(); }
            this.changeScale(value);
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) { this.draftChanged(); }
          })
      }.width('100%')
      Row({ space: 10 }) {
        Button('保存方案').height(44).layoutWeight(1).fontSize(Type.buttonSmall).backgroundColor(Theme.accent)
          .enabled(!this.busy && this.layout.items.length > 0).onClick(() => this.save())
        Button('导出图片').height(44).layoutWeight(1).fontSize(Type.buttonSmall).backgroundColor(Theme.accentSoft)
          .fontColor(Theme.accent).enabled(!this.busy && this.layout.items.length > 0).onClick(() => this.exportImage())
      }.width('100%')
      if (this.hint.length > 0) { Text(this.hint).fontSize(Type.caption).fontColor(this.failed ? Theme.warning : Theme.secondary).width('100%') }
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(CATEGORIES, (category: Category, index: number) => {
          Text(category).fontSize(Type.caption).padding(10).borderRadius(8)
            .fontColor(index === this.categoryIndex ? Theme.accent : Theme.secondary)
            .backgroundColor(index === this.categoryIndex ? Theme.accentSoft : Color.Transparent)
            .onClick(() => this.categoryIndex = index)
        })
      }.width('100%')
      Grid() {
        ForEach(this.garments.filter((item: Garment) => item.category === CATEGORIES[this.categoryIndex] && item.status === GarmentStatus.READY), (item: Garment) => {
          GridItem() {
            Column({ space: 6 }) {
              Image(garmentImage(item)).width('100%').height(100).objectFit(ImageFit.Contain)
              Text(item.name).fontSize(Type.caption).fontColor(Theme.text).maxLines(2)
            }.width('100%').padding(8).backgroundColor(Theme.surface).borderRadius(8)
              .accessibilityText('加入画布 ' + item.name).enabled(!this.busy).onClick(() => this.add(item))
          }
        }, (item: Garment) => item.id)
      }.columnsTemplate('1fr 1fr 1fr').columnsGap(8).rowsGap(8).width('100%')
    }.width('100%').padding(16)
      .bindSheet($$this.showExport, this.exportSheet, { height: SheetSize.LARGE, showClose: true })
  }
}
