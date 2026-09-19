// 添加衣物：相册导入 + 属性确认。
//
// 为什么把表单独立成组件：衣橱页和首页都要能发起添加，表单状态跟着组件走比挂在大页面上
// 更不容易互相影响；导入的图片在未确认前也由这里负责清理。
import { Category, CATEGORIES, GarmentStatus, OCCASIONS } from '../model/Wardrobe';
import { Theme, Type } from '../components/Theme';
import { MaterialCard } from '../components/MaterialKit';

// 表单草稿。单独定义成 interface，便于整体重置。
export interface GarmentDraft {
  uri: string;
  name: string;
  categoryIndex: number;
  color: string;
  minTemp: number;
  maxTemp: number;
  occasions: string[];
  error: string;
}

export function emptyDraft(): GarmentDraft {
  return { uri: '', name: '', categoryIndex: 0, color: '白色', minTemp: 12, maxTemp: 30,
    occasions: ['上课'], error: '' };
}

// 默认温度区间按品类给不同起点，减少用户拖动次数。
export function defaultRange(categoryIndex: number): number[] {
  if (categoryIndex === 0) { return [16, 35]; }   // 上装
  if (categoryIndex === 1) { return [8, 30]; }    // 下装
  if (categoryIndex === 2) { return [5, 35]; }    // 鞋履
  if (categoryIndex === 3) { return [8, 22]; }    // 外套
  return [10, 32];                                // 配饰
}

@Component
export struct AddGarmentSheet {
  @Link draft: GarmentDraft;
  @Prop importing: boolean = false;
  @Prop cuttingOut: boolean = false;
  @Prop hasOriginal: boolean = false;
  @Prop showingOriginal: boolean = true;
  onCutout: () => void = () => {};
  onRestoreOriginal: () => void = () => {};
  @Prop readBlocked: boolean = false;
  @Prop editing: boolean = false;
  // 保存忙碌态：落盘成功前不关弹层，按钮显示"保存中…"。
  @Prop saving: boolean = false;
  @Prop existingImage: ResourceStr = '';
  onPickPhoto: () => void = () => {};
  onConfirm: () => void = () => {};

  private colors: string[] = ['白色', '黑色', '灰色', '蓝色', '绿色', '棕色', '多色'];

  @Builder
  private label(text: string) {
    Text(text).fontSize(Type.bodySmall).fontColor(Theme.text).width('100%').maxLines(1)
  }

