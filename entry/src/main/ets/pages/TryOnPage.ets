import { common } from '@kit.AbilityKit';
import { TryOnTask } from '../model/Wardrobe';
import { Theme, Type } from '../components/Theme';
import { DEMO_POSES, DEMO_SCENES, TryOnDemoPose, TryOnDemoPoseId, TryOnDemoScene,
  findDemoScene, formatTryOnDate } from '../service/TryOnDemo';
import { demoImages, demoPoseResult, exportDemoResult } from '../service/TryOnDemoMedia';
import { saveOutfitToAlbum, shareOutfitImage } from '../service/OutfitExport';
import { DadaOrb } from '../components/DadaOrb';
import { DadaState } from '../service/DadaContext';
import { TryOnCommand, TryOnPresentation, TryOnPresentationController, TryOnStage,
  presentationRunning, presentationText } from '../service/TryOnPresentationController';

// 离线演示从三组配套样片中选择，六秒过程由唯一控制器发布；结果始终来自打包的固定图片。
// 侧面和背面资源未就绪时保持禁用，未来接真实服务时不可把这些样片伪装成用户照片结果。
// 本页沿用 Index 的外层 Scroll，异步写入交给父组件统一提交。
@Component
export struct TryOnPage {
  @Prop tasks: TryOnTask[] = [];
  @Prop initialSceneId: string = 'denim_skirt';
  @Prop @Watch('consumeCommand') command: TryOnCommand = { id: 0, action: 'start', sceneId: 'denim_skirt' };
  @StorageProp('appForeground') @Watch('onForegroundChanged') foreground: boolean = true;
  onSubmit: (sceneId: string) => Promise<void> = () => Promise.reject(new Error('保存暂不可用'));
  onDeleteTask: (id: string) => Promise<void> = () => Promise.reject(new Error('删除暂不可用'));
  onReveal: () => void = () => {};
  onCommandConsumed: (id: number) => void = () => {};
  onSceneChange: (id: string) => void = () => {};
  onStageChange: (stage: TryOnStage) => void = () => {};

  @State selectedId: string = 'denim_skirt';
  @State selectedPose: TryOnDemoPoseId = 'front';
  @State generatedSceneId: string = '';
  @State mode: string = '示例效果';
  @State busy: boolean = false;
  @State generating: boolean = false;
  @State notice: string = '';
  @State failed: boolean = false;
  @State presentation: TryOnPresentation = { stage: TryOnStage.IDLE, sceneId: '', runId: 0 };
  private alive: boolean = false;
  private controller: TryOnPresentationController | undefined = undefined;
  private unsubscribe: (() => void) | undefined = undefined;
  private consumedCommandId: number = 0;

  aboutToAppear(): void {
    this.alive = true;
    if (this.generating) { this.busy = false; this.generating = false; }
    this.selectedId = findDemoScene(this.initialSceneId) ? this.initialSceneId : 'denim_skirt';
    this.generatedSceneId = this.hasSavedScene(this.selectedId) ? this.selectedId : '';
    this.selectedPose = 'front';
    this.controller = new TryOnPresentationController();
    this.unsubscribe = this.controller.subscribe((state: TryOnPresentation) => {
      if (!this.alive) { return; }
      const wasGenerating: boolean = this.generating;
      this.presentation = state;
      this.generating = presentationRunning(state.stage);
      if (wasGenerating || this.generating) { this.busy = this.generating; }
      if (state.stage === TryOnStage.REVEALING || state.stage === TryOnStage.COMPLETE) {
        this.generatedSceneId = state.sceneId; this.mode = '示例效果';
      }
      this.onStageChange(state.stage);
    });
    this.consumeCommand();
  }
  aboutToDisappear(): void {
    this.alive = false;
    if (this.unsubscribe !== undefined) { this.unsubscribe(); this.unsubscribe = undefined; }
    this.controller?.dispose(); this.controller = undefined;
    this.onStageChange(TryOnStage.IDLE);
    if (this.generating) { this.busy = false; this.generating = false; }
  }

  onForegroundChanged(): void { if (!this.foreground && this.generating) { this.cancelPresentation(); } }

