import { Palette } from '../../../common/components/Palette';
import { GarmentPhoto } from '../../../common/components/GarmentPhoto';
import { BatchChange, CATEGORIES, CATEGORY_LABELS, Garment, categoryLabel, seasonLabel, STATUSES, STATUS_LABELS, statusLabel } from '../../../domain/models/Garment';
import { WardrobeService } from '../../../domain/usecases/WardrobeService';
import { WardrobeViewModel } from '../viewmodels/WardrobeViewModel';

@ComponentV2
export struct WardrobePage {
  @Param vm: WardrobeViewModel = new WardrobeViewModel();
  @Param service: WardrobeService | undefined = undefined;
  @Event onAdd: () => void = () => {};
  @Event onDetail: (id: string) => void = () => {};
  @Event onChanged: () => void = () => {};
  @Local showBatch: boolean = false;
  @Local batchStatus: number = 0;
  @Local batchCategory: number = 0;
  @Local batchSeason: number = 0;
  private scroller: Scroller = new Scroller();

  private photoPath(garment: Garment): string {
    if (!this.service || !garment.thumbnailPath) { return ''; }
    try { return this.service.photos.absolute(garment.thumbnailPath); } catch (_) { return ''; }
  }

  private deleteSelected(): void {
    this.getUIContext().showAlertDialog({
      title: `永久删除 ${this.vm.selected.length} 件衣物？`,
      message: '只删除当前选中的已归档衣物，不可恢复。无引用的沙箱照片会一同清理。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '永久删除', action: async () => {
        await this.vm.deleteSelected(); this.onChanged();
      } }
    });
  }

  @Builder
  batchSheet() {
    Column({ space: 16 }) {
      Text(`批量修改 · ${this.vm.selected.length} 件`).fontSize(20).fontWeight(FontWeight.Bold).fontColor(Palette.text)
      Select(['状态不变', ...STATUS_LABELS].map((value: string): SelectOption => { return { value: value }; }))
        .selected(this.batchStatus).value(['状态不变', ...STATUS_LABELS][this.batchStatus])
        .width('100%').onSelect((index: number) => { this.batchStatus = index; })
      Select(['类别不变', ...CATEGORY_LABELS].map((value: string): SelectOption => { return { value: value }; }))
        .selected(this.batchCategory).value(['类别不变', ...CATEGORY_LABELS][this.batchCategory])
        .width('100%').onSelect((index: number) => { this.batchCategory = index; })
      Select(['季节不变', '未知', '春', '夏', '秋', '冬', '四季'].map((value: string): SelectOption => { return { value: value }; }))
        .selected(this.batchSeason).value(['季节不变', '未知', '春', '夏', '秋', '冬', '四季'][this.batchSeason])
        .width('100%').onSelect((index: number) => { this.batchSeason = index; })
      if (this.vm.error) { Text(this.vm.error).fontSize(14).fontColor(Palette.danger) }
      Button('应用修改', { type: ButtonType.Normal }).height(48).width('100%')
        .backgroundColor(Palette.accent).borderRadius(6).enabled(!this.vm.busy)
        .onClick(async () => {
          const change = new BatchChange();
          change.status = this.batchStatus > 0 ? STATUSES[this.batchStatus - 1] : '';
          change.category = this.batchCategory > 0 ? CATEGORIES[this.batchCategory - 1] : '';
          change.seasonMask = [-1, 0, 1, 2, 4, 8, 15][this.batchSeason];
          if (await this.vm.batch(change)) { this.showBatch = false; this.onChanged(); }
        })
    }.padding(24).width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text('衣橱').fontSize(26).fontWeight(FontWeight.Bold).fontColor(Palette.text)
          Select([{ value: '个人衣橱' }, { value: '示例衣橱' }])
            .selected(this.vm.space === 'demo' ? 1 : 0)
            .value(this.vm.space === 'demo' ? '示例衣橱' : '个人衣橱')
            .font({ size: 13 }).height(32).id('wardrobeSpace')
            .onSelect((index: number) => {
              this.vm.space = index === 1 ? 'demo' : 'personal'; this.vm.resetFilters();
            })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button(this.vm.selecting ? '完成' : '多选', { type: ButtonType.Normal })
          .fontSize(14).borderRadius(6).backgroundColor(Palette.panel).fontColor(Palette.text)
          .enabled(!this.vm.busy).onClick(() => { this.vm.selecting = !this.vm.selecting; this.vm.selected = []; })
        if (this.vm.space === 'personal') {
          Button({ type: ButtonType.Normal }) {
            Image($r('sys.media.ohos_ic_public_add')).width(22).height(22).fillColor(Color.White)
          }.id('addGarment').width(44).height(44).borderRadius(6).backgroundColor(Palette.accent)
            .accessibilityText('添加衣物').onClick(() => { this.onAdd(); })
        }
      }.width('100%')
      Search({ value: this.vm.search, placeholder: '搜索衣物名称' }).id('searchGarments')
        .height(44).borderRadius(6).onChange((value: string) => { this.vm.search = value; this.vm.load(); })
      Row({ space: 6 }) {
        Select(['全部类别', ...CATEGORY_LABELS].map((value: string): SelectOption => { return { value: value }; }))
          .selected(CATEGORIES.indexOf(this.vm.category) + 1)
          .value(this.vm.category ? categoryLabel(this.vm.category) : '全部类别').font({ size: 13 })
          .layoutWeight(1).onSelect((index: number) => { this.vm.category = index ? CATEGORIES[index - 1] : ''; this.vm.load(); })
        Select(['日常衣橱', ...STATUS_LABELS].map((value: string): SelectOption => { return { value: value }; }))
          .selected(STATUSES.indexOf(this.vm.status) + 1).font({ size: 13 })
          .value(this.vm.status ? statusLabel(this.vm.status) : '日常衣橱').layoutWeight(1)
          .onSelect((index: number) => { this.vm.status = index ? STATUSES[index - 1] : ''; this.vm.load(); })
        Select(['全部季节', '春', '夏', '秋', '冬'].map((value: string): SelectOption => { return { value: value }; }))
          .selected([0, 1, 2, 4, 8].indexOf(this.vm.seasonMask)).font({ size: 13 })
          .value(['全部季节', '春', '夏', '秋', '冬'][[0, 1, 2, 4, 8].indexOf(this.vm.seasonMask)])
          .layoutWeight(1).onSelect((index: number) => { this.vm.seasonMask = [0, 1, 2, 4, 8][index]; this.vm.load(); })
      }.width('100%')
      if (this.vm.selecting) {
        Row({ space: 8 }) {
          Checkbox().select(this.vm.items.length > 0 && this.vm.selected.length === this.vm.items.length)
            .onChange((value: boolean) => {
              this.vm.selected = value ? this.vm.items.slice(0, 200).map((item: Garment) => item.id) : [];
            }).selectedColor(Palette.accent).accessibilityText('全选当前结果，最多200件')
          Text(`已选 ${this.vm.selected.length}`).fontSize(13).fontColor(Palette.text).layoutWeight(1)
          Button('修改', { type: ButtonType.Normal }).fontSize(14).backgroundColor(Palette.accent).borderRadius(6)
            .enabled(this.vm.selected.length > 0 && !this.vm.busy)
            .onClick(() => {
              this.batchCategory = 0; this.batchStatus = 0; this.batchSeason = 0; this.vm.error = ''; this.showBatch = true;
            })
          if (this.vm.status === 'archived') {
            Button({ type: ButtonType.Normal }) {
              SymbolGlyph($r('sys.symbol.ohos_trash')).fontSize(20).fontColor([Palette.danger])
            }.width(40).height(40).borderRadius(6).backgroundColor(Palette.panel)
              .accessibilityText('永久删除选中衣物').enabled(this.vm.selected.length > 0 && !this.vm.busy)
              .onClick(() => { this.deleteSelected(); })
          }
        }.width('100%')
      }
      if (this.vm.error) {
        Text(this.vm.error).fontSize(14).fontColor(Palette.danger).width('100%')
      }
      if (this.vm.notice) {
        Text(this.vm.notice).fontSize(12).fontColor(Palette.muted).width('100%')
      }
      if (this.vm.phase === 'loading' || this.vm.phase === 'initial') {
        Column({ space: 12 }) {
          LoadingProgress().width(36).height(36)
          Text('正在读取衣橱').fontSize(14).fontColor(Palette.muted)
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.vm.phase === 'error') {
        Column() {
          Button('重试读取').onClick(() => { this.vm.load(); })
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.vm.phase === 'empty') {
        Column({ space: 18 }) {
          SymbolGlyph($r('sys.symbol.ohos_folder_badge_plus')).fontSize(44).fontColor([Palette.muted])
          Text(this.vm.search || this.vm.category || this.vm.status || this.vm.seasonMask ? '没有符合条件的衣物' : '衣橱里还没有衣物')
            .fontSize(18).fontColor(Palette.text)
          if (this.vm.search || this.vm.category || this.vm.status || this.vm.seasonMask) {
            Button('清除筛选').onClick(() => { this.vm.resetFilters(); })
          } else {
            if (this.vm.space === 'demo') {
              Button(this.vm.busy ? '正在导入' : '体验示例衣物').backgroundColor(Palette.accent)
                .enabled(!this.vm.busy).onClick(() => { this.vm.addSample(); })
            } else {
              Button('添加第一件衣物').backgroundColor(Palette.accent).onClick(() => { this.onAdd(); })
            }
          }
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Row() {
          Text(`${this.vm.items.length} 件衣物`).fontSize(12).fontColor(Palette.muted).layoutWeight(1)
          Button('清除筛选', { type: ButtonType.Normal }).fontSize(12).height(28)
            .fontColor(Palette.muted).backgroundColor(Color.Transparent).onClick(() => { this.vm.resetFilters(); })
        }.width('100%')
        Grid(this.scroller) {
          ForEach(this.vm.items, (garment: Garment) => {
            GridItem() {
              Column({ space: 8 }) {
                Stack({ alignContent: Alignment.TopEnd }) {
                  GarmentPhoto({ path: this.photoPath(garment), label: garment.name })
                  if (this.vm.selecting) {
                    Checkbox({ name: garment.id }).select(this.vm.selected.includes(garment.id))
                      .selectedColor(Palette.accent).margin(6)
                      .onChange((value: boolean) => {
                        if (value !== this.vm.selected.includes(garment.id)) { this.vm.toggle(garment.id); }
                      })
                  }
                }.width('100%').aspectRatio(1)
                Text(garment.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(Palette.text)
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).height(44).width('100%')
                Text(`${categoryLabel(garment.category)} · ${statusLabel(garment.status)}`)
                  .fontSize(12).fontColor(garment.status === 'wearable' ? Palette.accent : Palette.muted)
                  .width('100%').maxLines(1)
                Text(seasonLabel(garment.seasonMask)).fontSize(11).fontColor(Palette.muted).width('100%')
              }.width('100%').padding({ bottom: 12 })
                .onClick(() => { this.vm.selecting ? this.vm.toggle(garment.id) : this.onDetail(garment.id); })
            }
          }, (garment: Garment) => `${garment.id}:${garment.version}`)
        }.columnsTemplate('1fr 1fr').columnsGap(14).rowsGap(12).layoutWeight(1).width('100%')
      }
    }.padding({ left: 20, right: 20, top: 18, bottom: 8 }).width('100%').height('100%')
      .backgroundColor(Palette.background)
      .bindSheet($$this.showBatch, this.batchSheet(), { height: 450, showClose: true })
  }
}
