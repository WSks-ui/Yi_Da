// 批量录入页：一次选多张照片，逐件确认属性，逐件保存。
//
// 布局约定（见交接文档 A2）：
// - 本页在 routePage 里获得"有界布局"：整页不套外层 Scroll，只有属性表单自己滚动，
//   因此底部提交区始终可达，不会被键盘或长表单顶出屏幕。
// - 队列与在途任务的唯一所有者是父页面 Index。本页只接收值 + 回调，
//   不直接写文件、不直接写快照；这样离开流程时不会留下无人负责的异步任务。
// - 表单按字段回调（onName/onColor/...），不把整个队列项对象回传重建，
//   避免 ArkUI V1 复用节点时出现"数据已改但画面不动"。
import { Category, CATEGORIES, OCCASIONS } from '../model/Wardrobe';
import { ImportFailureStep, ImportItem, ImportPhase, ImportSummary } from '../model/GarmentImport';
import { activeImageUri, canSave, cutoutLabel, draftErrors, DraftErrors, hasUnfinished, IMPORT_SELECT_LIMIT,
  isActivePhase, remainingCapacity, summaryOf, WARDROBE_LIMIT } from '../service/GarmentImport';
import { cutoutSupported } from '../service/GarmentCutout';
import { Theme, Type } from '../components/Theme';

const COLORS: string[] = ['白色', '黑色', '灰色', '蓝色', '绿色', '棕色', '多色'];
const CONTENT_MAX_WIDTH: number = 840;

@Component
export struct GarmentImportPage {
  @Prop @Watch('onItemsChanged') items: ImportItem[] = [];
  @Prop @Watch('onCurrentChanged') currentIndex: number = 0;
  @Prop garmentCount: number = 0;
  @Prop readBlocked: boolean = false;
  @Prop busy: boolean = false;
  onPick: () => void = () => {};
  onSelect: (index: number) => void = () => {};
  onMove: (index: number) => void = () => {};
  onConfirm: (index: number) => void = () => {};
  onSkip: (index: number) => void = () => {};
  onRetry: (index: number) => void = () => {};
  onCutout: (index: number) => void = () => {};
  onOriginal: (index: number) => void = () => {};
  onName: (index: number, value: string) => void = () => {};
  onCategory: (index: number, categoryIndex: number) => void = () => {};
  onColor: (index: number, value: string) => void = () => {};
  onMinTemp: (index: number, value: number) => void = () => {};
  onMaxTemp: (index: number, value: number) => void = () => {};
  onOccasions: (index: number, occasions: string[]) => void = () => {};
  onExit: () => void = () => {};

  // 滑杆的拖动过程需要本地值，否则受控组件会边拖边被回写、手感发滞。
  @State sliderMin: number = 12;
  @State sliderMax: number = 30;

  // 记录上一次把哪一个任务/品类同步进滑杆。父页面每次异步状态更新都会发布新数组，
  // 但拖动滑杆时本地值要继续跟手，不能因为同一任务的普通 phase/image 更新被重置。
  private syncedTaskId: string = '';
  private syncedCategoryIndex: number = -2;

  aboutToAppear(): void { this.syncTemps(); }

  // 切项后把滑杆种子重置为当前项的温度，避免上一项的值留在滑杆上。
  onCurrentChanged(): void { this.syncTemps(); }

  // 品类默认温度由父层的不可变更新计算。只在任务或品类确实变化时同步，
  // 这样同一任务的名称/图片/phase 更新不会打断用户正在拖动的本地滑杆。
  onItemsChanged(): void {
    const item: ImportItem | undefined = this.current();
    if (!item) {
      this.syncedTaskId = '';
      this.syncedCategoryIndex = -2;
      return;
    }
    if (item.id !== this.syncedTaskId || item.draft.categoryIndex !== this.syncedCategoryIndex) {
      this.syncTemps();
    }
  }

  private syncTemps(): void {
    const item: ImportItem | undefined = this.current();
    if (!item) { return; }
    this.sliderMin = item.draft.minTemp;
    this.sliderMax = Math.max(item.draft.minTemp, item.draft.maxTemp);
    this.syncedTaskId = item.id;
    this.syncedCategoryIndex = item.draft.categoryIndex;
  }

