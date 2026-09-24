// 沉浸光感（Immersive Light）材质封装。
//
// 档位不是"越厚越好看"，而是由组件在页面中的位置和是否与内容重叠决定的。本文件按官方
// 设计规范的场景规范实现语义角色，页面只声明"这是什么位置的交互件"，不直接挑厚度：
//
//   topBarMaterial   顶部悬浮（顶栏、吸顶筛选）→ ULTRA_THIN + 渐变模糊
//   dockMaterial     底部悬浮（底部导航）      → THIN + 渐变颜色蒙层
//   floatingMaterial 任意位置弹出（气泡、浮层）→ THICK
//   sheetMaterial    半模态、弹出框            → ULTRA_THICK
//   cardMaterial     内容层卡片（常驻、不与内容重叠）→ REGULAR
//
// 用户可在系统里调三档强度，系统底层自动完成参数映射，因此这里不需要为三档分别适配。
//
// 设备不支持沉浸材质时全部返回 undefined，组件回落到普通卡片，不出现空白或报错。
// 参考：https://developer.huawei.com/consumer/cn/doc/design-guides/immersivelight-0000002612101053
import uiMaterial from '@ohos.arkui.uiMaterial';
import { hdsMaterial } from '@kit.UIDesignKit';
import { Theme, Type } from './Theme';

export class MaterialSupport {
  // 设备能力在启动时探测一次即可，避免每帧调用系统接口。
  private static supported: boolean | undefined = undefined;

  static isSupported(): boolean {
    if (MaterialSupport.supported === undefined) {
      try { MaterialSupport.supported = uiMaterial.isImmersiveMaterialSupported(); }
      catch (error) { MaterialSupport.supported = false; }
    }
    return MaterialSupport.supported;
  }

}

// 材质层着色必须带透明度：完全不透明会把材质滤镜整个挡住。
// 数值语义见文件末尾注释，便于后续统一调。
const TINT_CARD: string = '#12FFFFFF';
const TINT_TOP: string = '#0AFFFFFF';
const TINT_DOCK: string = '#14FFFFFF';
const TINT_FLOATING: string = '#26FFFFFF';

function build(style: uiMaterial.ImmersiveStyle, tint: string, shadow: boolean,
  interactive: boolean): uiMaterial.ImmersiveMaterial | undefined {
  if (!MaterialSupport.isSupported()) { return undefined; }
  return new uiMaterial.ImmersiveMaterial({
    style: style,
    materialColor: tint,
    applyShadow: shadow,
    interactive: interactive,
    // 光感交互反馈：手指触摸时光带沿边缘流转，颜色跟随品牌色。
    lightEffect: { color: $r('app.color.accent') }
  });
}

// 顶部悬浮：ULTRA_THIN。配渐变模糊向外延展，内容从下方淡出，不再有一条硬边。
export function topBarMaterial(): uiMaterial.ImmersiveMaterial | undefined {
  return build(uiMaterial.ImmersiveStyle.ULTRA_THIN, TINT_TOP, false, true);
}

// 底部悬浮：THIN。配渐变颜色蒙层把内容向下收住。
export function dockMaterial(): uiMaterial.ImmersiveMaterial | undefined {
  return build(uiMaterial.ImmersiveStyle.THIN, TINT_DOCK, false, true);
}

// 任意位置弹出：THICK。弹出位置不可预期，需要更高的内容可读性。
export function floatingMaterial(): uiMaterial.ImmersiveMaterial | undefined {
  return build(uiMaterial.ImmersiveStyle.THICK, TINT_FLOATING, true, true);
}

// 半模态与弹出框：ULTRA_THICK。面积大、信息多，可读性优先。
export function sheetMaterial(): uiMaterial.ImmersiveMaterial | undefined {
  return build(uiMaterial.ImmersiveStyle.ULTRA_THICK, TINT_FLOATING, true, false);
}

