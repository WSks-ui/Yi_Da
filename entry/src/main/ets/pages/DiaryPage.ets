// 穿搭日记 + 佩戴日历。
//
// 诚信前提：本工程没有接入任何生成式服务。日记只保存用户真实填写的内容
// （日期、单品、文字感受、天气、场合）；页面内不读取相册，保存时 photoUri 固定为空字符串，
// 卡片只在它有值时才渲染照片，绝不会用预置图片冒充用户的上身照。
//
// 根容器不加 Scroll：与 Index.ets 里的页面片段保持一致，由外层 TabContent 的 Scroll 提供滚动，
// 避免内层 Scroll 拿到无界高度后出现滚动嵌套异常。
import { DiaryEntry, Garment, Outfit, OCCASIONS, garmentImage } from '../model/Wardrobe';
import { Theme, Type } from '../components/Theme';
import { MaterialCard, SectionHeader, panelMaterial } from '../components/MaterialKit';

interface DayParts {
  year: number;
  // 0 基月份，与 Date.getMonth() 保持同一套编号，避免两套编号来回换算出错。
  month: number;
  day: number;
}

const WEEK_LABELS: string[] = ['一', '二', '三', '四', '五', '六', '日'];
const WEEK_NAMES: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const WEATHERS: string[] = ['晴', '多云', '阴', '小雨', '大风', '雪'];
const FEEDBACKS: string[] = ['合适', '偏冷', '偏热', '不舒服', '喜欢'];
const CONTENT_MAX_WIDTH: number = 840;
// 日历格子固定高度：有记录圆点与没有圆点的日期行高一致，翻月时版面不会跳动。
const CELL_HEIGHT: number = 44;
const NOTE_LIMIT: number = 200;

function pad2(value: number): string {
  return value < 10 ? '0' + value : String(value);
}

// 日期统一存成 YYYY-MM-DD：可直接按字符串比较大小，也避开 Date 解析字符串时各端规则不一致的问题。
function dayKey(year: number, month: number, day: number): string {
  return year + '-' + pad2(month + 1) + '-' + pad2(day);
}

function toNumber(text: string): number {
  const value: number = Number(text);
  return Number.isFinite(value) ? value : 0;
}

// 兼容 "2025-06-05"、"2025/6/5"、"2025.6.5" 三种写法：旧记录可能来自别的入口。
// 解析失败时返回全 0，调用方据此原样展示文本，不猜测日期。
function parseDay(value: string): DayParts {
  const parts: string[] = value.split('.').join('-').split('/').join('-').split('-');
  if (parts.length < 3) { return { year: 0, month: 0, day: 0 }; }
  return { year: toNumber(parts[0]), month: toNumber(parts[1]) - 1, day: toNumber(parts[2]) };
}

function dayText(key: string): string {
  const parts: DayParts = parseDay(key);
  if (parts.year <= 0) { return key; }
  return parts.year + '年' + (parts.month + 1) + '月' + parts.day + '日';
}

function shortDayText(key: string): string {
  const parts: DayParts = parseDay(key);
  if (parts.year <= 0) { return key; }
  return (parts.month + 1) + '月' + parts.day + '日';
}

function weekName(key: string): string {
  const parts: DayParts = parseDay(key);
  if (parts.year <= 0) { return ''; }
  return WEEK_NAMES[new Date(parts.year, parts.month, parts.day).getDay()];
}

@Component
export struct DiaryPage {
  @Prop diary: DiaryEntry[] = [];
  @Prop garments: Garment[] = [];
  @Prop saved: Outfit[] = [];
  onAddEntry: (entry: DiaryEntry) => Promise<void> = async () => {};
  onDeleteEntry: (id: string) => Promise<void> = async () => {};
  @State saving: boolean = false;
  private formEntryId: string = '';
  onOpenOutfit: (outfit: Outfit) => void = () => {};

