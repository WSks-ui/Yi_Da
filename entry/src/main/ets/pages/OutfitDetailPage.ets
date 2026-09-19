// 单套搭配详情与编辑。
//
// 这一页回答三件事：这套是怎么来的、哪一件不合适、改完之后要不要留下或穿出门。
// 替换/锁定/移除都发生在组件内的工作副本上，不直接改衣橱数据；保存、试穿、记录已穿
// 通过回调交给外层，由外层决定什么时候落盘。
//
// 组件本身不滚动，按现有页面的约定由外层放进 Scroll 或弹层里使用。
import { Category, Garment, GarmentStatus, Outfit, OutfitRequest, Recommendation,
  emptyProfile, garmentImage } from '../model/Wardrobe';
import { replaceGarment } from '../service/OutfitEngine';
import { normalizeLayout } from '../service/OutfitCanvas';
import { Theme, Type } from '../components/Theme';
import { MaterialCard, cardMaterial, panelMaterial } from '../components/MaterialKit';

// 空方案 / 空单品占位：ArkTS 的 @Builder 参数不接受可空类型，
// 未选中单品时用这份占位数据顶上，显隐由 focusedId 控制，不把 undefined 传进构建器。
function emptyOutfit(): Outfit {
  return { id: '', garmentIds: [], occasion: '', temperature: 0, reason: '', name: '',
    isCustom: false, savedAt: '' };
}

function emptyGarment(): Garment {
  return {
    id: '', name: '', category: Category.TOP, imageKey: '', imageUri: '', color: '', minTemp: 0, maxTemp: 0,
    occasions: [], status: GarmentStatus.READY, wearCount: 0, isDemo: false, fit: '', palette: '',
    style: '', layering: false, pattern: false
  };
}

// 不修改原对象地复制一套方案：ArkTS 禁用展开运算符，只能逐字段搬。
// 复制是为了让编辑动作产生新对象，@State 才会感知到变化并刷新界面。
function copyOutfit(look: Outfit): Outfit {
  return {
    id: look.id, garmentIds: look.garmentIds.slice(), occasion: look.occasion,
    temperature: look.temperature, reason: look.reason, name: look.name,
    isCustom: look.isCustom, savedAt: look.savedAt,
    layout: look.layout ? normalizeLayout(look.layout, look.garmentIds) : undefined
  };
}

@Component
export struct OutfitDetailPage {
  @Prop @Watch('syncOutfit') outfit: Outfit;
  @Prop garments: Garment[];
  @Link lockedIds: string[];
  @Link excludedIds: string[];
  @Prop savedIds: string[] = [];
  onToggleSave: (look: Outfit) => void = () => {};
  onWear: (look: Outfit) => void = () => {};
  onTryOn: (look: Outfit) => void = () => {};
  onEditCanvas: (look: Outfit) => void = () => {};
  onClose: () => void = () => {};

  // 组件内工作副本。@Prop 是单向的，本地编辑不会写回外层，
  // 因此外层每次下发新的 outfit 时用 @Watch 重新同步一次，避免显示旧内容。
  @State working: Outfit = emptyOutfit();
  // 当前展开的单品 id，空串表示没有展开。
  @State focusedId: string = '';
  // 本次调整的说明。引擎给的 reason 描述的是「生成时」的依据，
  // 手动改动不能篡改它，单独用一句提示讲清楚刚才做了什么。
  @State adjustNote: string = '';
  // 说明语气：0 中性、1 成功、2 失败原因。替换失败的原因必须显眼。
  @State adjustTone: number = 0;

  aboutToAppear(): void { this.working = copyOutfit(this.outfit); }

  private syncOutfit(): void {
    this.working = copyOutfit(this.outfit);
    this.focusedId = '';
    this.adjustNote = '';
    this.adjustTone = 0;
  }

  // 详情页同样不接收偏好档案：编辑动作只围绕这一套方案，
  // 替换候选按偏好排序的能力留给外层在接入档案后自行扩展。
  private request(): OutfitRequest {
    return { occasion: this.working.occasion, temperature: this.working.temperature,
      lockedIds: this.lockedIds, excludedIds: this.excludedIds, profile: emptyProfile() };
  }

  private title(): string {
    return this.working.name.length > 0 ? this.working.name : this.working.occasion + ' · ' + this.working.temperature + '℃';
  }

  private isSaved(): boolean { return this.savedIds.indexOf(this.working.id) >= 0; }