// 内容层卡片：REGULAR。这类卡片常驻且不与内容重叠，材质只需轻轻分层。
export function cardMaterial(): uiMaterial.ImmersiveMaterial | undefined {
  return build(uiMaterial.ImmersiveStyle.REGULAR, TINT_CARD, true, true);
}

// 悬浮胶囊专用材质：材质层着色比卡片更实。
// 原因：胶囊面积小，12% 白在浅色页面上几乎看不出形状，图标会被背景吃掉；
// 提到 55% 白之后形状立得住，同时仍保留材质的模糊与光感（不是纯色块）。
export function capsuleMaterial(): uiMaterial.ImmersiveMaterial | undefined {
  return build(uiMaterial.ImmersiveStyle.REGULAR, '#8CFFFFFF', true, true);
}
// 区域底板：比卡片更薄，用来把一整块区域托起来而不是强调单张卡片。
export function panelMaterial(): uiMaterial.ImmersiveMaterial | undefined {
  return build(uiMaterial.ImmersiveStyle.THIN, TINT_CARD, false, false);
}

// 顶部悬浮栏：材质 + 顶部渐变模糊，内容滚动到下面时自然淡出。
// 这是官方对"顶部悬浮组件"的推荐组合，单独成组件避免每处重复写模糊参数。
@Component
export struct TopBar {
  @Prop contentHeight: number = Theme.navBarHeight;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {}

  build() {
    Column() {
      this.content()
    }
      .width('100%')
      .height(this.contentHeight)
      .backgroundColor(Theme.background)
      .systemMaterial(topBarMaterial())
      // 0 → 1 的模糊梯度：上沿完全模糊，下沿清晰，形成"薄雾悬浮"而不是硬分割线。
      .linearGradientBlur(28, {
        fractionStops: [[0.0, 0.0], [1.0, 1.0]],
        direction: GradientDirection.Bottom
      })
  }
}

// 底部悬浮 Dock：材质 + 渐变颜色蒙层。蒙层从透明到不透明，把内容向下收住。
@Component
export struct BottomDock {
  @Prop contentHeight: number = Theme.navBarHeight + Theme.spaceS;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {}

  build() {
    Column() {
      this.content()
    }
      .width('100%')
      .height(this.contentHeight)
      .systemMaterial(dockMaterial())
      // 底部渐变蒙层：上方透明让内容透出，下方收实托住导航。
      .linearGradient({
        angle: 180,
        colors: [['#00FFFFFF', 0.0], ['#66FFFFFF', 0.55], ['#E6FFFFFF', 1.0]]
      })
  }
}

// 卡片容器：统一圆角、内边距与背景；支持沉浸材质时叠加材质层。
// 属性名避开 CustomComponent 自带的 padding，改用 contentPadding。
@Component
export struct MaterialCard {
  @Prop contentPadding: number = Theme.spaceL;
  @Prop radius: number = Theme.radiusCard;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {}

  build() {
    Column() {
      this.content()
    }
      .width('100%')
      .padding(this.contentPadding)
      .borderRadius(this.radius)
      .backgroundColor(Theme.surface)
      .systemMaterial(cardMaterial())
  }
}

// 区域底板：比卡片更薄，用于把整块区域托起来。
@Component
export struct MaterialPanel {
  @Prop contentPadding: number = Theme.spaceM;
  @Prop radius: number = Theme.radiusCard;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {}

  build() {
    Column() {
      this.content()
    }
      .width('100%')
      .padding(this.contentPadding)
      .borderRadius(this.radius)
      .backgroundColor(Theme.surface)
      .systemMaterial(panelMaterial())
  }
}

// 浮层容器：任意位置弹出，用 THICK 保证可读性。
@Component
export struct FloatingSurface {
  @Prop contentPadding: number = Theme.spaceL;
  @Prop radius: number = Theme.radiusCard;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {}