  // 日历游标与选中日期只属于本组件：父组件不需要知道用户翻到了哪个月。
  @State year: number = new Date().getFullYear();
  @State month: number = new Date().getMonth();
  @State selectedDate: string = '';
  @State showForm: boolean = false;
  @State formOutfitId: string = '';
  @State formGarmentIds: string[] = [];
  @State formNote: string = '';
  @State formWeather: string = WEATHERS[0];
  @State formTemperature: number = 24;
  @State formOccasion: string = OCCASIONS[0];
  @State formFeedback: string = FEEDBACKS[0];
  @State formError: string = '';
  // 删除是破坏性操作：第一次点击只进入待确认态，第二次点击才真正回调删除，避免误触丢掉手写记录。
  @State pendingDeleteId: string = '';
  @State hint: string = '';

  aboutToAppear(): void {
    this.backToToday();
  }

  // 点击态与禁用态统一处理，符合鸿蒙控件的按压反馈预期。
  @Styles
  pressable() {
    .stateStyles({
      pressed: { .opacity(Theme.pressedOpacity) },
      disabled: { .opacity(Theme.disabledOpacity) }
    })
  }

  private todayKey(): string {
    const now: Date = new Date();
    return dayKey(now.getFullYear(), now.getMonth(), now.getDate());
  }

  private cellDate(day: number): string {
    return dayKey(this.year, this.month, day);
  }

  // 逐条解析而不是要求调用方预排序：日记可能被父组件按任意顺序合并进来。
  private keyOf(entry: DiaryEntry): string {
    const parts: DayParts = parseDay(entry.date);
    return parts.year > 0 ? dayKey(parts.year, parts.month, parts.day) : entry.date;
  }

  private entryDays(): string[] {
    const keys: string[] = [];
    for (const entry of this.diary) {
      const key: string = this.keyOf(entry);
      if (keys.indexOf(key) < 0) { keys.push(key); }
    }
    return keys;
  }

  private entriesOfDay(key: string): DiaryEntry[] {
    return this.diary.filter((entry: DiaryEntry) => this.keyOf(entry) === key);
  }

  private monthKeys(): string[] {
    const prefix: string = this.year + '-' + pad2(this.month + 1) + '-';
    return this.entryDays().filter((key: string) => key.indexOf(prefix) === 0);
  }

  private lastKey(): string {
    // 零补齐的日期键可以直接按字典序排序，最后一条就是最近一次记录。
    const keys: string[] = this.entryDays().slice().sort();
    return keys.length > 0 ? keys[keys.length - 1] : '';
  }

  private hasEntry(day: number): boolean {
    return this.entryDays().indexOf(this.cellDate(day)) >= 0;
  }

  private isSelected(day: number): boolean {
    return this.cellDate(day) === this.selectedDate;
  }

  private isToday(day: number): boolean {
    return this.cellDate(day) === this.todayKey();
  }

  private cellLabel(day: number): string {
    return dayText(this.cellDate(day)) + (this.hasEntry(day) ? '，有穿搭记录' : '，没有记录');
  }

  // 通过状态拼出来的键：ForEach 只按 key 判断是否复用旧组件，把选中态/记录态写进 key，
  // 才能保证点击日期后格子立即重绘。
  private cellKey(day: number, index: number): string {
    if (day === 0) { return 'blank_' + index; }
    return 'day_' + index + '_' + day + (this.isSelected(day) ? '_s' : '_n') +
      (this.hasEntry(day) ? '_e' : '_n') + (this.isToday(day) ? '_t' : '_n');
  }

  // 周一起始：中国用户看月历时习惯把周一放在第一列。
  private monthCells(): number[] {
    const offset: number = (new Date(this.year, this.month, 1).getDay() + 6) % 7;
    const total: number = new Date(this.year, this.month + 1, 0).getDate();
    const cells: number[] = [];
    for (let index = 0; index < offset; index++) { cells.push(0); }
    for (let day = 1; day <= total; day++) { cells.push(day); }
    while (cells.length % 7 !== 0) { cells.push(0); }
    return cells;
  }

  private monthWeeks(): number[][] {
    const cells: number[] = this.monthCells();
    const weeks: number[][] = [];
    for (let start = 0; start < cells.length; start += 7) {
      weeks.push(cells.slice(start, start + 7));
    }
    return weeks;
  }

  private shiftMonth(step: number): void {
    const moved: Date = new Date(this.year, this.month + step, 1);
    this.year = moved.getFullYear();
    this.month = moved.getMonth();
    this.selectFirstOfMonth();
  }