  private current(): ImportItem | undefined {
    if (this.items.length === 0) { return undefined; }
    const index: number = this.currentIndex >= 0 && this.currentIndex < this.items.length ? this.currentIndex : 0;
    return this.items[index];
  }

  private capacity(): number { return remainingCapacity(this.garmentCount); }
  private savedSummary(): ImportSummary { return summaryOf(this.items); }
  private allHandled(): boolean { return this.items.length > 0 && !hasUnfinished(this.items); }

  // Builder 内部不能接收 ImportItem 普通参数：ArkUI 会把该参数值捕获进首次构建的闭包。
  // 下面这些小读取器每次都从 @Prop 快照现取，既保留 ForEach 的稳定 key，也让异步 phase、
  // 图片、错误和草稿更新进入同一条可观察依赖链。读取器内部可以使用局部变量，调用方不会
  // 把它保存到 Builder 闭包里。
  private currentImage(): string {
    const item: ImportItem | undefined = this.current();
    return item ? activeImageUri(item) : '';
  }

  private currentPhase(): ImportPhase {
    const item: ImportItem | undefined = this.current();
    return item ? item.phase : ImportPhase.WAITING;
  }

  private currentFailureStep(): ImportFailureStep {
    const item: ImportItem | undefined = this.current();
    return item ? item.failureStep : ImportFailureStep.NONE;
  }

  private currentError(): string {
    const item: ImportItem | undefined = this.current();
    return item ? item.error : '';
  }

  private currentOriginalUri(): string {
    const item: ImportItem | undefined = this.current();
    return item ? item.originalUri : '';
  }

  private currentUseCutout(): boolean {
    const item: ImportItem | undefined = this.current();
    return item ? item.useCutout : false;
  }

  private currentCutoutLabel(): string {
    const item: ImportItem | undefined = this.current();
    return item ? cutoutLabel(item) : '抠图';
  }

  private currentErrors(): DraftErrors {
    const item: ImportItem | undefined = this.current();
    return item ? draftErrors(item) : { name: '', category: '', temperature: '', occasions: '' };
  }

  private currentFieldError(field: string): string {
    const errors: DraftErrors = this.currentErrors();
    if (field === 'name') { return errors.name; }
    if (field === 'category') { return errors.category; }
    if (field === 'temperature') { return errors.temperature; }
    if (field === 'occasions') { return errors.occasions; }
    return '';
  }

  private currentName(): string {
    const item: ImportItem | undefined = this.current();
    return item ? item.draft.name : '';
  }

  private currentCategoryIndex(): number {
    const item: ImportItem | undefined = this.current();
    return item ? item.draft.categoryIndex : -1;
  }

  private currentColor(): string {
    const item: ImportItem | undefined = this.current();
    return item ? item.draft.color : '';
  }

  private currentMinTemp(): number {
    const item: ImportItem | undefined = this.current();
    return item ? item.draft.minTemp : this.sliderMin;
  }

  private currentMaxTemp(): number {
    const item: ImportItem | undefined = this.current();
    return item ? item.draft.maxTemp : this.sliderMax;
  }

  private currentOccasions(): string[] {
    const item: ImportItem | undefined = this.current();
    return item ? item.draft.occasions : [];
  }

  private currentSaveReason(): string {
    const item: ImportItem | undefined = this.current();
    return item ? canSave(item, this.garmentCount) : '';
  }

  // SAVED/SKIPPED 是导入会话的终态，只允许查看；在途态也不能编辑，避免回调与状态机竞争。
  private currentCanEdit(): boolean {
    const item: ImportItem | undefined = this.current();
    return item !== undefined && !this.busy && !this.readBlocked &&
      item.phase !== ImportPhase.SAVED && item.phase !== ImportPhase.SKIPPED &&
      !isActivePhase(item.phase);
  }

