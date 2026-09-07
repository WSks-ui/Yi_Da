import { common } from '@kit.AbilityKit';
import { AppServices } from '../../../common/AppServices';
import { Palette } from '../../../common/components/Palette';
import { ImportItemEditor } from '../components/ImportItemEditor';
import { ImportItem, ImportQueueViewModel } from '../viewmodels/ImportQueueViewModel';

@ComponentV2
export struct ImportQueuePage {
  @Param stack: NavPathStack = new NavPathStack();
  @Event onChanged: () => void = () => {};
  @Local vm: ImportQueueViewModel = new ImportQueueViewModel();

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.vm.connect(AppServices.get(context).wardrobe);
  }

  aboutToDisappear(): void { this.vm.dispose(); }

  private leave(): void {
    if (this.vm.closing) { return; }
    if (this.vm.hasUnfinished() || this.vm.picking) {
      this.getUIContext().showAlertDialog({
        title: '结束本次导入？',
        message: '已保存的衣物会保留。未保存的照片与属性将被丢弃，正在提交的一件会先完成。',
        primaryButton: { value: '继续导入', action: () => {} },
        secondaryButton: { value: '结束导入', action: async () => { await this.close(); } }
      });
    } else { this.close(); }
  }

  private async close(): Promise<void> {
    await this.vm.dispose();
    this.onChanged();
    this.stack.pop();
  }

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Text(`本次 ${this.vm.items.length} 张 · 已保存 ${this.vm.savedCount()} 件`)
            .fontSize(14).fontColor(Palette.muted).layoutWeight(1)
          Button({ type: ButtonType.Normal }) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.ohos_photo')).fontSize(20).fontColor([Palette.accent])
              Text('选择照片').fontSize(14).fontColor(Palette.accent)
            }.padding(10)
          }.id('importPick').borderRadius(6).backgroundColor(Palette.panel)
            .enabled(!this.vm.processing && !this.vm.saving && !this.vm.picking && !this.vm.closing)
            .onClick(() => { this.vm.pick(); })
        }.width('100%')
        if (this.vm.error) { Text(this.vm.error).fontColor(Palette.danger).fontSize(14).width('100%') }
        if (this.vm.notice) { Text(this.vm.notice).fontColor(Palette.muted).fontSize(13).width('100%') }
        if (this.vm.processing || this.vm.paused) {
          Row() {
            Text(this.vm.processing ? (this.vm.paused ? '当前照片完成后暂停' : '正在处理照片') : '处理已暂停')
              .fontSize(14).fontColor(Palette.muted).layoutWeight(1)
            Button(this.vm.processing ? '暂停' : '继续处理', { type: ButtonType.Normal })
              .borderRadius(6).backgroundColor(Palette.panel).fontColor(Palette.accent)
              .enabled(!this.vm.saving && !this.vm.closing).onClick(() => {
                this.vm.processing ? this.vm.pause() : this.vm.resume();
              })
          }.width('100%')
        }
        if (this.vm.picking || this.vm.closing) { LoadingProgress().width(24).height(24) }
        if (this.vm.items.length === 0) {
          Column({ space: 16 }) {
            SymbolGlyph($r('sys.symbol.ohos_photo')).fontSize(42).fontColor([Palette.muted])
            Text('还未选择衣物照片').fontSize(18).fontColor(Palette.text)
          }.layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ space: 0 }) {
            ForEach(this.vm.items, (item: ImportItem) => {
              ListItem() {
                ImportItemEditor({
                  item: item, frozen: this.vm.saving || this.vm.closing,
                  canRetry: !this.vm.processing && !this.vm.picking,
                  onSkip: () => { this.vm.skip(item); },
                  onRetry: () => { this.vm.retry(item); }
                })
              }
            }, (item: ImportItem) => item.id)
          }.layoutWeight(1).width('100%')
        }
        Row({ space: 10 }) {
          Button('结束导入', { type: ButtonType.Normal }).height(48).layoutWeight(1)
            .fontColor(Palette.text).backgroundColor(Palette.panel).borderRadius(6).enabled(!this.vm.closing)
            .onClick(() => { this.leave(); })
          Button(`保存已确认 (${this.vm.readyCount()})`, { type: ButtonType.Normal }).id('saveImport')
            .height(48).layoutWeight(2).backgroundColor(Palette.accent).borderRadius(6)
            .enabled(!this.vm.processing && !this.vm.picking && !this.vm.saving && !this.vm.closing)
            .onClick(async () => { await this.vm.saveConfirmed(); this.onChanged(); })
        }.width('100%')
      }.padding(20).width('100%').height('100%').backgroundColor(Palette.background)
    }.title('相册导入').onBackPressed(() => { this.leave(); return true; })
  }
}
