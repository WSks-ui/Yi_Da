// 首页：天气行、错落工作台、快捷入口、本月记录、推荐和日记。
// 切角纸片与轻微倾斜的贴纸形成层次，真实衣物照片与状态仍由父页面提供。
import { DiaryEntry, Garment, Outfit } from '../model/Wardrobe';
import { Theme, Type } from '../components/Theme';
import { MaterialChip, ChipTone } from '../components/MaterialKit';
import { DadaOrb } from '../components/DadaOrb';
import { precipitationAdvice, temperatureAdvice } from '../service/TemperatureAdvice';
import { common } from '@kit.AbilityKit';

function imageOfItem(item: Garment | undefined): ResourceStr {
  if (item === undefined) { return $r('app.media.demo_tee'); }
  if (item.imageUri.length > 0) { return item.imageUri; }
  switch (item.imageKey) {
    case 'shirt': return $r('app.media.demo_shirt');
    case 'jeans': return $r('app.media.demo_jeans');
    case 'shoes': return $r('app.media.demo_sneakers');
    case 'jacket': return $r('app.media.demo_jacket');
    case 'graphic': return $r('app.media.demo_knit');
    default: return $r('app.media.demo_tee');
  }
}

@Component
export struct HomePage {
  @Prop garmentCount: number = 0;
  @Prop todayRecorded: boolean = false;
  @Prop city: string = '';
  @Prop weather: string = '';
  @Prop tempMin: number = 0;
  @Prop tempMax: number = 0;
  @Prop weatherAvailable: boolean = false;
  @Prop monthRecorded: number = 0;
  @Prop outfits: Outfit[] = [];
  @Prop diary: DiaryEntry[] = [];
  @Prop garments: Garment[] = [];
  onOpenBanner: () => void = () => {};
  onAddGarment: () => void = () => {};
  onOpenWardrobe: () => void = () => {};
  onRecordOutfit: () => void = () => {};
  onOpenDiy: () => void = () => {};
  onOpenDiary: () => void = () => {};
  onOpenTryOn: () => void = () => {};
  onOpenAssistant: () => void = () => {};
  onSaveOutfit: (look: Outfit) => void = () => {};
  onRecordLook: (look: Outfit) => void = () => {};
  onOpenProfile: () => void = () => {};
  onOpenCity: () => void = () => {};
  onOpenOutfit: (look: Outfit) => void = () => {};
  onOpenTile: (name: string) => void = () => {};
  @State textScale: number = 1;
  // 首页各段是否已入场。初始 false，aboutToAppear 里延后一帧置 true，触发错峰动画。
  @State entered: boolean = false;
  private quickNames: string[] = ['今日搭配', '搭配收藏', '穿搭测评', '穿搭日记',
    '添加衣物', '衣橱整理', '桌面卡片', 'AI试穿'];
  private quickIcons: Resource[] = [
    $r('sys.symbol.shirt'), $r('sys.symbol.heart'), $r('sys.symbol.checkmark_circle'),
    $r('sys.symbol.calendar'), $r('sys.symbol.camera'), $r('sys.symbol.square_grid_2x2'),
    $r('sys.symbol.square_grid_2x2'), $r('sys.symbol.person')
  ];
  private tileColors: Resource[] = [$r('app.color.home_blue'), $r('app.color.home_rose'),
    $r('app.color.home_mint'), $r('app.color.home_yellow')];
  private tileInks: Resource[] = [$r('app.color.home_blue_ink'), Theme.accent,
    $r('app.color.home_mint_ink'), $r('app.color.home_yellow_ink')];

  private itemOf(id: string): Garment | undefined {
    return this.garments.find((item: Garment) => item.id === id);
  }

  aboutToAppear(): void {
    this.updateTextScale();
    // 错峰入场的开关。必须延后一帧再置 true：先让初始态（透明 + 下移）真正渲染一帧，
    // 属性变化才有起点可插值；在同一帧里直接置 true 会跳过动画、直接出现在终态。
    setTimeout(() => { this.entered = true; }, 30);
  }

