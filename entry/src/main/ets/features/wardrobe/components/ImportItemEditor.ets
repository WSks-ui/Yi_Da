import { GarmentPhoto } from '../../../common/components/GarmentPhoto';
import { Palette } from '../../../common/components/Palette';
import { CATEGORIES, CATEGORY_LABELS, COLORS, COLOR_LABELS, STATUSES, STATUS_LABELS } from '../../../domain/models/Garment';
import { toggleSeason } from '../../../domain/usecases/ImportPolicy';
import { ImportItem } from '../viewmodels/ImportQueueViewModel';

@ComponentV2
export struct ImportItemEditor {
  @Require @Param item: ImportItem;
  @Param frozen: boolean = false;
  @Param canRetry: boolean = true;
  @Event onSkip: () => void = () => {};
  @Event onRetry: () => void = () => {};

  private phaseLabel(): string {
    switch (this.item.phase) {
      case 'pending': return '等待处理';
      case 'processing': return '正在处理';
      case 'ready': return '待确认';
      case 'failed': return '处理失败';
      case 'saving': return '正在保存';
      case 'saved': return '已保存';
      default: return '已跳过';
    }
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        GarmentPhoto({ path: this.item.imagePath, label: this.item.name || '待录入衣物' }).width(84).height(84)
        Column({ space: 8 }) {
          Text(this.phaseLabel()).fontSize(13)
            .fontColor(this.item.phase === 'failed' ? Palette.danger : Palette.accent).width('100%')
          if (this.item.phase === 'ready') {
            TextInput({ text: this.item.name, placeholder: '衣物名称 *' }).height(44).borderRadius(6).maxLength(80)
              .id(`${this.item.id}-name`).enabled(!this.frozen)
              .onChange((value: string) => { this.item.name = value; this.item.confirmed = false; })
          } else {
            Text(this.item.name || '待录入衣物').fontSize(16).fontColor(Palette.text).maxLines(2).width('100%')
          }
        }.layoutWeight(1)
        if (this.item.phase !== 'saved' && this.item.phase !== 'skipped' && this.item.phase !== 'processing') {
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.ohos_trash')).fontSize(20).fontColor([Palette.muted])
          }.width(40).height(40).borderRadius(6).backgroundColor(Palette.panel).enabled(!this.frozen)
            .id(`${this.item.id}-skip`).accessibilityText('跳过这张照片').onClick(() => { this.onSkip(); })
        }
      }.width('100%')
      if (this.item.phase === 'processing' || this.item.phase === 'saving') {
        LoadingProgress().width(24).height(24)
      }
      if (this.item.error) { Text(this.item.error).fontSize(14).fontColor(Palette.danger).width('100%') }
      if (this.item.phase === 'failed') {
        Button('重试这张照片', { type: ButtonType.Normal }).borderRadius(6).fontColor(Palette.accent)
          .backgroundColor(Palette.panel).enabled(!this.frozen && this.canRetry).onClick(() => { this.onRetry(); })
      }
      if (this.item.phase === 'ready') {
        Row({ space: 12 }) {
          Select(['选择类别 *', ...CATEGORY_LABELS].map((value: string): SelectOption => { return { value: value }; }))
            .selected(CATEGORIES.indexOf(this.item.category) + 1).id(`${this.item.id}-category`)
            .value(CATEGORIES.includes(this.item.category) ? CATEGORY_LABELS[CATEGORIES.indexOf(this.item.category)] : '选择类别 *')
            .layoutWeight(1).onSelect((index: number) => {
              this.item.category = index > 0 ? CATEGORIES[index - 1] : ''; this.item.confirmed = false;
            })
          Select(STATUS_LABELS.map((value: string): SelectOption => { return { value: value }; }))
            .selected(STATUSES.indexOf(this.item.status)).value(STATUS_LABELS[STATUSES.indexOf(this.item.status)])
            .layoutWeight(1).onSelect((index: number) => { this.item.status = STATUSES[index]; this.item.confirmed = false; })
        }.enabled(!this.frozen).width('100%')
        Row() {
          Text('颜色与季节').fontSize(14).fontColor(Palette.muted).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.item.expanded }).selectedColor(Palette.accent)
            .onChange((value: boolean) => { this.item.expanded = value; })
        }.width('100%')
        if (this.item.expanded) {
          Select(COLOR_LABELS.map((value: string): SelectOption => { return { value: value }; }))
            .selected(COLORS.indexOf(this.item.colorGroup)).value(COLOR_LABELS[COLORS.indexOf(this.item.colorGroup)])
            .enabled(!this.frozen).width('100%').onSelect((index: number) => {
              this.item.colorGroup = COLORS[index]; this.item.confirmed = false;
            })
          Row() {
            ForEach(['春', '夏', '秋', '冬'], (name: string, index: number) => {
              Row() {
                Checkbox({ name: name }).select((this.item.seasonMask & (1 << index)) !== 0)
                  .selectedColor(Palette.accent).onChange((value: boolean) => {
                    this.item.seasonMask = toggleSeason(this.item.seasonMask, index, value);
                    this.item.confirmed = false;
                  }).margin({ right: 4 })
                Text(name).fontSize(14).fontColor(Palette.text)
              }.layoutWeight(1)
            })
          }.enabled(!this.frozen).width('100%')
        }
        if (this.item.duplicate) {
          Text('当前衣橱或本次导入中存在相同照片').fontSize(13).fontColor(Palette.danger).width('100%')
          Row() {
            Checkbox().select(this.item.allowDuplicate).selectedColor(Palette.accent).id(`${this.item.id}-duplicate`)
              .onChange((value: boolean) => { this.item.allowDuplicate = value; })
            Text('仍作为另一件衣物保存').fontSize(14).fontColor(Palette.text).layoutWeight(1)
          }.enabled(!this.frozen).width('100%')
        }
        Row() {
          Checkbox().select(this.item.confirmed).selectedColor(Palette.accent).id(`${this.item.id}-confirm`)
            .onChange((value: boolean) => { this.item.confirmed = value; })
          Text('已确认这件衣物的属性').fontSize(14).fontColor(Palette.text).layoutWeight(1)
        }.enabled(!this.frozen).width('100%')
      }
      Divider().color(Palette.line)
    }.padding({ top: 12, bottom: 8 }).width('100%')
  }
}
