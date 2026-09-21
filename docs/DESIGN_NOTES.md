# 设计与联调手记

本文件收录艺起搭开发过程中关于配色、布局、沉浸光感、动画与联调踩坑的详细记录，
供后续维护与答辩讲解引用。功能范围、构建与验收入口见 [README](../README.md)，
当前进度与未验证项见 [DEVELOPMENT_STATUS.md](DEVELOPMENT_STATUS.md)。

> 说明：以下内容按当时实际改动顺序保留，个别检查项数量是当时的快照，
> 最新数量以 README 与 `scripts/check-domain.cjs`、`scripts/check-index.cjs` 为准。

### 配色规范

配色按「衣橱与穿搭」这个品类重新定过。原先是冷紫（`#6F5CF4`），偏工具与科技感，放在衣物图片旁边显冷、也容易显廉价。现在换成暖色系，让人和衣服的关系更贴近：

| 角色 | 浅色 | 深色 | 用途 |
| --- | --- | --- | --- |
| 主色 | `#C4647C` 柔和玫瑰 | `#E79AAC` | 主按钮、选中态、强调数值 |
| 主色浅底 | `#FBEAF0` | `#3A282E` | 次级按钮、选中底、标签底 |
| 主色文字 | `#FFFFFF` | `#2B1419` | 主色实底上的文字（深浅色相反，保证对比度） |
| 强调色 | `#E8859B` 珊瑚粉 | `#F0A3B4` | 会员、限时权益等需要抓注意力的位置 |
| 页面底色 | `#FDF8F6` 暖白 | `#171315` | 降低长时间浏览衣物图片的视觉疲劳 |
| 卡片 | `#FFFFFF` | `#231D20` | 承载内容 |
| 下沉面 | `#F3EAE7` | `#1C1719` | 输入框、进度条槽等需要"凹进去"的位置 |
| 文字三级 | `#2B2225` / `#7A6C70` / `#A7989C` | 对应深色值 | 主要 / 次要 / 弱化，避免只有两级导致信息挤在一起 |
| 主视觉渐变 | `#F6DCDE` → `#F3E6DC` | 深色对应值 | 首页顶部渐变卡，整页唯一渐变块 |
| 成功 / 警示 | `#5F8A6E` / `#C4614E` | 对应深色值 | 可穿状态、重置等 |

阴影也从冷灰改为带暖调的 `#146B4B4F`，在暖底上不会显脏。

### 首页视觉层次

一屏内用「渐变主视觉 → 概览小卡 → 内容主体 → 快捷入口 → 最近日记」五段分层，靠渐变与材质厚度区分层次，不靠分割线和边框：

1. **渐变主视觉卡**：城市、天气、当日温度用 40fp 大字，两个主行动（录入衣物、调整城市）。整页唯一的渐变，用来立住第一眼。
2. **两栏概览小卡**：衣物件数 + 今日是否记录，最常看的两件事。
3. **今日推荐**：第一套给更大的图片高度（132vp），第二套 112vp，形成主次。
4. **常用功能**：四列宫格，去掉外层面板，减少一层无意义容器。
5. **最近穿搭日记**：空态给引导按钮，不留空白。

### 衣橱页的形态与交互改造

原来的衣橱页只有「搜索 + 两个下拉 + 网格」，是工具形态，没有内容感，衣物多了要一直翻。改了三处：

| 问题 | 改法 |
| --- | --- |
| 只有筛选，没有概览 | 顶部加统计卡：衣物总数 / 可穿 / 待处理，一眼知道衣橱状态 |
| 看不到"真正在穿的" | 加「常穿」横滑条，按穿着次数排序，露出买了没穿的 |
| 品类要展开两级下拉才筛 | 改成常驻标签行，一下点到位 |
| 状态筛选项过多 | 药丸只留「全部状态 / 可穿 / 待洗」三个高频项 |
| 其余状态无处处理 | 「整理任务」把待洗、收纳、季节隐藏、已归档聚合成入口，带数量；再点一次回到全部 |
| 大图翻找慢、信息密度低 | 加「紧凑视图」开关：格子 150→108，图片比例 0.88→1，隐藏次要信息 |