  build() {
    Column() {
      this.content()
    }
      .width('100%')
      .padding(this.contentPadding)
      .borderRadius(this.radius)
      .backgroundColor(Theme.surface)
      .shadow(Theme.floatShadow)
      .systemMaterial(floatingMaterial())
  }
}

// 区块标题：左标题 + 可选右侧"更多"入口。
@Component
export struct SectionHeader {
  @Prop title: string = '';
  @Prop action: string = '';

  build() {
    Row() {
      Text(this.title).fontSize(Type.section).fontWeight(FontWeight.Bold)
        .fontColor(Theme.text).maxLines(1)
      Blank()
      if (this.action.length > 0) {
        Text(this.action).fontSize(Type.bodySmall).fontColor(Theme.secondary).maxLines(1)
      }
    }.width('100%').padding({ top: Theme.spaceS, bottom: Theme.spaceM })
  }
}

// 带右侧入口的区块标题："更多"可点。
@Component
export struct SectionHeaderLink {
  @Prop title: string = '';
  @Prop action: string = '';
  onAction: () => void = () => {};

  build() {
    Row({ space: Theme.spaceXs }) {
      Text(this.title).fontSize(Type.section).fontWeight(FontWeight.Bold).fontColor(Theme.text).maxLines(1)
      Blank()
      Text(this.action).fontSize(Type.bodySmall).fontColor(Theme.accent).maxLines(1)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(Theme.iconSm).fontColor([Theme.accent])
    }
      .width('100%')
      .padding({ top: Theme.spaceS, bottom: Theme.spaceM })
      .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
      .onClick(() => this.onAction())
  }
}

// 功能宫格入口：图标 + 名称。
@Component
export struct ActionTile {
  @Prop icon: Resource = $r('sys.symbol.shirt');
  @Prop label: string = '';
  onTap: () => void = () => {};

  build() {
    Column({ space: Theme.spaceS }) {
      SymbolGlyph(this.icon).fontSize(Theme.iconLg).fontColor([Theme.accent])
      Text(this.label).fontSize(Type.caption).fontColor(Theme.text)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .width('100%')
      .padding({ top: Theme.spaceM, bottom: Theme.spaceM })
      .borderRadius(Theme.radiusCard)
      .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
      .onClick(() => this.onTap())
  }
}

// 标签色调用枚举而不是字符串：调用处拼错会编译失败，不会静默变成默认色。
export enum ChipTone {
  NEUTRAL = 0,
  ACCENT = 1,
  SUCCESS = 2
}

// 信息标签：温度、场合、状态这类短信息统一用它，保证跨页面观感一致。
@Component
export struct MaterialChip {
  @Prop label: string = '';
  @Prop icon: Resource = $r('sys.symbol.checkmark');
  @Prop showIcon: boolean = false;
  @Prop tone: ChipTone = ChipTone.NEUTRAL;

  private chipFg(): Resource {
    if (this.tone === ChipTone.ACCENT) { return Theme.accent; }
    if (this.tone === ChipTone.SUCCESS) { return Theme.success; }
    return Theme.secondary;
  }

  private chipBg(): Resource {
    if (this.tone === ChipTone.ACCENT) { return Theme.accentSoft; }
    if (this.tone === ChipTone.SUCCESS) { return Theme.successSoft; }
    return Theme.surfaceSoft;
  }

