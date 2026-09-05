import { common } from '@kit.AbilityKit';
import { AppServices } from '../../../common/AppServices';
import { GarmentPhoto } from '../../../common/components/GarmentPhoto';
import { Palette } from '../../../common/components/Palette';
import { categoryLabel, COLORS, COLOR_LABELS, seasonLabel, STATUSES, STATUS_LABELS, statusLabel } from '../../../domain/models/Garment';
import { GarmentRoute } from '../../../navigation/GarmentRoute';
import { GarmentDetailViewModel } from '../viewmodels/GarmentDetailViewModel';

@ComponentV2
export struct GarmentDetailPage {
  @Param garmentId: string = '';
  @Param space: string = 'personal';
  @Param stack: NavPathStack = new NavPathStack();
  @Event onChanged: () => void = () => {};
  @Local vm: GarmentDetailViewModel = new GarmentDetailViewModel();

  private load(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.vm.load(AppServices.get(context).wardrobe, this.garmentId, this.space);
  }

  private remove(): void {
    this.getUIContext().showAlertDialog({
      title: '永久删除这件衣物？',
      message: '衣物记录和无其他引用的沙箱照片将被删除，无法恢复。已导出到相册的副本不受影响。',
      primaryButton: { value: '保留衣物', action: () => {} },
      secondaryButton: { value: '永久删除', action: async () => {
        if (await this.vm.remove()) { this.onChanged(); this.stack.pop(); }
      } }
    });
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 20 }) {
          if (this.vm.phase === 'loading') {
            LoadingProgress().width(40).height(40)
          } else if (this.vm.phase === 'error') {
            Text(this.vm.error).fontColor(Palette.danger)
            Button('重新读取').onClick(() => { this.load(); })
          } else {
            GarmentPhoto({ path: this.vm.path, label: this.vm.garment.name }).height(300)
            Text(this.vm.garment.name).fontSize(24).fontWeight(FontWeight.Bold)
              .fontColor(Palette.text).width('100%')
            Text(this.space === 'demo' ? '示例衣橱' : '个人衣橱').fontSize(13).fontColor(Palette.muted).width('100%')
            Text(`${categoryLabel(this.vm.garment.category)} · ${COLOR_LABELS[COLORS.indexOf(this.vm.garment.colorGroup)]} · ${seasonLabel(this.vm.garment.seasonMask)}`)
              .fontSize(16).fontColor(Palette.text).width('100%')
            Divider().color(Palette.line)
            Row() {
              Text('当前状态').fontSize(16).fontColor(Palette.text).layoutWeight(1)
              Select(STATUS_LABELS.map((value: string): SelectOption => { return { value: value }; }))
                .selected(STATUSES.indexOf(this.vm.garment.status)).value(statusLabel(this.vm.garment.status))
                .enabled(!this.vm.busy).onSelect(async (index: number) => {
                  if (await this.vm.changeStatus(STATUSES[index])) { this.onChanged(); }
                })
            }.width('100%')
            Text(`记录版本 ${this.vm.garment.version}`).fontSize(12).fontColor(Palette.muted).width('100%')
            if (this.vm.error) { Text(this.vm.error).fontColor(Palette.danger).width('100%') }
            Button('编辑衣物', { type: ButtonType.Normal }).id('editGarment')
              .width('100%').height(48).borderRadius(6).backgroundColor(Palette.accent).enabled(!this.vm.busy)
              .onClick(() => {
                this.stack.pushPath({ name: 'garmentEdit', param: new GarmentRoute(this.garmentId, this.space) });
              })
            if (this.vm.garment.status === 'archived') {
              Button('永久删除', { type: ButtonType.Normal }).width('100%').height(44)
                .borderRadius(6).backgroundColor(Palette.panel).fontColor(Palette.danger)
                .enabled(!this.vm.busy).onClick(() => { this.remove(); })
            } else {
              Button('归档衣物', { type: ButtonType.Normal }).width('100%').height(44)
                .borderRadius(6).backgroundColor(Palette.panel).fontColor(Palette.text)
                .enabled(!this.vm.busy).onClick(async () => {
                  if (await this.vm.changeStatus('archived')) { this.onChanged(); }
                })
            }
          }
        }.padding(20).width('100%').constraintSize({ maxWidth: 680 })
      }.width('100%').height('100%').backgroundColor(Palette.background)
    }.title('衣物详情').onShown(() => { this.load(); })
      .onBackPressed(() => { return this.vm.busy; })
  }
}
