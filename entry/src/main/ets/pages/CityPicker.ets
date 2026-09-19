// 城市选择与手动温度。
//
// 为什么需要它：真实天气依赖系统的天气与定位能力，设备或账号不具备该能力时（本机模拟器就是
// 这种情况）拿不到数据。这时用户仍然需要告诉应用"今天大概多少度"，否则推荐无从下手。
// 因此这里把城市和温度放在一起：选城市会给出该城市的典型温度作为起点，用户再按当天实际感受微调。
import { CityOption, CITIES } from '../model/Wardrobe';
import { Theme, Type } from '../components/Theme';
import { MaterialPanel } from '../components/MaterialKit';

@Component
export struct CityPickerSheet {
  @Prop currentCity: string = '';
  @Prop currentTemperature: number = 24;
  // 是否已取到真实天气，用于给出手动模式的说明。
  @Prop weatherAvailable: boolean = false;
  @Prop weatherSource: string = '';
  onPick: (city: CityOption, temperature: number) => void = () => {};
  onUseLocation: () => void = () => {};

  @State picked: string = '';
  @State temperature: number = 24;

  aboutToAppear(): void {
    // 用当前状态回填，用户只改一项时不用重新选城市。
    this.picked = this.currentCity;
    this.temperature = this.currentTemperature;
  }

  private typicalOf(name: string): string {
    const found: CityOption | undefined = CITIES.find((city: CityOption) => city.name === name);
    if (found === undefined) { return ''; }
    return `${found.typicalMin}–${found.typicalMax}℃`;
  }

  private midOf(name: string): number {
    const found: CityOption | undefined = CITIES.find((city: CityOption) => city.name === name);
    if (found === undefined) { return this.temperature; }
    return Math.round((found.typicalMin + found.typicalMax) / 2);
  }

  @Builder
  private cityRow(city: CityOption) {
    Row({ space: Theme.spaceM }) {
      SymbolGlyph($r('sys.symbol.pin')).fontSize(Theme.iconSm)
        .fontColor([this.picked === city.name ? Theme.accent : Theme.tertiary])
      Text(city.name).fontSize(Type.body).fontColor(Theme.text).maxLines(1)
      Blank()
      Text(this.typicalOf(city.name)).fontSize(Type.caption)
        .fontColor(Theme.tertiary).maxLines(1)
      if (this.picked === city.name) {
        SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(Theme.iconSm)
          .fontColor([Theme.accent])
      }
    }
      .width('100%')
      .padding({ left: Theme.spaceL, right: Theme.spaceL, top: Theme.spaceM, bottom: Theme.spaceM })
      .backgroundColor(this.picked === city.name ? Theme.accentSoft : Color.Transparent)
      .borderRadius(Theme.radiusInput)
      .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
      .onClick(() => {
        this.picked = city.name;
        // 选城市把温度带到该城市的典型中值，用户接着可以自己调。
        this.temperature = this.midOf(city.name);
      })
  }

  build() {
    Scroll() {
      Column({ space: Theme.spaceL }) {
        Text('所在城市与温度').fontSize(Type.title).fontWeight(FontWeight.Bold)
          .fontColor(Theme.text).width('100%').padding({ right: 44 }).maxLines(2)
        Text(this.weatherAvailable
          ? `当前${this.weatherSource}，温度已按当日区间自动填入，也可以手动改。`
          : '本机取不到系统天气，选一个城市后按当天实际感受调一下温度即可，推荐不依赖联网。')
          .fontSize(Type.caption).fontColor(Theme.secondary).lineHeight(22).width('100%').maxLines(3)

        MaterialPanel({ contentPadding: Theme.spaceL }) {
          Column({ space: Theme.spaceS }) {
            Row({ space: Theme.spaceM }) {
              SymbolGlyph($r('sys.symbol.location_up_fill')).fontSize(Theme.iconMd).fontColor([Theme.accent])
              Column({ space: Theme.spaceXs }) {
                Text('使用当前位置').fontSize(Type.cardTitle).fontColor(Theme.text).maxLines(1)
                Text('尝试通过系统定位获取当地天气')
                  .fontSize(Type.caption).fontColor(Theme.secondary).maxLines(2)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Button('定位', { type: ButtonType.Normal }).fontSize(Type.buttonSmall)
                .height(Theme.buttonCompact).borderRadius(Theme.radiusPill)
                .backgroundColor(Theme.accentSoft).fontColor(Theme.accent)
                .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
                .onClick(() => this.onUseLocation())
            }.width('100%')
          }.width('100%')
        }

        Column({ space: Theme.spaceS }) {
          Text('选择城市').fontSize(Type.cardTitle).fontWeight(FontWeight.Medium)
            .fontColor(Theme.text).width('100%').maxLines(1)
          Column({ space: Theme.spaceXs }) {
            ForEach(CITIES, (city: CityOption) => {
              this.cityRow(city)
            }, (city: CityOption) => city.name)
          }.width('100%')
        }.width('100%')

        Column({ space: Theme.spaceM }) {
          Row() {
            Text('今天温度').fontSize(Type.cardTitle).fontWeight(FontWeight.Medium)
              .fontColor(Theme.text).layoutWeight(1).maxLines(1)
            Text(`${this.temperature}℃`).fontSize(Type.title).fontWeight(FontWeight.Bold)
              .fontColor(Theme.accent).maxLines(1)
          }.width('100%')
          Slider({ value: this.temperature, min: 5, max: 35, step: 1 })
            .selectedColor(Theme.accent)
            .onChange((value: number) => this.temperature = Math.round(value))
            .accessibilityText('今天温度')
          Text('推荐按这个温度挑可穿单品。温度只影响推荐，不会改动你的衣橱。')
            .fontSize(Type.caption).fontColor(Theme.tertiary).width('100%').maxLines(2)
        }.width('100%')

        Button('保存', { type: ButtonType.Normal }).width('100%').height(Theme.buttonHeight)
          .borderRadius(Theme.radiusPill).backgroundColor(Theme.accent).fontColor(Theme.onAccent)
          .fontSize(Type.button)
          .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
          .onClick(() => {
            const target: CityOption | undefined = CITIES.find((city: CityOption) => city.name === this.picked);
            if (target === undefined) { return; }
            this.onPick(target, this.temperature);
          })
      }.width('100%').padding({ left: Theme.spaceXl, right: Theme.spaceXl, top: Theme.spaceXl, bottom: Theme.spaceXxl })
    }.width('100%').align(Alignment.TopStart).backgroundColor(Theme.background)
  }
}