  private updateTextScale(): void {
    const context: common.UIAbilityContext | undefined = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    this.textScale = Math.max(1, Math.min(Theme.maxFontScale,
      context?.config.fontSizeScale ?? 1));
  }

  // 放大字体时同步增加纸片与按钮高度，保持左右两列齐底；不把内容裁在固定高度里。
  private boardHeight(): number { return 248 + (this.textScale - 1) * 280; }
  private sideHeight(): number { return (this.boardHeight() - 12) / 2; }

  private openTile(name: string): void {
    if (name === '穿搭日记') { this.onOpenDiary(); return; }
    if (name === 'AI试穿') { this.onOpenTryOn(); return; }
    this.onOpenTile(name);
  }

  // 副标题不再写「手动温度」这种数据来源标签——那对用户没有信息量。
  // 改成把温度翻译成一句可执行的提示：穿什么、要不要带伞。
  private adviceText(): string {
    const rain: string = precipitationAdvice(this.weatherAvailable ? this.weather : '');
    if (rain.length > 0) { return rain; }
    return temperatureAdvice(this.referenceTemp()).text;
  }

  // 取当天的代表性温度：有区间时取中间值，避免最高温把提示带偏。
  private referenceTemp(): number {
    if (this.tempMax > this.tempMin) { return Math.round((this.tempMin + this.tempMax) / 2); }
    return this.tempMax;
  }

  private adviceIcon(): Resource {
    const rain: string = precipitationAdvice(this.weatherAvailable ? this.weather : '');
    if (rain.length > 0) { return $r('sys.symbol.umbrella'); }
    return this.iconKeyToResource(temperatureAdvice(this.referenceTemp()).iconKey);
  }

  // 图标键到资源的映射放在组件里：service 层要能在 Node 里跑测试，
  // 而 $r() 是 ArkUI 运行时函数，脱离运行时会得到 undefined。
  private iconKeyToResource(key: string): Resource {
    if (key === 'snow') { return $r('sys.symbol.snowflake'); }
    if (key === 'cloud') { return $r('sys.symbol.cloud'); }
    // 温和天气用云加太阳：22℃ 配烈日图标会让人误以为很热。
    if (key === 'mild') { return $r('sys.symbol.cloud_and_sun_fill'); }
    return $r('sys.symbol.sun_max');
  }