  // 翻月后同步选中日期：优先落到当月第一条记录，没有记录就落在 1 号，
  // 否则详情区会一直停在别的月份，看起来像翻月失效。
  private selectFirstOfMonth(): void {
    const keys: string[] = this.monthKeys().slice().sort();
    this.selectedDate = keys.length > 0 ? keys[0] : dayKey(this.year, this.month, 1);
    this.pendingDeleteId = '';
    this.hint = '';
  }

  private backToToday(): void {
    const now: Date = new Date();
    this.year = now.getFullYear();
    this.month = now.getMonth();
    this.selectedDate = dayKey(now.getFullYear(), now.getMonth(), now.getDate());
    this.pendingDeleteId = '';
    this.hint = '';
  }

  private selectDay(day: number): void {
    this.selectedDate = this.cellDate(day);
    this.pendingDeleteId = '';
    this.hint = '';
  }

  private itemsOf(ids: string[]): Garment[] {
    const items: Garment[] = [];
    for (const id of ids) {
      const found: Garment | undefined = this.garments.find((item: Garment) => item.id === id);
      if (found) { items.push(found); }
    }
    return items;
  }

  private sameIds(left: string[], right: string[]): boolean {
    if (left.length !== right.length) { return false; }
    return left.slice().sort().join(',') === right.slice().sort().join(',');
  }

  // 日记里没有 outfitId 字段，因此用单品集合回查收藏搭配：只有完全一致才算同一条。
  private matchedOutfit(entry: DiaryEntry): Outfit | undefined {
    if (entry.garmentIds.length === 0) { return undefined; }
    return this.saved.find((look: Outfit) => this.sameIds(look.garmentIds, entry.garmentIds));
  }

  private outfitLabel(look: Outfit): string {
    if (look.name.length > 0) { return look.name; }
    return look.occasion + ' · ' + look.temperature + '℃ · ' + look.garmentIds.length + ' 件';
  }

  private openForm(): void {
    this.formEntryId = 'diary_' + Date.now();
    this.formOutfitId = '';
    this.formGarmentIds = [];
    this.formNote = '';
    // 默认值沿用最近一条真实记录，没有记录时才用中性初值，减少重复填写。
    const latestKey: string = this.lastKey();
    const latest: DiaryEntry | undefined = latestKey.length > 0 ? this.entriesOfDay(latestKey)[0] : undefined;
    this.formWeather = latest !== undefined && WEATHERS.indexOf(latest.weather) >= 0 ? latest.weather : WEATHERS[0];
    this.formTemperature = latest !== undefined ? latest.temperature : 24;
    this.formOccasion = latest !== undefined && OCCASIONS.indexOf(latest.occasion) >= 0 ? latest.occasion : OCCASIONS[0];
    this.formFeedback = latest !== undefined && FEEDBACKS.indexOf(latest.feedback) >= 0 ? latest.feedback : FEEDBACKS[0];
    this.formError = '';
    this.hint = '';
    this.showForm = true;
  }

  private pickOutfit(look: Outfit): void {
    // 二选一：选了整套就把它的单品同步勾上，用户仍可继续增删。
    this.formOutfitId = look.id;
    this.formGarmentIds = look.garmentIds.slice();
    this.formError = '';
  }

  private toggleGarment(item: Garment): void {
    const picked: boolean = this.formGarmentIds.indexOf(item.id) >= 0;
    this.formGarmentIds = picked ? this.formGarmentIds.filter((id: string) => id !== item.id)
      : this.formGarmentIds.concat([item.id]);
    // 增删单品后已不再是原来那套搭配，清掉整套标记，避免日记里记错来源。
    const look: Outfit | undefined = this.saved.find((entry: Outfit) => entry.id === this.formOutfitId);
    if (look !== undefined && !this.sameIds(this.formGarmentIds, look.garmentIds)) {
      this.formOutfitId = '';
    }
    this.formError = '';
  }

