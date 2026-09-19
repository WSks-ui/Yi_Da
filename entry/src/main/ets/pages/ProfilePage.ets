// 我的：会员体验、衣橱完善度、身材色彩档案、试穿记录。
//
// 设计原则：会员权益只描述真实存在的状态，不做促销式催促；身材与色彩信息全部可选，
// 不填写也不影响衣橱与推荐；任何一项都能单独修改或删除。
import { Theme, Type } from '../components/Theme';
import { MaterialCard, SectionHeader, SectionHeaderLink, MaterialSupport, hdsMaterialReport } from '../components/MaterialKit';
import { findDemoScene, formatTryOnDate } from '../service/TryOnDemo';
import { BodyProfile, Completeness, Membership, TryOnTask, completeness, trialDaysLeft }
  from '../model/Wardrobe';

@Component
export struct ProfilePage {  @Prop membership: Membership = { startDate: '', trialDays: 0, tryOnUsed: 0 };
  @Prop body: BodyProfile;
  @Prop tasks: TryOnTask[] = [];
  @Prop wardrobePercent: number = 0;
  @Prop garmentCount: number = 0;
  @Prop profileSummary: string = '';
  @Prop profileDone: boolean = false;
  @Prop cardSpaces: number = 0;
  onOpenQuiz: () => void = () => {};
  onOpenBody: () => void = () => {};
  onClaimTrial: () => void = () => {};
  onOpenTryOn: (sceneId?: string) => void = () => {};
  onOpenCardManager: () => void = () => {};
  onReset: () => void = () => {};

  private tryOnLabel(task: TryOnTask): string {
    const scene = task.demoSceneId ? findDemoScene(task.demoSceneId) : undefined;
    return scene ? scene.name + ' · 演示样片' : task.pose + ' · ' + task.garmentIds.length + ' 件';
  }

  @Builder
  private metric(value: string, label: string) {
    Column({ space: Theme.spaceXs }) {
      Text(value).fontSize(Type.title).fontWeight(FontWeight.Bold).fontColor(Theme.text).maxLines(1)
      Text(label).fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
    }.layoutWeight(1)
  }

  // 完善度用进度条呈现：只作为参考进度，不设置使用门槛。
  @Builder
  private completenessBar() {
    Column({ space: Theme.spaceM }) {
      Row() {
        Text('衣橱完善度').fontSize(Type.cardTitle).fontWeight(FontWeight.Medium)
          .fontColor(Theme.text).layoutWeight(1).maxLines(1)
        Text(`${this.wardrobePercent}%`).fontSize(Type.cardTitle)
          .fontColor(Theme.accent).maxLines(1)
      }.width('100%')
      Progress({ value: this.wardrobePercent, total: 100, type: ProgressType.Linear })
        .color(Theme.accent).backgroundColor(Theme.surfaceSoft).width('100%').height(6)
      Text(`${this.garmentCount} 件衣物 · 偏好档案${this.profileDone ? '已完成' : '未完成'} · 身材信息${this.body.height.length > 0 ? '已填写' : '未填写'}`)
        .fontSize(Type.caption).fontColor(Theme.secondary).width('100%').maxLines(2)
    }.width('100%')
  }

