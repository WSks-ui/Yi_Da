import { common } from '@kit.AbilityKit';
import { AppServices } from '../common/AppServices';
import { Palette } from '../common/components/Palette';
import { ShellViewModel } from '../features/ShellViewModel';
import { GarmentDetailPage } from '../features/wardrobe/pages/GarmentDetailPage';
import { GarmentEditPage } from '../features/wardrobe/pages/GarmentEditPage';
import { WardrobePage } from '../features/wardrobe/pages/WardrobePage';
import { GarmentRoute } from '../navigation/GarmentRoute';

@Entry
@ComponentV2
struct Index {
  @Local vm: ShellViewModel = new ShellViewModel();
  @Local tab: number = 1;
  private stack: NavPathStack = new NavPathStack();

  aboutToAppear(): void { this.initialize(); }

  private initialize(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.vm.initialize(AppServices.get(context));
  }

  private add(): void {
    this.stack.pushPath({ name: 'garmentEdit', param: new GarmentRoute('', 'personal') });
  }

  @Builder
  destination(name: string, param: Object) {
    if (name === 'garmentEdit') {
      GarmentEditPage({
        garmentId: (param as GarmentRoute).id, space: (param as GarmentRoute).space, stack: this.stack,
        onSaved: () => { this.vm.wardrobe.notice = '衣物已保存'; this.vm.refresh(); }
      })
    } else if (name === 'garmentDetail') {
      GarmentDetailPage({
        garmentId: (param as GarmentRoute).id, space: (param as GarmentRoute).space, stack: this.stack,
        onChanged: () => { this.vm.refresh(); }
      })
    }
  }

  @Builder
  tabLabel(index: number, label: string, symbol: Resource) {
    Column({ space: 4 }) {
      SymbolGlyph(symbol).fontSize(23).fontColor([this.tab === index ? Palette.accent : Palette.muted])
      Text(label).fontSize(12).fontColor(this.tab === index ? Palette.accent : Palette.muted)
    }.width('100%').height(54).justifyContent(FlexAlign.Center)
  }

  @Builder
  statusRow(label: string, count: number, status: string) {
    Row() {
      Text(label).fontSize(17).fontColor(Palette.text).layoutWeight(1)
      Text(`${count} 件`).fontSize(17).fontColor(Palette.accent)
    }.padding({ top: 20, bottom: 20 }).width('100%')
      .onClick(() => {
        this.vm.wardrobe.space = 'personal';
        this.vm.wardrobe.resetFilters(status);
        this.tab = 1;
      })
    Divider().color(Palette.line)
  }