  // 挂载和 @Watch 都可能收到同一条请求。先记录并通知父层消费，再启动，避免订阅发布引发重复播放。
  consumeCommand(): void {
    if (!this.alive || this.command.id <= 0 || this.command.id <= this.consumedCommandId) { return; }
    const request: TryOnCommand = this.command;
    this.consumedCommandId = request.id; this.onCommandConsumed(request.id);
    if (this.busy || !this.foreground) { return; }
    if (!findDemoScene(request.sceneId)) { this.notice = '这组试穿样片暂不可用。'; return; }
    if (request.action === 'start') { this.select(request.sceneId); this.generatePreview(); }
    else if (this.isGenerated()) { this.mode = '对比'; this.onReveal(); }
    else { this.notice = '先完成一次样片演示，再查看原图对比。'; this.onReveal(); }
  }

  private current(): TryOnDemoScene {
    return findDemoScene(this.selectedId) || DEMO_SCENES[0];
  }

  private currentResult(): Resource {
    return demoPoseResult(this.selectedId, this.selectedPose) || demoImages(this.selectedId).result;
  }

  private saved(): boolean {
    return this.tasks.some((task: TryOnTask) => task.demoSceneId === this.selectedId);
  }

  private hasSavedScene(sceneId: string): boolean {
    return this.tasks.some((task: TryOnTask) => task.demoSceneId === sceneId);
  }

  private isGenerated(): boolean {
    return this.generatedSceneId === this.selectedId &&
      demoPoseResult(this.selectedId, this.selectedPose) !== undefined;
  }

  private poseAvailable(pose: TryOnDemoPose): boolean {
    return demoPoseResult(this.selectedId, pose.id) !== undefined;
  }

  private selectPose(pose: TryOnDemoPose): void {
    if (this.busy) { return; }
    if (!this.poseAvailable(pose)) {
      this.notice = '暂无' + pose.label + '角度的示例图片';
      return;
    }
    this.selectedPose = pose.id;
    this.mode = '示例效果';
    this.notice = '';
  }

  private select(id: string): void {
    if (this.busy || !findDemoScene(id)) { return; }
    this.selectedId = id;
    this.selectedPose = 'front';
    this.generatedSceneId = this.hasSavedScene(id) ? id : '';
    this.mode = '示例效果';
    this.notice = '';
    this.failed = false;
    this.onSceneChange(id);
  }

  private generatePreview(): void {
    if (this.busy || !this.foreground || this.controller === undefined) { return; }
    this.generatedSceneId = '';
    this.notice = '';
    this.failed = false;
    try {
      this.controller.start(this.selectedId);
      this.onReveal();
    } catch (error) {
      this.notice = (error as Error).message || '演示样片暂不可用'; this.failed = true;
    }
  }

  private cancelPresentation(): void {
    this.controller?.cancel(); this.generatedSceneId = ''; this.notice = '已取消演示，可重新开始。';
  }

  private async saveRecord(): Promise<void> {
    if (this.busy || !this.isGenerated() || this.saved()) { return; }
    this.busy = true; this.notice = ''; this.failed = false;
    try {
      await this.onSubmit(this.selectedId);
      if (this.alive) { this.notice = '已保存到试穿记录'; }
    } catch (error) {
      if (this.alive) { this.notice = (error as Error).message || '保存失败，请重试'; this.failed = true; }
    } finally { if (this.alive) { this.busy = false; } }
  }