  @Builder
  private trialCard() {
    Column({ space: Theme.spaceM }) {
      Row({ space: Theme.spaceM }) {
        SymbolGlyph($r('sys.symbol.person')).fontSize(Theme.iconMd).fontColor([Theme.accent])
        Column({ space: Theme.spaceXs }) {
          Text('会员体验').fontSize(Type.cardTitle).fontColor(Theme.text).maxLines(1)
          Text(trialDaysLeft(this.membership) > 0
            ? `剩余 ${trialDaysLeft(this.membership)} 天 · 已用试穿 ${this.membership.tryOnUsed} 次`
            : '基础衣橱与规则推荐一直可用，不随体验到期失效')
            .fontSize(Type.caption).fontColor(Theme.secondary).maxLines(3)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%')
      if (trialDaysLeft(this.membership) === 0) {
        Button('领取 7 天体验', { type: ButtonType.Normal }).width('100%').height(Theme.buttonHeight)
          .borderRadius(Theme.radiusPill).backgroundColor(Theme.accent).fontColor(Color.White)
          .fontSize(Type.button)
          .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
          .onClick(() => this.onClaimTrial())
      }
    }.width('100%')
  }

  build() {
    Column({ space: Theme.spaceL }) {
      Column({ space: Theme.spaceXs }) {
        Text('我的').fontSize(Type.title).fontWeight(FontWeight.Bold).fontColor(Theme.text).maxLines(1)
        Text('艺起搭 · 本地衣橱').fontSize(Type.caption).fontColor(Theme.secondary).maxLines(1)
      }.alignItems(HorizontalAlign.Start).width('100%')

      MaterialCard({ contentPadding: Theme.spaceL }) {
        Row() {
          this.metric(String(this.garmentCount), '衣物')
          this.metric(String(this.tasks.length), '试穿记录')
          this.metric(`${this.wardrobePercent}%`, '完善度')
        }.width('100%')
      }

      MaterialCard({ contentPadding: Theme.spaceL }) {
        this.completenessBar()
      }

      MaterialCard({ contentPadding: Theme.spaceL }) {
        this.trialCard()
      }

      MaterialCard({ contentPadding: Theme.spaceL }) {
        Column({ space: Theme.spaceM }) {
          Row({ space: Theme.spaceM }) {
            SymbolGlyph($r('sys.symbol.person')).fontSize(Theme.iconMd).fontColor([Theme.accent])
            Column({ space: Theme.spaceXs }) {
              Text('穿搭档案').fontSize(Type.cardTitle).fontColor(Theme.text).maxLines(1)
              Text(this.profileDone ? this.profileSummary : '约 2 分钟完成，结果可随时修改')
                .fontSize(Type.caption).fontColor(Theme.secondary).maxLines(2)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Button(this.profileDone ? '修改' : '开始', { type: ButtonType.Normal })
              .fontSize(Type.buttonSmall).height(Theme.buttonCompact).borderRadius(Theme.radiusPill)
              .backgroundColor(Theme.accentSoft).fontColor(Theme.accent)
              .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
              .onClick(() => this.onOpenQuiz())
          }.width('100%')
          Divider().color(Theme.line)
          Row({ space: Theme.spaceM }) {
            SymbolGlyph($r('sys.symbol.shirt')).fontSize(Theme.iconMd).fontColor([Theme.accent])
            Column({ space: Theme.spaceXs }) {
              Text('身材与色彩档案').fontSize(Type.cardTitle).fontColor(Theme.text).maxLines(1)
              Text(this.body.height.length > 0
                ? `身高 ${this.body.height} · 常穿 ${this.body.size.length > 0 ? this.body.size : '未填'}`
                : '全部可选填，不影响衣橱与推荐')
                .fontSize(Type.caption).fontColor(Theme.secondary).maxLines(2)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Button('编辑', { type: ButtonType.Normal })
              .fontSize(Type.buttonSmall).height(Theme.buttonCompact).borderRadius(Theme.radiusPill)
              .backgroundColor(Theme.accentSoft).fontColor(Theme.accent)
              .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
              .onClick(() => this.onOpenBody())
          }.width('100%')
        }.width('100%')
      }

      MaterialCard({ contentPadding: Theme.spaceL }) {
        Column({ space: Theme.spaceM }) {
          Row({ space: Theme.spaceM }) {
            SymbolGlyph($r('sys.symbol.square_grid_2x2')).fontSize(Theme.iconMd).fontColor([Theme.accent])
            Column({ space: Theme.spaceXs }) {
              Text('今日穿搭桌面卡片').fontSize(Type.cardTitle).fontColor(Theme.text).maxLines(1)
              Text(this.cardSpaces > 0 ? `已添加 ${this.cardSpaces} 张` : '在桌面直接查看今天的搭配')
                .fontSize(Type.caption).fontColor(Theme.secondary).maxLines(2)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Button('管理', { type: ButtonType.Normal })
              .fontSize(Type.buttonSmall).height(Theme.buttonCompact).borderRadius(Theme.radiusPill)
              .backgroundColor(Theme.accentSoft).fontColor(Theme.accent)
              .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
              .onClick(() => this.onOpenCardManager())
          }.width('100%')
        }.width('100%')
      }

      SectionHeaderLink({ title: '试穿记录', action: this.tasks.length > 0 ? '查看' : '去试穿',
        onAction: () => this.onOpenTryOn() })
      if (this.tasks.length === 0) {
        MaterialCard({ contentPadding: Theme.spaceL }) {
          Column({ space: Theme.spaceS }) {
            Text('还没有试穿记录').fontSize(Type.bodySmall).fontColor(Theme.text).maxLines(1)
            Text('试穿间已有 3 组配套样片。')
              .fontSize(Type.caption).fontColor(Theme.secondary).maxLines(3)
          }.alignItems(HorizontalAlign.Start).width('100%')
        }
      } else {
        ForEach(this.tasks.slice(0, 3), (task: TryOnTask) => {
          MaterialCard({ contentPadding: Theme.spaceM }) {
            Row({ space: Theme.spaceM }) {
              SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(Theme.iconMd)
                .fontColor([Theme.secondary])
              Column({ space: Theme.spaceXs }) {
                Text(this.tryOnLabel(task)).fontSize(Type.bodySmall)
                  .fontColor(Theme.text).maxLines(1)
                Text(`${formatTryOnDate(task.createdAt)} · ${task.status}`).fontSize(Type.caption)
                  .fontColor(Theme.secondary).maxLines(1)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            }.width('100%').onClick(() => this.onOpenTryOn(task.demoSceneId))
          }
        }, (task: TryOnTask) => task.id)
      }

      Text(hdsMaterialReport())
        .fontSize(Type.caption).fontColor(MaterialSupport.isSupported() ? Theme.accent : Theme.secondary)
        .lineHeight(22).width('100%').padding(Theme.spaceM)
        .backgroundColor(Theme.accentSoft).borderRadius(Theme.radiusCard)
      Text('衣物与偏好保存在本机；没有上传人像、云端试穿或会员扣费。身体信息仅用于改善版型和配色建议。')
        .fontSize(Type.caption).fontColor(Theme.secondary).lineHeight(22).width('100%')
        .padding(Theme.spaceM).backgroundColor(Theme.surfaceSoft).borderRadius(Theme.radiusCard)

      Button('重置本地数据', { type: ButtonType.Normal }).fontSize(Type.buttonSmall).width('100%')
        .height(Theme.buttonHeight).backgroundColor(Theme.warningSoft).fontColor(Theme.warning)
        .borderRadius(Theme.radiusPill)
        .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
        .onClick(() => this.onReset())
    }.width('100%').padding({ left: Theme.pagePadding, right: Theme.pagePadding, bottom: Theme.spaceXl })
  }
}

// 身材、尺码与色彩档案编辑弹层。
//
// 分层填写：基础档案（身高、常穿尺码、版型偏好）与进阶档案（肩宽、胸围、腰围、臀围）
// 分开，色彩档案用色卡选择。每一项都可以留空，页面底部明确说明不填也能正常使用。
@Component
export struct BodyProfileSheet {
  @Link body: BodyProfile;
  onSave: () => void = () => {};

  @State draft: BodyProfile = { height: '', size: '', fitPreference: '', shoulder: '', chest: '', waist: '',
    hip: '', skinTone: '', hairColor: '', eyeColor: '', updatedAt: '' };

  private sizes: string[] = ['XS', 'S', 'M', 'L', 'XL', 'XXL'];
  private fits: string[] = ['宽松', '标准', '合身'];
  private tones: string[] = ['冷白', '暖白', '自然', '小麦', '深色'];

  aboutToAppear(): void {
    // 用已有档案回填，用户只改其中一项时不用重填全部。
    this.draft = { height: this.body.height, size: this.body.size, fitPreference: this.body.fitPreference,
      shoulder: this.body.shoulder, chest: this.body.chest, waist: this.body.waist, hip: this.body.hip,
      skinTone: this.body.skinTone, hairColor: this.body.hairColor, eyeColor: this.body.eyeColor,
      updatedAt: this.body.updatedAt };
  }

  @Builder
  private field(label: string, value: string, hint: string, onChange: (text: string) => void) {
    Column({ space: Theme.spaceXs }) {
      Text(label).fontSize(Type.bodySmall).fontColor(Theme.text).maxLines(1)
      TextInput({ text: value, placeholder: hint }).type(InputType.Number).maxLength(6)
        .fontColor(Theme.text).placeholderColor(Theme.secondary)
        .backgroundColor(Theme.surfaceSoft).borderRadius(Theme.radiusInput)
        .onChange((text: string) => onChange(text))
    }.alignItems(HorizontalAlign.Start).width('100%')
  }

  @Builder
  private chips(label: string, options: string[], selected: string, onPick: (value: string) => void) {
    Column({ space: Theme.spaceS }) {
      Text(label).fontSize(Type.bodySmall).fontColor(Theme.text).maxLines(1)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(options, (option: string) => {
          Text(option).fontSize(Type.caption)
            .fontColor(selected === option ? Theme.accent : Theme.text)
            .padding({ left: Theme.spaceM, right: Theme.spaceM, top: Theme.spaceS, bottom: Theme.spaceS })
            .backgroundColor(selected === option ? Theme.accentSoft : Theme.surfaceSoft)
            .borderRadius(Theme.radiusPill)
            .border({ width: 1, color: selected === option ? Theme.accent : Theme.line })
            .margin({ right: Theme.spaceS, bottom: Theme.spaceS })
            .onClick(() => onPick(option))
        }, (option: string) => option)
      }.width('100%')
    }.alignItems(HorizontalAlign.Start).width('100%')
  }

  build() {
    Scroll() {
      Column({ space: Theme.spaceL }) {
        Text('身材与色彩档案').fontSize(Type.title).fontWeight(FontWeight.Bold)
          .fontColor(Theme.text).width('100%').padding({ right: 44 }).maxLines(2)

        Text('基础档案').fontSize(Type.cardTitle).fontWeight(FontWeight.Medium)
          .fontColor(Theme.text).width('100%').maxLines(1)
        this.field('身高（厘米）', this.draft.height, '例如 170',
          (text: string) => this.draft.height = text)
        this.chips('常穿尺码', this.sizes, this.draft.size,
          (value: string) => this.draft.size = value)
        this.chips('版型偏好', this.fits, this.draft.fitPreference,
          (value: string) => this.draft.fitPreference = value)

        Divider().color(Theme.line)
        Text('进阶档案（可跳过）').fontSize(Type.cardTitle).fontWeight(FontWeight.Medium)
          .fontColor(Theme.text).width('100%').maxLines(1)
        Text('肩宽、胸围、腰围、臀围都用于换算版型建议，不填写也能使用。')
          .fontSize(Type.caption).fontColor(Theme.secondary).width('100%').maxLines(2)
        this.field('肩宽（厘米）', this.draft.shoulder, '例如 40',
          (text: string) => this.draft.shoulder = text)
        this.field('胸围（厘米）', this.draft.chest, '例如 88',
          (text: string) => this.draft.chest = text)
        this.field('腰围（厘米）', this.draft.waist, '例如 72',
          (text: string) => this.draft.waist = text)
        this.field('臀围（厘米）', this.draft.hip, '例如 94',
          (text: string) => this.draft.hip = text)

        Divider().color(Theme.line)
        Text('色彩档案（可跳过）').fontSize(Type.cardTitle).fontWeight(FontWeight.Medium)
          .fontColor(Theme.text).width('100%').maxLines(1)
        this.chips('肤色', this.tones, this.draft.skinTone,
          (value: string) => this.draft.skinTone = value)
        Text('色卡选择用于推荐配色，不做绝对化的风格诊断。')
          .fontSize(Type.caption).fontColor(Theme.secondary).width('100%').maxLines(2)

        Text('身体信息仅用于改善版型和配色建议；不填写也可正常使用衣橱与穿搭推荐。')
          .fontSize(Type.caption).fontColor(Theme.secondary).lineHeight(22).width('100%')
          .padding(Theme.spaceM).backgroundColor(Theme.surfaceSoft).borderRadius(Theme.radiusCard)

        Button('保存档案', { type: ButtonType.Normal }).width('100%').height(Theme.buttonHeight)
          .borderRadius(Theme.radiusPill).backgroundColor(Theme.accent).fontColor(Color.White)
          .fontSize(Type.button)
          .stateStyles({ pressed: { .opacity(Theme.pressedOpacity) } })
          .onClick(() => {
            this.draft.updatedAt = new Date().toLocaleDateString();
            this.body = this.draft;
            this.onSave();
          })
      }.width('100%').padding({ left: Theme.spaceXl, right: Theme.spaceXl, top: Theme.spaceXl, bottom: Theme.spaceXxl })
    }.width('100%').align(Alignment.TopStart).backgroundColor(Theme.background)
  }
}