  private categorySelected(index: number): boolean { return this.currentCategoryIndex() === index; }
  private colorSelected(value: string): boolean { return this.currentColor() === value; }
  private occasionSelected(value: string): boolean { return this.currentOccasions().indexOf(value) >= 0; }

  private itemById(id: string): ImportItem | undefined {
    return this.items.find((item: ImportItem) => item.id === id);
  }

  private thumbnailImage(id: string): string {
    const item: ImportItem | undefined = this.itemById(id);
    return item ? activeImageUri(item) : '';
  }

  private thumbnailPhase(id: string): ImportPhase {
    const item: ImportItem | undefined = this.itemById(id);
    return item ? item.phase : ImportPhase.WAITING;
  }

  private thumbnailStatusLabel(id: string): string {
    const item: ImportItem | undefined = this.itemById(id);
    return item ? this.statusLabel(item) : '';
  }

  private thumbnailStatusColor(id: string): Resource {
    const item: ImportItem | undefined = this.itemById(id);
    return item ? this.statusColor(item) : Theme.secondary;
  }

  private canConfirm(): boolean {
    const item: ImportItem | undefined = this.current();
    if (!item || this.busy || this.readBlocked) { return false; }
    return canSave(item, this.garmentCount).length === 0;
  }

  // 队列缩略图状态：用文字而不是纯颜色，色觉差异与深色模式下同样可读。
  private statusLabel(item: ImportItem): string {
    if (item.phase === ImportPhase.SAVED) { return '已保存'; }
    if (item.phase === ImportPhase.SKIPPED) { return '已跳过'; }
    if (item.phase === ImportPhase.ERROR) { return '失败'; }
    if (item.phase === ImportPhase.COPYING) { return '导入中'; }
    if (item.phase === ImportPhase.CUTTING) { return '抠图中'; }
    if (item.phase === ImportPhase.SAVING) { return '保存中'; }
    if (item.phase === ImportPhase.WAITING) { return '等待'; }
    return '待确认';
  }

  private statusColor(item: ImportItem): Resource {
    if (item.phase === ImportPhase.SAVED) { return Theme.success; }
    if (item.phase === ImportPhase.ERROR) { return Theme.warning; }
    return Theme.secondary;
  }

  private remainingHint(): string {
    const capacity: number = this.capacity();
    if (capacity <= 0) { return `衣橱已满 ${WARDROBE_LIMIT} 件，可先整理再继续录入。`; }
    return `衣橱还可以再放 ${capacity} 件。`;
  }

  private canAddMore(): boolean {
    if (this.busy || this.readBlocked || this.capacity() <= 0) { return false; }
    return !this.items.some((item: ImportItem) => isActivePhase(item.phase));
  }

  // ---- 结构 ----