  private subtitle(): string {
    const source: string = this.working.isCustom ? '自己搭的' : '规则推荐';
    return source + ' · ' + this.working.garmentIds.length + ' 件单品 · ' +
      this.working.temperature + '℃ ' + this.working.occasion;
  }

  private items(): Garment[] {
    const found: Garment[] = [];
    for (const id of this.working.garmentIds) {
      const item: Garment | undefined = this.garments.find((entry: Garment) => entry.id === id);
      if (item) { found.push(item); }
    }
    return found;
  }

  // 衣橱里被删掉的单品会在方案里留下悬空 id，如实提示，不假装方案还是完整的。
  private missingCount(): number { return this.working.garmentIds.length - this.items().length; }

  private focused(): Garment {
    const found: Garment | undefined = this.garments.find((entry: Garment) => entry.id === this.focusedId);
    return found ? found : emptyGarment();
  }

  private isLocked(id: string): boolean { return this.lockedIds.indexOf(id) >= 0; }

  private focusedInfo(): string {
    const item: Garment = this.focused();
    return '适穿 ' + item.minTemp + '–' + item.maxTemp + '℃ · 场合 ' +
      (item.occasions.length > 0 ? item.occasions.join('、') : '未标注');
  }

  private focusedUsage(): string {
    const item: Garment = this.focused();
    return '已穿 ' + item.wearCount + ' 次 · 状态 ' + item.status +
      (this.isLocked(item.id) ? ' · 已锁定' : '');
  }

  private noteColor(): Resource {
    if (this.adjustTone === 2) { return Theme.warning; }
    return this.adjustTone === 1 ? Theme.accent : Theme.secondary;
  }

  private noteBackground(): Resource {
    if (this.adjustTone === 2) { return Theme.warningSoft; }
    return this.adjustTone === 1 ? Theme.accentSoft : Theme.surfaceSoft;
  }

  private setNote(message: string, tone: number): void {
    this.adjustNote = message;
    this.adjustTone = tone;
  }

  private focus(item: Garment): void {
    // 再点一次收起，省一个关闭按钮，也避免误触后没法退出。
    this.focusedId = this.focusedId === item.id ? '' : item.id;
    this.setNote('', 0);
  }

  // 单件替换：失败原因（例如「这件衣物已锁定，请先解锁。」）原样反馈给用户，
  // 而不是静默失败或换成一个含糊的「操作失败」。
  private replaceFocused(): void {
    const item: Garment = this.focused();
    if (item.id.length === 0) { return; }
    const previous: Outfit = this.working;
    const result: Recommendation = replaceGarment(previous, item.id, this.garments, this.request());
    if (result.outfits.length === 0) { this.setNote(result.explanation, 2); return; }
    const updated: Outfit = result.outfits[0];
    const added: Garment | undefined = this.replacementOf(previous, updated);
    this.working = updated;
    if (added) {
      // 焦点跟到新单品上，用户可以接着判断这件行不行，不用再点一遍。
      this.focusedId = added.id;
      this.setNote('已把「' + item.name + '」换成「' + added.name + '」。', 1);
    } else {
      this.setNote('已替换「' + item.name + '」。', 1);
    }
  }

  private replacementOf(previous: Outfit, updated: Outfit): Garment | undefined {
    const addedId: string | undefined = updated.garmentIds.find((id: string) =>
      previous.garmentIds.indexOf(id) < 0);
    if (addedId === undefined) { return undefined; }
    return this.garments.find((entry: Garment) => entry.id === addedId);
  }

  // 锁定：锁住的品类不再参与替换。同一品类只保留一把锁，
  // 与首页「围绕这件搭」的规则一致，避免出现互相矛盾的锁定组合。
  private toggleLockFocused(): void {
    const item: Garment = this.focused();
    if (item.id.length === 0) { return; }
    if (this.isLocked(item.id)) {
      this.lockedIds = this.lockedIds.filter((id: string) => id !== item.id);
      this.setNote('已解锁「' + item.name + '」，' + item.category + '可以重新替换了。', 0);
      return;
    }
    if (this.working.garmentIds.indexOf(item.id) < 0) {
      this.setNote('「' + item.name + '」不在本方案里，加入方案后才能锁定。', 2); return;
    }
    const sameCategory: string[] = this.garments.filter((entry: Garment) => entry.category === item.category)
      .map((entry: Garment) => entry.id);
    this.lockedIds = this.lockedIds.filter((id: string) => sameCategory.indexOf(id) < 0).concat([item.id]);
    // 锁定与排除互斥：锁住的意思是「就要这件」，排除的意思是「别再出现」。
    this.excludedIds = this.excludedIds.filter((id: string) => id !== item.id);
    this.setNote('已锁定「' + item.name + '」，' + item.category + '不再参与替换。', 1);
  }