  build() {
    Navigation(this.stack) {
      if (this.vm.phase === 'loading') {
        Column({ space: 16 }) {
          LoadingProgress().width(40).height(40)
          Text('正在打开本地衣橱').fontColor(Palette.muted)
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else if (this.vm.phase === 'error') {
        Column({ space: 20 }) {
          Text('衣橱暂时无法打开').fontSize(22).fontColor(Palette.text)
          Text(this.vm.error).fontColor(Palette.danger)
          Button('重试').onClick(() => { this.initialize(); })
        }.width('100%').height('100%').padding(24).justifyContent(FlexAlign.Center)
      } else {
        Tabs({ barPosition: BarPosition.End, index: this.tab }) {
          TabContent() {
            Scroll() {
              Column({ space: 18 }) {
                Text('艺搭 · 今日').fontSize(26).fontWeight(FontWeight.Bold).fontColor(Palette.text).width('100%')
                Text('我的衣物').fontSize(15).fontColor(Palette.muted).width('100%')
                if (this.vm.statisticsReady) {
                  this.statusRow('日常衣橱', this.vm.total, '')
                  this.statusRow('今天可穿', this.vm.wearable, 'wearable')
                  this.statusRow('等待清洗', this.vm.laundry, 'laundry')
                } else {
                  Text('衣橱统计暂不可用').fontColor(Palette.danger)
                  Button('重新读取').onClick(() => { this.vm.refresh(); })
                }
                if (this.vm.statisticsReady && this.vm.total === 0) {
                  Text('还没有录入个人衣物').fontSize(16).fontColor(Palette.muted).width('100%')
                }
                Button('添加衣物', { type: ButtonType.Normal }).width('100%').height(48)
                  .borderRadius(6).backgroundColor(Palette.accent).onClick(() => { this.add(); })
              }.padding(24).width('100%').constraintSize({ maxWidth: 720 })
            }.width('100%').height('100%')
          }.tabBar(this.tabLabel(0, '今日', $r('sys.symbol.house_fill_1')))
          TabContent() {
            WardrobePage({
              vm: this.vm.wardrobe, service: this.vm.services?.wardrobe,
              onAdd: () => { this.add(); },
              onDetail: (id: string) => {
                this.stack.pushPath({ name: 'garmentDetail', param: new GarmentRoute(id, this.vm.wardrobe.space) });
              },
              onChanged: () => { this.vm.refresh(); }
            })
          }.tabBar(this.tabLabel(1, '衣橱', $r('sys.symbol.circle_grid_2x2')))
          TabContent() {
            Column({ space: 20 }) {
              Text('搭配').fontSize(26).fontWeight(FontWeight.Bold).fontColor(Palette.text).width('100%')
              Blank()
              SymbolGlyph($r('sys.symbol.square_and_square')).fontSize(42).fontColor([Palette.muted])
              Text('还没有保存的搭配').fontSize(20).fontColor(Palette.text)
              Text('推荐与试穿尚未接入').fontSize(14).fontColor(Palette.muted)
              Blank()
            }.padding(24).width('100%').height('100%')
          }.tabBar(this.tabLabel(2, '搭配', $r('sys.symbol.square_and_square')))
          TabContent() {
            Scroll() {
              Column({ space: 22 }) {
                Text('我的').fontSize(26).fontWeight(FontWeight.Bold).fontColor(Palette.text).width('100%')
                Text('本地衣橱').fontSize(20).fontWeight(FontWeight.Medium).fontColor(Palette.text).width('100%')
                Text(this.vm.statisticsReady ? `个人衣物 ${this.vm.total} 件（不含归档）` : '衣橱统计暂不可用')
                  .fontSize(16).fontColor(Palette.text).width('100%')
                Divider().color(Palette.line)
                Text('隐私与数据').fontSize(18).fontWeight(FontWeight.Medium).fontColor(Palette.text).width('100%')
                Text('衣物与照片保存在本机应用沙箱。本版本没有云端上传，也不需要账号。')
                  .fontSize(15).fontColor(Palette.muted).width('100%')
                Text('自动备份已关闭。卸载应用会清除本地衣橱；目前不提供备份导出。')
                  .fontSize(15).fontColor(Palette.muted).width('100%')
                Button('查看已归档衣物', { type: ButtonType.Normal }).width('100%').height(46)
                  .borderRadius(6).backgroundColor(Palette.panel).fontColor(Palette.text)
                  .onClick(() => {
                    this.vm.wardrobe.space = 'personal';
                    this.vm.wardrobe.resetFilters('archived');
                    this.tab = 1;
                  })
                if (this.vm.cleanupPending) {
                  Text('部分无引用图片尚未清理').fontColor(Palette.danger).width('100%')
                  Button('重试图片清理').onClick(() => { this.vm.retryCleanup(); })
                }
                Divider().color(Palette.line)
                Text('艺搭 Yi_Da · 本地开发版').fontSize(13).fontColor(Palette.muted).width('100%')
                Text('示例照片：T-shirt.jpg / Lateiner，CC BY-SA 3.0。来源：Wikimedia Commons。')
                  .fontSize(12).fontColor(Palette.muted).width('100%')
              }.padding(24).width('100%').constraintSize({ maxWidth: 720 })
            }.width('100%').height('100%')
          }.tabBar(this.tabLabel(3, '我的', $r('sys.symbol.person_crop_circle_fill_1')))
        }.barHeight(64).width('100%').height('100%').animationDuration(180)
          .onChange((index: number) => { this.tab = index; })
      }
    }.hideTitleBar(true).navDestination(this.destination).mode(NavigationMode.Stack)
      .width('100%').height('100%').backgroundColor(Palette.background)
  }
}