  private async submit(): Promise<void> {
    if (this.saving) { return; }
    if (this.formGarmentIds.length === 0) {
      this.formError = '请先选择一套搭配，或从衣橱勾选至少一件单品。';
      return;
    }
    const entry: DiaryEntry = {
      id: this.formEntryId,
      date: this.selectedDate,
      garmentIds: this.formGarmentIds.slice(),
      // 感受允许留空：强制填写会让用户放弃记录，留空时详情区会显示占位说明。
      note: this.formNote.trim(),
      // 页面内不读取相册：未选照片就是空字符串。父组件后续补上真实照片路径也能直接显示。
      photoUri: '',
      weather: this.formWeather,
      temperature: this.formTemperature,
      occasion: this.formOccasion,
      feedback: this.formFeedback
    };
    this.saving = true;
    try {
      await this.onAddEntry(entry);
      this.showForm = false; this.pendingDeleteId = '';
      this.hint = '已保存 ' + dayText(entry.date) + ' 的记录';
    } catch (error) { this.formError = (error as Error).message; }
    finally { this.saving = false; }
  }

  private async confirmDelete(id: string): Promise<void> {
    if (this.saving) { return; }
    if (this.pendingDeleteId !== id) {
      this.pendingDeleteId = id;
      this.hint = '';
      return;
    }
    this.saving = true;
    try {
      await this.onDeleteEntry(id); this.pendingDeleteId = ''; this.hint = '已删除这条记录';
    } catch (error) { this.hint = (error as Error).message; }
    finally { this.saving = false; }
  }