  // 排除：从本方案移除，并记入本轮排除名单，避免下一次推荐又把它带回来。
  private removeFocused(): void {
    const item: Garment = this.focused();
    if (item.id.length === 0) { return; }
    const updated: Outfit = copyOutfit(this.working);
    updated.garmentIds = updated.garmentIds.filter((id: string) => id !== item.id);
    // 组合改变后使用新标识，避免保存时误取消原组合的收藏。
    updated.id = 'custom_' + updated.garmentIds.slice().sort().join('_');
    updated.isCustom = true;
    this.working = updated;
    this.lockedIds = this.lockedIds.filter((id: string) => id !== item.id);
    if (this.excludedIds.indexOf(item.id) < 0) {
      this.excludedIds = this.excludedIds.concat([item.id]);
    }
    this.focusedId = '';
    this.setNote('已把「' + item.name + '」移出本方案，本轮也不会再推荐它。', 0);
  }

  @Styles
  pressable() {
    .stateStyles({
      pressed: { .opacity(Theme.pressedOpacity) },
      disabled: { .opacity(Theme.disabledOpacity) }
    })
  }

  @Builder
  private tag(label: string, background: Resource, foreground: Resource) {
    Text(label).fontSize(Type.caption).fontColor(foreground).maxLines(1)
      .padding({ left: Theme.spaceS, right: Theme.spaceS, top: Theme.spaceXs, bottom: Theme.spaceXs })
      .backgroundColor(background).borderRadius(Theme.radiusInput).margin(Theme.spaceXs)
  }

  // 页头：标题用自定义名，没起名字就退回「场合 · 温度」，和衣橱页的标题层级一致。
  @Builder
  private header() {
    Column({ space: Theme.spaceM }) {
      Row({ space: Theme.spaceM }) {
        Column({ space: Theme.spaceXs }) {
          Text(this.title()).fontSize(Type.title).fontWeight(FontWeight.Bold)
            .fontColor(Theme.text).maxLines(2).width('100%')
          Text(this.subtitle()).fontSize(Type.caption).fontColor(Theme.secondary).maxLines(2).width('100%')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('返回', { type: ButtonType.Normal }).fontSize(Type.buttonSmall)
          .height(Theme.buttonCompact).borderRadius(Theme.radiusPill)
          .backgroundColor(Theme.surfaceSoft).fontColor(Theme.text).pressable()
          .onClick(() => this.onClose())
      }.width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        this.tag(this.working.occasion, Theme.accentSoft, Theme.accent)
        this.tag(this.working.temperature + '℃', Theme.accentSoft, Theme.accent)
        this.tag(this.working.isCustom ? '自己搭的' : '规则推荐',
          this.working.isCustom ? Theme.successSoft : Theme.surfaceSoft,
          this.working.isCustom ? Theme.success : Theme.secondary)
        if (this.isSaved()) { this.tag('已收藏', Theme.successSoft, Theme.success) }
        if (this.lockedIds.length > 0) {
          this.tag('锁定 ' + this.lockedIds.length + ' 件', Theme.warningSoft, Theme.warning)
        }
      }.width('100%')
    }.width('100%')
  }

  // 单品网格：逐个可点，点开后在下面展开这一件的信息与操作。
  @Builder
  private garmentCard() {
    MaterialCard({ contentPadding: Theme.spaceL }) {
      Column({ space: Theme.spaceM }) {
        Row({ space: Theme.spaceS }) {
          Text('这套里的单品').fontSize(Type.section).fontWeight(FontWeight.Bold)
            .fontColor(Theme.text).maxLines(1)
          Blank()
          Text('点一件查看 / 替换').fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
        }.width('100%')
        if (this.items().length === 0) {
          Text('这套方案里暂时没有单品。可以在搭配工作台重新挑几件，或从收藏里换一套。')
            .fontSize(Type.bodySmall).fontColor(Theme.secondary).lineHeight(22).width('100%')
            .padding(Theme.spaceL).backgroundColor(Theme.surfaceSoft).borderRadius(Theme.radiusInput)
        } else {
          Grid() {
            ForEach(this.items(), (item: Garment) => {
              GridItem() { this.garmentTile(item) }
            }, (item: Garment) => item.id + (this.focusedId === item.id ? '_open' : '_idle'))
          }.columnsTemplate('repeat(auto-fit, 150)').columnsGap(Theme.spaceM).rowsGap(Theme.spaceM).width('100%')
        }
        if (this.missingCount() > 0) {
          Text('有 ' + this.missingCount() + ' 件单品已不在衣橱里，只保留了记录，建议替换或移除。')
            .fontSize(Type.caption).fontColor(Theme.warning).lineHeight(20).width('100%')
            .padding(Theme.spaceM).backgroundColor(Theme.warningSoft).borderRadius(Theme.radiusInput)
        }
      }.width('100%')
    }
  }

