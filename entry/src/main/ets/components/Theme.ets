// 鸿蒙设计令牌。字号全部使用系统资源 sys.float.ohos_id_text_size_*，
// 这样会跟随系统「字体与显示大小」设置缩放；颜色使用应用语义色，随深浅色模式自动切换。
//
// 间距沿用官方 4/8/12/16/24/32 vp 档位；卡片圆角与按钮高度按 HM Design 控件规则取值。
import uiMaterial from '@ohos.arkui.uiMaterial';

export class Theme {
  // 背景与容器
  static background: Resource = $r('app.color.page_background');
  static surface: Resource = $r('app.color.surface');
  static surfaceSoft: Resource = $r('app.color.surface_soft');
  // 比 surfaceSoft 更沉一档，用于输入框、进度条槽等需要"凹进去"的位置。
  static surfaceSunken: Resource = $r('app.color.surface_sunken');
  static imagePlaceholder: Resource = $r('app.color.image_placeholder');
  static shadow: Resource = $r('app.color.shadow');

  // 文字：三级层次，避免只有"主要/次要"两级导致信息挤在一起
  static text: Resource = $r('app.color.text_primary');
  static secondary: Resource = $r('app.color.text_secondary');
  static tertiary: Resource = $r('app.color.text_tertiary');
  static line: Resource = $r('app.color.divider');

  // 品牌与状态
  static accent: Resource = $r('app.color.accent');
  static accentSoft: Resource = $r('app.color.accent_soft');
  static accentPressed: Resource = $r('app.color.accent_pressed');
  // 主色实底上的文字色：浅色模式为白，深色模式为深色，保证对比度
  static onAccent: Resource = $r('app.color.accent_ink');
  static success: Resource = $r('app.color.success');
  static successSoft: Resource = $r('app.color.success_soft');
  static warning: Resource = $r('app.color.warning');
  static warningSoft: Resource = $r('app.color.warning_soft');
  // 强调色用于会员、限时权益这类需要抓注意力但不做主按钮的位置
  static highlight: Resource = $r('app.color.highlight');
  static highlightSoft: Resource = $r('app.color.highlight_soft');

  // 首页主视觉渐变：暖玫瑰到暖米，避免大面积纯色带来的廉价感
  static heroFrom: Resource = $r('app.color.hero_from');
  static heroTo: Resource = $r('app.color.hero_to');

  // 间距：官方 4/8/12/16/24/32 vp 档位
  static spaceXs: number = 4;
  static spaceS: number = 8;
  static spaceM: number = 12;
  static spaceL: number = 16;
  static spaceXl: number = 24;
  static spaceXxl: number = 32;

  // 圆角收敛为小幅圆角；保留原触控高度，不把可点击区域缩成难点的小控件。
  static radiusCard: number = 12;
  static radiusSheet: number = 20;
  static radiusPill: number = 8;
  static radiusInput: number = 8;
  static radiusChip: number = 10;

  // HdsNavigation 的标题栏是覆盖式的，正文顶部必须留出净空，否则会被硬边切掉。
  // 实测标题栏底边约占 98vp、胶囊下沿占 78vp；留到 104vp 让正文从标题栏下方开始。
  static titleBarClearance: number = 104;

  // 控件尺寸
  static pagePadding: number = 16;
  static buttonHeight: number = 48;
  static buttonCompact: number = 40;
  static navBarHeight: number = 56;
  static iconSm: number = 20;
  static iconMd: number = 24;
  static iconLg: number = 32;

  // 卡片阴影：暖色底上偏暖的阴影比中性灰更协调
  static cardShadow: ShadowOptions = { radius: 16, color: '#146B4B4F', offsetX: 0, offsetY: 4 };
  static floatShadow: ShadowOptions = { radius: 24, color: '#1F6B4B4F', offsetX: 0, offsetY: 8 };

  // 交互反馈
  static pressedOpacity: number = 0.6;
  static disabledOpacity: number = 0.4;
  // 文本放大上限，避免超大字号把卡片撑破
  static maxFontScale: number = 1.75;
}

// 字号层级统一走系统资源，保证跟随系统字体大小设置。
export class Type {
  static display: Resource = $r('sys.float.ohos_id_text_size_headline7');   // 24fp 应用名
  static title: Resource = $r('sys.float.ohos_id_text_size_headline8');     // 20fp 页面标题
  static section: Resource = $r('sys.float.ohos_id_text_size_sub_title1');  // 18fp 区块标题
  static cardTitle: Resource = $r('sys.float.ohos_id_text_size_sub_title2'); // 16fp 卡片标题
  static body: Resource = $r('sys.float.ohos_id_text_size_body1');          // 16fp 正文
  static bodySmall: Resource = $r('sys.float.ohos_id_text_size_body2');     // 14fp 次要正文
  static caption: Resource = $r('sys.float.ohos_id_text_size_body3');       // 12fp 说明
  static button: Resource = $r('sys.float.ohos_id_text_size_button1');      // 16fp 按钮
  static buttonSmall: Resource = $r('sys.float.ohos_id_text_size_button2'); // 14fp 次级按钮
}

// 沉浸光感：鸿蒙 7（API 26）的沉浸材质 + 光感交互反馈。
// 设备不支持时返回 undefined，组件回落到普通卡片样式，不会出现空白或报错。
export function immersiveCard(
  style: uiMaterial.ImmersiveStyle = uiMaterial.ImmersiveStyle.REGULAR,
  lightColor?: ResourceColor
): uiMaterial.ImmersiveMaterial | undefined {
  if (!uiMaterial.isImmersiveMaterialSupported()) { return undefined; }
  return new uiMaterial.ImmersiveMaterial({
    style: style,
    // 材质层着色必须带透明度，完全不透明会挡住材质滤镜。
    materialColor: '#1AFFFFFF',
    applyShadow: true,
    interactive: true,
    lightEffect: lightColor !== undefined ? { color: lightColor } : undefined
  });
}

// 只带光感反馈、不做材质着色的版本，用于图片之上的浮层。
export function lightFeedback(lightColor: ResourceColor): uiMaterial.ImmersiveMaterial | undefined {
  if (!uiMaterial.isImmersiveMaterialSupported()) { return undefined; }
  return new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    applyShadow: false,
    interactive: true,
    lightEffect: { color: lightColor }
  });
}