  build() {
    Row({ space: Theme.spaceXs }) {
      if (this.showIcon) {
        SymbolGlyph(this.icon).fontSize(Theme.iconSm).fontColor([this.chipFg()])
      }
      Text(this.label).fontSize(Type.caption).fontColor(this.chipFg()).maxLines(1)
    }
      .padding({ left: Theme.spaceS, right: Theme.spaceS, top: Theme.spaceXs, bottom: Theme.spaceXs })
      .backgroundColor(this.chipBg())
      .borderRadius(Theme.radiusInput)
  }
}

// ===== 悬浮胶囊组件 =====
// 官方沉浸光感的形态是"胶囊状悬浮组件"，而不是给整条栏加模糊：
// 内容在下方自由滚动，交互组件以圆角胶囊浮在其上，靠 Z 轴把内容与操作分开。
// 这里按官方场景规范实现两种位置：顶部 ULTRA_THIN、底部 THIN。

// 悬浮胶囊容器：圆角胶囊 + 材质 + 轻微投影。宽度自适应内容，便于"胶囊"形态成立。
@Component
export struct FloatingCapsule {
  @Prop contentPadding: number = Theme.spaceS;
  // 顶部胶囊底部圆角更大，底部胶囊顶部圆角更大，视觉上才像"浮"而不是"贴"。
  @Prop radius: number = Theme.radiusPill;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {}

  build() {
    Row() {
      this.content()
    }
      .padding(this.contentPadding)
      .borderRadius(this.radius)
      .backgroundColor(Theme.surface)
      .shadow(Theme.floatShadow)
      .systemMaterial(floatingMaterial())
  }
}

// 底部悬浮页签（Dock）的入口配置。
// 注意：底栏光效已改为使用官方 HdsTabs（见 Index.ets），这里的自绘 Dock 仅作为
// 设备不支持 HDS 时的备用形态保留。
export interface DockItem {
  icon: Resource;
  // 选中态用实心图标，与系统页签习惯一致。
  selectedIcon: Resource;
  label: string;
}

@Component
export struct ImmersiveDock {
  @Prop items: DockItem[] = [];
  @Prop selectedIndex: number = 0;
  onSelect: (index: number) => void = () => {};

  @Builder
  private dockItem(item: DockItem, index: number) {
    Column({ space: Theme.spaceXs }) {
      SymbolGlyph(item.icon).fontSize(Theme.iconMd)
        .fontColor([this.selectedIndex === index ? Theme.accent : Theme.tertiary])
      Text(item.label).fontSize(Type.caption)
        .fontColor(this.selectedIndex === index ? Theme.accent : Theme.tertiary)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .layoutWeight(1)
      .height(52)
      .justifyContent(FlexAlign.Center)
      // 选中态用浅色底托一下，不改变布局尺寸，避免图标跳动。
      .backgroundColor(this.selectedIndex === index ? Theme.accentSoft : Color.Transparent)
      .borderRadius(Theme.radiusCard)
      .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
      .onClick(() => this.onSelect(index))
  }

  build() {
    Row({ space: Theme.spaceXs }) {
      ForEach(this.items, (item: DockItem, index: number) => {
        this.dockItem(item, index)
      }, (item: DockItem) => item.label)
    }
      .width('100%')
      .padding(Theme.spaceXs)
      .margin({ left: Theme.spaceL, right: Theme.spaceL })
      .borderRadius(Theme.radiusPill)
      .backgroundColor(Theme.surface)
      .shadow(Theme.floatShadow)
      .systemMaterial(dockMaterial())
  }
}

// 顶部悬浮栏：ULTRA_THIN 材质 + 向下渐变模糊，内容从下方淡出。
// 只用于确实需要"整条栏悬浮"的页面；首页改用 TopPill（胶囊），避免全宽奶油底糊成一片。
@Component
export struct ImmersiveTopBar {
  @Prop contentHeight: number = Theme.navBarHeight;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {}

  build() {
    Column() {
      this.content()
    }
      .width('100%')
      .height(this.contentHeight)
      .backgroundColor(Theme.background)
      .systemMaterial(topBarMaterial())
      // 0 → 1 的模糊梯度：上沿完全模糊、下沿清晰，形成薄雾悬浮而不是硬分割线。
      .linearGradientBlur(28, {
        fractionStops: [[0.0, 0.0], [1.0, 1.0]],
        direction: GradientDirection.Bottom
      })
  }
}

// 顶部悬浮区：胶囊 + 向下渐隐遮罩。
//
// 只有胶囊是不够的：内容滚到胶囊下方时会直接顶上来，文字和胶囊边缘硬碰，既难读也难看。
// 所以这里在胶囊下沿补一层"从页面底色到透明"的渐变遮罩，内容淡出而不是被切断；
// 胶囊本身也换成实底而不是 ULTRA_THIN——浅色页面上薄材质会发灰，反而压不住内容。
@Component
export struct TopPill {
  @Prop contentPadding: number = Theme.spaceS;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {}