### 首页横幅

补齐了首屏缺的强调块。文案按真实状态分两种，不编造进度或权益：

- 衣物不足 5 件：`衣橱还差几件就能成套` + 还差几件，动作是「去添加」
- 衣物足够：`把这个月穿过的记下来` + 本月实际记录天数，动作是「查看日记」

天数由日记与穿着记录合并去重后按当月统计，不是写死的数字。

### 沉浸光感：按官方场景规范分层

档位不是「越厚越好看」，而是由**组件在页面中的位置、是否与内容重叠**决定。依据[官方设计规范](https://developer.huawei.com/consumer/cn/doc/design-guides/immersivelight-0000002612101053)的场景规范实现：

| 场景 | 档位 | 位置与做法 |
| --- | --- | --- |
| 顶部悬浮（顶栏） | `ULTRA_THIN` | 配 `linearGradientBlur` 向下渐变模糊，内容滚到下面时自然淡出，没有硬边 |
| 底部悬浮（Dock） | `THIN` | 配带透明度的颜色蒙层把内容向下收住，内容透出但不穿透导航文字 |
| 任意位置弹出（气泡、浮层） | `THICK` | 弹出位置不可预期，可读性优先 |
| 半模态、弹出框 | `ULTRA_THICK` | 通过 `SheetOptions.systemMaterial` 施加，面积大、信息多 |
| 内容层卡片（常驻） | `REGULAR` | 不与内容重叠，材质只需轻轻分层 |
| 区域底板 | `THIN` | 把一整块区域托起来，不强调单张卡片 |

实现放在 `MaterialKit.ets`，页面只声明「这是什么位置的交互件」（`topBarMaterial` / `dockMaterial` / `floatingMaterial` / `sheetMaterial` / `cardMaterial` / `panelMaterial`），不直接挑厚度，避免后续又出现随意取值。

**纠正了上一版的两个错误**：底部导航原先用 `BlurStyle.COMPONENT_THICK`，顶部栏根本没有材质，卡片一律 `REGULAR`——三者都不符合规范。另外光感反馈色原先写死旧品牌紫，已改为跟随当前品牌色的资源引用。

用户可在系统里调三档强度，系统底层自动完成参数映射，因此代码里不需要为三档分别适配。

虚拟机实测：`isImmersiveMaterialSupported()` 为 true，材质等级 `EXQUISITE`，「我的」页有对应状态条可直接核对。

### 沉浸光感的形态：用官方 HDS 组件，不是自绘模糊

官方「沉浸光感」有专门的通道：`@kit.UIDesignKit` 的 **`hdsMaterial` + HDS 组件**（`HdsTabs` / `HdsNavigation`）。第一版只给整条顶栏/底栏加 `systemMaterial`，那是低层的**材质**，不是官方的**沉浸光感能力**，已重做。

| 位置 | 实现 | 档位与做法 |
| --- | --- | --- |
| 底部悬浮页签 | **官方 `HdsTabs`** + `barFloatingStyle` | `systemMaterialEffect` 设 `IMMERSIVE` + `EXQUISITE`，`barOverlap(true)` 让内容延伸到页签下方，`lightColor` 跟随品牌色 |
| 顶部悬浮胶囊 | `TopPill` | 胶囊形态 + `ULTRA_THIN`，左侧品牌与城市天气合成一个可点胶囊，右侧加号独立成圆胶囊 |
| 筛选条 | `filterBar` | `THIN` + 向下渐变模糊 |
| 弹层（半模态） | `SheetOptions.systemMaterial` | `ULTRA_THICK` |
| 内容层卡片 | `MaterialCard` / `MaterialPanel` | `REGULAR` / `THIN` |

**顶部为什么从全宽栏改成胶囊**：全宽 `ULTRA_THIN` 栏配奶油底色，在浅色页面上表现为一整条发灰的横带，既压不住内容也糊掉品牌区。改成胶囊后左右留白，内容能从两侧和下方透出，品牌与城市天气的对比度也回来了。

**三处实测踩出来的细节，缺一个都会出问题**：

1. **顶栏必须是覆盖层，不能只是"在滚动区上方"**。只把顶栏放在 `Column` 里、滚动区放下面，滚动区会从顶栏下沿开始，内容滚上来时依旧与胶囊硬碰。现在用 `Stack` 让滚动区占满整个高度、顶栏叠在其上，并给内容留出顶部内边距。
2. **胶囊要有实底衬底**。材质层着色是半透明的，单层胶囊压在彩色内容（例如粉色横幅）上时文字读不清。现在是外层管形状与投影、内层管底色与材质的两层结构。
3. **悬浮胶囊必须按内容宽度收缩，不能写 `width('100%')`**。胶囊一旦撑满整行，同一行里的右侧按钮会被挤出屏幕——加号按钮就这样消失过一次，肉眼在真机上才发现。组件内部不要预设宽度，交给父级布局决定。
4. **底部必须留白**。`barOverlap(true)` 让内容延伸到悬浮页签下方，不补 `padding-bottom` 的话最后一行会被永久盖住——这个问题是用户反馈后才发现的，之前只截了首屏所以没暴露。留白取 `Theme.navBarHeight + Theme.spaceL`，留太多会空出一大块。
5. **`barBottomMargin` 用小负值把 Dock 压回底部**。`HdsTabs` 会在悬浮页签下方预留一块空白（与页签自身等高），导致 Dock 被顶高、下面拖着一条白带——用户反馈的「底部栏靠上了，被底部溢出的白色空白挤上去」就是这个。实测 `barBottomMargin: -14` 时胶囊底边距手势条约 12vp，既贴住底部又不压到手势条。

底部下沿渐隐层试过一版：`HdsTabs` 的页签层在 `Stack` 之后绘制，自绘的渐隐盖不住它，所以撤掉了。现在靠"底部留白足够大 + 内容本身是浅色卡片"来保证可读；后续如仍有糊斑，正解是用 `barFloatingStyle.gradientMask`（官方给底部渐隐用的参数），而不是再叠一层自绘渐变。

**必须先查设备能力再降级**：低端设备只支持背景模糊，强开 `IMMERSIVE` 会掉帧发热。`HdsMaterialSupport` 用 `hdsMaterial.getSystemMaterialTypes()` 判断，支持就用 `IMMERSIVE + EXQUISITE`，否则退回 `ADAPTIVE`。「我的」页底部有状态条显示设备实际支持的材质类型，可现场核对。

本机虚拟机实测：`getSystemMaterialTypes()` 返回 `IMMERSIVE`，因此底部页签走的是真实沉浸光感（点击时有光晕反馈）。

官方还说明：用户可在系统里调三档强度，系统底层自动完成参数映射与渲染，代码只需一次定义，不必为三档分别适配。

### 沉浸光感位置审计

按官方规范「**交互组件可能与内容区重叠时**使用沉浸光感」逐个位置过了一遍：

| 位置 | 是否重叠 | 处理 |
| --- | --- | --- |
| 底部四页签 | 是，浮在滚动内容上 | ✅ 官方 `HdsTabs` + IMMERSIVE |
| 顶部品牌与城市 | 是 | ✅ 胶囊 + `ULTRA_THIN` |
| 衣橱筛选条（品类/状态） | 是，与衣物图片相邻 | ✅ `THIN` + 渐变模糊 |
| 半模态弹层（城市、档案、添加衣物） | 是，覆盖页面 | ✅ `ULTRA_THICK` |
| 设置、来源说明等静态块 | 否，常驻内容 | ❌ 保持纯色，不加光效 |
| 衣物网格卡片 | 否，内容本身 | ❌ 保持纯色，加光效只会干扰读图 |

**没做的一项**：筛选条吸顶。`sticky` 只支持 `List`，当前页面用的是 `Scroll` + `Column`，要吸顶得把整页改成 `List` + `ListItemGroup`，改动量与收益不成比例，先如实保留现状。

### 顶栏：官方 HdsNavigation + 左右两个悬浮胶囊

顶部按官方「顶部悬浮区域」的形态做：**左右分成两个胶囊**，都铺沉浸材质、底色全透明。

| 位置 | 实现 | 光感 |
| --- | --- | --- |
| 左胶囊（品牌 + 城市） | `HdsNavigation.titleBar.content.stackBuilder` 自定义 builder，胶囊自身 `.systemMaterial(capsuleMaterial())` | 材质透出，点击换城市 |
| 右胶囊（添加） | 同左，也放在 `stackBuilder` 内自绘 | `capsuleMaterial()`，与左胶囊一致 |
| 底部页签 | 官方 `HdsTabs` + `barFloatingStyle` | `systemMaterialEffect` = `IMMERSIVE` + `EXQUISITE` |

**两个胶囊都必须自绘，而且 `menu` 必须留空**：`titleBar.content.menu` 的 `HdsNavigationIconItemStyle` 只能设 `backgroundColor` / `iconColor`，**不支持材质**，所以加号不能走 menu——否则它是一块系统灰底圆片，没有光感。

**`menu` 与 `stackBuilder` 会同时渲染**：把加号移进 `stackBuilder` 后如果忘了删 `menu`，屏幕上会出现**两个加号叠在一起**（一个系统灰底、一个自绘透光），看起来像渲染重影。两者只能留一个。

**胶囊材质单独定义 `capsuleMaterial()`**：`cardMaterial()` 的材质层着色只有 12% 白，胶囊面积小，在浅色页面上几乎看不出形状、图标会被背景吃掉。`capsuleMaterial()` 提到 55% 白，形状立得住，同时保留材质的模糊与光感（不是纯色块）。另外自定义栈区没有系统菜单那圈内边距，需要自己补左右内边距，否则右胶囊会被挤出屏幕。

```typescript
HdsNavigation() { this.mainTabs() }
  .titleMode(HdsNavigationTitleMode.MINI)
  .hideBackButton(true)
  .titleBar({
    content: {
      title: { mainTitle: '' },                    // 用 stackBuilder 接管左侧，标题留空
      stackBuilder: (): void => { this.brandCapsule() },
      menu: { maxCount: 1, value: [{ content: { icon: $r('sys.symbol.plus'), action: ... } }] }
    }
  })
```

**两个胶囊都自己铺材质**：	itleBar.content.menu 的 HdsNavigationIconItemStyle 只能设背景色、不支持材质，所以加号不能走 menu，必须和左胶囊一样放进 stackBuilder 自绘，否则它是一块灰底圆片、没有光感。

**胶囊必须底色透明**：材质滤镜是半透明的，一旦给实底（哪怕只是白色）就成一块死白板，光感全无。这一点我反复踩过——为了可读性加实底，光感就没了；改透明，内容又顶上来。最终方案是胶囊透明 + 标题栏自身材质托底，两者叠加后既能透光也够读。

**迁移中踩到的三个真问题**：

1. **`HdsNavigation` 的标题栏是覆盖式的**，内容不会自动让位。正文顶部净空取 `Theme.titleBarClearance = 104vp`（实测标题栏底边约 98vp、胶囊下沿约 78vp）。留少了首屏会顶进标题栏，留多了首屏空一大块。
2. **顶部遮挡要单独配滚动效果，靠留白解决不了**。留白只管内容起点，管不到滚动过程中的遮挡——第一次只加留白，滚下去仍然看到内容被标题栏下沿一刀切断。正解是官方那套滚动效果：

```typescript
style: {
  scrollEffectOpts: {
    enableScrollEffect: true,
    scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
  },
  originalStyle: {
    backgroundStyle: { backgroundColor: Color.Transparent, maskExtraHeight: 40 }, contentStyle: { }
  },
  scrollEffectStyle: {
    backgroundStyle: { backgroundColor: Theme.background, maskExtraHeight: 40 }, contentStyle: { }
  }
}
```

`maskExtraHeight` 让遮罩比标题栏多延展一段，内容滚上来时是渐隐而不是被切断；`IMMERSIVE_GRADIENT_BLUR` 是官方给沉浸光感配的渐变模糊。未滚动时标题栏透明（胶囊自己透光），滚动后收实底色保证正文可读。

3. **`overlay` 里放 `HdsTabs` 不显示**——页签需要真实布局高度，不能靠浮层承载，所以页签与内容必须放在同一棵 `Column` 树里。

**以及一个我自己造出来的问题**：迁移时屏幕出现过标题叠影，我据此排查了三轮。最后等界面稳定重新取证，发现**只有一处标题**——叠影是过渡动画的中间帧。`uitest dumpLayout` 与 `screenCap` 在动画未结束时都会抓到中间态，拿它当缺陷会反向修出真问题（期间确实把底栏改坏过一次）。

**教训**：先等界面稳定，再取证，再下结论。

### 温度带提示：把温度翻译成可执行的建议

首页天气卡的副标题原本写「手动温度」——那只是**数据来源标签，对用户没有信息量**。现在改成一句能直接用的提示：

| 温度 | 提示 |
| --- | --- |
| ≤ 0℃ | 冰冻，羽绒服加围巾手套 |
| ≤ 10℃ | 冷，需要保暖外套 |
| ≤ 20℃ | 凉爽，长袖正合适 |
| ≤ 25℃ | 微凉，适合薄外套 |
| ≤ 28℃ | 舒适，单穿长袖或薄衬衫 |
| ≤ 32℃ | 偏热，短袖透气为主 |
| > 32℃ | 炎热，选轻薄速干面料 |

三个设计决定：

1. **按区间取中间值**。有 `tempMin`/`tempMax` 时取中位数，否则最高温会把提示带偏（14–28℃ 取 21℃ → 微凉，而不是 28℃ → 舒适）。
2. **降水优先于温度**。下雨下雪时「记得带伞」比「穿什么」更影响当天出门，所以先判雨雪，命中就盖过温度提示。
3. **图标分四档而不是三档**。原先只有雪花/云/太阳三档，22℃ 配烈日图标会让人误以为很热；补了 `cloud_and_sun_fill` 给温和区间。

实现放在 `service/TemperatureAdvice.ets`，**图标只存字符串键、不在 service 层调 `$r()`** —— 这个模块要能在 Node 里跑测试，而 `$r()` 是 ArkUI 运行时函数，脱离运行时会得到 `undefined`。资源映射留在组件里。

测试从 17 项加到 25 项，覆盖：温度带升序、−40~50℃ 全覆盖、边界含等号不跳带、超出两端收敛、降水优先级。

### 页面切换动画

三处过渡：

| 切换 | 做法 | 时长 |
| --- | --- | --- |
| 独立页进入（搭配/日记/试穿） | 从右侧滑入 + 淡入；四入口层左移淡出 | 280ms |
| 独立页返回 | 反向：独立页右移淡出，四入口层归位 | 240ms |
| 底部页签切换 | 官方 `HdsTabs.animationDuration` | 280ms |

曲线统一用 `Curve.FastOutSlowIn`——起步快、收尾缓，符合"被推开"的物理直觉。

**关键：状态变更必须包在 `animateTo` 里**，否则属性变化是瞬切：

```typescript
private openRoute(route: string): void {
  if (route === this.mainRoute) { return; }
  this.routeHistory.push(this.mainRoute);
  animateTo({ duration: 280, curve: Curve.FastOutSlowIn }, () => { this.mainRoute = route; });
}
```

**踩到的坑：`if/else` 换子树时 `transition()` 不生效。** 第一版把 `TransitionEffect.asymmetric(...)` 挂在路由页容器上，期望 ArkUI 在子树出现/消失时播放过渡——实测**完全不播**：为了确认不是"动画太快截不到"，我把时长临时调到 2000ms 再抢中间帧，页面依然是瞬间到位。说明不是采样问题，是机制不成立。

改为**两层常驻 + 属性动画**：

```typescript
Stack() {
  Column() { /* 四入口层 */ }
    .opacity(this.mainRoute === 'tabs' ? 1 : 0)
    .translate({ x: this.mainRoute === 'tabs' ? 0 : -32 })
    .hitTestBehavior(this.mainRoute === 'tabs' ? HitTestMode.Default : HitTestMode.None)
    .visibility(this.mainRoute === 'tabs' ? Visibility.Visible : Visibility.Hidden)

  Column() { /* 独立页层，常驻在其上 */ }
    .opacity(this.mainRoute === 'tabs' ? 0 : 1)
    .translate({ x: this.mainRoute === 'tabs' ? 64 : 0 })
    .hitTestBehavior(this.mainRoute === 'tabs' ? HitTestMode.None : HitTestMode.Default)
    .visibility(this.mainRoute === 'tabs' ? Visibility.Hidden : Visibility.Visible)
}
```

两个必须注意的点：

1. **不可见图层必须设 `hitTestBehavior(HitTestMode.None)`**，否则独立页上的按钮会被下面那层四入口挡住。
2. **独立页层要判断 `mainRoute !== 'tabs'` 才渲染内容**。原来的 `routePage()` 末尾是 `else` 分支（试穿页），若不判断，停在四入口时会额外构建一整个试穿页。

### 入场与错峰动画

在页面切换之外，补了两处"内容出现"的动画：

| 位置 | 做法 |
| --- | --- |
| 首页六段 | 按 55ms 依次淡入 + 上移 20vp，300ms / `FastOutSlowIn` |
| 半模态内容 | 比面板本体晚 50ms 起势，淡入 + 上移 24vp |

首页用 20vp 位移、55ms 间隔：够看出"依次落位"，又不会让页面像在跳动；位移再大就会显得浮夸。

**关键：开关必须延后一帧再置 `true`。**

```typescript
aboutToAppear(): void {
  this.updateTextScale();
  // 先让初始态（透明 + 下移）真正渲染一帧，属性变化才有起点可插值；
  // 在同一帧里直接置 true 会跳过动画、直接出现在终态。
  setTimeout(() => { this.entered = true; }, 30);
}
```

每段包一层容器承载动画属性——ArkTS 里 `@Builder` 调用后不能直接挂属性（这个限制前面已经踩过一次）。

半模态的 50ms 延迟是有意的：面板自身的上滑先起势、内容再跟上，读起来是一件事而不是两件。

### 状态栏文字颜色：官方默认值在浅色页面上等于看不见

现象：**滑到顶部时状态栏的时间和电量消失**，往下滚一点又出现。

原因是 `SystemBarStyle.statusBarContentColor` 的**默认值是 `'#E5FFFFFF'`（半透明白）**：

- 未滚动：用默认白字，而页面底色是浅色 → 白字白底，看不见
- 滚动后：`HdsNavigation` 的滚动效果把文字转成深色 → 恢复正常

所以这不是"有时候坏了"，而是**滚动效果接管前一直在用默认值**。本页底色始终是浅色，状态栏文字就应该始终是深色，两段样式都给同一个值：

```typescript
.systemBarStyle(
  { statusBarContentColor: this.statusBarInk() },
  { statusBarContentColor: this.statusBarInk() }
)
```

`statusBarContentColor` 只接受字符串、不能用资源引用，所以按深浅色模式手工取色，与 `color.json` 的 `text_primary` 保持一致：

```typescript
private statusBarInk(): string {
  const dark: boolean = this.context().config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  return dark ? '#FFF7F1F3' : '#FF2B2225';
}
```

官方还提醒：不要与 Window 的状态栏 API 混用（本工程没有用）。
### 页签跳转必须先收口，再谈动画

第一版只给 `openRoute` / `closeRoute` 包了 `animateTo`，结果**首页里的入口点了没动画**——因为 `openTile` 里是直接赋值：

```typescript
else if (name === '衣橱整理') { this.tab = 1; }   // 瞬切，没有过渡
```

全工程有 9 处这样直接写 `this.tab = N`（首页入口、衣物添加完成、详情页按钮、我的页回调……）。逐个补 `animateTo` 只会漏，所以统一收口：

```typescript
private switchTab(index: number): void {
  if (index === this.tab) { return; }
  animateTo({ duration: 130, curve: Curve.FastOutSlowIn }, () => { this.tabPhase = 0; });
  setTimeout(() => {
    this.tab = index;
    animateTo({ duration: 240, curve: Curve.FastOutSlowIn }, () => { this.tabPhase = 1; });
  }, 140);
}
```

### 一个反直觉的发现：`animationDuration` 管不到程序化切换

`HdsTabs.animationDuration` **只作用于"用户点页签 / 左右滑动"**，程序化改 `index` 不走那套动画。

验证方式还是放慢抢帧：把 `animationDuration` 调到 **2000ms**，然后

- 点 Dock 上的「衣橱」→ 500ms 处抢帧，看到首页向左滑出、衣橱从右滑入 ✅ 原生动画在跑
- 点首页的「衣橱整理」→ 500ms 处抢帧，衣橱页**已经完全就位** ❌ 程序化切换是瞬切

所以程序化切换得自己做一段"先退场、再切换、后进场"（就是上面 `switchTab` 里的两段 `animateTo`）。点 Dock 时 `tabPhase` 始终为 1，不会和原生动画叠加。

### 动画的验证方法

动画看不见，所以两次都靠**临时把时长放大再抢中间帧**来确认机制真的在跑：

- 路由过渡：280ms → 2000ms，500ms 处抢帧 → 看到两层交叉淡化
- 首页错峰：间隔 ×8，2200ms 处抢帧 → 前三段已落位、后三段还没出现

这一步不能省。第一版路由过渡用 `if/else` + `transition()`，**代码看着完全合理，实际一帧都不播**；不看中间帧就发现不了。
**这次中间帧成了有效证据**：把时长临时放到 2000ms 后抢帧，能清楚看到两层交叉淡化、工作室页从右侧滑入——证明过渡确实在播。这和之前"把过渡帧误当缺陷"是相反的两件事：**中间帧本身没有对错，取决于你想验证的是状态还是过程。**
### 一个必须记住的工程事实

**ArkTS 只编译从入口可达的文件。** 只新建页面文件、不接入 `Index.ets`，构建会显示成功，但那些文件从未被类型检查。本轮踩到了这个坑：三个并行子代理各自报「构建成功」，实际接入后立刻暴露出一批语法与 API 不匹配的错误（`@Builder` 收尾不能挂属性修饰符、符号名不存在、HMS 共享包静态导入崩溃）。判断新页面是否真的编译过，必须确认它已在编译图里。

### 仅在手机上才能确认的项目

- 互动卡片点击展开：虚拟机返回错误码 `801`（当前设备能力不支持），未能跑通。
- 摇一摇激活卡片：需要真实传感器，`triggerTypes: shake` 已配置但未经真机确认。
- 字体放大到 1.75 倍后的实际排版、深色模式观感、安全区适配与分享目标真机行为。
- 平板与折叠屏的大屏列数：已用 `repeat(auto-fit)` 与限宽实现，但只在手机尺寸的虚拟机上确认过。
- 签名安装：当前 `signingConfigs` 为空，HAP 未签名。

构建工具仍提示部分文件 API 可能抛异常，错误由调用侧捕获并显示保存/加载失败状态。
