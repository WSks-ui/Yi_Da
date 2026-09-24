// 离线迁移操作弹层：只负责让用户明确发起手动导出或导入，不建立自动同步连接。
// 真正的文件选择、序列化和覆盖快照由外层通过 Promise 回调提供，页面不持有同步服务。
import { MaterialCard } from '../components/MaterialKit';
import { Theme, Type } from '../components/Theme';

@Component
export struct SyncTransferSheet {
  onExport: () => Promise<void> = async () => {};
  onImport: () => Promise<void> = async () => {};

  @State busy: boolean = false;
  @State busyAction: string = '';
  @State notice: string = '';
  @State failed: boolean = false;
  @State confirmImport: boolean = false;

  private errorText(error: Error): string {
    return error.message.length > 0 ? error.message : '操作失败，请重试。';
  }

  private async exportData(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.busyAction = 'export';
    this.notice = '';
    this.failed = false;
    try {
      await this.onExport();
      this.notice = '迁移文件已保存到所选位置，可在另一台设备通过“导入数据”恢复。';
    } catch (error) {
      this.notice = this.errorText(error as Error);
      this.failed = this.notice.indexOf('已取消') !== 0;
    } finally {
      this.busy = false;
      this.busyAction = '';
    }
  }

  private askImport(): void {
    if (this.busy) { return; }
    this.notice = '';
    this.failed = false;
    this.confirmImport = true;
  }

  private cancelImport(): void {
    if (this.busy) { return; }
    this.confirmImport = false;
  }

  private async importData(): Promise<void> {
    if (this.busy) { return; }
    this.confirmImport = false;
    this.busy = true;
    this.busyAction = 'import';
    this.notice = '';
    this.failed = false;
    try {
      await this.onImport();
      this.notice = '导入完成。当前本地数据已按迁移文件恢复。';
    } catch (error) {
      this.notice = this.errorText(error as Error);
      this.failed = this.notice.indexOf('已取消') !== 0;
    } finally {
      this.busy = false;
      this.busyAction = '';
    }
  }

  @Builder
  private actionCard(icon: Resource, title: string, detail: string, action: () => void) {
    MaterialCard({ contentPadding: Theme.spaceM }) {
      Row({ space: Theme.spaceM }) {
        SymbolGlyph(icon).fontSize(Theme.iconLg).fontColor([Theme.accent])
        Column({ space: Theme.spaceXs }) {
          Text(title).fontSize(Type.cardTitle).fontWeight(FontWeight.Medium)
            .fontColor(Theme.text).width('100%').maxLines(1)
          Text(detail).fontSize(Type.caption).fontColor(Theme.secondary)
            .width('100%').maxLines(2)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(Theme.iconSm).fontColor([Theme.tertiary])
      }
        .width('100%')
        .opacity(this.busy || this.confirmImport ? Theme.disabledOpacity : 1)
        .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
        .onClick(() => { if (!this.busy && !this.confirmImport) { action(); } })
    }
  }

  @Builder
  private importConfirmation() {
    Column({ space: Theme.spaceM }) {
      Row({ space: Theme.spaceS }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(Theme.iconMd)
          .fontColor([Theme.warning])
        Text('导入会覆盖当前本地数据').fontSize(Type.cardTitle).fontWeight(FontWeight.Medium)
          .fontColor(Theme.warning).layoutWeight(1).maxLines(2)
      }.width('100%')
      Text('请先确认已有数据已经手动导出。导入只在你确认后开始，不会自动同步，也不会上传云端。')
        .fontSize(Type.caption).fontColor(Theme.text).lineHeight(20).width('100%').maxLines(4)
      Row({ space: Theme.spaceS }) {
        Button('取消', { type: ButtonType.Normal }).height(Theme.buttonCompact).layoutWeight(1)
          .fontSize(Type.buttonSmall).fontColor(Theme.secondary).backgroundColor(Theme.surfaceSoft)
          .borderRadius(Theme.radiusPill).enabled(!this.busy)
          .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
          .onClick(() => this.cancelImport())
        Button(this.busyAction === 'import' ? '导入中…' : '确认导入', { type: ButtonType.Normal })
          .height(Theme.buttonCompact).layoutWeight(1).fontSize(Type.buttonSmall)
          .fontColor(Theme.onAccent).backgroundColor(Theme.accent).borderRadius(Theme.radiusPill)
          .enabled(!this.busy).stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
          .onClick(() => this.importData())
      }.width('100%')
    }
      .width('100%').padding(Theme.spaceM)
      .backgroundColor(Theme.warningSoft).borderRadius(Theme.radiusInput)
  }

  build() {
    Scroll() {
      Column({ space: Theme.spaceL }) {
        Column({ space: Theme.spaceXs }) {
          Text('离线迁移').fontSize(Type.title).fontWeight(FontWeight.Bold)
            .fontColor(Theme.text).width('100%').maxLines(1)
          Text('手动导出或导入本机衣橱数据，不会自动同步，也不会上传云端。')
            .fontSize(Type.bodySmall).fontColor(Theme.secondary).width('100%').maxLines(3)
        }.alignItems(HorizontalAlign.Start).width('100%')

        this.actionCard($r('sys.symbol.arrow_up'), '导出数据',
          '生成迁移文件，由你手动保存到安全位置。', () => this.exportData())
        this.actionCard($r('sys.symbol.arrow_down_circle'), '导入数据',
          '选择之前手动保存的迁移文件，恢复本机数据。', () => this.askImport())

        if (this.confirmImport) { this.importConfirmation(); }
        if (this.busy) {
          Row({ space: Theme.spaceS }) {
            LoadingProgress().width(Theme.iconSm).height(Theme.iconSm).color(Theme.accent)
            Text(this.busyAction === 'export' ? '正在导出迁移文件…' : '正在导入迁移文件…')
              .fontSize(Type.caption).fontColor(Theme.secondary).layoutWeight(1).maxLines(2)
          }.width('100%')
        }
        if (this.notice.length > 0) {
          Text(this.notice).fontSize(Type.caption).fontColor(this.failed ? Theme.warning : Theme.success)
            .lineHeight(20).width('100%').maxLines(4)
            .padding(Theme.spaceM)
            .backgroundColor(this.failed ? Theme.warningSoft : Theme.surfaceSoft)
            .borderRadius(Theme.radiusInput)
        }
        Text('文件包含衣物照片、日记和身材档案，请保存在可信位置。')
          .fontSize(Type.caption).fontColor(Theme.secondary).width('100%').maxLines(2)
      }
        .width('100%')
        .padding({ left: Theme.spaceXl, right: Theme.spaceXl, top: Theme.spaceXl, bottom: Theme.spaceXxl })
        .alignItems(HorizontalAlign.Start)
    }
      .width('100%').backgroundColor(Theme.background)
  }
}