  // 单品卡铺 thinMaterial()：比外层卡片薄一层，让「方案卡 → 单品卡」的层次读得出来。
  @Builder
  private garmentTile(item: Garment) {
    Column({ space: Theme.spaceS }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(garmentImage(item)).width('100%').aspectRatio(0.88).objectFit(ImageFit.Contain)
          .backgroundColor(Theme.imagePlaceholder).borderRadius(Theme.radiusInput)
        if (this.isLocked(item.id)) {
          SymbolGlyph($r('sys.symbol.lock_fill')).fontSize(Theme.iconSm).fontColor([Theme.accent])
            .padding(Theme.spaceXs).backgroundColor(Theme.accentSoft)
            .borderRadius(Theme.radiusInput).margin(Theme.spaceXs)
        }
      }.width('100%')
      Text(item.name).fontSize(Type.bodySmall).fontWeight(FontWeight.Medium).fontColor(Theme.text)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      Text(item.category + ' · ' + item.color).fontSize(Type.caption).fontColor(Theme.secondary)
        .maxLines(1).width('100%')
    }
      .padding(Theme.spaceS).width('100%').borderRadius(Theme.radiusCard)
      .backgroundColor(Theme.surfaceSoft)
      .border({ width: 1, color: this.focusedId === item.id ? Theme.accent : Theme.line })
      .systemMaterial(panelMaterial())
      .accessibilityText('查看 ' + item.name)
      .pressable()
      .onClick(() => this.focus(item))
  }

  // 单品操作区：替换 / 锁定 / 移除都在这里完成，改的是本方案，不动衣橱里的衣物。
  @Builder
  private focusPanel() {
    MaterialCard({ contentPadding: Theme.spaceL }) {
      Column({ space: Theme.spaceM }) {
        Row({ space: Theme.spaceM }) {
          Image(garmentImage(this.focused())).width(72).height(72).objectFit(ImageFit.Contain)
            .backgroundColor(Theme.imagePlaceholder).borderRadius(Theme.radiusInput)
          Column({ space: Theme.spaceXs }) {
            Text(this.focused().name).fontSize(Type.cardTitle).fontWeight(FontWeight.Medium)
              .fontColor(Theme.text).maxLines(2).width('100%')
            Text(this.focusedInfo()).fontSize(Type.caption).fontColor(Theme.secondary)
              .maxLines(2).width('100%')
            Text(this.focusedUsage()).fontSize(Type.caption)
              .fontColor(this.isLocked(this.focused().id) ? Theme.accent : Theme.secondary)
              .maxLines(2).width('100%')
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text('收起').fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
            .padding(Theme.spaceS).borderRadius(Theme.radiusInput)
            .accessibilityText('收起单品信息')
            .onClick(() => { this.focusedId = ''; this.setNote('', 0); })
        }.width('100%')
        Button('替换这件', { type: ButtonType.Normal }).width('100%').height(Theme.buttonHeight)
          .fontSize(Type.button).borderRadius(Theme.radiusPill)
          .backgroundColor(Theme.accent).fontColor(Color.White).pressable()
          .onClick(() => this.replaceFocused())
        // Flex 换行：系统字号放大后两个次要操作会折成上下排列，不会把按钮挤到看不见。
        Flex({ wrap: FlexWrap.Wrap }) {
          Button(this.isLocked(this.focused().id) ? '解除锁定' : '锁定这件', { type: ButtonType.Normal })
            .width('44%').height(Theme.buttonHeight).margin(Theme.spaceXs)
            .fontSize(Type.buttonSmall).borderRadius(Theme.radiusPill)
            .backgroundColor(Theme.accentSoft).fontColor(Theme.accent).pressable()
            .onClick(() => this.toggleLockFocused())
          Button('从方案移除', { type: ButtonType.Normal })
            .width('44%').height(Theme.buttonHeight).margin(Theme.spaceXs)
            .fontSize(Type.buttonSmall).borderRadius(Theme.radiusPill)
            .backgroundColor(Theme.surfaceSoft).fontColor(Theme.text).pressable()
            .onClick(() => this.removeFocused())
        }.width('100%')
        Text('替换只在同一品类里找符合条件的衣物；锁定后这个品类不再参与替换。')
          .fontSize(Type.caption).fontColor(Theme.secondary).maxLines(3).width('100%')
      }.width('100%')
    }
  }

  // 推荐理由 / 手搭说明。引擎生成的 reason 原样展示，
  // 本次手动调整单独记在下面，读者能分清「原来的依据」和「我刚改了什么」。
  @Builder
  private reasonCard() {
    MaterialCard({ contentPadding: Theme.spaceL }) {
      Column({ space: Theme.spaceM }) {
        Row({ space: Theme.spaceS }) {
          SymbolGlyph($r('sys.symbol.shirt')).fontSize(Theme.iconSm).fontColor([Theme.accent])
          Text(this.working.isCustom ? '这套怎么搭的' : '推荐理由').fontSize(Type.cardTitle)
            .fontWeight(FontWeight.Medium).fontColor(Theme.text).maxLines(1)
        }.width('100%')
        Text(this.working.reason.length > 0 ? this.working.reason : '这套方案还没有说明。')
          .fontSize(Type.bodySmall).fontColor(Theme.secondary).lineHeight(22).width('100%')
        if (this.adjustNote.length > 0) {
          Text(this.adjustNote).fontSize(Type.caption).fontColor(this.noteColor()).lineHeight(20)
            .width('100%').padding(Theme.spaceM)
            .backgroundColor(this.noteBackground()).borderRadius(Theme.radiusInput)
        }
      }.width('100%')
    }
  }

  // 操作工具条：直接铺 cardMaterial()，做出「浮在内容之上」的厚度，
  // 滚动时操作区和普通卡片在观感上是分开的两层。
  @Builder
  private actionBar() {
    Column({ space: Theme.spaceS }) {
      Button('编辑搭配画布', { type: ButtonType.Normal }).width('100%')
        .height(Theme.buttonHeight).fontSize(Type.button).borderRadius(Theme.radiusPill)
        .backgroundColor(Theme.accentSoft).fontColor(Theme.accent)
        .onClick(() => this.onEditCanvas(copyOutfit(this.working)))
      Button(this.isSaved() ? '取消收藏' : '保存收藏', { type: ButtonType.Normal }).width('100%')
        .height(Theme.buttonHeight).fontSize(Type.button).borderRadius(Theme.radiusPill)
        .backgroundColor(this.isSaved() ? Theme.accentSoft : Theme.accent)
        .fontColor(this.isSaved() ? Theme.accent : Color.White).pressable()
        .onClick(() => this.onToggleSave(copyOutfit(this.working)))
      Row({ space: Theme.spaceS }) {
        Button('试穿样片', { type: ButtonType.Normal }).layoutWeight(1).height(Theme.buttonHeight)
          .fontSize(Type.buttonSmall).borderRadius(Theme.radiusPill)
          .backgroundColor(Theme.surfaceSoft).fontColor(Theme.text).pressable()
          .onClick(() => this.onTryOn(copyOutfit(this.working)))
        Button('记录已穿', { type: ButtonType.Normal }).layoutWeight(1).height(Theme.buttonHeight)
          .fontSize(Type.buttonSmall).borderRadius(Theme.radiusPill)
          .backgroundColor(Theme.accentSoft).fontColor(Theme.accent).pressable()
          .onClick(() => this.onWear(copyOutfit(this.working)))
      }.width('100%')
    }
      .width('100%').padding(Theme.spaceM).borderRadius(Theme.radiusCard)
      .backgroundColor(Theme.surface)
      .systemMaterial(cardMaterial())
  }

  build() {
    Column({ space: Theme.spaceM }) {
      this.header()
      this.garmentCard()
      if (this.focusedId.length > 0 && this.focused().id.length > 0) { this.focusPanel() }
      this.reasonCard()
      this.actionBar()
    }.width('100%')
  }
}
