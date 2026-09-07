import { common } from '@kit.AbilityKit';
import { AppServices } from '../../../common/AppServices';
import { GarmentPhoto } from '../../../common/components/GarmentPhoto';
import { Palette } from '../../../common/components/Palette';
import { CATEGORIES, CATEGORY_LABELS, COLORS, COLOR_LABELS, COLOR_SWATCHES, STATUSES, STATUS_LABELS } from '../../../domain/models/Garment';
import { GarmentEditorViewModel } from '../viewmodels/GarmentEditorViewModel';

@ComponentV2
export struct GarmentEditPage {
  @Param garmentId: string = '';
  @Param space: string = 'personal';
  @Param stack: NavPathStack = new NavPathStack();
  @Event onSaved: () => void = () => {};
  @Event onClosed: () => void = () => {};
  @Local vm: GarmentEditorViewModel = new GarmentEditorViewModel();

  aboutToAppear(): void { this.load(); }
  aboutToDisappear(): void { this.vm.dispose().then(() => { this.onClosed(); }); }

  private load(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.vm.open(AppServices.get(context).wardrobe, this.garmentId, this.space);
  }

  private leave(): void {
    if (this.vm.busy) { return; }
    if (!this.vm.dirty) { this.stack.pop(); return; }
    this.getUIContext().showAlertDialog({
      title: '放弃未保存的修改？',
      message: '已保存的衣物不会受影响。',
      primaryButton: { value: '继续编辑', action: () => {} },
      secondaryButton: { value: '放弃修改', action: () => { this.stack.pop(); } }
    });
  }

  @Builder
  fieldLabel(label: string) {
    Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(Palette.muted).width('100%')
  }

  build() {
    NavDestination() {
      Column() {
        if (this.vm.loading) {
          LoadingProgress().width(40).height(40).margin(32)
        } else if (this.vm.loadFailed) {
          Text(this.vm.error).fontColor(Palette.danger).margin(24)
          Button('重新读取').onClick(() => { this.load(); })
        } else {
          Scroll() {
            Column({ space: 14 }) {
              if (this.space === 'demo') {
                Text('示例空间').fontSize(13).fontColor(Palette.muted).width('100%')
              }
              Stack({ alignContent: Alignment.BottomEnd }) {
                GarmentPhoto({ path: this.vm.imagePath, label: this.vm.name || '衣物照片' })
                Button({ type: ButtonType.Normal }) {
                  Row({ space: 6 }) {
                    SymbolGlyph($r('sys.symbol.ohos_photo')).fontSize(18).fontColor([Palette.accent])
                    Text(this.vm.imagePath ? '更换照片' : '从相册选择').fontSize(14).fontColor(Palette.accent)
                  }.padding(12)
                }.id('pickPhoto').borderRadius(6).backgroundColor(Palette.panel).margin(12)
                  .enabled(!this.vm.busy).onClick(() => { this.vm.pick(); })
              }.width('100%').height(220)
              if (this.vm.error) {
                Text(this.vm.error).id('editorError').fontSize(14).fontColor(Palette.danger).width('100%')
              }
              if (this.vm.duplicate) {
                Row() {
                  Checkbox().select(this.vm.allowDuplicate).selectedColor(Palette.accent)
                    .onChange((value: boolean) => { this.vm.allowDuplicate = value; })
                  Text('仍作为另一件衣物保存').fontSize(14).fontColor(Palette.text).layoutWeight(1)
                }.width('100%')
              }
              if (this.vm.busy) {
                Row({ space: 8 }) {
                  LoadingProgress().width(22).height(22)
                  Text('正在处理，请稍候').fontSize(14).fontColor(Palette.muted)
                }
              }
              if (this.vm.notice) {
                Text(this.vm.notice).fontSize(14).fontColor(Palette.muted).width('100%')
              }
              this.fieldLabel('衣物名称 *')
              TextInput({ text: this.vm.name, placeholder: '例如：白色棉衬衫' })
                .id('garmentName').maxLength(80).height(48).borderRadius(6)
                .onChange((value: string) => { this.vm.name = value; this.vm.dirty = true; })
              Row({ space: 16 }) {
                Column({ space: 8 }) {
                  this.fieldLabel('类别 *')
                  Select(CATEGORY_LABELS.map((value: string): SelectOption => { return { value: value }; }))
                    .selected(CATEGORIES.indexOf(this.vm.category))
                    .value(CATEGORY_LABELS[CATEGORIES.indexOf(this.vm.category)]).width('100%')
                    .onSelect((index: number) => { this.vm.category = CATEGORIES[index]; this.vm.dirty = true; })
                }.layoutWeight(1)
                Column({ space: 8 }) {
                  this.fieldLabel('衣物状态 *')
                  Select(STATUS_LABELS.map((value: string): SelectOption => { return { value: value }; }))
                    .selected(STATUSES.indexOf(this.vm.status)).value(STATUS_LABELS[STATUSES.indexOf(this.vm.status)])
                    .width('100%').onSelect((index: number) => { this.vm.status = STATUSES[index]; this.vm.dirty = true; })
                }.layoutWeight(1)
              }.width('100%')
              this.fieldLabel('适用季节')
              Row() {
                ForEach(['春', '夏', '秋', '冬'], (name: string, index: number) => {
                  Row() {
                    Checkbox({ name: name }).select((this.vm.seasonMask & (1 << index)) !== 0)
                      .selectedColor(Palette.accent).onChange((selected: boolean) => {
                        this.vm.seasonMask = selected ? this.vm.seasonMask | (1 << index) : this.vm.seasonMask & ~(1 << index);
                        this.vm.dirty = true;
                      }).margin({ right: 4 })
                    Text(name).fontSize(15).fontColor(Palette.text)
                  }.layoutWeight(1)
                })
              }.width('100%')
              this.fieldLabel(`颜色 · ${COLOR_LABELS[COLORS.indexOf(this.vm.colorGroup)]}`)
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(COLORS, (color: string, index: number) => {
                  Button({ type: ButtonType.Circle }) {
                    if (this.vm.colorGroup === color) {
                      SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(22)
                        .fontColor([index === 1 ? Color.White : Color.Black])
                    }
                  }.width(38).height(38).margin({ right: 10, bottom: 10 })
                    .backgroundColor(COLOR_SWATCHES[index])
                    .border({ width: 1, color: Palette.line })
                    .accessibilityText(COLOR_LABELS[index])
                    .onClick(() => { this.vm.colorGroup = color; this.vm.dirty = true; })
                })
              }.width('100%')
            }.enabled(!this.vm.busy).padding(20).width('100%').constraintSize({ maxWidth: 680 })
          }.layoutWeight(1).width('100%')
          Row({ space: 12 }) {
            Button('取消', { type: ButtonType.Normal }).layoutWeight(1).height(48).borderRadius(6)
              .backgroundColor(Palette.panel).fontColor(Palette.text).enabled(!this.vm.busy)
              .onClick(() => { this.leave(); })
            Button('保存衣物', { type: ButtonType.Normal }).id('saveGarment')
              .layoutWeight(2).height(48).borderRadius(6).backgroundColor(Palette.accent)
              .enabled(!this.vm.busy).onClick(async () => {
                if (await this.vm.save()) { this.onSaved(); this.stack.pop(); }
              })
          }.padding({ left: 20, right: 20, top: 12, bottom: 16 }).width('100%')
        }
      }.width('100%').height('100%').backgroundColor(Palette.background)
    }.title(this.garmentId ? '编辑衣物' : '添加衣物')
      .onBackPressed(() => { this.leave(); return true; })
  }
}