  build() {
    Column({ space: Theme.spaceL }) {
      Column({ space: Theme.spaceXs }) {
        Text(this.editing ? '编辑衣物' : '添加衣物').fontSize(Type.title).fontWeight(FontWeight.Bold)
          .fontColor(Theme.text).width('100%').padding({ right: 44 }).maxLines(2)
        Text('先放一张照片，再确认品类和适穿温度。属性之后随时能改。')
          .fontSize(Type.caption).fontColor(Theme.secondary).width('100%').maxLines(2)
      }.alignItems(HorizontalAlign.Start).width('100%')

      MaterialCard({ contentPadding: Theme.spaceM }) {
        Column({ space: Theme.spaceM }) {
          if (this.draft.uri.length > 0) {
            Image(this.draft.uri).height(180).width('100%').objectFit(ImageFit.Contain)
              .backgroundColor(Theme.imagePlaceholder).borderRadius(Theme.radiusInput)
          } else if (this.editing) {
            Image(this.existingImage).height(180).width('100%').objectFit(ImageFit.Contain)
              .backgroundColor(Theme.imagePlaceholder).borderRadius(Theme.radiusInput)
          } else {
            Column({ space: Theme.spaceS }) {
              SymbolGlyph($r('sys.symbol.camera')).fontSize(Theme.iconLg).fontColor([Theme.tertiary])
              Text('还没有选择照片').fontSize(Type.caption).fontColor(Theme.tertiary).maxLines(1)
            }.width('100%').height(140).justifyContent(FlexAlign.Center)
          }
          Button(this.importing ? '正在导入…' : (this.draft.uri.length > 0 ? '重新选择' : '从相册选择'),
            { type: ButtonType.Normal }).height(Theme.buttonHeight)
            .width('100%').backgroundColor(Theme.accentSoft).fontColor(Theme.accent).fontSize(Type.button)
            .borderRadius(Theme.radiusPill).enabled(!this.importing && !this.cuttingOut)
            .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
            .onClick(() => this.onPickPhoto())
          if (this.hasOriginal) {
            Row({ space: 8 }) {
              Button('原图', { type: ButtonType.Normal }).height(40).layoutWeight(1)
                .fontSize(Type.buttonSmall).borderRadius(8)
                .backgroundColor(this.showingOriginal ? Theme.accentSoft : Theme.surfaceSoft).fontColor(Theme.text)
                .enabled(!this.cuttingOut).onClick(() => this.onRestoreOriginal())
              Button(this.cuttingOut ? '处理中' : '主体抠图', { type: ButtonType.Normal }).height(40).layoutWeight(1)
                .fontSize(Type.buttonSmall).borderRadius(8)
                .backgroundColor(!this.showingOriginal ? Theme.accentSoft : Theme.surfaceSoft).fontColor(Theme.text)
                .enabled(!this.cuttingOut).onClick(() => this.onCutout())
            }.width('100%')
          }
        }.width('100%')
      }

      this.label('名称')
      TextInput({ text: this.draft.name, placeholder: '例如 白色圆领短袖' }).maxLength(30)
        .fontColor(Theme.text).placeholderColor(Theme.tertiary)
        .backgroundColor(Theme.surfaceSoft).borderRadius(Theme.radiusInput)
        .onChange((value: string) => this.draft.name = value)

      this.label('品类')
      // 品类用一排可点的标签而不是下拉：选项少，直接看到比展开选更快。
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(CATEGORIES, (value: Category, index: number) => {
          Text(value).fontSize(Type.caption)
            .fontColor(this.draft.categoryIndex === index ? Theme.accent : Theme.text)
            .padding({ left: Theme.spaceL, right: Theme.spaceL, top: Theme.spaceS, bottom: Theme.spaceS })
            .backgroundColor(this.draft.categoryIndex === index ? Theme.accentSoft : Theme.surfaceSoft)
            .borderRadius(Theme.radiusPill)
            .border({ width: 1, color: this.draft.categoryIndex === index ? Theme.accent : Theme.line })
            .margin({ right: Theme.spaceS, bottom: Theme.spaceS })
            .onClick(() => {
              this.draft.categoryIndex = index;
              // 换品类时把温度拉到该品类的常见区间，少拖几次。
              const range: number[] = defaultRange(index);
              this.draft.minTemp = range[0];
              this.draft.maxTemp = range[1];
            })
        }, (value: Category) => value)
      }.width('100%')

      this.label('颜色')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.colors, (value: string) => {
          Text(value).fontSize(Type.caption)
            .fontColor(this.draft.color === value ? Theme.accent : Theme.text)
            .padding({ left: Theme.spaceL, right: Theme.spaceL, top: Theme.spaceS, bottom: Theme.spaceS })
            .backgroundColor(this.draft.color === value ? Theme.accentSoft : Theme.surfaceSoft)
            .borderRadius(Theme.radiusPill)
            .border({ width: 1, color: this.draft.color === value ? Theme.accent : Theme.line })
            .margin({ right: Theme.spaceS, bottom: Theme.spaceS })
            .onClick(() => this.draft.color = value)
        }, (value: string) => value)
      }.width('100%')

      Row() {
        Text('适穿温度').fontSize(Type.bodySmall).fontColor(Theme.text).layoutWeight(1).maxLines(1)
        Text(`${this.draft.minTemp} – ${this.draft.maxTemp}℃`).fontSize(Type.bodySmall)
          .fontColor(Theme.accent).maxLines(1)
      }.width('100%')
      Column({ space: Theme.spaceS }) {
        Row({ space: Theme.spaceM }) {
          Text('最低').fontSize(Type.caption).fontColor(Theme.tertiary).width(36).maxLines(1)
          Slider({ value: this.draft.minTemp, min: -20, max: 45, step: 1 }).selectedColor(Theme.accent)
            .layoutWeight(1)
            .onChange((value: number) => this.draft.minTemp = Math.round(value))
            .accessibilityText('最低适穿温度')
        }.width('100%')
        Row({ space: Theme.spaceM }) {
          Text('最高').fontSize(Type.caption).fontColor(Theme.tertiary).width(36).maxLines(1)
          Slider({ value: this.draft.maxTemp, min: -20, max: 45, step: 1 }).selectedColor(Theme.accent)
            .layoutWeight(1)
            .onChange((value: number) => this.draft.maxTemp = Math.round(value))
            .accessibilityText('最高适穿温度')
        }.width('100%')
      }.width('100%')

      this.label('适合场合')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(OCCASIONS, (occasion: string) => {
          Row({ space: Theme.spaceXs }) {
            Checkbox({ name: occasion })
              .select(this.draft.occasions.indexOf(occasion) >= 0)
              .selectedColor(Theme.accent)
              .shape(CheckBoxShape.ROUNDED_SQUARE)
              .width(Theme.iconMd).height(Theme.iconMd)
              .onChange((checked: boolean) => {
                this.draft.occasions = checked
                  ? this.draft.occasions.filter((value: string) => value !== occasion).concat([occasion])
                  : this.draft.occasions.filter((value: string) => value !== occasion);
              })
            Text(occasion).fontSize(Type.caption).fontColor(Theme.text).maxLines(1)
          }.width('50%')
        }, (occasion: string) => occasion)
      }.width('100%')

      if (this.draft.error.length > 0) {
        Text(this.draft.error).fontSize(Type.caption).fontColor(Theme.warning).width('100%')
          .padding(Theme.spaceM).backgroundColor(Theme.warningSoft).borderRadius(Theme.radiusInput)
          .maxLines(3)
      }

      Button(this.saving ? '保存中…' : (this.editing ? '保存修改' : '确认并加入衣橱'), { type: ButtonType.Normal }).width('100%').height(Theme.buttonHeight)
        .borderRadius(Theme.radiusPill).backgroundColor(Theme.accent).fontColor(Theme.onAccent)
        .fontSize(Type.button)
        .enabled(!this.importing && !this.cuttingOut && !this.saving && !this.readBlocked)
        .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
        .onClick(() => this.onConfirm())
    }.width('100%')
  }
}
