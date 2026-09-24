// 衣橱页：内容概览、分类切换、常穿、整理任务、衣物网格。
//
// 交互上做了三处调整：
// 1. 品类从下拉改成常驻标签行——衣物分类是最常用的筛选，两级下拉要多点两次。
// 2. 状态从下拉改成横向药丸，且只保留"全部/可穿/待洗"三个高频项，其余进整理任务区。
// 3. 增加紧凑/舒适两档视图：衣物多时大图翻找很慢，紧凑档能一屏看更多。
import { Category, CATEGORIES, Garment, GarmentStatus, STATUSES, garmentImage } from '../model/Wardrobe';
import { Theme, Type } from '../components/Theme';
import { MaterialCard, ChipTone, cardMaterial, panelMaterial } from '../components/MaterialKit';

@Component
export struct WardrobePage {
  @Prop garments: Garment[] = [];
  @Prop search: string = '';
  @Link filterCategory: string;
  @Link filterStatus: string;
  @Prop readBlocked: boolean = false;
  @State compact: boolean = false;
  onSearch: (value: string) => void = () => {};
  onAddGarment: () => void = () => {};
  onOpenItem: (item: Garment) => void = () => {};
  onSetStatus: (id: string, status: GarmentStatus) => void = () => {};

  private readyCount(): number {
    return this.garments.filter((item: Garment) => item.status === GarmentStatus.READY).length;
  }

  // 常穿：按穿着次数排序。帮助用户看到"真正在穿的"和"买了没穿的"。
  private mostWorn(): Garment[] {
    return this.garments.slice()
      .sort((left: Garment, right: Garment) => right.wearCount - left.wearCount)
      .slice(0, 6);
  }

  private countByStatus(status: GarmentStatus): number {
    return this.garments.filter((item: Garment) => item.status === status).length;
  }

  private filtered(): Garment[] {
    const keyword: string = this.search.trim();
    return this.garments.filter((item: Garment) =>
      (this.filterCategory === '全部' || item.category === this.filterCategory) &&
      (this.filterStatus === '全部状态' || item.status === this.filterStatus) &&
      (keyword.length === 0 || item.name.indexOf(keyword) >= 0 || item.color.indexOf(keyword) >= 0 ||
        (item.subcategory || '').indexOf(keyword) >= 0 || (item.material || '').indexOf(keyword) >= 0));
  }

