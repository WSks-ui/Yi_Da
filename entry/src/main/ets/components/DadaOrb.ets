import { DadaState } from '../service/DadaContext';
import { Theme, Type } from './Theme';

@Component
export struct DadaOrb {
  @Prop @Watch('restart') state: DadaState = DadaState.IDLE;
  @Prop @Watch('restart') pulseKey: string = '';
  @Prop diameter: number = 28;
  @StorageProp('appForeground') @Watch('restart') foreground: boolean = true;
  @State expanded: boolean = false;
  private timer: number = -1;
  private alive: boolean = false;

  aboutToAppear(): void { this.alive = true; this.restart(); }
  aboutToDisappear(): void { this.alive = false; this.stop(); }
  private stop(): void { if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; } }
  private restart(): void {
    this.stop(); this.expanded = false;
    if (!this.alive || !this.foreground || this.state === DadaState.ERROR) { return; }
    this.timer = setTimeout(() => {
      if (!this.alive || !this.foreground) { return; }
      this.expanded = true;
      this.tick();
    }, 30);
  }
  private tick(): void {
    this.timer = setTimeout(() => {
      if (!this.alive || !this.foreground) { return; }
      this.expanded = !this.expanded;
      // 只有处理状态循环；待机与完成各播放一次，避免全局顶栏常驻时消耗动画资源。
      if (this.state === DadaState.WORKING) { this.tick(); }
      else { this.timer = -1; }
    }, this.state === DadaState.COMPLETE ? 600 : 900);
  }
  build() {
    Stack() {
      Circle().width(this.diameter).height(this.diameter).fill(Theme.accentSoft)
        .scale({ x: this.expanded ? 1.28 : 1.08, y: this.expanded ? 1.28 : 1.08 })
        .opacity(this.expanded ? 0.15 : 0.65).animation({ duration: 850, curve: Curve.EaseInOut })
      Circle().width(this.diameter * 0.94).height(this.diameter * 0.94).fill(Color.Transparent)
        .stroke(this.state === DadaState.ERROR ? Theme.warning : Theme.accent).strokeWidth(0.8)
        .scale({ x: this.expanded ? 1.12 : 1, y: this.expanded ? 1.12 : 1 })
        .opacity(0.45).animation({ duration: 850, curve: Curve.EaseInOut })
      Circle().width(this.diameter * 0.78).height(this.diameter * 0.78)
        .fill(Color.Transparent)
        .linearGradient({ angle: 135, colors: [[Theme.heroTo, 0], [Theme.highlight, 0.55], [Theme.accent, 1]] })
        .borderRadius(this.diameter).clip(true)
        .shadow({ radius: this.diameter * 0.2, color: Theme.shadow, offsetX: 0, offsetY: 2 })
        .scale({ x: this.expanded ? 1.05 : 1, y: this.expanded ? 1.05 : 1 })
        .animation({ duration: 850, curve: Curve.EaseInOut })
      Circle().width(this.diameter * 0.23).height(this.diameter * 0.16).fill(Theme.surface)
        .opacity(0.6).translate({ x: -this.diameter * 0.12, y: -this.diameter * 0.15 })
    }.width(this.diameter * 1.3).height(this.diameter * 1.3).hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
  }
}

@Component
export struct DadaEntry {
  @Prop state: DadaState = DadaState.IDLE;
  @Prop pulseKey: string = '';
  @Prop available: boolean = true;
  onOpen: () => void = () => {};
  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 4 }) {
        DadaOrb({ diameter: 28, state: this.state, pulseKey: this.pulseKey })
        Text('搭搭').fontSize(Type.buttonSmall).fontColor(Theme.accent).maxLines(1)
      }.padding({ left: 8, right: 12 }).justifyContent(FlexAlign.Center)
    }.height(48).constraintSize({ minWidth: 88 }).borderRadius(Theme.radiusPill)
      .backgroundColor(Theme.accentSoft).enabled(this.available).onClick(() => this.onOpen())
      .accessibilityText('打开搭搭助手').stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
  }
}