  build() {
    // 这里的取舍是全工程唯一一处：胶囊内部必须压住滚上来的内容才读得清，
    // 而沉浸材质是半透明的，单靠材质做不到这一点——试过全透明 + 自绘渐隐，
    // 结果是内容与品牌字直接叠在一起。所以顶栏胶囊保留实底、放弃透光，
    // 沉浸光感集中在底部悬浮页签（官方在页面内只对白名单组件生效，底部页签正在其中）。
    Row() {
      this.content()
    }
      .padding(this.contentPadding)
      .borderRadius(Theme.radiusPill)
      .backgroundColor(Theme.surface)
      .border({ width: 1, color: Theme.line })
      .clip(true)
      .shadow(Theme.floatShadow)
  }
}
// 顶部渐隐层：从页面底色渐到透明，垫在悬浮胶囊后面。
// 它负责让滚上来的内容柔和淡出，胶囊本身得以保持全透明。
@Component
export struct TopScrim {
  @Prop scrimHeight: number = 96;

  build() {
    Column()
      .width('100%')
      .height(this.scrimHeight)
      .linearGradient({
        angle: 180,
        colors: [[Theme.background, 0.0], [Theme.background, 0.55], ['#00FFFFFF', 1.0]]
      })
      // 渐隐层只是视觉垫底，不能吃掉点击事件，否则胶囊与底部页签会点不动。
      .hitTestBehavior(HitTestMode.Transparent)
  }
}
// ===== HDS 官方沉浸光感材质 =====
// 官方通道是 @kit.UIDesignKit 的 hdsMaterial + HDS 组件（HdsTabs / HdsNavigation），
// 与低层的 uiMaterial 是两套东西：前者由设计系统托管，能跟随系统"沉浸光感强度"三档设置。
// 设备不一定支持 IMMERSIVE（低端机只支持背景模糊），所以必须先查能力再降级。
export class HdsMaterialSupport {
  private static types: string[] = [];

  static load(): void {
    if (HdsMaterialSupport.types.length > 0) { return; }
    try {
      const list: number[] = hdsMaterial.getSystemMaterialTypes();
      const names: string[] = [];
      for (const item of list) {
        if (item === hdsMaterial.MaterialType.IMMERSIVE) { names.push('IMMERSIVE'); }
        else if (item === hdsMaterial.MaterialType.ADAPTIVE) { names.push('ADAPTIVE'); }
        else if (item === hdsMaterial.MaterialType.NONE) { names.push('NONE'); }
        else { names.push(String(item)); }
      }
      HdsMaterialSupport.types = names;
    } catch (error) {
      HdsMaterialSupport.types = [];
    }
  }

  static supportsImmersive(): boolean {
    HdsMaterialSupport.load();
    return HdsMaterialSupport.types.indexOf('IMMERSIVE') >= 0;
  }

  // 设备支持就用沉浸光感，否则退回跟随系统的自适应策略。
  static materialType(): hdsMaterial.MaterialType {
    return HdsMaterialSupport.supportsImmersive()
      ? hdsMaterial.MaterialType.IMMERSIVE
      : hdsMaterial.MaterialType.ADAPTIVE;
  }

  static materialLevel(): hdsMaterial.MaterialLevel {
    return HdsMaterialSupport.supportsImmersive()
      ? hdsMaterial.MaterialLevel.EXQUISITE
      : hdsMaterial.MaterialLevel.ADAPTIVE;
  }

}