  @Builder
  private statCell(label: string, value: string) {
    Column({ space: Theme.spaceXs }) {
      Text(value).fontSize(Type.cardTitle).fontWeight(FontWeight.Bold).fontColor(Theme.text).maxLines(1)
      Text(label).fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
  }

  // 统计条：本月记录天数与最近一次记录日期都从真实数据算出来，不做任何推测。
  @Builder
  private statsCard() {
    MaterialCard({ contentPadding: Theme.spaceM }) {
      Column({ space: Theme.spaceM }) {
        Row() {
          this.statCell('本月记录', this.monthKeys().length + ' 天')
          this.statCell('全部记录', this.diary.length + ' 条')
          this.statCell('最近一次', this.lastKey().length > 0 ? shortDayText(this.lastKey()) : '暂无')
        }.width('100%')
        Text(this.diary.length === 0 ?
          '还没有任何记录：点下面的「添加记录」，选一套搭配或几件单品就能开始。' :
          '记录只保存在本机，随时可以删除；本月已记录 ' + this.monthKeys().length + ' 天。')
          .fontSize(Type.caption).fontColor(Theme.secondary).lineHeight(20).width('100%')
      }.width('100%')
    }
  }

  @Builder
  private calendarCard() {
    MaterialCard({ contentPadding: Theme.spaceM }) {
      Column({ space: Theme.spaceS }) {
        Row({ space: Theme.spaceS }) {
          Text(this.year + '年' + (this.month + 1) + '月').fontSize(Type.cardTitle)
            .fontWeight(FontWeight.Medium).fontColor(Theme.text).layoutWeight(1).maxLines(1)
          Button('上月', { type: ButtonType.Normal }).fontSize(Type.buttonSmall).height(Theme.buttonCompact)
            .borderRadius(Theme.radiusPill).backgroundColor(Theme.surfaceSoft).fontColor(Theme.text)
            .constraintSize({ minWidth: 64 }).pressable().onClick(() => this.shiftMonth(-1))
          Button('下月', { type: ButtonType.Normal }).fontSize(Type.buttonSmall).height(Theme.buttonCompact)
            .borderRadius(Theme.radiusPill).backgroundColor(Theme.surfaceSoft).fontColor(Theme.text)
            .constraintSize({ minWidth: 64 }).pressable().onClick(() => this.shiftMonth(1))
        }.width('100%')
        Row() {
          ForEach(WEEK_LABELS, (label: string) => {
            Text(label).fontSize(Type.caption).fontColor(Theme.secondary)
              .textAlign(TextAlign.Center).layoutWeight(1).maxLines(1)
          }, (label: string) => 'week_' + label)
        }.width('100%')
        ForEach(this.monthWeeks(), (week: number[], weekIndex: number) => {
          Row() {
            ForEach(week, (day: number, index: number) => {
              if (day === 0) {
                // 占位格子保持同样的高度，保证日期与星期表头对齐。
                Row().layoutWeight(1).height(CELL_HEIGHT)
              } else {
                Column({ space: 2 }) {
                  Text(String(day)).fontSize(Type.bodySmall).maxLines(1)
                    .fontColor(this.isSelected(day) ? Color.White : (this.isToday(day) ? Theme.accent : Theme.text))
                    .fontWeight(this.isSelected(day) || this.isToday(day) ? FontWeight.Medium : FontWeight.Normal)
                  // 有记录的日子画一个圆点；没有记录时用透明圆点占位，避免行高抖动。
                  Row().width(4).height(4).borderRadius(2)
                    .backgroundColor(this.hasEntry(day) ?
                      (this.isSelected(day) ? Color.White : Theme.accent) : Color.Transparent)
                }
                  .layoutWeight(1).height(CELL_HEIGHT).justifyContent(FlexAlign.Center)
                  .borderRadius(Theme.radiusInput)
                  // 选中态用品牌强调色实底，未选中保持中性；今天用描边提示，不抢选中态。
                  .backgroundColor(this.isSelected(day) ? Theme.accent : Color.Transparent)
                  .border({ width: 1, color: this.isToday(day) && !this.isSelected(day) ? Theme.accent : Color.Transparent })
                  .accessibilityText(this.cellLabel(day))
                  .pressable()
                  .onClick(() => this.selectDay(day))
              }
            }, (day: number, index: number) => this.cellKey(day, index))
          }.width('100%')
        }, (week: number[], weekIndex: number) => 'week_' + this.year + '_' + this.month + '_' + weekIndex)
        Row({ space: Theme.spaceL }) {
          Row({ space: Theme.spaceXs }) {
            Row().width(6).height(6).borderRadius(3).backgroundColor(Theme.accent)
            Text('有记录').fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
          }
          Row({ space: Theme.spaceXs }) {
            Row().width(12).height(12).borderRadius(3).backgroundColor(Theme.accent)
            Text('已选中').fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
          }
          Row({ space: Theme.spaceXs }) {
            Row().width(12).height(12).borderRadius(3).border({ width: 1, color: Theme.accent })
            Text('今天').fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
          }
          Blank()
          Button('今天', { type: ButtonType.Normal }).fontSize(Type.buttonSmall).height(Theme.buttonCompact)
            .borderRadius(Theme.radiusPill).backgroundColor(Theme.accentSoft).fontColor(Theme.accent)
            .pressable().onClick(() => this.backToToday())
        }.width('100%')
      }.width('100%')
    }
  }

  @Builder
  private garmentTile(item: Garment) {
    Column({ space: Theme.spaceXs }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(garmentImage(item)).width('100%').height(58).objectFit(ImageFit.Contain)
          .backgroundColor(Theme.imagePlaceholder).borderRadius(Theme.radiusInput)
        if (this.formGarmentIds.indexOf(item.id) >= 0) {
          SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(Theme.iconSm).fontColor([Theme.accent])
        }
      }.width('100%')
      Text(item.name).fontSize(Type.caption).fontColor(Theme.text).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Center).width('100%')
    }
      .width('25%').padding(Theme.spaceXs)
      .accessibilityText(item.name + (this.formGarmentIds.indexOf(item.id) >= 0 ? '，已选择' : '，未选择'))
      .pressable()
      .onClick(() => this.toggleGarment(item))
  }

  @Builder
  private outfitChip(look: Outfit) {
    Button(this.outfitLabel(look), { type: ButtonType.Normal }).fontSize(Type.buttonSmall)
      .height(Theme.buttonCompact).borderRadius(Theme.radiusPill).margin(Theme.spaceXs)
      .backgroundColor(this.formOutfitId === look.id ? Theme.accentSoft : Theme.surfaceSoft)
      .fontColor(this.formOutfitId === look.id ? Theme.accent : Theme.text)
      .border({ width: 1, color: this.formOutfitId === look.id ? Theme.accent : Theme.line })
      .pressable()
      .onClick(() => this.pickOutfit(look))
  }

  @Builder
  private feedbackChip(value: string) {
    Button(value, { type: ButtonType.Normal }).fontSize(Type.buttonSmall).width('31%')
      .height(Theme.buttonCompact).borderRadius(Theme.radiusPill).margin(Theme.spaceXs)
      .backgroundColor(this.formFeedback === value ? Theme.accentSoft : Theme.surfaceSoft)
      .fontColor(this.formFeedback === value ? Theme.accent : Theme.text)
      .border({ width: 1, color: this.formFeedback === value ? Theme.accent : Theme.line })
      .pressable()
      .onClick(() => this.formFeedback = value)
  }

  @Builder
  private formCard() {
    MaterialCard({ contentPadding: Theme.spaceM }) {
      if (!this.showForm) {
        Column({ space: Theme.spaceM }) {
          Row({ space: Theme.spaceS }) {
            SymbolGlyph($r('sys.symbol.plus')).fontSize(Theme.iconMd).fontColor([Theme.accent])
            Column({ space: Theme.spaceXs }) {
              Text('添加记录').fontSize(Type.cardTitle).fontColor(Theme.text).maxLines(1)
              Text('选一套已收藏的搭配，或从衣橱挑单品，再写下当天的感受。')
                .fontSize(Type.caption).fontColor(Theme.secondary).maxLines(2)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }.width('100%')
          Button('记录 ' + shortDayText(this.selectedDate) + ' 的穿搭', { type: ButtonType.Normal })
            .width('100%').height(Theme.buttonHeight).borderRadius(Theme.radiusPill)
            .backgroundColor(Theme.accent).fontColor(Color.White).fontSize(Type.button)
            .pressable().onClick(() => this.openForm())
        }.width('100%')
      } else {
        Column({ space: Theme.spaceM }) {
          Text('新记录 · ' + dayText(this.selectedDate) + ' ' + weekName(this.selectedDate))
            .fontSize(Type.cardTitle).fontWeight(FontWeight.Medium).fontColor(Theme.text).width('100%').maxLines(2)
          Text('1 · 选一套已收藏的搭配（可选）').fontSize(Type.bodySmall).fontColor(Theme.text).width('100%').maxLines(1)
          if (this.saved.length === 0) {
            Text('还没有收藏的搭配，可以直接在下面从衣橱挑单品。')
              .fontSize(Type.caption).fontColor(Theme.secondary).width('100%').maxLines(2)
          } else {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.saved, (look: Outfit) => {
                this.outfitChip(look)
              }, (look: Outfit) => 'outfit_' + look.id + (this.formOutfitId === look.id ? '_1' : '_0'))
            }.width('100%')
          }
          Text('2 · 从衣橱选单品（已选 ' + this.formGarmentIds.length + ' 件）')
            .fontSize(Type.bodySmall).fontColor(Theme.text).width('100%').maxLines(1)
          if (this.garments.length === 0) {
            Text('衣橱里还没有衣物，先到「衣橱」添加一件，再回来记录。')
              .fontSize(Type.caption).fontColor(Theme.secondary).width('100%').maxLines(2)
          } else {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.garments, (item: Garment) => {
                this.garmentTile(item)
              }, (item: Garment) => 'pick_' + item.id + (this.formGarmentIds.indexOf(item.id) >= 0 ? '_1' : '_0'))
            }.width('100%')
          }
          Text('3 · 文字感受（可留空）').fontSize(Type.bodySmall).fontColor(Theme.text).width('100%').maxLines(1)
          TextArea({ text: $$this.formNote, placeholder: '例如：今天风大，加了外套刚刚好；社团活动穿这双鞋走了很多路。' })
            .width('100%').height(96).maxLength(NOTE_LIMIT)
            .fontSize(Type.bodySmall).fontColor(Theme.text).placeholderColor(Theme.secondary)
            .backgroundColor(Theme.surfaceSoft).borderRadius(Theme.radiusInput)
          Text('4 · 天气与场合').fontSize(Type.bodySmall).fontColor(Theme.text).width('100%').maxLines(1)
          Row({ space: Theme.spaceM }) {
            Select(WEATHERS.map((value: string): SelectOption => { return { value: value }; }))
              .value(this.formWeather).font({ size: Type.bodySmall }).fontColor(Theme.text).layoutWeight(1)
              .selectedOptionFontColor(Theme.accent).optionFontColor(Theme.text)
              .backgroundColor(Theme.surfaceSoft).borderRadius(Theme.radiusInput)
              .onSelect((index: number) => this.formWeather = WEATHERS[index])
            Select(OCCASIONS.map((value: string): SelectOption => { return { value: value }; }))
              .value(this.formOccasion).font({ size: Type.bodySmall }).fontColor(Theme.text).layoutWeight(1)
              .selectedOptionFontColor(Theme.accent).optionFontColor(Theme.text)
              .backgroundColor(Theme.surfaceSoft).borderRadius(Theme.radiusInput)
              .onSelect((index: number) => this.formOccasion = OCCASIONS[index])
          }.width('100%')
          Text('参考温度 ' + this.formTemperature + '℃')
            .fontSize(Type.caption).fontColor(Theme.secondary).width('100%').maxLines(2)
          Slider({ value: this.formTemperature, min: -10, max: 40, step: 1 }).selectedColor(Theme.accent)
            .onChange((value: number) => this.formTemperature = Math.round(value))
            .accessibilityText('当天温度')
          Text('5 · 穿着感受').fontSize(Type.bodySmall).fontColor(Theme.text).width('100%').maxLines(1)
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(FEEDBACKS, (value: string) => {
              this.feedbackChip(value)
            }, (value: string) => 'fb_' + value + (this.formFeedback === value ? '_1' : '_0'))
          }.width('100%')
          if (this.formError.length > 0) {
            Text(this.formError).fontSize(Type.caption).fontColor(Theme.warning).width('100%')
              .padding(Theme.spaceM).backgroundColor(Theme.warningSoft).borderRadius(Theme.radiusInput)
          }
          Row({ space: Theme.spaceM }) {
            Button('取消', { type: ButtonType.Normal }).fontSize(Type.buttonSmall).height(Theme.buttonHeight)
              .layoutWeight(1).borderRadius(Theme.radiusPill).backgroundColor(Theme.surfaceSoft)
              .fontColor(Theme.text).pressable().onClick(() => { this.showForm = false; this.formError = ''; })
            Button('保存记录', { type: ButtonType.Normal }).fontSize(Type.buttonSmall).height(Theme.buttonHeight)
              .layoutWeight(1).borderRadius(Theme.radiusPill).backgroundColor(Theme.accent)
              .fontColor(Color.White).pressable().onClick(() => this.submit())
          }.width('100%')
        }.width('100%')
      }
    }
  }

  @Builder
  private entryCard(entry: DiaryEntry) {
    MaterialCard({ contentPadding: Theme.spaceM }) {
      Column({ space: Theme.spaceM }) {
        Row({ space: Theme.spaceS }) {
          Text(entry.weather + ' · ' + entry.temperature + '℃').fontSize(Type.bodySmall)
            .fontColor(Theme.text).maxLines(1)
          Text(entry.occasion).fontSize(Type.caption).fontColor(Theme.accent).maxLines(1)
            .padding({ left: Theme.spaceS, right: Theme.spaceS, top: 2, bottom: 2 })
            .backgroundColor(Theme.accentSoft).borderRadius(Theme.radiusInput)
          Blank()
          Text(entry.feedback.length > 0 ? entry.feedback : '未记录感受').fontSize(Type.caption)
            .fontColor(entry.feedback.length > 0 ? Theme.success : Theme.secondary).maxLines(1)
        }.width('100%')
        // 只有父组件确实写入了照片路径才渲染照片，避免出现打不开的空图。
        if (entry.photoUri.length > 0) {
          Image(entry.photoUri).width('100%').height(180).objectFit(ImageFit.Cover)
            .backgroundColor(Theme.imagePlaceholder).borderRadius(Theme.radiusInput)
            .accessibilityText(dayText(this.keyOf(entry)) + '的上身照片')
        }
        Text(entry.note.length > 0 ? entry.note : '这条记录没有写感受。')
          .fontSize(Type.bodySmall).lineHeight(22).width('100%')
          .fontColor(entry.note.length > 0 ? Theme.text : Theme.secondary)
        if (this.itemsOf(entry.garmentIds).length === 0) {
          Text('记录中的单品已不在衣橱里，因此没有可显示的图片。')
            .fontSize(Type.caption).fontColor(Theme.secondary).width('100%').maxLines(2)
        } else {
          // 单品托盘用更薄的材质：与记录卡片形成层次，同时保留按压光感。
          Column() {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.itemsOf(entry.garmentIds), (item: Garment) => {
                Column({ space: Theme.spaceXs }) {
                  Image(garmentImage(item)).width('100%').height(56).objectFit(ImageFit.Contain)
                    .backgroundColor(Theme.imagePlaceholder).borderRadius(Theme.radiusInput)
                    .accessibilityText(item.name)
                  Text(item.name).fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Center).width('100%')
                }.width('25%').padding(Theme.spaceXs)
              }, (item: Garment) => 'entry_' + entry.id + '_' + item.id)
            }.width('100%')
          }
            .width('100%').padding(Theme.spaceXs).borderRadius(Theme.radiusInput)
            .backgroundColor(Theme.surfaceSoft).systemMaterial(panelMaterial())
        }
        Row({ space: Theme.spaceM }) {
          if (this.matchedOutfit(entry) !== undefined) {
            Button('查看这套搭配', { type: ButtonType.Normal }).fontSize(Type.buttonSmall)
              .height(Theme.buttonCompact).borderRadius(Theme.radiusPill)
              .backgroundColor(Theme.accentSoft).fontColor(Theme.accent).pressable()
              .onClick(() => {
                const look: Outfit | undefined = this.matchedOutfit(entry);
                if (look !== undefined) { this.onOpenOutfit(look); }
              })
          }
          Blank()
          Button(this.pendingDeleteId === entry.id ? '确认删除' : '删除', { type: ButtonType.Normal })
            .fontSize(Type.buttonSmall).height(Theme.buttonCompact).borderRadius(Theme.radiusPill)
            .backgroundColor(this.pendingDeleteId === entry.id ? Theme.warningSoft : Theme.surfaceSoft)
            .fontColor(this.pendingDeleteId === entry.id ? Theme.warning : Theme.secondary)
            .pressable().onClick(() => this.confirmDelete(entry.id))
        }.width('100%')
      }.width('100%')
    }
  }

  build() {
    Column({ space: Theme.spaceM }) {
      Column({ space: Theme.spaceXs }) {
        Text('穿搭日记').fontSize(Type.title).fontWeight(FontWeight.Bold).fontColor(Theme.text).maxLines(1)
        Text('记录每天穿过的搭配与当时的感受；佩戴日历按日期归组，数据只保存在本机。')
          .fontSize(Type.caption).fontColor(Theme.secondary).maxLines(2)
      }.alignItems(HorizontalAlign.Start).width('100%')
      this.statsCard()
      this.calendarCard()
      SectionHeader({ title: '当天记录', action: this.entriesOfDay(this.selectedDate).length + ' 条 · ' +
        shortDayText(this.selectedDate) })
      if (this.hint.length > 0) {
        Text(this.hint).fontSize(Type.caption).fontColor(Theme.accent).width('100%')
          .padding(Theme.spaceM).backgroundColor(Theme.accentSoft).borderRadius(Theme.radiusCard)
      }
      if (this.entriesOfDay(this.selectedDate).length === 0) {
        // 空状态给出去处，而不是留一片空白。
        MaterialCard({ contentPadding: Theme.spaceL }) {
          Column({ space: Theme.spaceS }) {
            SymbolGlyph($r('sys.symbol.shirt')).fontSize(Theme.iconLg).fontColor([Theme.secondary])
            Text('这一天还没有穿搭记录').fontSize(Type.cardTitle).fontColor(Theme.text)
              .textAlign(TextAlign.Center).maxLines(2)
            Text('点下面的「添加记录」，选一套搭配或几件单品，写下当天的感受；也可以点日历上的其他日期查看已有记录。')
              .fontSize(Type.bodySmall).fontColor(Theme.secondary).lineHeight(22)
              .textAlign(TextAlign.Center).maxLines(4)
          }.width('100%').alignItems(HorizontalAlign.Center)
            .padding({ top: Theme.spaceM, bottom: Theme.spaceM })
        }
      } else {
        ForEach(this.entriesOfDay(this.selectedDate), (entry: DiaryEntry) => {
          this.entryCard(entry)
        }, (entry: DiaryEntry) => entry.id)
      }
      this.formCard()
    }
      .width('100%').constraintSize({ maxWidth: CONTENT_MAX_WIDTH })
      .padding({ left: Theme.pagePadding, right: Theme.pagePadding, bottom: Theme.spaceXl })
  }
}
