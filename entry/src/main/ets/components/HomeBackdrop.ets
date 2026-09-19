// 首页的织物底纹固定在页面背后，滚动时只移动内容，不跟随每张卡片重复绘制。
// 颜色由深浅色资源控制；底纹不接收触摸，避免挡住导航和滚动手势。
@Component
export struct HomeBackdrop {
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;

  private drawWeave(): void {
    this.context.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    this.context.strokeStyle = '#09707880';
    this.context.lineWidth = 0.6;
    // 短线交错模拟斜纹布的经纬，留出足够空白，文字区域不会出现高对比网格。
    for (let y: number = 0; y < this.canvasHeight; y += 24) {
      for (let x: number = 0; x < this.canvasWidth; x += 24) {
        const offset: number = (y / 24) % 2 === 0 ? 0 : 12;
        this.context.beginPath();
        this.context.moveTo(x + offset, y);
        this.context.lineTo(x + offset + 7, y + 7);
        this.context.moveTo(x + offset + 3, y);
        this.context.lineTo(x + offset + 10, y + 7);
        this.context.stroke();
      }
    }
  }

  build() {
    Canvas(this.context)
      .width('100%').height('100%')
      .linearGradient({ angle: 145, colors: [
        [$r('app.color.home_rose'), 0], [$r('app.color.home_blue'), 0.46],
        [$r('app.color.home_mint'), 0.78], [$r('app.color.page_background'), 1]
      ] })
      .onReady(() => this.drawWeave())
      .onAreaChange((_old: Area, area: Area) => {
        this.canvasWidth = Number(area.width);
        this.canvasHeight = Number(area.height);
        this.drawWeave();
      })
      .hitTestBehavior(HitTestMode.None)
  }
}