  private async removeRecord(task: TryOnTask): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.notice = ''; this.failed = false;
    try {
      const answer = await this.getUIContext().getPromptAction().showDialog({
        title: '删除这条试穿记录？', message: '已导出到相册的图片会保留。',
        buttons: [{ text: '取消', color: Theme.secondary }, { text: '删除', color: Theme.warning }]
      });
      if (!this.alive || answer.index !== 1) { return; }
      await this.onDeleteTask(task.id);
      if (this.alive) { this.notice = '记录已删除'; }
    } catch (error) {
      if (this.alive) { this.notice = (error as Error).message || '删除失败，请重试'; this.failed = true; }
    } finally { if (this.alive) { this.busy = false; } }
  }

  private async deliver(album: boolean): Promise<void> {
    if (this.busy || !this.isGenerated()) { return; }
    this.busy = true; this.notice = ''; this.failed = false;
    // 捕获当前场景；离开页面后仍完成资源释放，但不再弹出系统窗口。
    const sceneId: string = this.selectedId;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const uri: string = await exportDemoResult(sceneId, context);
      if (!this.alive) { return; }
      if (album) {
        const saved: boolean = await saveOutfitToAlbum(uri, context);
        if (this.alive) { this.notice = saved ? '样片已保存到相册' : '已取消保存'; }
      } else {
        await shareOutfitImage(uri, context, '艺起搭 · 试穿演示样片');
      }
    } catch (error) {
      if (this.alive) {
        this.notice = album ? '相册保存未完成，请重试' : '分享未完成，请重试';
        this.failed = true;
      }
    } finally { if (this.alive) { this.busy = false; } }
  }

  private taskScene(task: TryOnTask): TryOnDemoScene | undefined {
    return task.demoSceneId ? findDemoScene(task.demoSceneId) : undefined;
  }

  private taskName(task: TryOnTask): string {
    const scene: TryOnDemoScene | undefined = this.taskScene(task);
    return scene ? scene.name : (task.demoSceneId ? '样片暂不可用' : '历史试穿输入');
  }

  private openRecord(task: TryOnTask): void {
    const scene: TryOnDemoScene | undefined = this.taskScene(task);
    if (this.busy || !scene) { return; }
    this.select(scene.id);
    this.generatedSceneId = scene.id;
    this.selectedPose = 'front';
    this.mode = '示例效果';
    this.onReveal();
  }

  @Styles
  pressable() {
    .stateStyles({ normal: { .opacity(1) }, pressed: { .opacity(Theme.pressedOpacity) },
      disabled: { .opacity(Theme.disabledOpacity) } })
  }

  @Builder
  private sceneTile(scene: TryOnDemoScene) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 6 }) {
        Image(demoImages(scene.id).garment).width('100%').height(48).objectFit(ImageFit.Contain)
        Text(scene.name).fontSize(Type.caption).maxLines(2).textAlign(TextAlign.Center)
          .fontColor(this.selectedId === scene.id ? Theme.accent : Theme.text).width('100%')
      }.width('100%').padding(8)
    }.layoutWeight(1).height(94).borderRadius(8)
      .backgroundColor(this.selectedId === scene.id ? Theme.accentSoft : Theme.surface)
      .border({ width: this.selectedId === scene.id ? 2 : 1,
        color: this.selectedId === scene.id ? Theme.accent : Theme.line })
      .accessibilityText(scene.name + (this.selectedId === scene.id ? '，已选中' : ''))
      .enabled(!this.busy).pressable().onClick(() => this.select(scene.id))
  }

  @Builder
  private modeControl() {
    Row({ space: 4 }) {
      ForEach(['示例效果', '原图', '对比'], (label: string) => {
        Button(label, { type: ButtonType.Normal }).layoutWeight(1).height(36).borderRadius(6)
          .fontSize(Type.buttonSmall).fontColor(this.mode === label ? Theme.accent : Theme.secondary)
          .backgroundColor(this.mode === label ? Theme.surface : Color.Transparent)
          .accessibilityText(label + (this.mode === label ? '，已选中' : ''))
          .enabled(!this.busy).pressable().onClick(() => { this.mode = label; })
      }, (label: string) => label + (this.mode === label ? '_active' : '_idle'))
    }.width('100%').padding(4).backgroundColor(Theme.surfaceSoft).borderRadius(8)
  }

  @Builder
  private poseControl() {
    Row({ space: 6 }) {
      ForEach(DEMO_POSES, (pose: TryOnDemoPose) => {
        Button({ type: ButtonType.Normal }) {
          Column({ space: 2 }) {
            Text(pose.label).fontSize(Type.buttonSmall)
              .fontColor(this.selectedPose === pose.id ? Theme.accent : Theme.secondary)
            if (!this.poseAvailable(pose)) {
              Text('暂无图片').fontSize(Type.caption).fontColor(Theme.tertiary)
            }
          }.width('100%').alignItems(HorizontalAlign.Center)
        }.layoutWeight(1).height(48).borderRadius(6)
          .backgroundColor(this.selectedPose === pose.id ? Theme.accentSoft : Theme.surface)
          .border({ width: this.selectedPose === pose.id ? 2 : 1,
            color: this.selectedPose === pose.id ? Theme.accent : Theme.line })
          .accessibilityText(pose.label + (this.poseAvailable(pose) ? '，可用' : '，暂无示例图片'))
          .enabled(!this.busy && this.poseAvailable(pose)).pressable().onClick(() => this.selectPose(pose))
      }, (pose: TryOnDemoPose) => pose.id)
    }.width('100%')
  }

  @Builder
  private generationAction() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.arrow_right')).fontSize(20).fontColor([Theme.onAccent])
        Text(this.generating ? '取消演示' :
          (this.isGenerated() ? '重播演示' : '让搭搭演示试穿'))
          .fontSize(Type.button).fontColor(Theme.onAccent)
      }.justifyContent(FlexAlign.Center).width('100%')
    }.width('100%').height(48).borderRadius(8).backgroundColor(Theme.accent)
      .enabled(!this.busy || this.generating).pressable()
      .onClick(() => { if (this.generating) { this.cancelPresentation(); } else { this.generatePreview(); } })
  }

  @Builder
  private preview() {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.mode === '对比') {
        Row({ space: 2 }) {
          Column({ space: 8 }) {
            Text('原图').fontSize(Type.caption).fontColor(Theme.secondary)
            Image(demoImages(this.selectedId).person).width('100%').layoutWeight(1)
              .objectFit(ImageFit.Contain).accessibilityText(this.current().name + '，原始人像')
          }.layoutWeight(1).height('100%').padding({ top: 12, bottom: 12 })
          Divider().vertical(true).height('90%').color(Theme.line)
          Column({ space: 8 }) {
            Text('固定结果 · ' + this.current().pose).fontSize(Type.caption).fontColor(Theme.accent)
            Image(this.currentResult()).width('100%').layoutWeight(1)
              .objectFit(ImageFit.Contain).accessibilityText(this.current().name + '，试穿样片')
          }.layoutWeight(1).height('100%').padding({ top: 12, bottom: 12 })
        }.width('100%').height('100%')
      } else {
        Image(this.mode === '原图' ? demoImages(this.selectedId).person : this.currentResult())
          .width('100%').height('100%').objectFit(ImageFit.Contain)
          .accessibilityText(this.current().name + (this.mode === '原图' ? '，原始人像' : '，试穿样片'))
      }
      if (this.mode !== '对比') {
        Text('固定样片 · ' + this.current().pose).fontSize(11).fontColor('#FFFFFF')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('#B3303338').borderRadius(4).margin(8)
      }
    }.width('100%').aspectRatio(1.18).constraintSize({ maxHeight: 400 })
      .backgroundColor(Theme.surfaceSoft).borderRadius(8).clip(true)
  }

  @Builder
  private waitingPreview() {
    Row({ space: 12 }) {
      Image(demoImages(this.selectedId).person).layoutWeight(1).height(190)
        .objectFit(ImageFit.Contain).accessibilityText(this.current().name + '，演示原图')
      SymbolGlyph($r('sys.symbol.arrow_right')).fontSize(22).fontColor([Theme.secondary])
      Image(demoImages(this.selectedId).garment).layoutWeight(1).height(190)
        .objectFit(ImageFit.Contain).accessibilityText(this.current().name + '，服装参考图')
    }.width('100%').padding(12).backgroundColor(Theme.surfaceSoft).borderRadius(8)
  }

  @Builder
  private presentationCard() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        DadaOrb({ diameter: 80, state: this.presentation.stage === TryOnStage.REVEALING ? DadaState.COMPLETE : DadaState.WORKING,
          pulseKey: String(this.presentation.runId) })
        Column({ space: 6 }) {
          Text('搭搭陪你试穿').fontSize(Type.cardTitle).fontWeight(FontWeight.Medium).fontColor(Theme.text)
          Text(presentationText(this.presentation.stage)).fontSize(Type.bodySmall).fontColor(Theme.secondary).lineHeight(22)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      Stack() {
        Row({ space: 10 }) {
          Image(demoImages(this.selectedId).person).layoutWeight(1).height(210).objectFit(ImageFit.Contain)
            .translate({ x: this.presentation.stage === TryOnStage.PREPARING ? 0 : 8 })
            .animation({ duration: 1600, curve: Curve.EaseInOut })
          Image(demoImages(this.selectedId).garment).layoutWeight(1).height(210).objectFit(ImageFit.Contain)
            .translate({ x: this.presentation.stage === TryOnStage.PREPARING ? 0 : -8 })
            .animation({ duration: 1600, curve: Curve.EaseInOut })
        }.width('100%').opacity(this.presentation.stage === TryOnStage.REVEALING ? 0 :
          this.presentation.stage === TryOnStage.PRESENTING ? 0.35 : 1)
          .animation({ duration: 600, curve: Curve.EaseInOut })
        Image(demoImages(this.selectedId).result).width('100%').height(210).objectFit(ImageFit.Contain)
          .opacity(this.presentation.stage === TryOnStage.REVEALING ? 1 : 0)
          .scale({ x: this.presentation.stage === TryOnStage.REVEALING ? 1 : 0.96,
            y: this.presentation.stage === TryOnStage.REVEALING ? 1 : 0.96 })
          .animation({ duration: 600, curve: Curve.EaseInOut })
        Row().width('100%').height(40).linearGradient({ angle: 0,
          colors: [[Color.Transparent, 0], [Theme.accentSoft, 0.5], [Color.Transparent, 1]] })
          .opacity(this.presentation.stage === TryOnStage.INTERACTING ? 0.7 : 0)
          .translate({ y: this.presentation.stage === TryOnStage.PREPARING ? -80 : 80 })
          .animation({ duration: 1700, curve: Curve.EaseInOut }).hitTestBehavior(HitTestMode.None)
      }.width('100%').height(210).backgroundColor(Theme.surfaceSoft).borderRadius(12).clip(true)
      Row({ space: 8 }) {
        ForEach(['准备素材', '演示交互', '呈现样片', '结果揭晓'], (label: string, index: number) => {
          Column({ space: 6 }) {
            Row().width('100%').height(4).borderRadius(2)
              .backgroundColor(this.stepIndex() >= index ? Theme.accent : Theme.line)
            Text(label).fontSize(Type.caption).fontColor(this.stepIndex() === index ? Theme.accent : Theme.secondary)
          }.layoutWeight(1)
        }, (label: string) => label)
      }.width('100%')
    }.width('100%').padding(16).backgroundColor(Theme.surface).borderRadius(Theme.radiusCard)
      .border({ width: 1, color: Theme.line })
  }

  private stepIndex(): number {
    if (this.presentation.stage === TryOnStage.PREPARING) { return 0; }
    if (this.presentation.stage === TryOnStage.INTERACTING) { return 1; }
    if (this.presentation.stage === TryOnStage.REVEALING || this.presentation.stage === TryOnStage.COMPLETE) { return 3; }
    return 2;
  }

  @Builder
  private tool(icon: Resource, label: string, action: () => void, requiresResult: boolean = false) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(icon).fontSize(22).fontColor([Theme.accent])
    }.width(48).height(48).borderRadius(8).backgroundColor(Theme.accentSoft)
      // Builder 不接收生成状态的布尔快照；直接读取页面状态，保证过程结束后导出入口立即可用。
      .accessibilityText(label).enabled(!this.busy && (!requiresResult || this.isGenerated())).pressable().onClick(action)
      .onHover((hover: boolean) => {
        if (hover) { this.getUIContext().getPromptAction().showToast({ message: label }); }
      })
  }

  @Builder
  private actions() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          SymbolGlyph(this.saved() ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.heart'))
            .fontSize(20).fontColor([Theme.onAccent])
          Text(this.busy ? '处理中' : (this.saved() ? '已保存记录' : '保存试穿记录'))
            .fontSize(Type.buttonSmall).fontColor(Theme.onAccent).maxLines(1)
        }.justifyContent(FlexAlign.Center).width('100%')
      }.layoutWeight(1).height(48).borderRadius(8).backgroundColor(Theme.accent)
        .enabled(!this.busy && this.isGenerated() && !this.saved())
        .pressable().onClick(() => this.saveRecord())
      this.tool($r('sys.symbol.arrow_down_circle'), '保存样片到相册', () => this.deliver(true), true)
      this.tool($r('sys.symbol.share'), '分享试穿样片', () => this.deliver(false), true)
    }.width('100%')
  }

  @Builder
  private record(task: TryOnTask) {
    Row({ space: 12 }) {
      if (this.taskScene(task)) {
        Image(demoImages(task.demoSceneId || '').result).width(52).height(76).objectFit(ImageFit.Contain)
          .backgroundColor(Theme.surfaceSoft).borderRadius(4).onClick(() => this.openRecord(task))
      } else {
        SymbolGlyph($r('sys.symbol.person')).fontSize(28).fontColor([Theme.secondary]).width(52)
      }
      Column({ space: 4 }) {
        Text(this.taskName(task)).fontSize(Type.bodySmall).fontColor(Theme.text).maxLines(2)
        Text(this.taskScene(task) ? task.pose + ' · 固定演示样片' : '无可用结果图')
          .fontSize(Type.caption).fontColor(Theme.secondary)
        Text(formatTryOnDate(task.createdAt)).fontSize(Type.caption).fontColor(Theme.secondary)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(() => this.openRecord(task))
      if (this.taskScene(task)) {
        this.tool($r('sys.symbol.chevron_right'), '查看' + this.taskName(task), () => this.openRecord(task))
      }
      this.tool($r('sys.symbol.trash'), '删除' + this.taskName(task), () => this.removeRecord(task))
    }.width('100%').padding({ top: 10, bottom: 10 })
      .border({ width: { bottom: 1 }, color: Theme.line })
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('试穿间').fontSize(Type.title).fontWeight(FontWeight.Bold).fontColor(Theme.text)
        Blank()
        Text('离线样片 · 3 组').fontSize(Type.caption).fontColor(Theme.secondary)
      }.width('100%')
      Row({ space: 8 }) {
        ForEach(DEMO_SCENES, (scene: TryOnDemoScene) => {
          this.sceneTile(scene)
        }, (scene: TryOnDemoScene) => scene.id + (this.selectedId === scene.id ? '_active' : '_idle'))
      }.width('100%')
      if (!this.generating) {
        Row({ space: 12 }) {
          Image(demoImages(this.selectedId).person).width(44).height(64).objectFit(ImageFit.Contain)
            .backgroundColor(Theme.surfaceSoft).borderRadius(4).accessibilityText('配套人像')
          Image(demoImages(this.selectedId).garment).width(44).height(64).objectFit(ImageFit.Contain)
            .backgroundColor(Theme.surfaceSoft).borderRadius(4).accessibilityText('配套服装参考图')
          Column({ space: 4 }) {
            Text(this.current().name).fontSize(Type.cardTitle).fontColor(Theme.text).fontWeight(FontWeight.Medium)
            Text('配套人像 / ' + this.current().garmentLabel).fontSize(Type.caption).fontColor(Theme.secondary).maxLines(2)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }.width('100%')
      }
      if (this.generating) {
        this.presentationCard()
      } else if (this.isGenerated()) {
        this.poseControl()
        this.modeControl()
        this.preview()
      } else {
        this.waitingPreview()
        Text('选择一组样片，查看预置的试穿效果。')
          .fontSize(Type.bodySmall).fontColor(Theme.secondary).width('100%')
      }
      this.generationAction()
      this.actions()
      if (this.notice.length > 0) {
        Text(this.notice).fontSize(Type.bodySmall).fontColor(this.failed ? Theme.warning : Theme.accent)
          .width('100%')
      }
      Row() {
        Text('试穿记录').fontSize(Type.section).fontWeight(FontWeight.Medium).fontColor(Theme.text)
        Blank()
        Text(this.tasks.length + ' 条').fontSize(Type.caption).fontColor(Theme.secondary)
      }.width('100%').margin({ top: 12 })
      if (this.tasks.length === 0) {
        Text('暂无保存记录').fontSize(Type.bodySmall).fontColor(Theme.secondary).width('100%').padding({ top: 12, bottom: 12 })
      } else {
        ForEach(this.tasks, (task: TryOnTask) => { this.record(task) },
          (task: TryOnTask) => task.id + '_' + task.createdAt)
      }
      Text('预置示例图片，不会使用你的照片或衣橱单品生成结果。')
        .fontSize(Type.caption).fontColor(Theme.secondary).width('100%').margin({ top: 8 })
    }.width('100%').constraintSize({ maxWidth: 840 })
      .padding({ left: Theme.pagePadding, right: Theme.pagePadding, bottom: Theme.spaceXl })
  }
}