  @Builder
  private header() {
    Row({ space: Theme.spaceS }) {
      Row() {
        SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(Theme.iconMd).fontColor([Theme.text])
      }
        .width(Theme.buttonCompact).height(Theme.buttonCompact)
        .justifyContent(FlexAlign.Center)
        .borderRadius(Theme.radiusPill)
        .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
        .accessibilityText('返回')
        .onClick(() => this.onExit())
      Column({ space: 2 }) {
        Text('批量录入衣物').fontSize(Type.section).fontWeight(FontWeight.Medium).fontColor(Theme.text)
          .maxLines(1)
        Text(this.items.length > 0
          ? `${this.currentIndex + 1} / ${this.items.length} · 已保存 ${this.savedSummary().saved} 件`
          : `一次最多 ${IMPORT_SELECT_LIMIT} 张`)
          .fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
    }
      .width('100%').height(Theme.navBarHeight).alignItems(VerticalAlign.Center)
      .padding({ left: Theme.spaceS, right: Theme.pagePadding })
  }

  @Builder
  private emptyState() {
    Column({ space: Theme.spaceM }) {
      SymbolGlyph($r('sys.symbol.camera')).fontSize(Theme.iconLg).fontColor([Theme.tertiary])
      Text('从相册选择衣物照片').fontSize(Type.bodySmall).fontColor(Theme.text)
        .maxLines(2).textAlign(TextAlign.Center)
      Text(this.capacity() > 0
        ? `可一次选择多张，逐件确认后再保存。本次最多可选 ${this.capacity()} 张。`
        : `衣橱已满 ${WARDROBE_LIMIT} 件，请先整理衣橱再添加。`)
        .fontSize(Type.caption).fontColor(Theme.secondary).maxLines(3).textAlign(TextAlign.Center)
      Button('从相册选择', { type: ButtonType.Normal }).width('100%').height(Theme.buttonHeight)
        .borderRadius(Theme.radiusPill).backgroundColor(Theme.accent).fontColor(Theme.onAccent)
        .fontSize(Type.button)
        .enabled(!this.readBlocked && !this.busy && this.capacity() > 0)
        .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
        .onClick(() => this.onPick())
    }
      .width('100%').padding(Theme.spaceXl).justifyContent(FlexAlign.Center)
  }

  @Builder
  private preview() {
    Column({ space: Theme.spaceS }) {
      if (this.currentImage().length > 0) {
        Image(this.currentImage()).height(200).width('100%').objectFit(ImageFit.Contain)
          .backgroundColor(Theme.imagePlaceholder).borderRadius(Theme.radiusInput)
      } else {
        Column({ space: Theme.spaceS }) {
          if (this.currentPhase() === ImportPhase.COPYING || this.currentPhase() === ImportPhase.WAITING) {
            LoadingProgress().width(36).height(36).color(Theme.accent)
            Text('正在导入这张照片…').fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
          } else {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(Theme.iconLg)
              .fontColor([Theme.warning])
            Text(this.currentError().length > 0 ? this.currentError() : '这张照片没有可用图片')
              .fontSize(Type.caption).fontColor(Theme.warning).maxLines(3).textAlign(TextAlign.Center)
          }
        }.width('100%').height(180).justifyContent(FlexAlign.Center)
      }
      // 处理状态与错误紧贴图片，不放到页面其它角落。
      if (this.currentPhase() === ImportPhase.CUTTING) {
        Row({ space: Theme.spaceS }) {
          LoadingProgress().width(18).height(18).color(Theme.accent)
          Text('正在主体抠图…').fontSize(Type.caption).fontColor(Theme.secondary)
            .layoutWeight(1).maxLines(1)
        }.width('100%')
      } else if (this.currentFailureStep() === ImportFailureStep.CUTOUT) {
        Row({ space: Theme.spaceS }) {
          Text(this.currentError().length > 0 ? this.currentError() : '抠图未完成，可重试或直接用原图')
            .fontSize(Type.caption).fontColor(Theme.warning).layoutWeight(1).maxLines(2)
          Button('重试抠图', { type: ButtonType.Normal }).height(32).fontSize(Type.buttonSmall)
            .backgroundColor(Theme.accentSoft).fontColor(Theme.accent).borderRadius(Theme.radiusPill)
            .enabled(this.currentCanEdit())
            .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
            .onClick(() => this.onRetry(this.currentIndex))
        }.width('100%')
      } else if (this.currentFailureStep() === ImportFailureStep.COPY) {
        Row({ space: Theme.spaceS }) {
          Text(this.currentError().length > 0 ? this.currentError() : '导入失败，可重试或跳过')
            .fontSize(Type.caption).fontColor(Theme.warning).layoutWeight(1).maxLines(2)
          Button('重试导入', { type: ButtonType.Normal }).height(32).fontSize(Type.buttonSmall)
            .backgroundColor(Theme.accentSoft).fontColor(Theme.accent).borderRadius(Theme.radiusPill)
            .enabled(this.currentCanEdit())
            .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
            .onClick(() => this.onRetry(this.currentIndex))
        }.width('100%')
      } else if (this.currentError().length > 0 && this.currentFailureStep() !== ImportFailureStep.SAVE) {
        Text(this.currentError()).fontSize(Type.caption).fontColor(Theme.warning).width('100%').maxLines(3)
      }
      Row({ space: Theme.spaceS }) {
        Button('原图', { type: ButtonType.Normal }).height(36).layoutWeight(1)
          .fontSize(Type.buttonSmall).borderRadius(Theme.radiusInput)
          .backgroundColor(!this.currentUseCutout() ? Theme.accentSoft : Theme.surfaceSoft).fontColor(Theme.text)
          .enabled(this.currentCanEdit() && this.currentOriginalUri().length > 0)
          .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
          .onClick(() => this.onOriginal(this.currentIndex))
        Button(this.currentCutoutLabel(), { type: ButtonType.Normal }).height(36).layoutWeight(1)
          .fontSize(Type.buttonSmall).borderRadius(Theme.radiusInput)
          .backgroundColor(this.currentUseCutout() ? Theme.accentSoft : Theme.surfaceSoft).fontColor(Theme.text)
          .enabled(this.currentCanEdit() && this.currentOriginalUri().length > 0)
          .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
          .onClick(() => this.onCutout(this.currentIndex))
      }.width('100%')
      if (!cutoutSupported()) {
        Text('当前设备不提供主体抠图，保存时使用原图。').fontSize(Type.caption)
          .fontColor(Theme.tertiary).width('100%').maxLines(2)
      }
    }.width('100%')
  }

  @Builder
  private thumbnails() {
    Scroll() {
      Row({ space: Theme.spaceS }) {
        ForEach(this.items, (item: ImportItem, index: number) => {
          // item.id 在任务生命周期内不变；缩略图内容始终按 ID 回查最新快照。
          Column({ space: Theme.spaceXs }) {
            Stack() {
              if (this.thumbnailImage(item.id).length > 0) {
                Image(this.thumbnailImage(item.id)).width(64).height(64).objectFit(ImageFit.Cover)
                  .borderRadius(Theme.radiusChip)
              } else {
                Column() {
                  SymbolGlyph($r('sys.symbol.camera')).fontSize(Theme.iconSm).fontColor([Theme.tertiary])
                }.width(64).height(64).justifyContent(FlexAlign.Center)
                  .backgroundColor(Theme.surfaceSoft).borderRadius(Theme.radiusChip)
              }
            }
            .width(64).height(64)
            .border({ width: index === this.currentIndex ? 2 : 1,
              color: index === this.currentIndex ? Theme.accent : Theme.line })
              .borderRadius(Theme.radiusChip)
              .opacity(this.thumbnailPhase(item.id) === ImportPhase.SKIPPED ? Theme.disabledOpacity : 1)
            Text(this.thumbnailStatusLabel(item.id)).fontSize(Type.caption)
              .fontColor(this.thumbnailStatusColor(item.id)).maxLines(1)
          }
          .width(68)
          .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
          .onClick(() => this.onSelect(index))
        }, (item: ImportItem) => item.id)
      }.padding({ left: Theme.pagePadding, right: Theme.pagePadding })
    }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
  }

  @Builder
  private fieldLabel(text: string, field: string) {
    Row() {
      Text(text).fontSize(Type.bodySmall).fontColor(Theme.text).layoutWeight(1).maxLines(1)
      if (this.currentFieldError(field).length > 0) {
        Text(this.currentFieldError(field)).fontSize(Type.caption).fontColor(Theme.warning).maxLines(2)
          .textAlign(TextAlign.End).layoutWeight(1)
      }
    }.width('100%')
  }

  @Builder
  private form() {
    Column({ space: Theme.spaceM }) {
      Column({ space: Theme.spaceXs }) {
        this.fieldLabel('名称', 'name')
        TextInput({ text: this.currentName(), placeholder: '例如 白色圆领短袖' }).maxLength(30)
          .fontColor(Theme.text).placeholderColor(Theme.tertiary)
          .backgroundColor(Theme.surfaceSoft).borderRadius(Theme.radiusInput)
          .enabled(this.currentCanEdit())
          .onChange((value: string) => this.onName(this.currentIndex, value))
      }.width('100%')

      Column({ space: Theme.spaceXs }) {
        this.fieldLabel('品类', 'category')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(CATEGORIES, (value: Category, index: number) => {
            Text(value).fontSize(Type.caption)
              .fontColor(this.categorySelected(index) ? Theme.accent : Theme.text)
              .padding({ left: Theme.spaceL, right: Theme.spaceL, top: Theme.spaceS, bottom: Theme.spaceS })
              .backgroundColor(this.categorySelected(index) ? Theme.accentSoft : Theme.surfaceSoft)
              .borderRadius(Theme.radiusPill)
              .border({ width: 1, color: this.categorySelected(index) ? Theme.accent : Theme.line })
              .margin({ right: Theme.spaceS, bottom: Theme.spaceS })
              .enabled(this.currentCanEdit())
              .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
              .onClick(() => { if (this.currentCanEdit()) { this.onCategory(this.currentIndex, index); } })
          }, (value: Category) => value)
        }.width('100%')
      }.width('100%')

      Column({ space: Theme.spaceXs }) {
        this.fieldLabel('颜色', '')
        Flex({ wrap: FlexWrap.Wrap }) {
          Text('未设置').fontSize(Type.caption)
            .fontColor(this.currentColor().length === 0 ? Theme.accent : Theme.text)
            .padding({ left: Theme.spaceL, right: Theme.spaceL, top: Theme.spaceS, bottom: Theme.spaceS })
            .backgroundColor(this.currentColor().length === 0 ? Theme.accentSoft : Theme.surfaceSoft)
            .borderRadius(Theme.radiusPill)
            .border({ width: 1, color: this.currentColor().length === 0 ? Theme.accent : Theme.line })
            .margin({ right: Theme.spaceS, bottom: Theme.spaceS })
            .enabled(this.currentCanEdit())
            .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
            .onClick(() => { if (this.currentCanEdit()) { this.onColor(this.currentIndex, ''); } })
          ForEach(COLORS, (value: string) => {
            Text(value).fontSize(Type.caption)
              .fontColor(this.colorSelected(value) ? Theme.accent : Theme.text)
              .padding({ left: Theme.spaceL, right: Theme.spaceL, top: Theme.spaceS, bottom: Theme.spaceS })
              .backgroundColor(this.colorSelected(value) ? Theme.accentSoft : Theme.surfaceSoft)
              .borderRadius(Theme.radiusPill)
              .border({ width: 1, color: this.colorSelected(value) ? Theme.accent : Theme.line })
              .margin({ right: Theme.spaceS, bottom: Theme.spaceS })
              .enabled(this.currentCanEdit())
              .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
              .onClick(() => { if (this.currentCanEdit()) { this.onColor(this.currentIndex, value); } })
          }, (value: string) => value)
        }.width('100%')
      }.width('100%')

      Column({ space: Theme.spaceXs }) {
        Row() {
          Text('适穿温度').fontSize(Type.bodySmall).fontColor(Theme.text).layoutWeight(1).maxLines(1)
          Text(`${this.currentMinTemp()} – ${this.currentMaxTemp()}℃`).fontSize(Type.bodySmall)
            .fontColor(Theme.accent).maxLines(1)
        }.width('100%')
        if (this.currentErrors().temperature.length > 0) {
          Text(this.currentErrors().temperature).fontSize(Type.caption).fontColor(Theme.warning)
            .width('100%').maxLines(2)
        }
        Row({ space: Theme.spaceM }) {
          Text('最低').fontSize(Type.caption).fontColor(Theme.tertiary).width(36).maxLines(1)
          Slider({ value: this.sliderMin, min: -20, max: 45, step: 1 }).selectedColor(Theme.accent)
            .layoutWeight(1).enabled(this.currentCanEdit())
            .onChange((value: number) => {
              const nextMin: number = Math.round(value);
              const nextMax: number = Math.max(nextMin, this.sliderMax);
              const maxChanged: boolean = nextMax !== this.sliderMax;
              this.sliderMin = nextMin;
              this.sliderMax = nextMax;
              this.onMinTemp(this.currentIndex, nextMin);
              // 最低温度越过最高温度时，把本地联动值一并交给父层，避免保存时丢失。
              if (maxChanged) { this.onMaxTemp(this.currentIndex, nextMax); }
            })
            .accessibilityText('最低适穿温度')
        }.width('100%')
        Row({ space: Theme.spaceM }) {
          Text('最高').fontSize(Type.caption).fontColor(Theme.tertiary).width(36).maxLines(1)
          Slider({ value: this.sliderMax, min: -20, max: 45, step: 1 }).selectedColor(Theme.accent)
            .layoutWeight(1).enabled(this.currentCanEdit())
            .onChange((value: number) => {
              const nextMax: number = Math.round(value);
              const nextMin: number = Math.min(nextMax, this.sliderMin);
              const minChanged: boolean = nextMin !== this.sliderMin;
              this.sliderMax = nextMax;
              this.sliderMin = nextMin;
              this.onMaxTemp(this.currentIndex, nextMax);
              // 最高温度越过最低温度时，把本地联动值一并交给父层，保持草稿可保存。
              if (minChanged) { this.onMinTemp(this.currentIndex, nextMin); }
            })
            .accessibilityText('最高适穿温度')
        }.width('100%')
      }.width('100%')

      Column({ space: Theme.spaceXs }) {
        this.fieldLabel('适合场合', 'occasions')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(OCCASIONS, (occasion: string) => {
            Row({ space: Theme.spaceXs }) {
              Checkbox({ name: occasion })
                .select(this.occasionSelected(occasion))
                .selectedColor(Theme.accent)
                .shape(CheckBoxShape.ROUNDED_SQUARE)
                .width(Theme.iconMd).height(Theme.iconMd)
                .enabled(this.currentCanEdit())
                .onChange((checked: boolean) => {
                  if (this.currentCanEdit()) {
                    const next: string[] = checked
                      ? this.currentOccasions().filter((value: string) => value !== occasion).concat([occasion])
                      : this.currentOccasions().filter((value: string) => value !== occasion);
                    this.onOccasions(this.currentIndex, next);
                  }
                })
              Text(occasion).fontSize(Type.caption).fontColor(Theme.text).maxLines(1)
            }.width('50%')
          }, (occasion: string) => occasion)
        }.width('100%')
      }.width('100%')
    }.width('100%')
  }

  @Builder
  private footer() {
    Column({ space: Theme.spaceS }) {
      if (this.currentPhase() === ImportPhase.SAVED) {
        Row({ space: Theme.spaceS }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(Theme.iconMd).fontColor([Theme.success])
          Text('这一件已保存，可在衣橱里继续编辑').fontSize(Type.caption).fontColor(Theme.success)
            .layoutWeight(1).maxLines(2)
        }.width('100%')
      } else if (this.currentPhase() === ImportPhase.SKIPPED) {
        Text('这一件已跳过，未保存任何内容。').fontSize(Type.caption).fontColor(Theme.secondary)
          .width('100%').maxLines(2)
      } else if (this.currentPhase() === ImportPhase.ERROR && this.currentFailureStep() === ImportFailureStep.SAVE) {
        Text(this.currentError().length > 0 ? this.currentError() : '保存失败，当前输入与图片都还在，可以直接重试。')
          .fontSize(Type.caption).fontColor(Theme.warning).width('100%').maxLines(3)
      }
      if (this.currentPhase() !== ImportPhase.SAVED && this.currentPhase() !== ImportPhase.SKIPPED &&
        !isActivePhase(this.currentPhase()) && !this.canConfirm()) {
        Text(this.currentSaveReason()).fontSize(Type.caption).fontColor(Theme.secondary)
          .width('100%').maxLines(2)
      }
      Row({ space: Theme.spaceS }) {
        Button('上一件', { type: ButtonType.Normal }).height(Theme.buttonHeight).layoutWeight(1)
          .fontSize(Type.buttonSmall).borderRadius(Theme.radiusPill)
          .backgroundColor(Theme.surfaceSoft).fontColor(Theme.text)
          .enabled(!this.busy && this.currentIndex > 0)
          .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
          .onClick(() => this.onMove(this.currentIndex - 1))
        Button('下一件', { type: ButtonType.Normal }).height(Theme.buttonHeight).layoutWeight(1)
          .fontSize(Type.buttonSmall).borderRadius(Theme.radiusPill)
          .backgroundColor(Theme.surfaceSoft).fontColor(Theme.text)
          .enabled(!this.busy && this.currentIndex < this.items.length - 1)
          .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
          .onClick(() => this.onMove(this.currentIndex + 1))
      }.width('100%')
      Row({ space: Theme.spaceS }) {
        Button('跳过', { type: ButtonType.Normal }).height(Theme.buttonHeight).layoutWeight(1)
          .fontSize(Type.button).borderRadius(Theme.radiusPill)
          .backgroundColor(Theme.surfaceSoft).fontColor(Theme.text)
          .enabled(!this.busy && this.currentPhase() !== ImportPhase.SAVED && this.currentPhase() !== ImportPhase.SKIPPED)
          .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
          .onClick(() => this.onSkip(this.currentIndex))
        Button(this.currentPhase() === ImportPhase.SAVING ? '保存中…' : '保存并继续', { type: ButtonType.Normal })
          .height(Theme.buttonHeight).layoutWeight(2)
          .fontSize(Type.button).borderRadius(Theme.radiusPill)
          .backgroundColor(Theme.accent).fontColor(Theme.onAccent)
          .enabled(this.canConfirm())
          .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
          .onClick(() => this.onConfirm(this.currentIndex))
      }.width('100%')
    }.width('100%')
  }

  @Builder
  private doneFooter() {
    Column({ space: Theme.spaceS }) {
      Text(`本次共处理 ${this.items.length} 张，已保存 ${this.savedSummary().saved} 件，跳过 ${this.savedSummary().skipped} 件。`)
        .fontSize(Type.bodySmall).fontColor(Theme.text).width('100%').maxLines(3)
      Text(this.remainingHint()).fontSize(Type.caption).fontColor(Theme.secondary).width('100%').maxLines(2)
      Row({ space: Theme.spaceS }) {
        Button('再看一遍', { type: ButtonType.Normal }).height(Theme.buttonHeight).layoutWeight(1)
          .fontSize(Type.buttonSmall).borderRadius(Theme.radiusPill)
          .backgroundColor(Theme.surfaceSoft).fontColor(Theme.text)
          .enabled(!this.busy)
          .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
          .onClick(() => this.onSelect(0))
        Button('完成', { type: ButtonType.Normal }).height(Theme.buttonHeight).layoutWeight(1)
          .fontSize(Type.button).borderRadius(Theme.radiusPill)
          .backgroundColor(Theme.accent).fontColor(Theme.onAccent)
          .enabled(!this.busy)
          .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
          .onClick(() => this.onExit())
      }.width('100%')
    }.width('100%')
  }

  build() {
    Column() {
      this.header()
      if (this.items.length === 0) {
        this.emptyState()
      } else {
        this.thumbnails()
        Scroll() {
          Column({ space: Theme.spaceL }) {
            if (this.current() !== undefined) { this.preview() }
            if (this.current() !== undefined) { this.form() }
            Button('继续选择照片', { type: ButtonType.Normal }).width('100%').height(40)
              .fontSize(Type.buttonSmall).borderRadius(Theme.radiusPill)
              .backgroundColor(Theme.accentSoft).fontColor(Theme.accent)
              .enabled(this.canAddMore())
              .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
              .onClick(() => this.onPick())
          }
            .width('100%').constraintSize({ maxWidth: CONTENT_MAX_WIDTH })
            .padding({ left: Theme.pagePadding, right: Theme.pagePadding,
              top: Theme.spaceS, bottom: Theme.spaceXs })
        }
          .width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Off)
      }
      Column() {
          if (this.items.length > 0) {
            if (this.allHandled()) { this.doneFooter() }
            else if (this.current() !== undefined) { this.footer() }
        }
      }
        .width('100%').constraintSize({ maxWidth: CONTENT_MAX_WIDTH })
        .padding({ left: Theme.pagePadding, right: Theme.pagePadding,
          top: Theme.spaceS, bottom: Theme.spaceL })
        .backgroundColor(Theme.background)
    }
      .width('100%').height('100%').backgroundColor(Theme.background)
  }
}