  @Builder
  private summary() {
    Column({ space: Theme.spaceM }) {
      Row({ space: Theme.spaceM }) {
        Column({ space: Theme.spaceXs }) {
          Text(String(this.garments.length)).fontSize(32).fontWeight(FontWeight.Bold)
            .fontColor(Theme.text).maxLines(1)
          Text('件衣物').fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Column({ space: Theme.spaceXs }) {
          Text(String(this.readyCount())).fontSize(32).fontWeight(FontWeight.Bold)
            .fontColor(Theme.accent).maxLines(1)
          Text('件可穿').fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Column({ space: Theme.spaceXs }) {
          Text(String(this.garments.length - this.readyCount())).fontSize(32).fontWeight(FontWeight.Bold)
            .fontColor(Theme.tertiary).maxLines(1)
          Text('件待处理').fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%')
      Button('上传衣物', { type: ButtonType.Normal }).width('100%').height(Theme.buttonHeight)
        .borderRadius(Theme.radiusPill).backgroundColor(Theme.accent).fontColor(Theme.onAccent)
        .fontSize(Type.button).enabled(!this.readBlocked)
        .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
        .onClick(() => this.onAddGarment())
    }
      .width('100%')
      .padding(Theme.spaceL)
      .borderRadius(Theme.radiusCard)
      .backgroundColor(Theme.surface)
      .systemMaterial(cardMaterial())
  }

  // 筛选条：品类 + 状态 + 视图开关放在同一条，作为固定控件与下方衣物图片分层。
  // 说明：这里没有做吸顶——Scroll 容器不支持 sticky（只有 List 支持），
  // 要做到吸顶需要把整页改成 List + ListItemGroup，收益与改动量不成比例，先如实保留。
  // 这正是官方规范里"交互组件与内容重叠"的场景，所以给它材质：
  // THIN + 向下渐变模糊，内容从下沿淡出，不会出现硬边把图片切断。
  @Builder
  private filterBar() {
    Column({ space: Theme.spaceS }) {
      Scroll() {
        Row({ space: Theme.spaceS }) {
          Text('全部').fontSize(Type.bodySmall)
            .fontColor(this.filterCategory === '全部' ? Theme.accent : Theme.secondary)
            .padding({ left: Theme.spaceL, right: Theme.spaceL, top: Theme.spaceS, bottom: Theme.spaceS })
            .backgroundColor(this.filterCategory === '全部' ? Theme.accentSoft : Theme.surfaceSoft)
            .borderRadius(Theme.radiusPill)
            .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
            .onClick(() => this.filterCategory = '全部')
          ForEach(CATEGORIES, (value: Category) => {
            Text(value).fontSize(Type.bodySmall)
              .fontColor(this.filterCategory === value ? Theme.accent : Theme.secondary)
              .padding({ left: Theme.spaceL, right: Theme.spaceL, top: Theme.spaceS, bottom: Theme.spaceS })
              .backgroundColor(this.filterCategory === value ? Theme.accentSoft : Theme.surfaceSoft)
              .borderRadius(Theme.radiusPill)
              .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
              .onClick(() => this.filterCategory = value)
          }, (value: Category) => value)
        }
      }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      Row({ space: Theme.spaceS }) {
        ForEach(['全部状态', GarmentStatus.READY, GarmentStatus.LAUNDRY], (value: string) => {
          Text(value).fontSize(Type.caption)
            .fontColor(this.filterStatus === value ? Theme.accent : Theme.secondary)
            .padding({ left: Theme.spaceM, right: Theme.spaceM, top: Theme.spaceXs, bottom: Theme.spaceXs })
            .backgroundColor(this.filterStatus === value ? Theme.accentSoft : Theme.surfaceSoft)
            .borderRadius(Theme.radiusChip)
            .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
            .onClick(() => this.filterStatus = value)
        }, (value: string) => value)
        Blank()
        Text(this.compact ? '舒适视图' : '紧凑视图').fontSize(Type.caption).fontColor(Theme.accent)
          .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
          .onClick(() => this.compact = !this.compact)
      }.width('100%')
    }
      .width('100%')
      .padding({ top: Theme.spaceS, bottom: Theme.spaceS })
      .backgroundColor(Theme.background)
      .systemMaterial(panelMaterial())
      // 下沿渐变模糊：吸顶时下方的衣物图片柔化，不会撞在一条硬边上。
      .linearGradientBlur(20, {
        fractionStops: [[0.0, 0.0], [1.0, 1.0]],
        direction: GradientDirection.Top
      })
  }

  @Builder
  private mostWornStrip() {
    Column({ space: Theme.spaceS }) {
      Row() {
        Text('常穿').fontSize(Type.cardTitle).fontWeight(FontWeight.Medium)
          .fontColor(Theme.text).layoutWeight(1).maxLines(1)
        Text('按穿着次数排序').fontSize(Type.caption).fontColor(Theme.tertiary).maxLines(1)
      }.width('100%')
      Scroll() {
        Row({ space: Theme.spaceS }) {
          ForEach(this.mostWorn(), (item: Garment) => {
            Column({ space: Theme.spaceXs }) {
              Image(garmentImage(item)).width(72).height(72).objectFit(ImageFit.Contain)
                .backgroundColor(Theme.imagePlaceholder).borderRadius(Theme.radiusInput)
              Text(String(item.wearCount) + ' 次').fontSize(Type.caption)
                .fontColor(Theme.tertiary).maxLines(1)
            }
              .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
              .onClick(() => this.onOpenItem(item))
          }, (item: Garment) => 'worn_' + item.id)
        }
      }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
    }.width('100%')
  }

  // 整理任务：把非可穿状态的衣物聚合成入口，点一下直接筛出来处理。
  @Builder
  private tidyTasks() {
    Column({ space: Theme.spaceS }) {
      Row() {
        Text('整理任务').fontSize(Type.cardTitle).fontWeight(FontWeight.Medium)
          .fontColor(Theme.text).layoutWeight(1).maxLines(1)
      }.width('100%')
      Row({ space: Theme.spaceS }) {
        ForEach([GarmentStatus.LAUNDRY, GarmentStatus.STORED, GarmentStatus.HIDDEN, GarmentStatus.ARCHIVED],
          (status: GarmentStatus) => {
            Column({ space: Theme.spaceXs }) {
              Text(String(this.countByStatus(status))).fontSize(Type.cardTitle)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.countByStatus(status) > 0 ? Theme.accent : Theme.tertiary).maxLines(1)
              Text(status).fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
            }
              .layoutWeight(1)
              .padding({ top: Theme.spaceS, bottom: Theme.spaceS })
              .backgroundColor(Theme.surfaceSoft)
              .borderRadius(Theme.radiusChip)
              .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
              .onClick(() => {
                // 再点一次同一个状态就回到全部，省一次额外操作。
                this.filterStatus = this.filterStatus === status ? '全部状态' : status;
              })
          }, (status: GarmentStatus) => 'tidy_' + status)
      }.width('100%')
    }.width('100%')
  }

  @Builder
  private garmentCell(item: Garment) {
    Column({ space: this.compact ? Theme.spaceXs : Theme.spaceS }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(garmentImage(item))
          .width('100%')
          .aspectRatio(this.compact ? 1 : 0.88)
          .objectFit(ImageFit.Contain)
          .backgroundColor(Theme.imagePlaceholder)
          .borderRadius(Theme.radiusInput)
        Text(item.status).fontSize(10)
          .fontColor(item.status === GarmentStatus.READY ? Theme.success : Theme.secondary)
          .padding({ left: Theme.spaceS, right: Theme.spaceS, top: 2, bottom: 2 })
          .backgroundColor(item.status === GarmentStatus.READY ? Theme.successSoft : Theme.surfaceSoft)
          .borderRadius(Theme.radiusChip)
          .margin(Theme.spaceS)
      }.width('100%')
      Text(item.name).fontSize(Type.caption).fontWeight(FontWeight.Medium).fontColor(Theme.text)
        .maxLines(this.compact ? 1 : 2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      if (!this.compact) {
        Text((item.subcategory || item.category) + ' · ' + item.wearCount + ' 次')
          .fontSize(Type.caption).fontColor(Theme.tertiary).maxLines(1).width('100%')
      }
    }
      .padding(Theme.spaceS)
      .width('100%')
      .backgroundColor(Theme.surface)
      .borderRadius(Theme.radiusCard)
      .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
      .onClick(() => this.onOpenItem(item))
  }

  @Builder
  private emptyResult() {
    MaterialCard({ contentPadding: Theme.spaceXl }) {
      Column({ space: Theme.spaceM }) {
        SymbolGlyph($r('sys.symbol.shirt')).fontSize(40).fontColor([Theme.tertiary])
        Text(this.garments.length === 0 ? '衣橱还是空的' : '这里还没有衣物')
          .fontSize(Type.bodySmall).fontColor(Theme.text).maxLines(2).textAlign(TextAlign.Center)
        Text(this.garments.length === 0
          ? '先添加 5 件常穿单品，就能生成第一套搭配。拍照或从相册导入都可以。'
          : '可以调整筛选条件，或添加一件常穿的衣物。')
          .fontSize(Type.caption).fontColor(Theme.tertiary).maxLines(4).textAlign(TextAlign.Center)
        Button(this.garments.length === 0 ? '上传衣物' : '清除筛选', { type: ButtonType.Normal })
          .fontSize(Type.buttonSmall).height(Theme.buttonHeight).width('100%')
          .borderRadius(Theme.radiusPill).backgroundColor(Theme.accent).fontColor(Theme.onAccent)
          .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
          .onClick(() => {
            if (this.garments.length === 0) { this.onAddGarment(); return; }
            this.filterCategory = '全部';
            this.filterStatus = '全部状态';
            this.onSearch('');
          })
      }.alignItems(HorizontalAlign.Center).width('100%')
    }
  }

  build() {
    Column({ space: Theme.spaceL }) {
      Column({ space: Theme.spaceXs }) {
        Text('我的衣橱').fontSize(Type.title).fontWeight(FontWeight.Bold)
          .fontColor(Theme.text).maxLines(1)
        Text('按品类和状态整理，常穿的会排在推荐前面')
          .fontSize(Type.caption).fontColor(Theme.secondary).maxLines(2)
      }.alignItems(HorizontalAlign.Start).width('100%')

      this.summary()
      if (this.garments.length > 0) { this.mostWornStrip() }
      if (this.garments.length > 0) { this.tidyTasks() }

      Search({ value: this.search, placeholder: '搜索衣物名称或颜色' }).height(Theme.buttonCompact)
        .backgroundColor(Theme.surfaceSoft).fontColor(Theme.text).placeholderColor(Theme.tertiary)
        .borderRadius(Theme.radiusPill)
        .onChange((value: string) => this.onSearch(value))
      // 筛选条吸顶：滚到顶部时压住衣物图片。
      this.filterBar()

      if (this.filtered().length === 0) {
        this.emptyResult()
      } else {
        Grid() {
          ForEach(this.filtered(), (item: Garment) => {
            GridItem() { this.garmentCell(item) }
          }, (item: Garment) => item.id + '_' + item.status + '_' + this.compact)
        }
          .columnsTemplate(this.compact ? 'repeat(auto-fit, 108)' : 'repeat(auto-fit, 150)')
          .columnsGap(this.compact ? Theme.spaceS : Theme.spaceM)
          .rowsGap(this.compact ? Theme.spaceS : Theme.spaceM)
          .width('100%')
      }
    }
      .width('100%')
      .constraintSize({ maxWidth: 840 })
      .padding({ left: Theme.pagePadding, right: Theme.pagePadding, bottom: Theme.spaceXxl })
  }
}