  @Builder
  private weatherRow() {
    Row({ space: 8 }) {
      SymbolGlyph(this.adviceIcon()).fontSize(27).fontColor([Theme.secondary])
      Column({ space: 2 }) {
        Text(this.city.length > 0 ? this.city : '选择城市').fontSize(Type.bodySmall)
          .fontWeight(FontWeight.Medium).fontColor(Theme.text).maxLines(1)
        Text(this.adviceText()).fontSize(Type.caption)
          .fontColor(Theme.secondary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text(this.tempMax > this.tempMin ? `${this.tempMin}° / ${this.tempMax}°` : `${this.tempMax}°`)
        .fontSize(Type.title).fontWeight(FontWeight.Medium).fontColor(Theme.text)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([Theme.secondary])
    }.width('100%').constraintSize({ minHeight: 40 }).padding({ left: 4, right: 4 })
      .accessibilityGroup(true).accessibilityText('城市与天气，点击调整')
      .onClick(() => this.onOpenCity())
  }

  // 顶部占 72% 宽，与下半部组成切角轮廓；右上缺口给贴纸留出空间。
  // 使用相对宽度而非固定 Path 坐标，换屏幕宽度时转折比例保持一致。
  @Builder
  private paper(height: number, color: ResourceColor) {
    Column() {
      Row().width('72%').height(30).backgroundColor(color)
        .borderRadius({ topLeft: 20, topRight: 26 })
      Row().width('100%').height(height - 30).backgroundColor(color)
        .borderRadius({ topRight: 26, bottomLeft: 20, bottomRight: 20 })
    }.width('100%').height(height).alignItems(HorizontalAlign.Start)
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private sticker(icon: Resource, color: ResourceColor, ink: ResourceColor, angle: number) {
    Stack() {
      Rect().width(44).height(48).radius(12).fill(color)
        .border({ width: 2, color: Theme.surface, radius: 12 })
      SymbolGlyph(icon).fontSize(27).fontColor([ink])
    }.width(48).height(52).rotate({ angle: angle })
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private wardrobeEntry() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.paper(this.boardHeight(), Theme.surface)
      Column({ space: 6 }) {
        Text('我的衣橱').fontSize(Type.section).fontWeight(FontWeight.Bold)
          .fontColor(Theme.text).maxLines(2).width('75%')
          .onClick(() => this.onOpenWardrobe())
        Text(`已收纳 ${this.garmentCount} 件衣物`).fontSize(Type.caption)
          .fontColor(Theme.secondary).maxLines(2).width('100%')
        Stack() {
          if (this.garments.length > 0) {
            Image(imageOfItem(this.garments[this.garments.length > 1 ? 1 : 0]))
              .width(73).height(94).objectFit(ImageFit.Cover)
              .border({ width: 4, color: Theme.surface }).borderRadius(8)
              .rotate({ angle: 11 }).translate({ x: 26, y: -2 }).shadow(Theme.cardShadow)
            Image(imageOfItem(this.garments[0])).width(73).height(94).objectFit(ImageFit.Cover)
              .border({ width: 4, color: Theme.surface }).borderRadius(8)
              .rotate({ angle: -9 }).translate({ x: -22, y: 2 }).shadow(Theme.cardShadow)
          } else {
            SymbolGlyph($r('sys.symbol.shirt')).fontSize(66).fontColor([Theme.accent])
          }
        }.width('100%').height(112).accessibilityGroup(true).accessibilityText('打开我的衣橱')
          .onClick(() => this.onOpenWardrobe())
        Button({ type: ButtonType.Normal }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.plus')).fontSize(15).fontColor([Theme.onAccent])
            Text('上传衣物').fontSize(Type.buttonSmall).fontColor(Theme.onAccent)
              .maxLines(2).layoutWeight(1).textAlign(TextAlign.Center)
          }.width('100%').padding({ left: 12, right: 12 }).justifyContent(FlexAlign.Center)
        }.width('100%').height(40 * this.textScale).backgroundColor(Theme.accent).borderRadius(20)
          .onClick(() => this.onAddGarment())
      }.width('100%').height(this.boardHeight()).padding({ top: 18, left: 14, right: 14, bottom: 14 })
        .alignItems(HorizontalAlign.Start)
      Row() {
        this.sticker($r('sys.symbol.shirt'), $r('app.color.home_rose'), Theme.accent, 10)
      }.width('100%').justifyContent(FlexAlign.End).padding({ right: 3 }).translate({ y: -10 })
        // 整行装饰层都穿透，不能仅设置贴纸本身，否则空白处会挡住衣橱标题的点击。
        .hitTestBehavior(HitTestMode.None)
    }.width('100%').height(this.boardHeight())
  }

  @Builder
  private smallEntry(record: boolean) {
    Stack({ alignContent: Alignment.TopStart }) {
      this.paper(this.sideHeight(), record ? Theme.surface : $r('app.color.home_mint'))
      Column({ space: 8 }) {
        Text(record ? '今日穿搭' : '搭配 DIY').fontSize(Type.section).fontWeight(FontWeight.Bold)
          .fontColor(Theme.text).maxLines(2).width('75%')
        Text(record ? (this.todayRecorded ? '已记录，回看今天' : '今天，想怎么穿？') : '灵感由你，自由组合')
          .fontSize(Type.caption).fontColor(Theme.secondary).maxLines(2)
        Row({ space: 5 }) {
          Text(record ? (this.todayRecorded ? '查看日记' : '记录穿搭') : '开始搭配')
            .fontSize(Type.caption).fontWeight(FontWeight.Medium)
            .fontColor(record ? Theme.accent : $r('app.color.home_mint_ink'))
          SymbolGlyph($r('sys.symbol.arrow_right')).fontSize(13)
            .fontColor([record ? Theme.accent : $r('app.color.home_mint_ink')])
        }
      }.width('100%').padding({ top: 18, left: 14, right: 12 }).alignItems(HorizontalAlign.Start)
      Row() {
        this.sticker(record ? $r('sys.symbol.calendar') : $r('sys.symbol.square_grid_2x2'),
          record ? $r('app.color.home_blue') : $r('app.color.home_yellow'),
          record ? $r('app.color.home_blue_ink') : $r('app.color.home_yellow_ink'), record ? 9 : -9)
      }.width('100%').justifyContent(FlexAlign.End).padding({ right: 2 }).translate({ y: -10 })
        .hitTestBehavior(HitTestMode.None)
    }.width('100%').height(this.sideHeight())
      .stateStyles({ pressed: { .scale({ x: 0.97, y: 0.97 }) } })
      .accessibilityGroup(true).accessibilityText(record ? '今日穿搭' : '搭配DIY')
      .onClick(() => { if (record) { this.onRecordOutfit(); } else { this.onOpenDiy(); } })
  }

  @Builder
  private entryBoard() {
    Row({ space: 12 }) {
      Column() { this.wardrobeEntry() }.layoutWeight(1)
      Column({ space: 12 }) {
        this.smallEntry(true)
        this.smallEntry(false)
      }.layoutWeight(1)
    }.width('100%').alignItems(VerticalAlign.Top).margin({ top: 8 })
  }

  @Builder
  private quickGrid() {
    // 两行快捷入口紧随主操作区，去掉重复标题与包围整组功能的大卡片。
    Grid() {
      ForEach(this.quickNames, (name: string, index: number) => {
        GridItem() {
          Button({ type: ButtonType.Normal }) {
            Column({ space: 9 }) {
              Stack() {
                Rect().width(42).height(42).radius(12).fill(this.tileColors[index % 4])
                  .rotate({ angle: index % 2 === 0 ? -6 : 6 })
                SymbolGlyph(this.quickIcons[index]).fontSize(24).fontColor([this.tileInks[index % 4]])
              }.width(48).height(46)
              Text(name).fontSize(Type.caption).fontColor(Theme.text).maxLines(2)
            }.width('100%').justifyContent(FlexAlign.Center)
          }.width('100%').height(78 + (this.textScale - 1) * 48)
            .backgroundColor(Color.Transparent).borderRadius(8)
            .accessibilityText(name).onClick(() => this.openTile(name))
        }
      }, (name: string) => name)
    }.columnsTemplate('1fr 1fr 1fr 1fr').rowsTemplate('1fr 1fr')
      .columnsGap(4).rowsGap(8).width('100%').height(164 + (this.textScale - 1) * 96)
  }

  @Builder
  private monthlyNote() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(String(this.monthRecorded).padStart(2, '0')).fontSize(30).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.home_blue_ink'))
        Text('本月穿搭').fontSize(Type.caption).fontColor(Theme.secondary)
      }.width(72).rotate({ angle: -5 })
      Column({ space: 4 }) {
        Text(this.garmentCount < 5 ? '给衣橱添一点新灵感' : '穿过的日常，都值得收藏')
          .fontSize(Type.cardTitle).fontWeight(FontWeight.Medium).fontColor(Theme.text).maxLines(2)
        Text(this.garmentCount < 5 ? '添加常穿单品，开始你的搭配' : `已记下 ${this.monthRecorded} 天 · 翻开穿搭日记`)
          .fontSize(Type.caption).fontColor(Theme.secondary).maxLines(2)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.arrow_right')).fontSize(18).fontColor([$r('app.color.home_blue_ink')])
    }.width('100%').padding({ top: 14, bottom: 14, left: 10, right: 14 })
      .border({ width: { top: 1, bottom: 1 }, color: Theme.line, style: BorderStyle.Dashed })
      .onClick(() => this.onOpenBanner())
  }

  @Builder
  private outfitCard(look: Outfit, primary: boolean) {
    Column({ space: Theme.spaceM }) {
      Row({ space: Theme.spaceS }) {
        MaterialChip({ label: look.occasion, tone: ChipTone.NEUTRAL })
        MaterialChip({ label: `${look.temperature}℃`, tone: ChipTone.ACCENT })
        if (look.isCustom) { MaterialChip({ label: 'DIY', tone: ChipTone.SUCCESS }) }
        Blank()
      }.width('100%')
      Row({ space: Theme.spaceS }) {
        ForEach(look.garmentIds, (id: string) => {
          Column({ space: Theme.spaceXs }) {
            Image(imageOfItem(this.itemOf(id))).width('100%').height(primary ? 132 : 112)
              .objectFit(ImageFit.Contain).backgroundColor(Theme.imagePlaceholder).borderRadius(8)
            Text(this.itemOf(id)?.category || '').fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
          }.layoutWeight(1)
        }, (id: string) => id)
      }.width('100%')
      Text(look.reason).fontSize(Type.bodySmall).fontColor(Theme.secondary)
        .lineHeight(22).maxLines(3).width('100%')
      Button({ type: ButtonType.Normal }) {
        Row() {
          Text('看看这套搭配').fontSize(Type.buttonSmall).fontColor(Theme.accent).layoutWeight(1)
          SymbolGlyph($r('sys.symbol.arrow_right')).fontSize(18).fontColor([Theme.accent])
        }.width('100%')
      }.height(44).width('100%').backgroundColor(Theme.accentSoft).borderRadius(8)
        .onClick(() => this.onOpenOutfit(look))
      Row({ space: Theme.spaceS }) {
        Button('收藏方案', { type: ButtonType.Normal }).layoutWeight(1).height(36)
          .fontSize(Type.buttonSmall).borderRadius(Theme.radiusPill)
          .backgroundColor(Theme.surfaceSoft).fontColor(Theme.secondary)
          .onClick(() => this.onSaveOutfit(look))
        Button('记录已穿', { type: ButtonType.Normal }).layoutWeight(1).height(36)
          .fontSize(Type.buttonSmall).borderRadius(Theme.radiusPill)
          .backgroundColor(Theme.accent).fontColor(Theme.onAccent)
          .onClick(() => this.onRecordLook(look))
      }.width('100%')
    }.width('100%').padding(16).borderRadius(Theme.radiusCard).backgroundColor(Theme.surface)
  }

  @Builder
  private recommendations() {
    Column({ space: 12 }) {
      Row() {
        Text('今日灵感').fontSize(Type.section).fontWeight(FontWeight.Bold).fontColor(Theme.text).layoutWeight(1)
        Text(this.outfits.length > 0 ? `${this.outfits.length} 套为你挑选` : '等待新灵感')
          .fontSize(Type.caption).fontColor(Theme.secondary)
      }.width('100%')
      if (this.outfits.length === 0) {
        Column({ space: 12 }) {
          Text(this.garmentCount === 0 ? '从第一件喜欢的衣服开始' : '当前条件下没有合适搭配')
            .fontSize(Type.bodySmall).fontColor(Theme.text)
          Button(this.garmentCount === 0 ? '上传衣物' : '调整搭配条件')
            .fontSize(Type.buttonSmall).height(44).backgroundColor(Theme.accent).fontColor(Theme.onAccent)
            .onClick(() => {
              if (this.garmentCount === 0) { this.onAddGarment(); } else { this.onOpenTile('今日搭配'); }
            })
        }.width('100%').padding(20)
      } else {
        ForEach(this.outfits.slice(0, 2), (look: Outfit, index: number) => {
          this.outfitCard(look, index === 0)
        }, (look: Outfit) => look.id)
      }
    }.width('100%')
  }

  @Builder
  private recentDiary() {
    Column({ space: 12 }) {
      Row() {
        Text('穿搭手记').fontSize(Type.section).fontWeight(FontWeight.Bold).fontColor(Theme.text).layoutWeight(1)
        Button('全部', { type: ButtonType.Normal }).fontSize(Type.caption).fontColor(Theme.secondary)
          .height(36).backgroundColor(Color.Transparent).onClick(() => this.onOpenDiary())
      }.width('100%')
      if (this.diary.length === 0) {
        Text('今天的穿搭，留给以后的自己。').fontSize(Type.bodySmall).fontColor(Theme.secondary).width('100%')
        Button('记录今日穿搭').fontSize(Type.buttonSmall).height(44).backgroundColor(Theme.accentSoft)
          .fontColor(Theme.accent).onClick(() => this.onRecordOutfit())
      } else {
        ForEach(this.diary.slice(0, 2), (entry: DiaryEntry) => {
          Row({ space: 12 }) {
            if (entry.garmentIds.length > 0) {
              Image(imageOfItem(this.itemOf(entry.garmentIds[0]))).width(52).height(64)
                .objectFit(ImageFit.Cover).borderRadius(8).rotate({ angle: -4 })
            }
            Column({ space: 6 }) {
              Text(entry.date).fontSize(Type.caption).fontColor(Theme.secondary)
              Text(entry.note.length > 0 ? entry.note : `${entry.garmentIds.length} 件单品 · ${entry.occasion}`)
                .fontSize(Type.bodySmall).fontColor(Theme.text).maxLines(2)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([Theme.secondary])
          }.width('100%').padding(14).backgroundColor(Theme.surface).borderRadius(Theme.radiusCard)
            .onClick(() => this.onOpenDiary())
        }, (entry: DiaryEntry) => entry.id)
      }
    }.width('100%')
  }

  build() {
    Column({ space: 22 }) {
      // 错峰入场：六段按 55ms 依次淡入并轻微上移。
      // 每段包一层容器承载动画属性——ArkTS 里 @Builder 调用后不能直接挂属性。
      // 位移只有 20vp，够看出"依次落位"，又不会让页面像在跳动。
      Column() { this.weatherRow() }.width('100%')
        .opacity(this.entered ? 1 : 0).translate({ y: this.entered ? 0 : 20 })
        .animation({ duration: 300, delay: 0, curve: Curve.FastOutSlowIn })
      Row({ space: 10 }) {
        DadaOrb({ diameter: 28, pulseKey: 'today' })
        Column({ space: 2 }) {
          Text('搭搭').fontSize(Type.bodySmall).fontWeight(FontWeight.Medium).fontColor(Theme.text)
          Text('说说场合和温度，先看看穿搭建议').fontSize(Type.caption).fontColor(Theme.secondary)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('开始', { type: ButtonType.Normal }).height(48).width(68).fontSize(Type.buttonSmall)
          .borderRadius(Theme.radiusPill).backgroundColor(Theme.accentSoft).fontColor(Theme.accent)
          .onClick(() => this.onOpenAssistant())
      }.width('100%').padding({ left: 14, right: 8, top: 8, bottom: 8 })
        .backgroundColor(Theme.accentSoft).borderRadius(Theme.radiusCard)
        .opacity(this.entered ? 1 : 0).translate({ y: this.entered ? 0 : 20 })
        .animation({ duration: 300, delay: 35, curve: Curve.FastOutSlowIn })
      Column() { this.entryBoard() }.width('100%')
        .opacity(this.entered ? 1 : 0).translate({ y: this.entered ? 0 : 20 })
        .animation({ duration: 300, delay: 55, curve: Curve.FastOutSlowIn })
      Column() { this.quickGrid() }.width('100%')
        .opacity(this.entered ? 1 : 0).translate({ y: this.entered ? 0 : 20 })
        .animation({ duration: 300, delay: 110, curve: Curve.FastOutSlowIn })
      Column() { this.monthlyNote() }.width('100%')
        .opacity(this.entered ? 1 : 0).translate({ y: this.entered ? 0 : 20 })
        .animation({ duration: 300, delay: 165, curve: Curve.FastOutSlowIn })
      Column() { this.recommendations() }.width('100%')
        .opacity(this.entered ? 1 : 0).translate({ y: this.entered ? 0 : 20 })
        .animation({ duration: 300, delay: 220, curve: Curve.FastOutSlowIn })
      Column() { this.recentDiary() }.width('100%')
        .opacity(this.entered ? 1 : 0).translate({ y: this.entered ? 0 : 20 })
        .animation({ duration: 300, delay: 275, curve: Curve.FastOutSlowIn })
    }.width('100%').constraintSize({ maxWidth: 840 })
      .padding({ left: Theme.pagePadding, right: Theme.pagePadding, top: 4, bottom: 24 })
      .onAreaChange(() => this.updateTextScale())
  }
}
